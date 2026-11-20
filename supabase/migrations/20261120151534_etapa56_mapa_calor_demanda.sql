-- Etapa 56: mapa de calor de los próximos servicios (12 horas) para la app del conductor y el panel.
-- Solo la zona aproximada del retiro (redondeada a ~1 km) y los minutos que faltan: sin datos del pasajero ni dirección.
create or replace function mapa_demanda(p_horas integer default 12)
returns table(o_lat double precision, o_lng double precision, o_minutos integer)
language sql stable security definer set search_path = public as $$
  select round(r.origen_lat::numeric, 2)::float8, round(r.origen_lng::numeric, 2)::float8,
         greatest(0, floor(extract(epoch from (r.fecha_hora - now())) / 60))::int
  from reservas r
  join perfiles p on p.id = auth.uid() and p.activo and p.empresa_id = r.empresa_id
   and (p.conduce or p.rol in ('conductor', 'admin', 'despachador', 'telefonista'))
  where r.eliminada_en is null and r.estado in ('recibida', 'confirmada', 'asignada')
    and r.origen_lat is not null and r.origen_lng is not null
    and r.fecha_hora > now() - interval '10 minutes'
    and r.fecha_hora < now() + make_interval(hours => least(greatest(coalesce(p_horas, 12), 1), 24))
  order by r.fecha_hora
  limit 500
$$;
revoke execute on function mapa_demanda(integer) from public, anon;
grant execute on function mapa_demanda(integer) to authenticated;
