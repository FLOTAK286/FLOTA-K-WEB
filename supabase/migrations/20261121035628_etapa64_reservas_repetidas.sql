-- Etapa 64: reservas que se repiten. Desde la ficha, el equipo repite una reserva los días de la semana elegidos hasta
-- una fecha (máx. 3 meses, máx. 60 copias), a la misma hora, con los mismos datos. Opcional: con el mismo conductor.
-- Las copias quedan ligadas por serie_id (para verlas o cancelarlas juntas).
alter table reservas add column if not exists serie_id uuid;

create or replace function repetir_reserva(p_reserva uuid, p_dias integer[], p_hasta date, p_mismo_conductor boolean default false)
returns integer language plpgsql security definer set search_path = public as $$
declare r reservas; v_serie uuid; v_hora time; d date; n int := 0; v_id uuid; v_hoy date := (now() at time zone 'America/Santiago')::date;
begin
  if not es_staff() then raise exception 'Sin permiso'; end if;
  select * into r from reservas where id = p_reserva and empresa_id = mi_empresa() and eliminada_en is null;
  if r.id is null then raise exception 'Reserva no encontrada'; end if;
  if p_dias is null or cardinality(p_dias) = 0 then raise exception 'Elija al menos un día de la semana'; end if;
  if p_hasta is null or p_hasta > v_hoy + 92 then raise exception 'Elija una fecha final dentro de los próximos 3 meses'; end if;
  v_serie := coalesce(r.serie_id, gen_random_uuid());
  update reservas set serie_id = v_serie where id = r.id and serie_id is null;
  v_hora := (r.fecha_hora at time zone 'America/Santiago')::time;
  for d in select g::date from generate_series(greatest(v_hoy, (r.fecha_hora at time zone 'America/Santiago')::date + 1), p_hasta, interval '1 day') g
            where extract(isodow from g)::int = any (p_dias) loop
    exit when n >= 60;
    if exists (select 1 from reservas x where x.serie_id = v_serie and x.eliminada_en is null and x.estado <> 'cancelada'
               and (x.fecha_hora at time zone 'America/Santiago')::date = d) then continue; end if;
    insert into reservas (empresa_id, cliente_id, nombre_pasajero, telefono, correo, origen, destino, origen_lat, origen_lng, destino_lat, destino_lng,
      paradas, pasajeros, maletas, tipo_servicio, vehiculo, canal, tipo_cobro, precio, tarifa_web, forma_pago, comentarios,
      cuenta_corporativa_id, centro_costo, solicitante_nombre, solicitante_telefono, solicitante_correo, retiro_detalle, duracion_min, km_ida,
      fecha_hora, estado, serie_id, conductor_id, vehiculo_id)
    values (r.empresa_id, r.cliente_id, r.nombre_pasajero, r.telefono, r.correo, r.origen, r.destino, r.origen_lat, r.origen_lng, r.destino_lat, r.destino_lng,
      coalesce(r.paradas, '[]'::jsonb), r.pasajeros, r.maletas, r.tipo_servicio, r.vehiculo, r.canal, r.tipo_cobro, r.precio, r.tarifa_web, r.forma_pago, r.comentarios,
      r.cuenta_corporativa_id, r.centro_costo, r.solicitante_nombre, r.solicitante_telefono, r.solicitante_correo, r.retiro_detalle, r.duracion_min, r.km_ida,
      (d + v_hora) at time zone 'America/Santiago',
      case when p_mismo_conductor and r.conductor_id is not null then 'asignada'::estado_reserva else 'confirmada'::estado_reserva end,
      v_serie, case when p_mismo_conductor then r.conductor_id end, case when p_mismo_conductor then r.vehiculo_id end)
    returning id into v_id;
    insert into reserva_eventos (reserva_id, estado, nota, usuario_id) values (v_id, 'confirmada', 'Creada al repetir ' || r.codigo, auth.uid());
    n := n + 1;
  end loop;
  if n > 0 then
    insert into reserva_eventos (reserva_id, estado, nota, usuario_id) values (r.id, r.estado, 'Repetida: ' || n || ' reserva(s) hasta el ' || to_char(p_hasta, 'DD/MM/YYYY'), auth.uid());
  end if;
  return n;
end $$;
revoke execute on function repetir_reserva(uuid, integer[], date, boolean) from public, anon;
grant execute on function repetir_reserva(uuid, integer[], date, boolean) to authenticated;

-- Cancelar las reservas futuras de una serie (las que aún no empiezan)
create or replace function cancelar_serie(p_reserva uuid)
returns integer language plpgsql security definer set search_path = public as $$
declare v_serie uuid; n int := 0; x record;
begin
  if not es_staff() then raise exception 'Sin permiso'; end if;
  select serie_id into v_serie from reservas where id = p_reserva and empresa_id = mi_empresa();
  if v_serie is null then raise exception 'Esta reserva no es parte de una serie'; end if;
  for x in select id from reservas where serie_id = v_serie and eliminada_en is null and estado in ('recibida', 'confirmada', 'asignada') and fecha_hora > now() loop
    perform cambiar_estado_reserva(x.id, 'cancelada', 'Serie cancelada');
    n := n + 1;
  end loop;
  return n;
end $$;
revoke execute on function cancelar_serie(uuid) from public, anon;
grant execute on function cancelar_serie(uuid) to authenticated;
