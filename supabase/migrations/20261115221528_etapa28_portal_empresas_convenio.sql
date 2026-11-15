-- Etapa 28: portal de empresas con convenio (/empresa).
-- Usuarios de la empresa cliente: "encargado" (encargado de convenio) y "pasajero" (pasajero autorizado).
-- No son parte del equipo de Flota-K: no tienen fila en perfiles y no ven el panel.
-- Datos de facturación obligatorios, presupuesto mensual de la empresa y por pasajero (aviso o bloqueo),
-- y servicios habituales con tarifa fija que carga el administrador de Flota-K.

-- 1) Datos de facturación y presupuesto de la empresa cliente
alter table cuentas_corporativas add column if not exists giro text check (length(giro) <= 200);
alter table cuentas_corporativas add column if not exists direccion text check (length(direccion) <= 300);
alter table cuentas_corporativas add column if not exists comuna text check (length(comuna) <= 100);
alter table cuentas_corporativas add column if not exists fact_nombre text check (length(fact_nombre) <= 200);
alter table cuentas_corporativas add column if not exists fact_telefono text check (length(fact_telefono) <= 30);
alter table cuentas_corporativas add column if not exists requiere_oc boolean not null default false;
alter table cuentas_corporativas add column if not exists oc_detalle text check (length(oc_detalle) <= 500);
alter table cuentas_corporativas add column if not exists centros_costo text[] not null default '{}';
alter table cuentas_corporativas add column if not exists datos_completos_en timestamptz;
alter table cuentas_corporativas add column if not exists presupuesto_mensual int check (presupuesto_mensual between 0 and 1000000000);
alter table cuentas_corporativas add column if not exists presupuesto_modo text not null default 'alerta' check (presupuesto_modo in ('alerta', 'bloqueo'));

-- 2) Personas de la empresa cliente con acceso al portal
create table if not exists convenio_usuarios (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id),
  cuenta_id uuid not null references cuentas_corporativas(id),
  user_id uuid unique references auth.users(id),
  cliente_id uuid references clientes(id),
  rol text not null check (rol in ('encargado', 'pasajero')),
  nombre text not null check (length(nombre) between 2 and 200),
  correo text not null check (length(correo) <= 200),
  telefono text check (length(telefono) <= 30),
  presupuesto_mensual int check (presupuesto_mensual between 0 and 1000000000),
  activo boolean not null default true,
  clave_cambiada boolean not null default false,
  creado_en timestamptz not null default now(),
  creado_por uuid
);
create unique index if not exists convenio_usuarios_correo on convenio_usuarios (cuenta_id, lower(correo));
alter table convenio_usuarios enable row level security;
create policy convenio_usuarios_equipo on convenio_usuarios for select using (empresa_id = mi_empresa() and es_staff());
create policy convenio_usuarios_propio on convenio_usuarios for select using (user_id = auth.uid());

-- 3) Servicios habituales de cada empresa (tarifa fija, los carga el administrador)
create table if not exists servicios_habituales (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id),
  cuenta_id uuid not null references cuentas_corporativas(id),
  nombre text not null check (length(nombre) between 2 and 120),
  tipo_servicio text not null default 'punto_a_punto' check (tipo_servicio in ('ida', 'regreso', 'punto_a_punto', 'por_hora')),
  origen text not null check (length(origen) between 3 and 300),
  destino text not null check (length(destino) between 3 and 300),
  origen_lat double precision, origen_lng double precision,
  destino_lat double precision, destino_lng double precision,
  vehiculo text not null default 'auto' check (vehiculo in ('auto', 'suv', 'van')),
  precio int not null check (precio between 0 and 10000000),
  activo boolean not null default true,
  orden int not null default 0,
  creado_en timestamptz not null default now()
);
create index if not exists servicios_habituales_cuenta on servicios_habituales (cuenta_id);
alter table servicios_habituales enable row level security;
create policy habituales_equipo_ver on servicios_habituales for select using (empresa_id = mi_empresa() and es_staff());
create policy habituales_admin on servicios_habituales for all
  using (empresa_id = mi_empresa() and mi_rol() = 'admin')
  with check (empresa_id = mi_empresa() and mi_rol() = 'admin');
create policy habituales_convenio_ver on servicios_habituales for select
  using (activo and cuenta_id in (select cuenta_id from convenio_usuarios where user_id = auth.uid() and activo));

-- Las personas del convenio ven los datos de su empresa (para el portal); los cambios van por funciones
create policy corporativas_convenio_ver on cuentas_corporativas for select
  using (id in (select cuenta_id from convenio_usuarios where user_id = auth.uid() and activo));

-- Reserva: aviso cuando se pasó del presupuesto (modo "alerta")
alter table reservas add column if not exists convenio_aviso text check (length(convenio_aviso) <= 300);
alter table reservas add column if not exists servicio_habitual_id uuid references servicios_habituales(id);

-- ===== Funciones =====

-- Mi fila de convenio (activa)
create or replace function convenio_yo() returns convenio_usuarios
language sql stable security definer set search_path = public as $$
  select cu.* from convenio_usuarios cu
  join cuentas_corporativas c on c.id = cu.cuenta_id and c.activa
  where cu.user_id = auth.uid() and cu.activo
$$;
revoke execute on function convenio_yo() from public, anon;
grant execute on function convenio_yo() to authenticated;

-- Gasto de un mes (hora de Chile) de la empresa o de un pasajero: reservas no canceladas ni eliminadas
create or replace function convenio_gasto(p_cuenta uuid, p_cliente uuid, p_mes timestamptz) returns int
language sql stable security definer set search_path = public as $$
  select coalesce(sum(coalesce(r.precio, r.tarifa_web, 0)), 0)::int from reservas r
  where r.cuenta_corporativa_id = p_cuenta and r.estado <> 'cancelada' and r.eliminada_en is null
    and (p_cliente is null or r.cliente_id = p_cliente)
    and date_trunc('month', r.fecha_hora at time zone 'America/Santiago') = date_trunc('month', p_mes at time zone 'America/Santiago')
$$;
revoke execute on function convenio_gasto(uuid, uuid, timestamptz) from public, anon, authenticated;

-- Todo lo que necesita el portal al entrar
create or replace function convenio_inicio() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare yo convenio_usuarios; c cuentas_corporativas; v jsonb;
begin
  yo := convenio_yo();
  if yo.id is null then return null; end if;
  select * into c from cuentas_corporativas where id = yo.cuenta_id;
  v := jsonb_build_object(
    'yo', jsonb_build_object('id', yo.id, 'rol', yo.rol, 'nombre', yo.nombre, 'correo', yo.correo, 'telefono', yo.telefono,
      'presupuesto', yo.presupuesto_mensual, 'clave_cambiada', yo.clave_cambiada,
      'gasto_mes', convenio_gasto(yo.cuenta_id, yo.cliente_id, now())),
    'empresa', jsonb_build_object('razon_social', c.razon_social, 'rut', c.rut, 'giro', c.giro, 'direccion', c.direccion,
      'comuna', c.comuna, 'fact_nombre', c.fact_nombre, 'fact_correo', c.correo_facturacion, 'fact_telefono', c.fact_telefono,
      'requiere_oc', c.requiere_oc, 'oc_detalle', c.oc_detalle, 'centros_costo', to_jsonb(c.centros_costo),
      'datos_completos', c.datos_completos_en is not null, 'dias_pago', c.dias_pago,
      'presupuesto', c.presupuesto_mensual, 'modo', c.presupuesto_modo,
      'gasto_mes', case when yo.rol = 'encargado' then convenio_gasto(c.id, null, now()) end),
    'habituales', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'nombre', s.nombre, 'tipo', s.tipo_servicio,
        'origen', s.origen, 'destino', s.destino, 'vehiculo', s.vehiculo, 'precio', s.precio) order by s.orden, s.nombre)
      from servicios_habituales s where s.cuenta_id = c.id and s.activo), '[]'::jsonb),
    'equipo', case when yo.rol = 'encargado' then coalesce((select jsonb_agg(jsonb_build_object('id', u.id, 'rol', u.rol, 'nombre', u.nombre,
        'correo', u.correo, 'telefono', u.telefono, 'presupuesto', u.presupuesto_mensual, 'activo', u.activo,
        'gasto_mes', convenio_gasto(c.id, u.cliente_id, now())) order by u.activo desc, u.rol, u.nombre)
      from convenio_usuarios u where u.cuenta_id = c.id), '[]'::jsonb) end);
  return v;
end $$;
revoke execute on function convenio_inicio() from public, anon;
grant execute on function convenio_inicio() to authenticated;

-- El encargado completa o corrige los datos de facturación
create or replace function convenio_guardar_facturacion(p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare yo convenio_usuarios; v_cc text[];
begin
  yo := convenio_yo();
  if yo.id is null or yo.rol <> 'encargado' then raise exception 'Solo el encargado de convenio puede editar la facturación'; end if;
  if length(trim(coalesce(p->>'razon_social', ''))) < 2 then raise exception 'Ingrese la razón social'; end if;
  if coalesce(p->>'rut', '') !~ '^[0-9]{1,2}\.?[0-9]{3}\.?[0-9]{3}-[0-9kK]$' then raise exception 'Ingrese el RUT con guion, por ejemplo 76.123.456-7'; end if;
  if length(trim(coalesce(p->>'giro', ''))) < 2 then raise exception 'Ingrese el giro'; end if;
  if length(trim(coalesce(p->>'direccion', ''))) < 3 then raise exception 'Ingrese la dirección comercial'; end if;
  if length(trim(coalesce(p->>'comuna', ''))) < 2 then raise exception 'Ingrese la comuna'; end if;
  if length(trim(coalesce(p->>'fact_nombre', ''))) < 2 then raise exception 'Ingrese el nombre del encargado de facturación'; end if;
  if coalesce(p->>'fact_correo', '') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Ingrese un correo de facturación válido'; end if;
  if length(regexp_replace(coalesce(p->>'fact_telefono', ''), '\D', '', 'g')) < 8 then raise exception 'Ingrese el teléfono del encargado de facturación'; end if;
  select coalesce(array_agg(distinct left(trim(x), 100)) filter (where trim(x) <> ''), '{}') into v_cc
    from jsonb_array_elements_text(coalesce(p->'centros_costo', '[]'::jsonb)) x;
  if array_length(v_cc, 1) > 50 then raise exception 'Máximo 50 centros de costo'; end if;
  update cuentas_corporativas set
    razon_social = left(trim(p->>'razon_social'), 200), rut = upper(replace(trim(p->>'rut'), '.', '')),
    giro = left(trim(p->>'giro'), 200), direccion = left(trim(p->>'direccion'), 300), comuna = left(trim(p->>'comuna'), 100),
    fact_nombre = left(trim(p->>'fact_nombre'), 200), correo_facturacion = lower(trim(p->>'fact_correo')),
    fact_telefono = left(trim(p->>'fact_telefono'), 30),
    requiere_oc = coalesce((p->>'requiere_oc')::boolean, false), oc_detalle = nullif(left(trim(coalesce(p->>'oc_detalle', '')), 500), ''),
    centros_costo = v_cc, datos_completos_en = coalesce(datos_completos_en, now())
  where id = yo.cuenta_id;
end $$;
revoke execute on function convenio_guardar_facturacion(jsonb) from public, anon;
grant execute on function convenio_guardar_facturacion(jsonb) to authenticated;

-- El encargado fija el presupuesto mensual de la empresa y qué pasa al superarlo
create or replace function convenio_presupuesto_empresa(p_monto int, p_modo text) returns void
language plpgsql security definer set search_path = public as $$
declare yo convenio_usuarios;
begin
  yo := convenio_yo();
  if yo.id is null or yo.rol <> 'encargado' then raise exception 'Solo el encargado de convenio puede fijar el presupuesto'; end if;
  if p_modo not in ('alerta', 'bloqueo') then raise exception 'Opción no válida'; end if;
  if p_monto is not null and p_monto not between 0 and 1000000000 then raise exception 'Monto no válido'; end if;
  update cuentas_corporativas set presupuesto_mensual = p_monto, presupuesto_modo = p_modo where id = yo.cuenta_id;
end $$;
revoke execute on function convenio_presupuesto_empresa(int, text) from public, anon;
grant execute on function convenio_presupuesto_empresa(int, text) to authenticated;

-- El encargado ajusta a una persona: presupuesto, rol o acceso (no puede quitarse el rol ni el acceso a sí mismo)
create or replace function convenio_ajustar_usuario(p_usuario uuid, p_presupuesto int, p_rol text, p_activo boolean) returns void
language plpgsql security definer set search_path = public as $$
declare yo convenio_usuarios; u convenio_usuarios;
begin
  yo := convenio_yo();
  if yo.id is null or yo.rol <> 'encargado' then raise exception 'Solo el encargado de convenio puede hacer esto'; end if;
  select * into u from convenio_usuarios where id = p_usuario and cuenta_id = yo.cuenta_id;
  if u.id is null then raise exception 'Persona no encontrada'; end if;
  if p_rol is not null and p_rol not in ('encargado', 'pasajero') then raise exception 'Rol no válido'; end if;
  if p_presupuesto is not null and p_presupuesto not between 0 and 1000000000 then raise exception 'Monto no válido'; end if;
  if u.id = yo.id and (coalesce(p_rol, u.rol) <> 'encargado' or not coalesce(p_activo, true)) then
    raise exception 'No puede quitarse a sí mismo el rol de encargado ni el acceso';
  end if;
  update convenio_usuarios set presupuesto_mensual = p_presupuesto, rol = coalesce(p_rol, rol), activo = coalesce(p_activo, activo)
  where id = u.id;
end $$;
revoke execute on function convenio_ajustar_usuario(uuid, int, text, boolean) from public, anon;
grant execute on function convenio_ajustar_usuario(uuid, int, text, boolean) to authenticated;

-- Marca que la persona ya cambió su contraseña provisoria
create or replace function convenio_clave_cambiada() returns void
language sql security definer set search_path = public as $$
  update convenio_usuarios set clave_cambiada = true where user_id = auth.uid()
$$;
revoke execute on function convenio_clave_cambiada() from public, anon;
grant execute on function convenio_clave_cambiada() to authenticated;

-- Alta de una persona (la usa la Edge Function crear-usuario-convenio después de crear la cuenta de acceso).
-- La pueden usar: el administrador de Flota-K (cualquier empresa con convenio) o el encargado (solo su empresa).
create or replace function convenio_registrar_usuario(p_cuenta uuid, p_user uuid, p_rol text, p_nombre text, p_correo text, p_telefono text, p_por uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare c cuentas_corporativas; v_cli uuid; v_id uuid; v_correo text := lower(trim(p_correo));
begin
  select * into c from cuentas_corporativas where id = p_cuenta;
  if c.id is null then raise exception 'Empresa no encontrada'; end if;
  if p_rol not in ('encargado', 'pasajero') then raise exception 'Rol no válido'; end if;
  if exists (select 1 from perfiles where id = p_user) then raise exception 'Ese correo ya pertenece al equipo de Flota-K'; end if;
  if exists (select 1 from convenio_usuarios where user_id = p_user and cuenta_id <> p_cuenta) then raise exception 'Ese correo ya está en otra empresa con convenio'; end if;
  -- Ficha de cliente (las reservas se cobran a la empresa por el cliente)
  select id into v_cli from clientes where empresa_id = c.empresa_id and user_id = p_user;
  if v_cli is null then
    insert into clientes (empresa_id, user_id, cuenta_corporativa_id, nombre, telefono, correo)
    values (c.empresa_id, p_user, c.id, trim(p_nombre), nullif(trim(coalesce(p_telefono, '')), ''), v_correo) returning id into v_cli;
  else
    update clientes set cuenta_corporativa_id = c.id where id = v_cli;
  end if;
  insert into convenio_usuarios (empresa_id, cuenta_id, user_id, cliente_id, rol, nombre, correo, telefono, creado_por)
  values (c.empresa_id, c.id, p_user, v_cli, p_rol, trim(p_nombre), v_correo, nullif(trim(coalesce(p_telefono, '')), ''), p_por)
  on conflict (user_id) do update set rol = excluded.rol, nombre = excluded.nombre, telefono = coalesce(excluded.telefono, convenio_usuarios.telefono), activo = true
  returning id into v_id;
  return v_id;
end $$;
revoke execute on function convenio_registrar_usuario(uuid, uuid, text, text, text, text, uuid) from public, anon, authenticated;

-- Reserva desde el portal de empresas
create or replace function crear_reserva_convenio(
  p_habitual uuid, p_para uuid, p_fecha_hora timestamptz,
  p_tipo_servicio text default null, p_origen text default null, p_destino text default null,
  p_origen_lat double precision default null, p_origen_lng double precision default null,
  p_destino_lat double precision default null, p_destino_lng double precision default null,
  p_vehiculo text default 'auto', p_tarifa int default null, p_comuna text default null,
  p_vuelo text default null, p_pasajeros int default 1, p_maletas int default null,
  p_centro_costo text default null, p_comentarios text default null, p_retiro_detalle text default null
) returns table (o_codigo text, o_token uuid, o_aviso text)
language plpgsql security definer set search_path = public as $$
declare
  yo convenio_usuarios; pax convenio_usuarios; c cuentas_corporativas; s servicios_habituales;
  v_precio int; v_aviso text; g_emp int; g_pax int;
  v_tipo text; v_ori text; v_des text; v_olat double precision; v_olng double precision; v_dlat double precision; v_dlng double precision; v_veh text;
  v_cod text; v_tok uuid;
begin
  yo := convenio_yo();
  if yo.id is null then raise exception 'Su usuario no tiene acceso al convenio'; end if;
  select * into c from cuentas_corporativas where id = yo.cuenta_id;
  if c.datos_completos_en is null then raise exception 'Antes de agendar, el encargado de convenio debe completar los datos de facturación'; end if;
  -- Para quién: el pasajero agenda para sí mismo; el encargado puede agendar para cualquier persona activa de su empresa
  if p_para is null or p_para = yo.id then pax := yo;
  else
    if yo.rol <> 'encargado' then raise exception 'Solo el encargado de convenio puede agendar para otra persona'; end if;
    select * into pax from convenio_usuarios where id = p_para and cuenta_id = yo.cuenta_id and activo;
    if pax.id is null then raise exception 'Pasajero no encontrado'; end if;
  end if;
  if p_fecha_hora < now() + interval '60 minutes' then raise exception 'Para traslados en menos de 1 hora, escríbanos por WhatsApp al +56 9 2227 5399'; end if;
  if p_fecha_hora > now() + interval '365 days' then raise exception 'La fecha es demasiado lejana'; end if;
  if coalesce(p_pasajeros, 1) not between 1 and 20 then raise exception 'Número de pasajeros no válido'; end if;
  if p_maletas is not null and p_maletas not between 0 and 30 then raise exception 'Número de maletas no válido'; end if;
  if p_centro_costo is not null and array_length(c.centros_costo, 1) > 0 and not (p_centro_costo = any (c.centros_costo)) then
    raise exception 'Centro de costo no válido';
  end if;
  if length(coalesce(p_comentarios, '')) > 1000 then raise exception 'El comentario es demasiado largo'; end if;

  if p_habitual is not null then
    select * into s from servicios_habituales where id = p_habitual and cuenta_id = c.id and activo;
    if s.id is null then raise exception 'Servicio habitual no encontrado'; end if;
    v_tipo := s.tipo_servicio; v_ori := s.origen; v_des := s.destino; v_veh := s.vehiculo; v_precio := s.precio;
    v_olat := s.origen_lat; v_olng := s.origen_lng; v_dlat := s.destino_lat; v_dlng := s.destino_lng;
  else
    if p_tipo_servicio not in ('ida', 'regreso', 'punto_a_punto') then raise exception 'Tipo de servicio no válido'; end if;
    if length(trim(coalesce(p_origen, ''))) < 3 or length(trim(coalesce(p_destino, ''))) < 3 then raise exception 'Ingrese origen y destino'; end if;
    if p_origen_lat is null or p_origen_lat not between -56 and -17 or p_origen_lng not between -76 and -66 then raise exception 'Marque en el mapa el punto exacto de retiro'; end if;
    if p_vehiculo not in ('auto', 'van') then raise exception 'Vehículo no válido'; end if;
    if p_tarifa is not null and p_tarifa not between 0 and 2000000 then raise exception 'Tarifa no válida'; end if;
    v_tipo := p_tipo_servicio; v_ori := trim(p_origen); v_des := trim(p_destino); v_veh := p_vehiculo; v_precio := p_tarifa;
    v_olat := p_origen_lat; v_olng := p_origen_lng; v_dlat := p_destino_lat; v_dlng := p_destino_lng;
  end if;

  -- Presupuesto del mes del viaje (hora de Chile): de la empresa y del pasajero
  g_emp := convenio_gasto(c.id, null, p_fecha_hora) + coalesce(v_precio, 0);
  g_pax := convenio_gasto(c.id, pax.cliente_id, p_fecha_hora) + coalesce(v_precio, 0);
  if pax.presupuesto_mensual is not null and g_pax > pax.presupuesto_mensual then
    v_aviso := format('Supera el presupuesto mensual de %s ($%s de $%s)', pax.nombre,
      replace(to_char(g_pax, 'FM999,999,999'), ',', '.'), replace(to_char(pax.presupuesto_mensual, 'FM999,999,999'), ',', '.'));
  elsif c.presupuesto_mensual is not null and g_emp > c.presupuesto_mensual then
    v_aviso := format('Supera el presupuesto mensual de la empresa ($%s de $%s)',
      replace(to_char(g_emp, 'FM999,999,999'), ',', '.'), replace(to_char(c.presupuesto_mensual, 'FM999,999,999'), ',', '.'));
  end if;
  if v_aviso is not null and c.presupuesto_modo = 'bloqueo' then
    raise exception '%. Su empresa tiene bloqueadas las reservas sobre el presupuesto: pida al encargado de convenio que lo ajuste.', v_aviso;
  end if;

  insert into reservas (empresa_id, cliente_id, cuenta_corporativa_id, centro_costo, nombre_pasajero, telefono, correo, fecha_hora,
                        origen, destino, vuelo, pasajeros, comentarios, canal, maletas, tipo_servicio, vehiculo, comuna, tarifa_web, precio,
                        origen_lat, origen_lng, destino_lat, destino_lng, retiro_detalle, servicio_habitual_id, convenio_aviso,
                        solicitante_nombre, solicitante_telefono, solicitante_correo)
  values (c.empresa_id, pax.cliente_id, c.id, nullif(trim(coalesce(p_centro_costo, '')), ''), pax.nombre, coalesce(pax.telefono, yo.telefono), pax.correo, p_fecha_hora,
          v_ori, v_des, nullif(trim(coalesce(p_vuelo, '')), ''), coalesce(p_pasajeros, 1),
          nullif(trim(concat_ws(' · ', case when s.id is not null then 'Servicio habitual: ' || s.nombre end, nullif(trim(coalesce(p_comentarios, '')), ''))), ''),
          'convenio', p_maletas, v_tipo, v_veh, p_comuna, v_precio, case when s.id is not null then s.precio end,
          v_olat, v_olng, v_dlat, v_dlng, nullif(left(trim(coalesce(p_retiro_detalle, '')), 200), ''), s.id, v_aviso,
          case when pax.id <> yo.id then yo.nombre end, case when pax.id <> yo.id then yo.telefono end, case when pax.id <> yo.id then yo.correo end)
  returning reservas.codigo, reservas.token_seguimiento into v_cod, v_tok;
  o_codigo := v_cod; o_token := v_tok; o_aviso := v_aviso;
  return next;
end $$;
revoke execute on function crear_reserva_convenio(uuid, uuid, timestamptz, text, text, text, double precision, double precision, double precision, double precision, text, int, text, text, int, int, text, text, text) from public, anon;
grant execute on function crear_reserva_convenio(uuid, uuid, timestamptz, text, text, text, double precision, double precision, double precision, double precision, text, int, text, text, int, int, text, text, text) to authenticated;

-- Viajes que ve cada persona: el encargado, todos los de su empresa; el pasajero, los suyos
create or replace function convenio_reservas(p_desde timestamptz default now() - interval '60 days')
returns table (o_id uuid, o_codigo text, o_estado estado_reserva, o_fecha_hora timestamptz, o_origen text, o_destino text,
               o_pasajero text, o_valor int, o_centro_costo text, o_aviso text, o_token uuid, o_conductor text, o_puede_cancelar boolean)
language plpgsql stable security definer set search_path = public as $$
declare yo convenio_usuarios;
begin
  yo := convenio_yo();
  if yo.id is null then return; end if;
  return query
  select r.id, r.codigo, r.estado, r.fecha_hora, r.origen, r.destino, r.nombre_pasajero,
         coalesce(r.precio, r.tarifa_web), r.centro_costo, r.convenio_aviso, r.token_seguimiento,
         (select p.nombre from perfiles p where p.id = r.conductor_id),
         r.estado in ('recibida', 'confirmada', 'asignada') and r.fecha_hora > now() + interval '2 hours'
  from reservas r
  where r.cuenta_corporativa_id = yo.cuenta_id and r.eliminada_en is null and r.fecha_hora >= p_desde
    and (yo.rol = 'encargado' or r.cliente_id = yo.cliente_id)
  order by r.fecha_hora desc limit 500;
end $$;
revoke execute on function convenio_reservas(timestamptz) from public, anon;
grant execute on function convenio_reservas(timestamptz) to authenticated;

-- Cancelar desde el portal (hasta 2 horas antes; después, por WhatsApp). Queda nota en el historial.
create or replace function convenio_cancelar(p_reserva uuid, p_motivo text default null) returns void
language plpgsql security definer set search_path = public as $$
declare yo convenio_usuarios; r reservas;
begin
  yo := convenio_yo();
  if yo.id is null then raise exception 'Sin permiso'; end if;
  select * into r from reservas where id = p_reserva and cuenta_corporativa_id = yo.cuenta_id and eliminada_en is null for update;
  if r.id is null or (yo.rol <> 'encargado' and r.cliente_id is distinct from yo.cliente_id) then raise exception 'Reserva no encontrada'; end if;
  if r.estado not in ('recibida', 'confirmada', 'asignada') then raise exception 'Esta reserva ya no se puede cancelar desde aquí'; end if;
  if r.fecha_hora <= now() + interval '2 hours' then raise exception 'Faltan menos de 2 horas: para cancelar, escríbanos por WhatsApp al +56 9 2227 5399'; end if;
  update reservas set estado = 'cancelada' where id = r.id;
  update reserva_eventos set nota = left('Cancelada desde el portal de empresas por ' || yo.nombre || coalesce(': ' || nullif(trim(p_motivo), ''), ''), 1000)
    where id = (select max(id) from reserva_eventos where reserva_id = r.id);
end $$;
revoke execute on function convenio_cancelar(uuid, text) from public, anon;
grant execute on function convenio_cancelar(uuid, text) to authenticated;

-- Panel del equipo: personas y servicios habituales de cada empresa (solo staff de la misma empresa)
create or replace function convenio_admin_ver(p_cuenta uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c cuentas_corporativas;
begin
  if not es_staff() then raise exception 'Sin permiso'; end if;
  select * into c from cuentas_corporativas where id = p_cuenta and empresa_id = mi_empresa();
  if c.id is null then raise exception 'Empresa no encontrada'; end if;
  return jsonb_build_object(
    'facturacion', jsonb_build_object('razon_social', c.razon_social, 'rut', c.rut, 'giro', c.giro, 'direccion', c.direccion, 'comuna', c.comuna,
      'fact_nombre', c.fact_nombre, 'fact_correo', c.correo_facturacion, 'fact_telefono', c.fact_telefono, 'requiere_oc', c.requiere_oc,
      'oc_detalle', c.oc_detalle, 'centros_costo', to_jsonb(c.centros_costo), 'datos_completos_en', c.datos_completos_en,
      'presupuesto', c.presupuesto_mensual, 'modo', c.presupuesto_modo, 'gasto_mes', convenio_gasto(c.id, null, now())),
    'usuarios', coalesce((select jsonb_agg(jsonb_build_object('id', u.id, 'rol', u.rol, 'nombre', u.nombre, 'correo', u.correo,
        'telefono', u.telefono, 'presupuesto', u.presupuesto_mensual, 'activo', u.activo, 'clave_cambiada', u.clave_cambiada,
        'user_id', u.user_id) order by u.rol, u.nombre) from convenio_usuarios u where u.cuenta_id = c.id), '[]'::jsonb));
end $$;
revoke execute on function convenio_admin_ver(uuid) from public, anon;
grant execute on function convenio_admin_ver(uuid) to authenticated;

-- Panel del equipo (solo admin): activar o desactivar el acceso de una persona
create or replace function convenio_admin_activo(p_usuario uuid, p_activo boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if mi_rol() is distinct from 'admin' then raise exception 'Solo el administrador'; end if;
  update convenio_usuarios set activo = p_activo where id = p_usuario and empresa_id = mi_empresa();
  if not found then raise exception 'Persona no encontrada'; end if;
end $$;
revoke execute on function convenio_admin_activo(uuid, boolean) from public, anon;
grant execute on function convenio_admin_activo(uuid, boolean) to authenticated;
