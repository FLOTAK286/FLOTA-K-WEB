-- Etapa 75: cambiar o quitar el conductor de un servicio que ya estaba en curso.
-- Antes: si el servicio estaba "En camino" o "En el lugar" y la central quitaba y volvía a asignar al conductor,
-- el estado seguía "En el lugar" y la espera seguía contando desde la primera llegada (el servicio quedaba "pegado").
-- Ahora: al quitar o cambiar el conductor (o derivarlo) de un servicio en camino o en el lugar, el servicio vuelve a
-- "Asignada" (o "Confirmada" si queda sin conductor) y el conductor parte de nuevo. Con el pasajero a bordo no se permite.
-- La espera se cuenta desde la llegada posterior a la última asignación.

create or replace function public.asignar_reserva(p_reserva uuid, p_conductor uuid, p_vehiculo uuid default null::uuid,
                                                  p_derivado_a text default null::text, p_costo_partner integer default null::integer)
 returns void language plpgsql security definer set search_path to 'public' as $function$
declare
  v_emp uuid := mi_empresa();
  v_estado estado_reserva;
  v_cond_antes uuid;
  v_der_antes text;
  v_der text := nullif(trim(coalesce(p_derivado_a, '')), '');
  v_nombre text;
  v_nota text;
  v_veh uuid := p_vehiculo;
  v_reinicia boolean;
begin
  if not es_staff() then raise exception 'Sin permiso'; end if;
  select estado, conductor_id, derivado_a into v_estado, v_cond_antes, v_der_antes
    from reservas where id = p_reserva and empresa_id = v_emp for update;
  if not found then raise exception 'Reserva no encontrada'; end if;
  if p_conductor is not null and not exists (select 1 from perfiles where id = p_conductor and empresa_id = v_emp and activo) then
    raise exception 'Conductor no válido';
  end if;
  if v_veh is null and p_conductor is not null then
    select id into v_veh from vehiculos
      where empresa_id = v_emp and conductor_habitual = p_conductor and activo order by creado_en limit 1;
  end if;
  if v_veh is not null and not exists (select 1 from vehiculos where id = v_veh and empresa_id = v_emp) then
    raise exception 'Vehículo no válido';
  end if;

  v_reinicia := (p_conductor is distinct from v_cond_antes or v_der is distinct from v_der_antes);
  if v_reinicia and v_estado = 'a_bordo' then
    raise exception 'El pasajero ya está a bordo: no se puede cambiar el conductor. Finalice o cancele el servicio.';
  end if;

  update reservas set conductor_id = p_conductor, vehiculo_id = v_veh, derivado_a = v_der, costo_partner = p_costo_partner
   where id = p_reserva;

  select coalesce('Móvil ' || movil || ' · ', '') || nombre into v_nombre from perfiles where id = p_conductor;
  v_nota := case
    when v_der is not null then 'Derivado a ' || v_der
    when p_conductor is null then 'Sin conductor asignado'
    else 'Asignado a ' || v_nombre || coalesce(' · ' || (select patente from vehiculos where id = v_veh), '') end;

  -- Servicio en camino o en el lugar al que se le quita o cambia el conductor: vuelve a empezar
  if v_reinicia and v_estado in ('en_camino', 'en_lugar') then
    update reservas set estado = case when p_conductor is not null or v_der is not null then 'asignada' else 'confirmada' end::estado_reserva
     where id = p_reserva;
    update reserva_eventos set nota = v_nota || ' · el servicio vuelve a empezar (estaba ' ||
           case v_estado when 'en_camino' then 'en camino' else 'en el lugar' end || ')'
     where id = (select max(id) from reserva_eventos where reserva_id = p_reserva);
    return;
  end if;

  if p_conductor is not null or v_der is not null then
    if v_estado in ('recibida', 'confirmada') then
      update reservas set estado = 'asignada' where id = p_reserva;
      update reserva_eventos set nota = v_nota
        where id = (select max(id) from reserva_eventos where reserva_id = p_reserva);
      return;
    end if;
  end if;
  insert into reserva_eventos (reserva_id, estado, nota, usuario_id)
  values (p_reserva, (select estado from reservas where id = p_reserva), v_nota, auth.uid());
end $function$;

-- Espera: la llegada que cuenta es la primera "En el lugar" después de la última vez que el servicio volvió a
-- Asignada/Confirmada (si se reasignó, se cuenta desde la nueva llegada). En un servicio normal es la misma de siempre.
create or replace function public.espera_calculo(p_reserva uuid)
 returns table(aplica boolean, gracia_hasta timestamp with time zone, llegada_en timestamp with time zone, a_bordo_en timestamp with time zone,
               cobro_desde timestamp with time zone, tarifa_min integer, minutos integer, monto integer, ahora timestamp with time zone)
 language sql stable security definer set search_path to 'public' as $function$
  with r as (
    select r.*,
      (select max(e.creado_en) from reserva_eventos e where e.reserva_id = r.id and e.estado in ('recibida', 'confirmada', 'asignada')) as t_reinicio
    from reservas r where r.id = p_reserva
  ), r2 as (
    select r.*,
      (select min(e.creado_en) from reserva_eventos e where e.reserva_id = r.id and e.estado = 'en_lugar'
          and e.creado_en > coalesce(r.t_reinicio, '-infinity'::timestamptz)) as t_llegada,
      (select min(e.creado_en) from reserva_eventos e where e.reserva_id = r.id and e.estado = 'a_bordo'
          and e.creado_en > coalesce(r.t_reinicio, '-infinity'::timestamptz)) as t_abordo
    from r
  ), c as (
    select r2.*,
      (r2.tipo_servicio = 'punto_a_punto' and coalesce(r2.tipo_cobro, '') <> 'taximetro') as ap,
      r2.fecha_hora + interval '15 minutes' as gracia,
      case when r2.vehiculo in ('suv', 'van') then 270 else 180 end as tarifa,
      greatest(r2.fecha_hora + interval '15 minutes', r2.t_llegada) as desde
    from r2
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
$function$;
