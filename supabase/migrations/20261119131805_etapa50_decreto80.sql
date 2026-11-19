-- Etapa 50: acreditación Decreto 80 por vehículo. Toda reserva de una empresa con convenio (cuenta_corporativa_id)
-- exige un vehículo con Decreto 80 vigente: en Reservas para conductores no se le ofrece a quien no lo tenga y no la puede tomar;
-- en el panel, al asignar, aparece una advertencia. En la inscripción el conductor indica si su vehículo lo tiene (el admin lo verifica).

alter table vehiculos add column if not exists decreto80 boolean not null default false;
alter table vehiculos add column if not exists decreto80_vence date;
alter table postulaciones_conductor add column if not exists dice_decreto80 boolean not null default false;

create or replace function vehiculo_decreto80_ok(p_veh uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select decreto80 and (decreto80_vence is null or decreto80_vence >= (now() at time zone 'America/Santiago')::date)
                     from vehiculos where id = p_veh), false)
$$;
revoke execute on function vehiculo_decreto80_ok(uuid) from public, anon;
grant execute on function vehiculo_decreto80_ok(uuid) to authenticated;

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
              when 'suv' then (select categoria from mi_veh) in ('suv', 'van', 'particular_suv') else exists (select 1 from mi_veh) end)
           and (r.cuenta_corporativa_id is null or coalesce(vehiculo_decreto80_ok((select id from mi_veh)), false)),
         exists (select 1 from reservas o, yo where o.conductor_id = yo.id and o.estado not in ('cancelada', 'finalizada')
                 and o.fecha_hora < r.fecha_hora + make_interval(mins => coalesce(r.duracion_min, 90) + 15)
                 and r.fecha_hora < o.fecha_hora + make_interval(mins => coalesce(o.duracion_min, 90) + 15)),
         r.bolsa_desde
  from reservas r, yo
  where r.empresa_id = yo.empresa_id and r.en_bolsa and r.conductor_id is null and r.eliminada_en is null
    and r.estado in ('recibida', 'confirmada', 'asignada') and r.fecha_hora > now()
    and bolsa_visible(r, yo.nivel)
    and (r.cuenta_corporativa_id is null or coalesce(vehiculo_decreto80_ok((select id from mi_veh)), false))
  order by r.fecha_hora
  limit 200
$$;

-- Tomar desde Reservas: también exige Decreto 80 vigente en servicios de empresas con convenio
do $$
begin
  execute replace(pg_get_functiondef('conductor_tomar_reserva'::regproc),
    '  if exists (select 1 from reservas o where o.conductor_id = v_yo.id',
    '  if r.cuenta_corporativa_id is not null and not vehiculo_decreto80_ok(v_veh.id) then
    raise exception ''Este servicio es de una empresa con convenio y exige un vehículo con Decreto 80 vigente'';
  end if;
  if exists (select 1 from reservas o where o.conductor_id = v_yo.id');
end $$;

-- Inscripción: guarda si dice tener Decreto 80 (solo informativo, el admin lo verifica y marca la casilla en Flota)
do $$
begin
  execute replace(replace(pg_get_functiondef('conductor_postular(uuid, text, text, jsonb)'::regprocedure),
    'anio, color, categoria)', 'anio, color, categoria, dice_decreto80)'),
    'end, v_cat);', 'end, v_cat, v_veh and coalesce((p_datos->>''decreto80'')::boolean, false));');
end $$;
