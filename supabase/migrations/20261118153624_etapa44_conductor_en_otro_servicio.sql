-- Etapa 44: "Estoy en otro servicio". El conductor indica que está en otro viaje (Cabify, particular, etc.):
-- hacia dónde va y a qué hora termina aprox. El seguimiento del próximo pasajero lo muestra ("Su conductor está
-- terminando otro traslado") con una llegada estimada. Si el otro viaje es de Flota-K (en camino, en el lugar o a bordo),
-- se muestra solo. Nunca se muestran datos del otro pasajero: solo una zona aproximada.

alter table perfiles add column if not exists otro_servicio_desde timestamptz;
alter table perfiles add column if not exists otro_servicio_hasta timestamptz;
alter table perfiles add column if not exists otro_servicio_destino text check (length(otro_servicio_destino) <= 300);
alter table perfiles add column if not exists otro_servicio_lat double precision;
alter table perfiles add column if not exists otro_servicio_lng double precision;

create or replace function conductor_otro_servicio(p_destino text, p_lat double precision, p_lng double precision, p_hasta timestamptz)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_hasta is null or p_hasta < now() or p_hasta > now() + interval '12 hours' then
    raise exception 'Indique a qué hora termina (dentro de las próximas 12 horas)';
  end if;
  if p_lat is not null and (p_lat not between -56 and -17 or p_lng not between -76 and -66) then raise exception 'Punto no válido'; end if;
  update perfiles set otro_servicio_desde = now(), otro_servicio_hasta = p_hasta,
         otro_servicio_destino = nullif(left(trim(coalesce(p_destino, '')), 300), ''), otro_servicio_lat = p_lat, otro_servicio_lng = p_lng
   where id = auth.uid() and activo and (conduce or rol = 'conductor');
  if not found then raise exception 'Solo conductores'; end if;
end $$;
revoke execute on function conductor_otro_servicio(text, double precision, double precision, timestamptz) from public, anon;
grant execute on function conductor_otro_servicio(text, double precision, double precision, timestamptz) to authenticated;

create or replace function conductor_fin_otro_servicio()
returns void language plpgsql security definer set search_path = public as $$
begin
  update perfiles set otro_servicio_desde = null, otro_servicio_hasta = null, otro_servicio_destino = null,
         otro_servicio_lat = null, otro_servicio_lng = null
   where id = auth.uid();
end $$;
revoke execute on function conductor_fin_otro_servicio() from public, anon;
grant execute on function conductor_fin_otro_servicio() to authenticated;

-- Para el seguimiento (con el enlace del pasajero): ¿su conductor está terminando otro servicio?
-- Solo para reservas confirmadas o asignadas que empiezan dentro de las próximas 3 horas.
-- Devuelve el punto donde termina el otro viaje redondeado (~1 km), la hora estimada en que queda libre
-- y el punto de retiro de esta reserva (para calcular la llegada).
create or replace function ver_conductor_ocupado(p_token uuid)
returns table(o_tipo text, o_lat double precision, o_lng double precision, o_libre timestamptz,
              o_origen_lat double precision, o_origen_lng double precision)
language plpgsql stable security definer set search_path = public as $$
declare r reservas; o reservas; p perfiles; v_libre timestamptz;
begin
  select * into r from reservas where token_seguimiento = p_token and eliminada_en is null;
  if r.id is null or r.conductor_id is null or r.estado not in ('confirmada', 'asignada')
     or r.fecha_hora > now() + interval '3 hours' then return; end if;
  -- 1) Otro servicio de Flota-K en curso del mismo conductor
  select * into o from reservas
   where conductor_id = r.conductor_id and id <> r.id and eliminada_en is null and estado in ('en_camino', 'en_lugar', 'a_bordo')
   order by fecha_hora limit 1;
  if o.id is not null then
    v_libre := greatest(o.fecha_hora + make_interval(mins => coalesce(o.duracion_min, 60)), now() + interval '5 minutes');
    return query select 'flotak'::text, round(o.destino_lat::numeric, 2)::float8, round(o.destino_lng::numeric, 2)::float8, v_libre,
                        r.origen_lat, r.origen_lng;
    return;
  end if;
  -- 2) Otro servicio indicado por el conductor
  select * into p from perfiles where id = r.conductor_id;
  if p.otro_servicio_hasta is not null and p.otro_servicio_hasta > now() - interval '10 minutes' then
    return query select 'otro'::text, round(p.otro_servicio_lat::numeric, 2)::float8, round(p.otro_servicio_lng::numeric, 2)::float8,
                        greatest(p.otro_servicio_hasta, now() + interval '5 minutes'), r.origen_lat, r.origen_lng;
  end if;
end $$;
revoke execute on function ver_conductor_ocupado(uuid) from public;
grant execute on function ver_conductor_ocupado(uuid) to anon, authenticated;
