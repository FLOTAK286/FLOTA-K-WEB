-- Etapa 41: cuentas de clientes particulares (personas sin empresa) en el mismo portal (/empresa).
-- Cada empresa de transporte tiene una "cuenta" interna marcada es_particulares ("Clientes particulares"):
-- sus personas entran con usuario y contraseña, agendan a su nombre y ven sus viajes. Sus reservas quedan como
-- particulares (sin convenio: cuenta_corporativa_id vacío), sin facturación, presupuesto ni servicios habituales.

alter table cuentas_corporativas add column if not exists es_particulares boolean not null default false;
create unique index if not exists cuentas_particulares_una on cuentas_corporativas (empresa_id) where es_particulares;

-- Cuenta interna de particulares de mi empresa (la crea la primera vez). Solo administrador.
create or replace function public.cuenta_particulares()
returns uuid language plpgsql security definer set search_path to 'public' as $$
declare v uuid;
begin
  if mi_rol() is distinct from 'admin' then raise exception 'Solo el administrador'; end if;
  select id into v from cuentas_corporativas where empresa_id = mi_empresa() and es_particulares;
  if v is null then
    insert into cuentas_corporativas (empresa_id, razon_social, activa, es_particulares, datos_completos_en, notas)
    values (mi_empresa(), 'Clientes particulares', true, true, now(), 'Cuenta interna: personas sin empresa con acceso al portal. No es un convenio.')
    returning id into v;
  end if;
  return v;
end $$;
revoke execute on function public.cuenta_particulares() from public, anon;
grant execute on function public.cuenta_particulares() to authenticated;

-- Alta de personas: en la cuenta de particulares el rol es siempre "pasajero" y la ficha de cliente no queda con convenio
create or replace function public.convenio_registrar_usuario(p_cuenta uuid, p_user uuid, p_rol text, p_nombre text, p_correo text, p_telefono text, p_por uuid)
 returns uuid language plpgsql security definer set search_path to 'public'
as $function$
declare c cuentas_corporativas; v_cli uuid; v_id uuid; v_correo text := lower(trim(p_correo));
  v_tel8 text := right(regexp_replace(coalesce(p_telefono, ''), '\D', '', 'g'), 8);
begin
  select * into c from cuentas_corporativas where id = p_cuenta;
  if c.id is null then raise exception 'Empresa no encontrada'; end if;
  if p_rol not in ('encargado', 'pasajero', 'directivo') then raise exception 'Rol no válido'; end if;
  if c.es_particulares and p_rol <> 'pasajero' then raise exception 'Un cliente particular solo puede ser pasajero'; end if;
  if exists (select 1 from perfiles where id = p_user) then raise exception 'Ese correo ya pertenece al equipo de Flota-K'; end if;
  if exists (select 1 from convenio_usuarios where user_id = p_user and cuenta_id <> p_cuenta) then
    raise exception 'Ese correo o usuario ya tiene cuenta en el portal (en otra empresa o como particular)';
  end if;
  -- Ficha de cliente: si ya era cliente (por correo o, si no, por teléfono), se usa la misma ficha y conserva su historial
  select id into v_cli from clientes where empresa_id = c.empresa_id and user_id = p_user;
  if v_cli is null then
    select id into v_cli from clientes where empresa_id = c.empresa_id and user_id is null and v_correo <> '' and lower(correo) = v_correo order by creado_en limit 1;
  end if;
  if v_cli is null and length(v_tel8) = 8 then
    select id into v_cli from clientes where empresa_id = c.empresa_id and user_id is null
      and right(regexp_replace(coalesce(telefono, ''), '\D', '', 'g'), 8) = v_tel8 order by creado_en limit 1;
  end if;
  if v_cli is not null then
    update clientes set user_id = p_user,
      cuenta_corporativa_id = case when c.es_particulares then cuenta_corporativa_id else c.id end,
      correo = coalesce(correo, nullif(v_correo, '')) where id = v_cli;
  else
    insert into clientes (empresa_id, user_id, cuenta_corporativa_id, nombre, telefono, correo)
    values (c.empresa_id, p_user, case when c.es_particulares then null else c.id end, trim(p_nombre),
            nullif(trim(coalesce(p_telefono, '')), ''), nullif(v_correo, '')) returning id into v_cli;
  end if;
  insert into convenio_usuarios (empresa_id, cuenta_id, user_id, cliente_id, rol, nombre, correo, telefono, creado_por)
  values (c.empresa_id, c.id, p_user, v_cli, p_rol, trim(p_nombre), v_correo, nullif(trim(coalesce(p_telefono, '')), ''), p_por)
  on conflict (user_id) do update set rol = excluded.rol, nombre = excluded.nombre, telefono = coalesce(excluded.telefono, convenio_usuarios.telefono), activo = true
  returning id into v_id;
  return v_id;
end $function$;

-- Inicio del portal: indica si la persona es cliente particular
create or replace function public.convenio_inicio(p_como uuid default null)
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
declare yo convenio_usuarios; c cuentas_corporativas; v jsonb;
begin
  yo := convenio_yo_o_vista(p_como);
  if yo.id is null then return null; end if;
  select * into c from cuentas_corporativas where id = yo.cuenta_id;
  v := jsonb_build_object(
    'particular', c.es_particulares,
    'yo', jsonb_build_object('id', yo.id, 'rol', yo.rol, 'nombre', yo.nombre, 'correo', yo.correo, 'telefono', yo.telefono,
      'presupuesto', case when c.es_particulares then null else yo.presupuesto_mensual end, 'clave_cambiada', yo.clave_cambiada, 'activo', yo.activo,
      'gasto_mes', case when c.es_particulares then 0 else convenio_gasto(yo.cuenta_id, yo.cliente_id, now()) end),
    'empresa', case when c.es_particulares then jsonb_build_object('razon_social', yo.nombre, 'datos_completos', true, 'centros_costo', '[]'::jsonb)
      else jsonb_build_object('razon_social', c.razon_social, 'rut', c.rut, 'giro', c.giro, 'direccion', c.direccion,
      'comuna', c.comuna, 'fact_nombre', c.fact_nombre, 'fact_correo', c.correo_facturacion, 'fact_telefono', c.fact_telefono,
      'requiere_oc', c.requiere_oc, 'oc_detalle', c.oc_detalle, 'centros_costo', to_jsonb(c.centros_costo),
      'datos_completos', c.datos_completos_en is not null, 'dias_pago', c.dias_pago,
      'presupuesto', c.presupuesto_mensual, 'modo', c.presupuesto_modo,
      'gasto_mes', case when yo.rol in ('encargado', 'directivo') then convenio_gasto(c.id, null, now()) end) end,
    'habituales', case when c.es_particulares then '[]'::jsonb else coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'nombre', s.nombre, 'tipo', s.tipo_servicio,
        'origen', s.origen, 'destino', s.destino, 'vehiculo', s.vehiculo, 'precio', s.precio) order by s.orden, s.nombre)
      from servicios_habituales s where s.cuenta_id = c.id and s.activo), '[]'::jsonb) end,
    'equipo', case when yo.rol = 'encargado' and not c.es_particulares then coalesce((select jsonb_agg(jsonb_build_object('id', u.id, 'rol', u.rol, 'nombre', u.nombre,
        'correo', u.correo, 'telefono', u.telefono, 'presupuesto', u.presupuesto_mensual, 'activo', u.activo,
        'gasto_mes', convenio_gasto(c.id, u.cliente_id, now())) order by u.activo desc, u.rol, u.nombre)
      from convenio_usuarios u where u.cuenta_id = c.id), '[]'::jsonb) end);
  return v;
end $function$;

-- Viajes: la persona también puede cancelar sus viajes particulares (con más de 2 horas de anticipación)
create or replace function public.convenio_reservas(p_desde timestamptz default (now() - interval '60 days'), p_como uuid default null)
 returns table(o_id uuid, o_codigo text, o_estado estado_reserva, o_fecha_hora timestamptz, o_origen text, o_destino text, o_pasajero text,
   o_valor integer, o_centro_costo text, o_aviso text, o_token uuid, o_conductor text, o_puede_cancelar boolean, o_tipo text)
 language plpgsql stable security definer set search_path to 'public'
as $function$
declare yo convenio_usuarios;
begin
  yo := convenio_yo_o_vista(p_como);
  if yo.id is null then return; end if;
  return query
  select r.id, r.codigo, r.estado, r.fecha_hora, r.origen, r.destino, r.nombre_pasajero,
         valor_cobro(r.id), r.centro_costo, r.convenio_aviso, r.token_seguimiento,
         (select p.nombre from perfiles p where p.id = r.conductor_id),
         ((r.cuenta_corporativa_id is not null and (yo.rol = 'encargado' or r.cliente_id = yo.cliente_id))
           or (r.cuenta_corporativa_id is null and yo.cliente_id is not null and r.cliente_id = yo.cliente_id))
           and r.estado in ('recibida', 'confirmada', 'asignada') and r.fecha_hora > now() + interval '2 hours',
         case when r.cuenta_corporativa_id is null then 'particular' else 'empresa' end
  from reservas r
  where r.eliminada_en is null and r.fecha_hora >= p_desde
    and (
      (r.cuenta_corporativa_id = yo.cuenta_id and (yo.rol in ('encargado', 'directivo') or r.cliente_id = yo.cliente_id))
      or (r.cuenta_corporativa_id is null and yo.cliente_id is not null and r.cliente_id = yo.cliente_id)
    )
  order by r.fecha_hora desc limit 500;
end $function$;

create or replace function public.convenio_cancelar(p_reserva uuid, p_motivo text default null)
 returns void language plpgsql security definer set search_path to 'public'
as $function$
declare yo convenio_usuarios; r reservas;
begin
  yo := convenio_yo();
  if yo.id is null then raise exception 'Sin permiso'; end if;
  select * into r from reservas where id = p_reserva and eliminada_en is null
    and (cuenta_corporativa_id = yo.cuenta_id or (cuenta_corporativa_id is null and yo.cliente_id is not null and cliente_id = yo.cliente_id))
    for update;
  if r.id is null or (r.cuenta_corporativa_id is not null and yo.rol <> 'encargado' and r.cliente_id is distinct from yo.cliente_id) then
    raise exception 'Reserva no encontrada';
  end if;
  if r.estado not in ('recibida', 'confirmada', 'asignada') then raise exception 'Esta reserva ya no se puede cancelar desde aquí'; end if;
  if r.fecha_hora <= now() + interval '2 hours' then raise exception 'Faltan menos de 2 horas: para cancelar, escríbanos por WhatsApp al +56 9 2227 5399'; end if;
  update reservas set estado = 'cancelada' where id = r.id;
  update reserva_eventos set nota = left('Cancelada desde el portal por ' || yo.nombre || coalesce(': ' || nullif(trim(p_motivo), ''), ''), 1000)
    where id = (select max(id) from reserva_eventos where reserva_id = r.id);
end $function$;

-- Agendar: un cliente particular agenda a su nombre; la reserva queda particular (sin convenio), sin presupuestos
create or replace function public.crear_reserva_convenio(p_habitual uuid, p_para uuid, p_fecha_hora timestamptz, p_tipo_servicio text default null,
  p_origen text default null, p_destino text default null, p_origen_lat double precision default null, p_origen_lng double precision default null,
  p_destino_lat double precision default null, p_destino_lng double precision default null, p_vehiculo text default 'auto', p_tarifa integer default null,
  p_comuna text default null, p_vuelo text default null, p_pasajeros integer default 1, p_maletas integer default null, p_centro_costo text default null,
  p_comentarios text default null, p_retiro_detalle text default null, p_paradas jsonb default '[]'::jsonb)
 returns table(o_codigo text, o_token uuid, o_aviso text)
 language plpgsql security definer set search_path to 'public'
as $function$
declare
  yo convenio_usuarios; pax convenio_usuarios; c cuentas_corporativas; s servicios_habituales;
  v_precio int; v_aviso text; g_emp int; g_pax int; v_part boolean;
  v_tipo text; v_ori text; v_des text; v_olat double precision; v_olng double precision; v_dlat double precision; v_dlng double precision; v_veh text;
  v_cod text; v_tok uuid; v_par jsonb;
begin
  yo := convenio_yo();
  if yo.id is null then raise exception 'Su usuario no tiene acceso al portal'; end if;
  select * into c from cuentas_corporativas where id = yo.cuenta_id;
  v_part := c.es_particulares;
  if c.datos_completos_en is null and not v_part then raise exception 'Antes de agendar, el encargado de convenio debe completar los datos de facturación'; end if;
  if p_para is null or p_para = yo.id then pax := yo;
  else
    if yo.rol <> 'encargado' or v_part then raise exception 'Solo el encargado de convenio puede agendar para otra persona'; end if;
    select * into pax from convenio_usuarios where id = p_para and cuenta_id = yo.cuenta_id and activo;
    if pax.id is null then raise exception 'Pasajero no encontrado'; end if;
  end if;
  if p_fecha_hora < now() + interval '60 minutes' then raise exception 'Para traslados en menos de 1 hora, escríbanos por WhatsApp al +56 9 2227 5399'; end if;
  if p_fecha_hora > now() + interval '365 days' then raise exception 'La fecha es demasiado lejana'; end if;
  if coalesce(p_pasajeros, 1) not between 1 and 20 then raise exception 'Número de pasajeros no válido'; end if;
  if p_maletas is not null and p_maletas not between 0 and 30 then raise exception 'Número de maletas no válido'; end if;
  if p_centro_costo is not null and (v_part or (array_length(c.centros_costo, 1) > 0 and not (p_centro_costo = any (c.centros_costo)))) then
    raise exception 'Centro de costo no válido';
  end if;
  if length(coalesce(p_comentarios, '')) > 1000 then raise exception 'El comentario es demasiado largo'; end if;
  v_par := paradas_limpias(p_paradas);

  if p_habitual is not null then
    select * into s from servicios_habituales where id = p_habitual and cuenta_id = c.id and activo;
    if s.id is null then raise exception 'Servicio habitual no encontrado'; end if;
    v_tipo := s.tipo_servicio; v_ori := s.origen; v_des := s.destino; v_veh := s.vehiculo; v_precio := s.precio;
    v_olat := s.origen_lat; v_olng := s.origen_lng; v_dlat := s.destino_lat; v_dlng := s.destino_lng;
    v_par := '[]'::jsonb;
  else
    if p_tipo_servicio not in ('ida', 'regreso', 'punto_a_punto') then raise exception 'Tipo de servicio no válido'; end if;
    if length(trim(coalesce(p_origen, ''))) < 3 or length(trim(coalesce(p_destino, ''))) < 3 then raise exception 'Ingrese origen y destino'; end if;
    if p_origen_lat is null or p_origen_lat not between -56 and -17 or p_origen_lng not between -76 and -66 then raise exception 'Marque en el mapa el punto exacto de retiro'; end if;
    if p_vehiculo not in ('auto', 'van') then raise exception 'Vehículo no válido'; end if;
    if p_tarifa is not null and p_tarifa not between 0 and 2000000 then raise exception 'Tarifa no válida'; end if;
    v_tipo := p_tipo_servicio; v_ori := trim(p_origen); v_des := trim(p_destino); v_veh := p_vehiculo; v_precio := p_tarifa;
    v_olat := p_origen_lat; v_olng := p_origen_lng; v_dlat := p_destino_lat; v_dlng := p_destino_lng;
    if jsonb_array_length(v_par) > 0 then v_precio := null; end if;
  end if;

  if not v_part then
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
  end if;

  insert into reservas (empresa_id, cliente_id, cuenta_corporativa_id, centro_costo, nombre_pasajero, telefono, correo, fecha_hora,
                        origen, destino, vuelo, pasajeros, comentarios, canal, maletas, tipo_servicio, vehiculo, comuna, tarifa_web, precio,
                        origen_lat, origen_lng, destino_lat, destino_lng, retiro_detalle, servicio_habitual_id, convenio_aviso,
                        solicitante_nombre, solicitante_telefono, solicitante_correo, paradas)
  values (c.empresa_id, pax.cliente_id, case when v_part then null else c.id end, case when v_part then null else nullif(trim(coalesce(p_centro_costo, '')), '') end,
          pax.nombre, coalesce(pax.telefono, yo.telefono), pax.correo, p_fecha_hora,
          v_ori, v_des, case when v_tipo in ('ida', 'regreso') then nullif(trim(coalesce(p_vuelo, '')), '') end, coalesce(p_pasajeros, 1),
          nullif(trim(concat_ws(' · ', case when s.id is not null then 'Servicio habitual: ' || s.nombre end, nullif(trim(coalesce(p_comentarios, '')), ''))), ''),
          case when v_part then 'portal' else 'convenio' end, p_maletas, v_tipo, v_veh, p_comuna, v_precio, case when s.id is not null then s.precio end,
          v_olat, v_olng, v_dlat, v_dlng, nullif(left(trim(coalesce(p_retiro_detalle, '')), 200), ''), s.id, v_aviso,
          case when pax.id <> yo.id then yo.nombre end, case when pax.id <> yo.id then yo.telefono end, case when pax.id <> yo.id then yo.correo end, v_par)
  returning reservas.codigo, reservas.token_seguimiento into v_cod, v_tok;
  o_codigo := v_cod; o_token := v_tok; o_aviso := v_aviso;
  return next;
end $function$;
