-- Etapa 65: el negativo detecta solo los retiros "fuera de Santiago" (comunas de la periferia, fuera del anillo de
-- Américo Vespucio, según el tarifario y los Términos): se cobra el 60 % del valor del servicio en vez del valor fijo.
-- El punto que cuenta es donde se retira al pasajero (en un regreso del aeropuerto, su destino).
create or replace function comuna_periferia(p_texto text)
returns text language sql immutable set search_path = public as $$
  select c from unnest(array['lampa', 'batuco', 'padre hurtado', 'penaflor', 'talagante', 'el monte', 'isla de maipo', 'calera de tango',
    'buin', 'paine', 'linderos', 'huelquen', 'champa', 'pirque', 'san jose de maipo', 'colina', 'chicureo', 'til til', 'tiltil', 'curacavi',
    'maria pinto', 'melipilla', 'lonquen', 'farellones', 'los andes', 'san felipe', 'rancagua', 'valparaiso', 'vina del mar']) c
  where translate(lower(coalesce(p_texto, '')), 'áéíóúüñ', 'aeiouun') like '%' || c || '%'
  limit 1
$$;

create or replace function negativo_calculo(p_reserva uuid)
returns table(o_valor integer, o_minutos integer, o_tarifa integer, o_desde timestamptz)
language sql stable security definer set search_path = public as $$
  with r as (
    select r.*, (select min(e.creado_en) from reserva_eventos e where e.reserva_id = r.id and e.estado = 'en_lugar') as llegada,
           comuna_periferia(case when r.tipo_servicio = 'regreso' then r.destino else r.origen end) as perif,
           case when r.tipo_cobro = 'taximetro' then null else coalesce(r.precio, r.tarifa_web) end as valor_serv
    from reservas r where r.id = p_reserva
  ), c as (
    select greatest(r.fecha_hora + case when r.tipo_servicio = 'regreso' then interval '45 minutes' else interval '15 minutes' end,
                    coalesce(r.llegada, r.fecha_hora)) as desde,
           coalesce(r.negativo_solicitado_en, now()) as hasta,
           case when r.vehiculo in ('suv', 'van') then 270 else 180 end as tarifa,
           case when r.vehiculo = 'van' then 19000 when r.tipo_servicio = 'regreso' then 15000 else 5000 end as base,
           case when r.perif is not null and r.valor_serv is not null then round(r.valor_serv * 0.6)::int end as perif_valor
    from r
  )
  select case when perif_valor is not null then perif_valor
              else (base + greatest(0, floor(extract(epoch from (hasta - desde)) / 60)) * tarifa)::int end,
         case when perif_valor is not null then 0 else greatest(0, floor(extract(epoch from (hasta - desde)) / 60))::int end,
         tarifa, desde
  from c
$$;

-- Explicación del cálculo para la ficha del panel
create or replace function negativo_detalle(p_reserva uuid)
returns text language sql stable security definer set search_path = public as $$
  select case
    when comuna_periferia(case when r.tipo_servicio = 'regreso' then r.destino else r.origen end) is not null
         and r.tipo_cobro <> 'taximetro' and coalesce(r.precio, r.tarifa_web) is not null
      then 'Fuera de Santiago (' || comuna_periferia(case when r.tipo_servicio = 'regreso' then r.destino else r.origen end) || '): 60 % de '
           || negativo_texto(coalesce(r.precio, r.tarifa_web))
    when comuna_periferia(case when r.tipo_servicio = 'regreso' then r.destino else r.origen end) is not null
      then 'Fuera de Santiago (' || comuna_periferia(case when r.tipo_servicio = 'regreso' then r.destino else r.origen end) || '): el servicio no tiene valor fijo; ajuste el 60 % a mano'
    end
  from reservas r where r.id = p_reserva and (es_staff() or r.conductor_id = auth.uid())
$$;
revoke execute on function negativo_detalle(uuid) from public, anon;
grant execute on function negativo_detalle(uuid) to authenticated;
