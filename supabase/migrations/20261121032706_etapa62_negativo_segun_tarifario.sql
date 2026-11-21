-- Etapa 62: valor del negativo según el tarifario 2026 (pedido del dueño):
--   Van: $19.000 · Regreso desde el aeropuerto: $15.000 con 45 min de espera incluida · Domicilio/otros: $5.000 con 15 min.
--   Más la espera después del tiempo incluido ($180/min auto, $270/min SUV o van). Fuera de Santiago (60 %): la central ajusta el valor.
create or replace function negativo_calculo(p_reserva uuid)
returns table(o_valor integer, o_minutos integer, o_tarifa integer, o_desde timestamptz)
language sql stable security definer set search_path = public as $$
  with r as (
    select r.*, (select min(e.creado_en) from reserva_eventos e where e.reserva_id = r.id and e.estado = 'en_lugar') as llegada
    from reservas r where r.id = p_reserva
  ), c as (
    select greatest(r.fecha_hora + case when r.tipo_servicio = 'regreso' then interval '45 minutes' else interval '15 minutes' end,
                    coalesce(r.llegada, r.fecha_hora)) as desde,
           coalesce(r.negativo_solicitado_en, now()) as hasta,
           case when r.vehiculo in ('suv', 'van') then 270 else 180 end as tarifa,
           case when r.vehiculo = 'van' then 19000 when r.tipo_servicio = 'regreso' then 15000 else 5000 end as base
    from r
  )
  select (base + greatest(0, floor(extract(epoch from (hasta - desde)) / 60)) * tarifa)::int,
         greatest(0, floor(extract(epoch from (hasta - desde)) / 60))::int, tarifa, desde
  from c
$$;
