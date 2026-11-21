-- Etapa 62b: los conductores ven en el mapa dónde están los demás conductores conectados (zona aproximada, ~1 km,
-- sin nombres), para saber dónde hay más y menos conductores. Solo ubicaciones de los últimos 15 minutos.
create or replace function mapa_conductores()
returns table(o_lat double precision, o_lng double precision, o_ocupado boolean)
language sql stable security definer set search_path = public as $$
  select round(u.lat::numeric, 2)::float8, round(u.lng::numeric, 2)::float8,
         exists (select 1 from reservas r where r.conductor_id = p.id and r.estado in ('en_camino', 'en_lugar', 'a_bordo') and r.eliminada_en is null)
  from perfiles yo
  join perfiles p on p.empresa_id = yo.empresa_id and p.id <> yo.id and p.activo and (p.conduce or p.rol = 'conductor') and p.disponible
  join ubicaciones u on u.conductor_id = p.id and u.actualizado_en > now() - interval '15 minutes'
  where yo.id = auth.uid() and yo.activo and (yo.conduce or yo.rol in ('conductor', 'admin', 'despachador', 'telefonista'))
$$;
revoke execute on function mapa_conductores() from public, anon;
grant execute on function mapa_conductores() to authenticated;
