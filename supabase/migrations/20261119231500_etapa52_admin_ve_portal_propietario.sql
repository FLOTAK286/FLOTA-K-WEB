-- Etapa 52: el administrador puede ver el portal /propietario tal como lo ve un propietario (solo lectura), para revisarlo y mejorarlo.
create or replace function admin_puede_ver_propietario(p_propietario uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select mi_rol() = 'admin' and exists (select 1 from perfiles where id = p_propietario and empresa_id = mi_empresa())
$$;
revoke execute on function admin_puede_ver_propietario(uuid) from public, anon;
grant execute on function admin_puede_ver_propietario(uuid) to authenticated;

create or replace function admin_ver_propietario_vehiculos(p_propietario uuid)
returns table(o_id uuid, o_patente text, o_marca text, o_modelo text, o_anio integer, o_color text, o_categoria text, o_activo boolean,
              o_conductor text, o_movil text, o_comision numeric, o_docs_vencidos integer, o_docs_por_vencer integer, o_foto text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not admin_puede_ver_propietario(p_propietario) then raise exception 'Solo el administrador'; end if;
  return query
  select v.id, v.patente, v.marca, v.modelo, v.anio, v.color, v.categoria, v.activo, p.nombre, p.movil, v.comision_pct,
         (select count(*)::int from documentos d where d.vehiculo_id = v.id and d.vence < current_date),
         (select count(*)::int from documentos d where d.vehiculo_id = v.id and d.vence between current_date and current_date + 30),
         v.foto_path
  from vehiculos v left join perfiles p on p.id = v.conductor_habitual
  where v.propietario_id = p_propietario
  order by v.patente;
end $$;
revoke execute on function admin_ver_propietario_vehiculos(uuid) from public, anon;
grant execute on function admin_ver_propietario_vehiculos(uuid) to authenticated;

create or replace function admin_ver_propietario_servicios(p_propietario uuid, p_desde timestamptz, p_hasta timestamptz)
returns table(o_codigo text, o_fecha_hora timestamptz, o_estado estado_reserva, o_vehiculo_id uuid, o_patente text, o_conductor text, o_movil text,
              o_origen text, o_destino text, o_tipo_servicio text, o_tipo_cobro text, o_km numeric, o_total integer, o_gastos integer, o_pagado boolean, o_comision numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  if not admin_puede_ver_propietario(p_propietario) then raise exception 'Solo el administrador'; end if;
  return query
  select r.codigo, r.fecha_hora, r.estado, v.id, v.patente, p.nombre, p.movil,
         case when position(',' in r.origen) > 0 then trim(split_part(r.origen, ',', -1)) else r.origen end,
         case when position(',' in r.destino) > 0 then trim(split_part(r.destino, ',', -1)) else r.destino end,
         r.tipo_servicio::text, r.tipo_cobro, round(r.taxi_metros / 1000.0, 1),
         c.total, c.gastos, r.pagado, v.comision_pct
  from reservas r
  join vehiculos v on v.id = r.vehiculo_id
  join v_cobro c on c.id = r.id
  left join perfiles p on p.id = r.conductor_id
  where v.propietario_id = p_propietario
    and r.estado <> 'cancelada'
    and r.fecha_hora >= p_desde and r.fecha_hora < p_hasta
  order by r.fecha_hora;
end $$;
revoke execute on function admin_ver_propietario_servicios(uuid, timestamptz, timestamptz) from public, anon;
grant execute on function admin_ver_propietario_servicios(uuid, timestamptz, timestamptz) to authenticated;
