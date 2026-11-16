-- Etapa 31: rol "directivo" en empresas con convenio y viajes particulares en el portal.
-- Directivo (ej.: dueño de la empresa): ve TODOS los viajes de la empresa y el gasto de la empresa,
-- pero no administra personas, presupuestos ni facturación (eso es del encargado de convenio).
-- Toda persona del portal ve además sus viajes particulares (los que paga ella misma, sin convenio).
-- El equipo de Flota-K decide en cada reserva si es particular o de convenio: el convenio ya no se pone solo.

alter table public.convenio_usuarios drop constraint if exists convenio_usuarios_rol_check;
alter table public.convenio_usuarios add constraint convenio_usuarios_rol_check
  check (rol = any (array['encargado', 'pasajero', 'directivo']));

-- Alta de personas: acepta el nuevo rol
create or replace function public.convenio_registrar_usuario(p_cuenta uuid, p_user uuid, p_rol text, p_nombre text, p_correo text, p_telefono text, p_por uuid)
 returns uuid language plpgsql security definer set search_path to 'public'
as $function$
declare c cuentas_corporativas; v_cli uuid; v_id uuid; v_correo text := lower(trim(p_correo));
begin
  select * into c from cuentas_corporativas where id = p_cuenta;
  if c.id is null then raise exception 'Empresa no encontrada'; end if;
  if p_rol not in ('encargado', 'pasajero', 'directivo') then raise exception 'Rol no válido'; end if;
  if exists (select 1 from perfiles where id = p_user) then raise exception 'Ese correo ya pertenece al equipo de Flota-K'; end if;
  if exists (select 1 from convenio_usuarios where user_id = p_user and cuenta_id <> p_cuenta) then raise exception 'Ese correo ya está en otra empresa con convenio'; end if;
  -- Ficha de cliente: si ya existía (por ejemplo, como cliente particular por su correo), se reutiliza
  select id into v_cli from clientes where empresa_id = c.empresa_id and user_id = p_user;
  if v_cli is null then
    select id into v_cli from clientes where empresa_id = c.empresa_id and user_id is null and v_correo <> '' and lower(correo) = v_correo order by creado_en limit 1;
    if v_cli is not null then update clientes set user_id = p_user where id = v_cli; end if;
  end if;
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
end $function$;

-- El encargado puede asignar el rol directivo
create or replace function public.convenio_ajustar_usuario(p_usuario uuid, p_presupuesto integer, p_rol text, p_activo boolean)
 returns void language plpgsql security definer set search_path to 'public'
as $function$
declare yo convenio_usuarios; u convenio_usuarios;
begin
  yo := convenio_yo();
  if yo.id is null or yo.rol <> 'encargado' then raise exception 'Solo el encargado de convenio puede hacer esto'; end if;
  select * into u from convenio_usuarios where id = p_usuario and cuenta_id = yo.cuenta_id;
  if u.id is null then raise exception 'Persona no encontrada'; end if;
  if p_rol is not null and p_rol not in ('encargado', 'pasajero', 'directivo') then raise exception 'Rol no válido'; end if;
  if p_presupuesto is not null and p_presupuesto not between 0 and 1000000000 then raise exception 'Monto no válido'; end if;
  if u.id = yo.id and (coalesce(p_rol, u.rol) <> 'encargado' or not coalesce(p_activo, true)) then
    raise exception 'No puede quitarse a sí mismo el rol de encargado ni el acceso';
  end if;
  update convenio_usuarios set presupuesto_mensual = p_presupuesto, rol = coalesce(p_rol, rol), activo = coalesce(p_activo, activo)
  where id = u.id;
end $function$;

-- Viajes del portal: de la empresa (encargado y directivo: todos; pasajero: los suyos) + sus particulares
drop function if exists public.convenio_reservas(timestamptz);
create function public.convenio_reservas(p_desde timestamptz default (now() - interval '60 days'))
 returns table(o_id uuid, o_codigo text, o_estado estado_reserva, o_fecha_hora timestamptz, o_origen text, o_destino text,
               o_pasajero text, o_valor integer, o_centro_costo text, o_aviso text, o_token uuid, o_conductor text,
               o_puede_cancelar boolean, o_tipo text)
 language plpgsql stable security definer set search_path to 'public'
as $function$
declare yo convenio_usuarios;
begin
  yo := convenio_yo();
  if yo.id is null then return; end if;
  return query
  select r.id, r.codigo, r.estado, r.fecha_hora, r.origen, r.destino, r.nombre_pasajero,
         coalesce(r.precio, r.tarifa_web), r.centro_costo, r.convenio_aviso, r.token_seguimiento,
         (select p.nombre from perfiles p where p.id = r.conductor_id),
         r.cuenta_corporativa_id is not null
           and (yo.rol = 'encargado' or r.cliente_id = yo.cliente_id)
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
revoke all on function public.convenio_reservas(timestamptz) from public, anon;
grant execute on function public.convenio_reservas(timestamptz) to authenticated;

-- Encabezado del portal: el directivo también ve el gasto del mes de la empresa
create or replace function public.convenio_inicio()
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
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
      'gasto_mes', case when yo.rol in ('encargado', 'directivo') then convenio_gasto(c.id, null, now()) end),
    'habituales', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'nombre', s.nombre, 'tipo', s.tipo_servicio,
        'origen', s.origen, 'destino', s.destino, 'vehiculo', s.vehiculo, 'precio', s.precio) order by s.orden, s.nombre)
      from servicios_habituales s where s.cuenta_id = c.id and s.activo), '[]'::jsonb),
    'equipo', case when yo.rol = 'encargado' then coalesce((select jsonb_agg(jsonb_build_object('id', u.id, 'rol', u.rol, 'nombre', u.nombre,
        'correo', u.correo, 'telefono', u.telefono, 'presupuesto', u.presupuesto_mensual, 'activo', u.activo,
        'gasto_mes', convenio_gasto(c.id, u.cliente_id, now())) order by u.activo desc, u.rol, u.nombre)
      from convenio_usuarios u where u.cuenta_id = c.id), '[]'::jsonb) end);
  return v;
end $function$;

-- Reservas que agenda el equipo: el despachador elige particular o convenio, no se asigna solo.
-- (Las que crea el propio cliente siguen tomando el convenio de su ficha.)
create or replace function public.asignar_cuenta_corporativa()
 returns trigger language plpgsql security definer set search_path to 'public'
as $function$
begin
  if new.cuenta_corporativa_id is null and new.cliente_id is not null and not es_staff() then
    select cuenta_corporativa_id into new.cuenta_corporativa_id from clientes where id = new.cliente_id;
  end if;
  return new;
end $function$;
