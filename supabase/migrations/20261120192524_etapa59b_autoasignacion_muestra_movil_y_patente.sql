-- Etapa 59b: la asignación automática informa móvil, conductor y patente (como la asignación manual:
-- "Móvil 286 · Juan Kieferling · SSHY88") en el aviso a Operaciones y en el historial de la reserva.
create or replace function conductor_mas_cercano(r reservas)
returns table(o_conductor uuid, o_vehiculo uuid, o_nombre text, o_km double precision)
language sql stable security definer set search_path = public as $$
  select p.id, v.id, concat_ws(' · ', 'Móvil ' || p.movil, p.nombre, v.patente),
         case when u.lat is not null and r.origen_lat is not null then distancia_km(u.lat, u.lng, r.origen_lat, r.origen_lng) end
  from perfiles p
  join lateral (select * from vehiculos x where x.conductor_habitual = p.id and x.activo order by x.creado_en limit 1) v on true
  left join ubicaciones u on u.conductor_id = p.id
  where p.empresa_id = r.empresa_id and p.activo and (p.conduce or p.rol = 'conductor')
    and motivo_requisitos_bolsa(r, p.id) is null
    and case coalesce(r.vehiculo, 'auto') when 'van' then v.categoria = 'van'
             when 'suv' then v.categoria in ('suv', 'van', 'particular_suv') else true end
    and not exists (select 1 from reservas o where o.conductor_id = p.id and o.id <> r.id and o.eliminada_en is null
                    and o.estado not in ('cancelada', 'finalizada')
                    and o.fecha_hora < r.fecha_hora + make_interval(mins => coalesce(r.duracion_min, 90) + 15)
                    and r.fecha_hora < o.fecha_hora + make_interval(mins => coalesce(o.duracion_min, 90) + 15))
    and not coalesce(p.otro_servicio_hasta > r.fecha_hora - interval '15 minutes', false)
  order by p.disponible desc,
           (u.actualizado_en is null or u.actualizado_en < now() - interval '2 hours'),
           case when u.lat is not null and r.origen_lat is not null then distancia_km(u.lat, u.lng, r.origen_lat, r.origen_lng) end nulls last
  limit 1
$$;
revoke execute on function conductor_mas_cercano(reservas) from public, anon, authenticated;

-- Corrige la nota del historial de la reserva ya asignada sola hoy (FK-888BC8)
update reserva_eventos e set nota = replace(e.nota, 'a Juan Kieferling · a ', 'a Móvil 286 · Juan Kieferling · SSHY88 · a ')
 where e.nota like 'Asignada automáticamente (nadie la tomó en Reservas) a Juan Kieferling · a %'
   and e.reserva_id = (select id from reservas where codigo = 'FK-888BC8');
