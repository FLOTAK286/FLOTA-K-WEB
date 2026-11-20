-- Etapa 54: requisitos al publicar en Reservas para conductores. El despachador elige qué categorías de vehículo pueden
-- tomarla, si exige vehículo corporativo y una calificación mínima (promedio de los últimos 90 días). Solo la ven y la
-- pueden tomar los conductores que cumplen.
alter table reservas add column if not exists bolsa_categorias text[];
alter table reservas add column if not exists bolsa_corporativo boolean not null default false;
alter table reservas add column if not exists bolsa_calif_min numeric(3,2) check (bolsa_calif_min between 1 and 5);
alter table reservas add column if not exists bolsa_sin_calif boolean not null default false;

-- ¿El conductor (con su vehículo habitual) cumple los requisitos de esta reserva publicada?
create or replace function cumple_requisitos_bolsa(r reservas, p_conductor uuid)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare v vehiculos; v_n int; v_prom numeric;
begin
  select * into v from vehiculos where conductor_habitual = p_conductor and activo order by creado_en limit 1;
  if r.bolsa_categorias is not null and cardinality(r.bolsa_categorias) > 0 and (v.id is null or not v.categoria = any (r.bolsa_categorias)) then
    return false;
  end if;
  if (r.bolsa_corporativo or r.cuenta_corporativa_id is not null) and not vehiculo_decreto80_ok(v.id) then return false; end if;
  if r.bolsa_calif_min is not null then
    select count(*), avg(estrellas) into v_n, v_prom from calificaciones
     where conductor_id = p_conductor and autor = 'pasajero' and creado_en > now() - interval '90 days';
    if v_n = 0 then return r.bolsa_sin_calif; end if;
    if round(v_prom, 2) < r.bolsa_calif_min then return false; end if;
  end if;
  return true;
end $$;
revoke execute on function cumple_requisitos_bolsa(reservas, uuid) from public, anon;
grant execute on function cumple_requisitos_bolsa(reservas, uuid) to authenticated;

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
    and cumple_requisitos_bolsa(r, yo.id)
  order by r.fecha_hora
  limit 200
$$;

-- Tomar: también exige los requisitos
do $$
declare f text;
begin
  f := pg_get_functiondef('conductor_tomar_reserva'::regproc);
  if position('  if r.cuenta_corporativa_id is not null and not vehiculo_decreto80_ok(v_veh.id) then' in f) = 0 then
    raise exception 'conductor_tomar_reserva cambió: revisar la migración';
  end if;
  execute replace(f, '  if r.cuenta_corporativa_id is not null and not vehiculo_decreto80_ok(v_veh.id) then',
    '  if not cumple_requisitos_bolsa(r, v_yo.id) and not (r.cuenta_corporativa_id is not null and not vehiculo_decreto80_ok(v_veh.id)) then
    raise exception ''Este servicio tiene requisitos (tipo de vehículo, vehículo corporativo o calificación mínima) que su perfil no cumple'';
  end if;
  if r.cuenta_corporativa_id is not null and not vehiculo_decreto80_ok(v_veh.id) then');
end $$;

-- Al publicar de nuevo (también en grupo) se parte sin requisitos
do $$
declare f text;
begin
  f := pg_get_functiondef('liberar_a_bolsa(uuid, boolean)'::regprocedure);
  if position('estado = ''confirmada'', en_bolsa = true, bolsa_desde = now() where id = r.id;' in f) = 0 then
    raise exception 'liberar_a_bolsa cambió: revisar la migración';
  end if;
  execute replace(f, 'estado = ''confirmada'', en_bolsa = true, bolsa_desde = now() where id = r.id;',
    'estado = ''confirmada'', en_bolsa = true, bolsa_desde = now(),
         bolsa_categorias = null, bolsa_corporativo = false, bolsa_calif_min = null, bolsa_sin_calif = false where id = r.id;');
end $$;

-- Publicar con bono y requisitos (panel)
create or replace function liberar_a_bolsa_requisitos(p_reserva uuid, p_bono integer, p_categorias text[], p_corporativo boolean,
                                                       p_calif_min numeric, p_sin_calif boolean)
returns void language plpgsql security definer set search_path = public as $$
declare v_cats text[]; v_txt text;
begin
  perform liberar_a_bolsa_bono(p_reserva, p_bono);
  v_cats := nullif(array(select distinct c from unnest(coalesce(p_categorias, '{}'::text[])) c
                         where c in ('taxi_basico', 'taxi_turismo', 'taxi_ejecutivo', 'suv', 'van', 'particular_sedan', 'particular_suv', 'particular_vip')), '{}');
  if p_calif_min is not null and (p_calif_min < 1 or p_calif_min > 5) then raise exception 'Calificación mínima entre 1 y 5'; end if;
  update reservas set bolsa_categorias = v_cats, bolsa_corporativo = coalesce(p_corporativo, false),
         bolsa_calif_min = p_calif_min, bolsa_sin_calif = coalesce(p_sin_calif, false)
   where id = p_reserva and empresa_id = mi_empresa();
  v_txt := concat_ws(' · ',
    case when v_cats is not null then 'categorías: ' || array_to_string(v_cats, ', ') end,
    case when coalesce(p_corporativo, false) then 'solo corporativos' end,
    case when p_calif_min is not null then 'calificación mínima ' || replace(p_calif_min::text, '.', ',')
         || case when coalesce(p_sin_calif, false) then ' (o sin calificaciones)' else '' end end);
  if v_txt <> '' then
    update reserva_eventos set nota = nota || ' · requisitos: ' || v_txt where id = (select max(id) from reserva_eventos where reserva_id = p_reserva);
  end if;
end $$;
revoke execute on function liberar_a_bolsa_requisitos(uuid, integer, text[], boolean, numeric, boolean) from public, anon;
grant execute on function liberar_a_bolsa_requisitos(uuid, integer, text[], boolean, numeric, boolean) to authenticated;
