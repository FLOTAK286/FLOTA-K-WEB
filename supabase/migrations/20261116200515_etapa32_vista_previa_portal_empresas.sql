-- Etapa 32: vista previa del portal de empresas para el equipo de Flota-K.
-- El equipo puede ver /empresa exactamente como lo ve una persona de una empresa con convenio,
-- sin entrar a su cuenta y SOLO PARA LEER (las funciones que guardan o cancelan no cambian:
-- siguen exigiendo ser esa persona).

-- Persona del convenio "como quien se mira": uno mismo, o (si es del equipo) la persona elegida
create or replace function public.convenio_yo_o_vista(p_como uuid)
 returns convenio_usuarios language plpgsql stable security definer set search_path to 'public'
as $function$
declare u convenio_usuarios;
begin
  if p_como is null then return convenio_yo(); end if;
  if not es_staff() then raise exception 'Sin permiso'; end if;
  select cu.* into u from convenio_usuarios cu
    join cuentas_corporativas c on c.id = cu.cuenta_id
   where cu.id = p_como and c.empresa_id = mi_empresa();
  if u.id is null then raise exception 'Persona no encontrada'; end if;
  return u;
end $function$;
revoke all on function public.convenio_yo_o_vista(uuid) from public, anon;
grant execute on function public.convenio_yo_o_vista(uuid) to authenticated;

drop function if exists public.convenio_inicio();
create function public.convenio_inicio(p_como uuid default null)
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
declare yo convenio_usuarios; c cuentas_corporativas; v jsonb;
begin
  yo := convenio_yo_o_vista(p_como);
  if yo.id is null then return null; end if;
  select * into c from cuentas_corporativas where id = yo.cuenta_id;
  v := jsonb_build_object(
    'yo', jsonb_build_object('id', yo.id, 'rol', yo.rol, 'nombre', yo.nombre, 'correo', yo.correo, 'telefono', yo.telefono,
      'presupuesto', yo.presupuesto_mensual, 'clave_cambiada', yo.clave_cambiada, 'activo', yo.activo,
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
revoke all on function public.convenio_inicio(uuid) from public, anon;
grant execute on function public.convenio_inicio(uuid) to authenticated;

drop function if exists public.convenio_reservas(timestamptz);
create function public.convenio_reservas(p_desde timestamptz default (now() - interval '60 days'), p_como uuid default null)
 returns table(o_id uuid, o_codigo text, o_estado estado_reserva, o_fecha_hora timestamptz, o_origen text, o_destino text,
               o_pasajero text, o_valor integer, o_centro_costo text, o_aviso text, o_token uuid, o_conductor text,
               o_puede_cancelar boolean, o_tipo text)
 language plpgsql stable security definer set search_path to 'public'
as $function$
declare yo convenio_usuarios;
begin
  yo := convenio_yo_o_vista(p_como);
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
revoke all on function public.convenio_reservas(timestamptz, uuid) from public, anon;
grant execute on function public.convenio_reservas(timestamptz, uuid) to authenticated;
