-- Etapa 30: espera en servicios punto a punto.
-- 15 min de gracia desde la hora agendada. Después: $180 por minuto (auto) o $270 (SUV o van).
-- Solo se cobra mientras el conductor está en el lugar: desde que marca "llegué" (en_lugar)
-- o desde que termina la gracia (lo que ocurra después) hasta que el pasajero sube (a_bordo).
-- Se cobran minutos completos. Al subir el pasajero, el monto queda como gasto "espera" de la reserva.

alter table public.reserva_gastos drop constraint if exists reserva_gastos_tipo_check;
alter table public.reserva_gastos add constraint reserva_gastos_tipo_check
  check (tipo = any (array['tag', 'peaje', 'estacionamiento', 'otro', 'espera']));

create or replace function public.espera_calculo(p_reserva uuid)
returns table (aplica boolean, gracia_hasta timestamptz, llegada_en timestamptz, a_bordo_en timestamptz,
               cobro_desde timestamptz, tarifa_min integer, minutos integer, monto integer, ahora timestamptz)
language sql stable security definer set search_path to 'public'
as $$
  with r as (
    select r.*,
      (select min(e.creado_en) from reserva_eventos e where e.reserva_id = r.id and e.estado = 'en_lugar') as t_llegada,
      (select min(e.creado_en) from reserva_eventos e where e.reserva_id = r.id and e.estado = 'a_bordo') as t_abordo
    from reservas r where r.id = p_reserva
  ), c as (
    select r.*,
      (r.tipo_servicio = 'punto_a_punto' and coalesce(r.tipo_cobro, '') <> 'taximetro') as ap,
      r.fecha_hora + interval '15 minutes' as gracia,
      case when r.vehiculo in ('suv', 'van') then 270 else 180 end as tarifa,
      greatest(r.fecha_hora + interval '15 minutes', r.t_llegada) as desde
    from r
  )
  select c.ap, c.gracia, c.t_llegada, c.t_abordo,
         case when c.t_llegada is null then null else c.desde end,
         c.tarifa,
         case when not c.ap or c.t_llegada is null then 0
              else greatest(0, floor(extract(epoch from (coalesce(c.t_abordo, now()) - c.desde)) / 60))::int end,
         case when not c.ap or c.t_llegada is null then 0
              else (greatest(0, floor(extract(epoch from (coalesce(c.t_abordo, now()) - c.desde)) / 60)) * c.tarifa)::int end,
         now()
  from c
$$;
revoke all on function public.espera_calculo(uuid) from public, anon, authenticated;

-- Para el enlace del pasajero y su app (con el token del enlace)
create or replace function public.ver_espera_publica(p_token uuid)
returns table (aplica boolean, gracia_hasta timestamptz, llegada_en timestamptz, a_bordo_en timestamptz,
               cobro_desde timestamptz, tarifa_min integer, minutos integer, monto integer, ahora timestamptz)
language sql stable security definer set search_path to 'public'
as $$
  select x.* from reservas r, lateral espera_calculo(r.id) x
  where r.token_seguimiento = p_token and r.eliminada_en is null
$$;
grant execute on function public.ver_espera_publica(uuid) to anon, authenticated;

-- Para la app del conductor (solo sus servicios) y el equipo
create or replace function public.ver_espera(p_reserva uuid)
returns table (aplica boolean, gracia_hasta timestamptz, llegada_en timestamptz, a_bordo_en timestamptz,
               cobro_desde timestamptz, tarifa_min integer, minutos integer, monto integer, ahora timestamptz)
language sql stable security definer set search_path to 'public'
as $$
  select x.* from reservas r, lateral espera_calculo(r.id) x
  where r.id = p_reserva
    and (r.conductor_id = auth.uid() or (r.empresa_id = mi_empresa() and es_staff()))
$$;
revoke all on function public.ver_espera(uuid) from public, anon;
grant execute on function public.ver_espera(uuid) to authenticated;

-- Al subir el pasajero, la espera cobrada queda como gasto de la reserva (entra en cobros y totales)
create or replace function public.registrar_cobro_espera()
returns trigger language plpgsql security definer set search_path to 'public'
as $$
declare x record;
begin
  if new.estado = 'a_bordo' and old.estado is distinct from 'a_bordo' then
    select * into x from espera_calculo(new.id);
    delete from reserva_gastos where reserva_id = new.id and tipo = 'espera';
    if x.aplica and x.monto > 0 then
      insert into reserva_gastos (empresa_id, reserva_id, tipo, cantidad, monto, descripcion, creado_por)
      values (new.empresa_id, new.id, 'espera', 1, x.monto,
              'Espera ' || x.minutos || ' min x $' || x.tarifa_min || ' (desde ' ||
              to_char(x.cobro_desde at time zone 'America/Santiago', 'HH24:MI') || ')', auth.uid());
    end if;
  end if;
  return new;
end $$;

drop trigger if exists reservas_zz_cobro_espera on public.reservas;
create trigger reservas_zz_cobro_espera after update on public.reservas
  for each row execute function public.registrar_cobro_espera();
