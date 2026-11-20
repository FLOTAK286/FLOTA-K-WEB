-- Etapa 55: Reservas para conductores más transparentes. Todos ven las reservas publicadas (respetando la prioridad
-- por calificación), con la categoría y los requisitos; quien no cumple la ve pero no la puede tomar y ve el motivo.
create or replace function categoria_nombre(p text)
returns text language sql immutable set search_path = public as $$
  select case p when 'taxi_basico' then 'Taxi básico' when 'taxi_turismo' then 'Taxi turismo' when 'taxi_ejecutivo' then 'Taxi ejecutivo'
    when 'suv' then 'SUV' when 'van' then 'Van' when 'particular_sedan' then 'Particular sedán' when 'particular_suv' then 'Particular SUV'
    when 'particular_vip' then 'Particular VIP' else p end
$$;

-- Motivo por el que el conductor no cumple los requisitos (null si cumple)
create or replace function motivo_requisitos_bolsa(r reservas, p_conductor uuid)
returns text language plpgsql stable security definer set search_path = public as $$
declare v vehiculos; v_n int; v_prom numeric; m text[] := '{}';
begin
  select * into v from vehiculos where conductor_habitual = p_conductor and activo order by creado_en limit 1;
  if r.bolsa_categorias is not null and cardinality(r.bolsa_categorias) > 0 and (v.id is null or not v.categoria = any (r.bolsa_categorias)) then
    m := m || ('Pide ' || (select string_agg(categoria_nombre(c), ' o ') from unnest(r.bolsa_categorias) c)
               || case when v.id is null then ' y usted no tiene vehículo registrado' else ' y su vehículo es ' || categoria_nombre(v.categoria) end);
  end if;
  if (r.bolsa_corporativo or r.cuenta_corporativa_id is not null) and not vehiculo_decreto80_ok(v.id) then
    m := m || 'Pide vehículo corporativo (con autorización ministerial vigente)'::text;
  end if;
  if r.bolsa_calif_min is not null then
    select count(*), avg(estrellas) into v_n, v_prom from calificaciones
     where conductor_id = p_conductor and autor = 'pasajero' and creado_en > now() - interval '90 days';
    if v_n = 0 and not r.bolsa_sin_calif then
      m := m || ('Pide calificación de ' || replace(to_char(r.bolsa_calif_min, 'FM0.00'), '.', ',') || '★ o más y usted aún no tiene calificaciones');
    elsif v_n > 0 and round(v_prom, 2) < r.bolsa_calif_min then
      m := m || ('Pide calificación de ' || replace(to_char(r.bolsa_calif_min, 'FM0.00'), '.', ',') || '★ o más y la suya es '
                 || replace(to_char(round(v_prom, 2), 'FM0.00'), '.', ',') || '★');
    end if;
  end if;
  return nullif(array_to_string(m, '. '), '');
end $$;
revoke execute on function motivo_requisitos_bolsa(reservas, uuid) from public, anon;
grant execute on function motivo_requisitos_bolsa(reservas, uuid) to authenticated;

create or replace function cumple_requisitos_bolsa(r reservas, p_conductor uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select motivo_requisitos_bolsa(r, p_conductor) is null
$$;

-- La lista ya no esconde a quien no cumple (tomar sigue bloqueado en conductor_tomar_reserva)
create or replace function bolsa_servicios()
returns table(o_id uuid, o_codigo text, o_fecha_hora timestamptz, o_tipo_servicio text, o_vehiculo text, o_zona_origen text, o_zona_destino text,
              o_pasajeros integer, o_maletas integer, o_vuelo text, o_valor integer, o_duracion integer, o_sirve boolean, o_choque boolean, o_desde timestamptz)
language sql stable security definer set search_path = public as $$
  with yo as (select p.id, p.empresa_id, nivel_bolsa(p.id) as nivel from perfiles p where p.id = auth.uid() and p.activo and (p.conduce or p.rol = 'conductor')),
       mi_veh as (select v.id, v.categoria from vehiculos v, yo where v.conductor_habitual = yo.id and v.activo order by v.creado_en limit 1)
  select r.id, r.codigo, r.fecha_hora, r.tipo_servicio, coalesce(r.vehiculo, 'auto'),
         case when array_length(string_to_array(r.origen, ','), 1) > 1 then trim(array_to_string((string_to_array(r.origen, ','))[2:3], ',')) else r.origen end,
         case when array_length(string_to_array(r.destino, ','), 1) > 1 then trim(array_to_string((string_to_array(r.destino, ','))[2:3], ',')) else r.destino end,
         r.pasajeros, r.maletas, r.vuelo,
         case when r.tipo_cobro = 'taximetro' then null else coalesce(r.precio, r.tarifa_web) end,
         coalesce(r.duracion_min, 90),
         (case coalesce(r.vehiculo, 'auto') when 'van' then (select categoria from mi_veh) = 'van'
              when 'suv' then (select categoria from mi_veh) in ('suv', 'van', 'particular_suv') else exists (select 1 from mi_veh) end),
         exists (select 1 from reservas o, yo where o.conductor_id = yo.id and o.estado not in ('cancelada', 'finalizada')
                 and o.fecha_hora < r.fecha_hora + make_interval(mins => coalesce(r.duracion_min, 90) + 15)
                 and r.fecha_hora < o.fecha_hora + make_interval(mins => coalesce(o.duracion_min, 90) + 15)),
         r.bolsa_desde
  from reservas r, yo
  where r.empresa_id = yo.empresa_id and r.en_bolsa and r.conductor_id is null and r.eliminada_en is null
    and r.estado in ('recibida', 'confirmada', 'asignada') and r.fecha_hora > now()
    and bolsa_visible(r, yo.nivel)
  order by r.fecha_hora
  limit 200
$$;

-- Para la app: v3 + categorías pedidas, requisitos y motivo si no cumple
create or replace function bolsa_servicios_v4()
returns table(o_id uuid, o_codigo text, o_fecha_hora timestamptz, o_tipo_servicio text, o_vehiculo text, o_zona_origen text, o_zona_destino text,
              o_pasajeros integer, o_maletas integer, o_vuelo text, o_valor integer, o_duracion integer, o_sirve boolean, o_choque boolean,
              o_desde timestamptz, o_bono integer, o_km numeric, o_exclusiva boolean,
              o_categorias text, o_corporativo boolean, o_calif_min numeric, o_motivo text)
language sql stable security definer set search_path = public as $$
  select v.*,
         (select string_agg(categoria_nombre(c), ' · ') from unnest(r.bolsa_categorias) c),
         (r.bolsa_corporativo or r.cuenta_corporativa_id is not null),
         r.bolsa_calif_min,
         motivo_requisitos_bolsa(r, auth.uid())
  from bolsa_servicios_v3() v join reservas r on r.id = v.o_id
$$;
revoke execute on function bolsa_servicios_v4() from public, anon;
grant execute on function bolsa_servicios_v4() to authenticated;

-- Tomar: el mensaje de error ahora dice el motivo exacto
do $$
declare f text;
begin
  f := pg_get_functiondef('conductor_tomar_reserva'::regproc);
  if position('  if not cumple_requisitos_bolsa(r, v_yo.id) and not (r.cuenta_corporativa_id is not null and not vehiculo_decreto80_ok(v_veh.id)) then
    raise exception ''Este servicio tiene requisitos (tipo de vehículo, vehículo corporativo o calificación mínima) que su perfil no cumple'';
  end if;' in f) = 0 then raise exception 'conductor_tomar_reserva cambió: revisar la migración'; end if;
  execute replace(f, '  if not cumple_requisitos_bolsa(r, v_yo.id) and not (r.cuenta_corporativa_id is not null and not vehiculo_decreto80_ok(v_veh.id)) then
    raise exception ''Este servicio tiene requisitos (tipo de vehículo, vehículo corporativo o calificación mínima) que su perfil no cumple'';
  end if;', '  if motivo_requisitos_bolsa(r, v_yo.id) is not null then
    raise exception ''No puede tomar este servicio: %'', motivo_requisitos_bolsa(r, v_yo.id);
  end if;');
end $$;
