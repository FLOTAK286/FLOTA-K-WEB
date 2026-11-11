-- Etapa 21: bolsa de servicios. El despachador libera una reserva y los conductores la ven en su app;
-- el primero que la toma se la queda (la base de datos garantiza que solo uno pueda tomarla).
alter table reservas add column if not exists en_bolsa boolean not null default false;
alter table reservas add column if not exists bolsa_desde timestamptz;
create index if not exists reservas_en_bolsa on reservas (empresa_id, fecha_hora) where en_bolsa;

-- Si la reserva queda asignada, derivada, cancelada, eliminada o en curso, sale sola de la bolsa.
create or replace function bolsa_limpiar() returns trigger language plpgsql set search_path = public as $$
begin
  if new.en_bolsa and (new.conductor_id is not null or new.derivado_a is not null or new.eliminada_en is not null
      or new.estado not in ('recibida', 'confirmada', 'asignada')) then
    new.en_bolsa := false;
  end if;
  return new;
end $$;
create trigger reservas_bolsa_limpiar before update on reservas for each row execute function bolsa_limpiar();

-- Despachador: liberar a la bolsa (quita al conductor que tuviera) o retirar de la bolsa.
create or replace function liberar_a_bolsa(p_reserva uuid, p_liberar boolean default true)
returns void language plpgsql security definer set search_path = public as $$
declare r reservas%rowtype;
begin
  if not es_staff() then raise exception 'Sin permiso'; end if;
  select * into r from reservas where id = p_reserva and empresa_id = mi_empresa() for update;
  if not found then raise exception 'Reserva no encontrada'; end if;
  if not p_liberar then
    update reservas set en_bolsa = false, bolsa_desde = null where id = r.id;
    insert into reserva_eventos (reserva_id, estado, nota, usuario_id) values (r.id, r.estado, 'Retirada de la bolsa de servicios', auth.uid());
    return;
  end if;
  if r.estado not in ('confirmada', 'asignada') then raise exception 'Solo se pueden liberar reservas confirmadas que aún no empiezan'; end if;
  if r.fecha_hora < now() then raise exception 'El servicio ya pasó'; end if;
  update reservas set conductor_id = null, vehiculo_id = null, derivado_a = null, costo_partner = null, conductor_respuesta = null,
         estado = 'confirmada', en_bolsa = true, bolsa_desde = now() where id = r.id;
  if r.estado <> 'confirmada' then  -- el cambio de estado ya dejó una nota en el historial: se le pone el motivo
    update reserva_eventos set nota = 'Liberada a la bolsa de servicios' where id = (select max(id) from reserva_eventos where reserva_id = r.id);
  else
    insert into reserva_eventos (reserva_id, estado, nota, usuario_id) values (r.id, 'confirmada', 'Liberada a la bolsa de servicios', auth.uid());
  end if;
end $$;

-- Conductor: servicios disponibles en la bolsa (sin datos del pasajero ni dirección exacta).
create or replace function bolsa_servicios()
returns table (o_id uuid, o_codigo text, o_fecha_hora timestamptz, o_tipo_servicio text, o_vehiculo text, o_zona_origen text, o_zona_destino text,
               o_pasajeros int, o_maletas int, o_vuelo text, o_valor int, o_duracion int, o_sirve boolean, o_choque boolean, o_desde timestamptz)
language sql stable security definer set search_path = public as $$
  with yo as (select p.id, p.empresa_id from perfiles p where p.id = auth.uid() and p.activo and (p.conduce or p.rol = 'conductor')),
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
  order by r.fecha_hora
  limit 200
$$;

-- Conductor: tomar un servicio de la bolsa. Solo uno puede tomarlo: la actualización exige que siga libre.
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
  if (coalesce(r.vehiculo, 'auto') = 'van' and v_veh.categoria <> 'van') or (r.vehiculo = 'suv' and v_veh.categoria not in ('suv', 'van')) then
    raise exception 'Este servicio pide %: su vehículo no corresponde', case r.vehiculo when 'van' then 'van' else 'SUV o van' end;
  end if;
  if exists (select 1 from reservas o where o.conductor_id = v_yo.id and o.estado not in ('cancelada', 'finalizada')
             and o.fecha_hora < r.fecha_hora + make_interval(mins => coalesce(r.duracion_min, 90) + 15)
             and r.fecha_hora < o.fecha_hora + make_interval(mins => coalesce(o.duracion_min, 90) + 15)) then
    raise exception 'Se le cruza con otro servicio suyo a esa hora';
  end if;
  -- Paso clave: solo se actualiza si sigue en la bolsa y sin conductor (si dos lo intentan a la vez, gana uno)
  update reservas set conductor_id = v_yo.id, vehiculo_id = v_veh.id, conductor_respuesta = 'aceptado', respuesta_en = now(),
         en_bolsa = false, bolsa_desde = null
   where id = r.id and en_bolsa and conductor_id is null and estado in ('recibida', 'confirmada', 'asignada') and fecha_hora > now()
   returning id into v_id;
  if v_id is null then raise exception 'Otro conductor ya tomó este servicio'; end if;
  -- (al cambiar el conductor, otra regla borra la respuesta: se marca como aceptado en un segundo paso)
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

revoke execute on function liberar_a_bolsa(uuid, boolean) from public, anon;
revoke execute on function bolsa_servicios() from public, anon;
revoke execute on function conductor_tomar_reserva(uuid) from public, anon;
grant execute on function liberar_a_bolsa(uuid, boolean) to authenticated;
grant execute on function bolsa_servicios() to authenticated;
grant execute on function conductor_tomar_reserva(uuid) to authenticated;
