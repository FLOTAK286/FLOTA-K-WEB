-- Etapa 44b: "terminando otro traslado" también se muestra si el conductor ya marcó "en camino" la reserva
-- mientras sigue en otro servicio (el mapa lo mostraría yendo a otro lado).
create or replace function ver_conductor_ocupado(p_token uuid)
returns table(o_tipo text, o_lat double precision, o_lng double precision, o_libre timestamptz,
              o_origen_lat double precision, o_origen_lng double precision)
language plpgsql stable security definer set search_path = public as $$
declare r reservas; o reservas; p perfiles; v_libre timestamptz;
begin
  select * into r from reservas where token_seguimiento = p_token and eliminada_en is null;
  if r.id is null or r.conductor_id is null or r.estado not in ('confirmada', 'asignada', 'en_camino')
     or r.fecha_hora > now() + interval '3 hours' then return; end if;
  -- 1) Otro servicio de Flota-K en curso del mismo conductor
  select * into o from reservas
   where conductor_id = r.conductor_id and id <> r.id and eliminada_en is null and estado in ('en_camino', 'en_lugar', 'a_bordo')
     and fecha_hora < r.fecha_hora
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
