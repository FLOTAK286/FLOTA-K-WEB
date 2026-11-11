-- Etapa 24: la bolsa la libera el despachador (la automática queda apagada salvo que se active a propósito)
-- y la prioridad en la bolsa la tienen los móviles de Flota-K (vehículo propio) y los conductores destacados.
alter table empresas add column if not exists bolsa_auto_activa boolean not null default false;

create or replace function bolsa_automatica() returns int language plpgsql security definer set search_path = public as $$
declare n int := 0; r record;
begin
  for r in select res.id, e.bolsa_auto_horas h from reservas res join empresas e on e.id = res.empresa_id
    where e.bolsa_auto_activa and e.bolsa_auto_horas is not null and res.estado = 'confirmada' and res.conductor_id is null and res.derivado_a is null
      and not res.en_bolsa and not res.bolsa_auto_hecha and res.eliminada_en is null and res.creada_en < now() - interval '15 minutes'
      and res.fecha_hora > now() + interval '1 hour' and res.fecha_hora <= now() + make_interval(hours => e.bolsa_auto_horas)
    for update of res skip locked
  loop
    update reservas set en_bolsa = true, bolsa_desde = now(), bolsa_auto_hecha = true where id = r.id;
    insert into reserva_eventos (reserva_id, estado, nota) values (r.id, 'confirmada', 'Liberada automáticamente a la bolsa (sin conductor a ' || r.h || ' h o menos del servicio)');
    n := n + 1;
  end loop;
  return n;
end $$;

-- Prioridad: móvil de Flota-K (conduce un vehículo propio) o conductor destacado (4,5★ o más).
create or replace function conductor_prioritario(p_conductor uuid) returns boolean language sql stable security definer set search_path = public as $$
  select conductor_destacado(p_conductor) or exists (select 1 from vehiculos where conductor_habitual = p_conductor and activo and propio)
$$;
revoke execute on function conductor_prioritario(uuid) from public, anon;

-- Ventana de prioridad: 10 minutos; 5 minutos si el servicio es dentro de las próximas 2 horas (servicios de momento).
create or replace function bolsa_exclusiva(r reservas) returns boolean language sql stable set search_path = public as $$
  select r.bolsa_desde is not null
     and r.bolsa_desde > now() - case when r.fecha_hora > now() + interval '2 hours' then interval '10 minutes' else interval '5 minutes' end
$$;

create or replace function bolsa_servicios()
returns table (o_id uuid, o_codigo text, o_fecha_hora timestamptz, o_tipo_servicio text, o_vehiculo text, o_zona_origen text, o_zona_destino text,
               o_pasajeros int, o_maletas int, o_vuelo text, o_valor int, o_duracion int, o_sirve boolean, o_choque boolean, o_desde timestamptz)
language sql stable security definer set search_path = public as $$
  with yo as (select p.id, p.empresa_id, conductor_prioritario(p.id) as dest from perfiles p where p.id = auth.uid() and p.activo and (p.conduce or p.rol = 'conductor')),
       mi_veh as (select v.categoria from vehiculos v, yo where v.conductor_habitual = yo.id and v.activo order by v.creado_en limit 1)
  select r.id, r.codigo, r.fecha_hora, r.tipo_servicio, coalesce(r.vehiculo, 'auto'),
         case when array_length(string_to_array(r.origen, ','), 1) > 1 then trim(array_to_string((string_to_array(r.origen, ','))[2:3], ',')) else r.origen end,
         case when array_length(string_to_array(r.destino, ','), 1) > 1 then trim(array_to_string((string_to_array(r.destino, ','))[2:3], ',')) else r.destino end,
         r.pasajeros, r.maletas, r.vuelo,
         case when r.tipo_cobro = 'taximetro' then null else coalesce(r.precio, r.tarifa_web) end,
         coalesce(r.duracion_min, 90),
         case coalesce(r.vehiculo, 'auto') when 'van' then (select categoria from mi_veh) = 'van'
              when 'suv' then (select categoria from mi_veh) in ('suv', 'van') else exists (select 1 from mi_veh) end,
         exists (select 1 from reservas o, yo where o.conductor_id = yo.id and o.estado not in ('cancelada', 'finalizada')
                 and o.fecha_hora < r.fecha_hora + make_interval(mins => coalesce(r.duracion_min, 90) + 15)
                 and r.fecha_hora < o.fecha_hora + make_interval(mins => coalesce(o.duracion_min, 90) + 15)),
         r.bolsa_desde
  from reservas r, yo
  where r.empresa_id = yo.empresa_id and r.en_bolsa and r.conductor_id is null and r.eliminada_en is null
    and r.estado in ('recibida', 'confirmada', 'asignada') and r.fecha_hora > now()
    and (yo.dest or not bolsa_exclusiva(r))
  order by r.fecha_hora
  limit 200
$$;

create or replace function conductor_tomar_reserva(p_reserva uuid)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_yo perfiles%rowtype; v_veh vehiculos%rowtype; r reservas%rowtype; v_id uuid; v_nota text;
begin
  select * into v_yo from perfiles where id = auth.uid() and activo and (conduce or rol = 'conductor');
  if not found then raise exception 'Solo los conductores pueden tomar servicios'; end if;
  select * into v_veh from vehiculos where conductor_habitual = v_yo.id and activo order by creado_en limit 1;
  if not found then raise exception 'Primero registre su vehículo (Perfil → Mi vehículo)'; end if;
  select * into r from reservas where id = p_reserva and empresa_id = v_yo.empresa_id;
  if not found or not r.en_bolsa or r.conductor_id is not null then raise exception 'Otro conductor ya tomó este servicio'; end if;
  if bolsa_exclusiva(r) and not conductor_prioritario(v_yo.id) then
    raise exception 'Por unos minutos este servicio es solo para móviles de Flota-K y conductores destacados. Luego quedará disponible para todos.';
  end if;
  if (coalesce(r.vehiculo, 'auto') = 'van' and v_veh.categoria <> 'van') or (r.vehiculo = 'suv' and v_veh.categoria not in ('suv', 'van')) then
    raise exception 'Este servicio pide %: su vehículo no corresponde', case r.vehiculo when 'van' then 'van' else 'SUV o van' end;
  end if;
  if exists (select 1 from reservas o where o.conductor_id = v_yo.id and o.estado not in ('cancelada', 'finalizada')
             and o.fecha_hora < r.fecha_hora + make_interval(mins => coalesce(r.duracion_min, 90) + 15)
             and r.fecha_hora < o.fecha_hora + make_interval(mins => coalesce(o.duracion_min, 90) + 15)) then
    raise exception 'Se le cruza con otro servicio suyo a esa hora';
  end if;
  -- Paso clave: solo se actualiza si sigue en la bolsa y sin conductor (si dos lo intentan a la vez, gana uno)
  update reservas set conductor_id = v_yo.id, vehiculo_id = v_veh.id, en_bolsa = false, bolsa_desde = null
   where id = r.id and en_bolsa and conductor_id is null and estado in ('recibida', 'confirmada', 'asignada') and fecha_hora > now()
   returning id into v_id;
  if v_id is null then raise exception 'Otro conductor ya tomó este servicio'; end if;
  update reservas set conductor_respuesta = 'aceptado', respuesta_en = now() where id = r.id;
  v_nota := 'Tomado desde la bolsa por ' || coalesce('Móvil ' || v_yo.movil || ' · ', '') || v_yo.nombre || ' · ' || v_veh.patente;
  if r.estado in ('recibida', 'confirmada') then
    update reservas set estado = 'asignada' where id = r.id;
    update reserva_eventos set nota = v_nota where id = (select max(id) from reserva_eventos where reserva_id = r.id);
  else
    insert into reserva_eventos (reserva_id, estado, nota, usuario_id) values (r.id, r.estado, v_nota, auth.uid());
  end if;
  return r.codigo;
end $$;
