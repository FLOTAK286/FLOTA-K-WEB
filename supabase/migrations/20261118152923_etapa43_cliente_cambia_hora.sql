-- Etapa 43: el cliente puede cambiar la fecha u hora de su reserva desde el portal (/empresa) o la app (/app),
-- hasta 2 horas antes del retiro (como dicen los Términos). Al conductor asignado le llega "Servicio modificado"
-- (etapa 38) y a Operaciones "🕒 Cliente cambió la hora".

-- Aviso a Operaciones (se agrega el cambio de hora hecho por alguien fuera del equipo)
create or replace function avisar_equipo_reserva()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_det text; v_quien text; v_cond text;
begin
  if new.eliminada_en is not null then return new; end if;
  v_det := to_char(new.fecha_hora at time zone 'America/Santiago', 'DD/MM HH24:MI') || ' · ' ||
           coalesce(new.nombre_pasajero, 'Pasajero') || ': ' || left(coalesce(new.origen, ''), 80) || ' → ' || left(coalesce(new.destino, ''), 80);
  if tg_op = 'INSERT' then
    select case when es_staff() then 'Agendada por ' || coalesce(nombre, 'el equipo') else 'Agendada por ' || coalesce(nombre, 'el cliente') end
      into v_quien from perfiles where id = auth.uid();
    insert into avisos_equipo (empresa_id, reserva_id, tipo, titulo, texto, autor_id)
    values (new.empresa_id, new.id, 'nueva', '📅 Reserva nueva', v_det || '. ' || coalesce(v_quien, 'Agendada desde la web o el portal'), auth.uid());
    return new;
  end if;
  if new.estado = 'cancelada' and old.estado <> 'cancelada' and not es_staff() then
    insert into avisos_equipo (empresa_id, reserva_id, tipo, titulo, texto, autor_id)
    values (new.empresa_id, new.id, 'cancelada', '❌ Reserva cancelada por el cliente', v_det, auth.uid());
  end if;
  if new.fecha_hora is distinct from old.fecha_hora and not es_staff() and new.estado not in ('cancelada', 'finalizada') then
    insert into avisos_equipo (empresa_id, reserva_id, tipo, titulo, texto, autor_id)
    values (new.empresa_id, new.id, 'cambio_hora', '🕒 Cliente cambió la hora',
            'Nueva hora: ' || v_det || ' (antes: ' || to_char(old.fecha_hora at time zone 'America/Santiago', 'DD/MM HH24:MI') || ')', auth.uid());
  end if;
  if new.conductor_respuesta = 'rechazado' and old.conductor_respuesta is distinct from 'rechazado' then
    select coalesce(nombre, 'El conductor') into v_cond from perfiles where id = new.conductor_id;
    insert into avisos_equipo (empresa_id, reserva_id, tipo, titulo, texto, autor_id)
    values (new.empresa_id, new.id, 'rechazo', '⚠️ ' || coalesce(v_cond, 'El conductor') || ' no puede', 'Reasigne este servicio. ' || v_det, auth.uid());
  end if;
  if old.en_bolsa and new.conductor_id is not null and old.conductor_id is null and new.conductor_id = auth.uid() then
    select coalesce(nombre, 'Un conductor') into v_cond from perfiles where id = new.conductor_id;
    insert into avisos_equipo (empresa_id, reserva_id, tipo, titulo, texto, autor_id)
    values (new.empresa_id, new.id, 'tomada', '✅ ' || coalesce(v_cond, 'Un conductor') || ' tomó una reserva', v_det, auth.uid());
  end if;
  return new;
end $$;

-- Reglas comunes del cambio de hora hecho por el cliente (uso interno)
create or replace function cambiar_hora_cliente(p_reserva uuid, p_fecha_hora timestamptz, p_quien text)
returns timestamptz language plpgsql security definer set search_path = public as $$
declare r reservas;
begin
  select * into r from reservas where id = p_reserva for update;
  if r.estado not in ('recibida', 'confirmada', 'asignada') then raise exception 'Esta reserva ya no se puede cambiar desde aquí'; end if;
  if r.fecha_hora <= now() + interval '2 hours' then
    raise exception 'Faltan menos de 2 horas: para cambiar la hora, escríbanos por WhatsApp al +56 9 2227 5399';
  end if;
  if p_fecha_hora is null or p_fecha_hora < now() + interval '2 hours' then
    raise exception 'La nueva hora debe ser al menos 2 horas desde ahora. Para algo más próximo, escríbanos por WhatsApp al +56 9 2227 5399';
  end if;
  if p_fecha_hora > now() + interval '365 days' then raise exception 'La fecha es demasiado lejana'; end if;
  if p_fecha_hora = r.fecha_hora then raise exception 'Es la misma hora que ya tenía'; end if;
  update reservas set fecha_hora = p_fecha_hora where id = r.id;
  insert into reserva_eventos (reserva_id, estado, nota, usuario_id)
  values (r.id, r.estado, left('Hora cambiada por ' || p_quien || ': ' ||
    to_char(r.fecha_hora at time zone 'America/Santiago', 'DD/MM HH24:MI') || ' → ' ||
    to_char(p_fecha_hora at time zone 'America/Santiago', 'DD/MM HH24:MI'), 1000), auth.uid());
  return p_fecha_hora;
end $$;
revoke execute on function cambiar_hora_cliente(uuid, timestamptz, text) from public, anon, authenticated;

-- Portal (/empresa): mismas personas que pueden cancelar
create or replace function convenio_cambiar_hora(p_reserva uuid, p_fecha_hora timestamptz)
returns timestamptz language plpgsql security definer set search_path = public as $$
declare yo convenio_usuarios; r reservas;
begin
  yo := convenio_yo();
  if yo.id is null then raise exception 'Sin permiso'; end if;
  select * into r from reservas where id = p_reserva and eliminada_en is null
    and (cuenta_corporativa_id = yo.cuenta_id or (cuenta_corporativa_id is null and yo.cliente_id is not null and cliente_id = yo.cliente_id));
  if r.id is null or (r.cuenta_corporativa_id is not null and yo.rol <> 'encargado' and r.cliente_id is distinct from yo.cliente_id) then
    raise exception 'Reserva no encontrada';
  end if;
  return cambiar_hora_cliente(r.id, p_fecha_hora, yo.nombre || ' (portal)');
end $$;
revoke execute on function convenio_cambiar_hora(uuid, timestamptz) from public, anon;
grant execute on function convenio_cambiar_hora(uuid, timestamptz) to authenticated;

-- App del pasajero (/app): sus viajes particulares
create or replace function pasajero_cambiar_hora(p_reserva uuid, p_fecha_hora timestamptz)
returns timestamptz language plpgsql security definer set search_path = public as $$
declare r reservas; v_cli uuid;
begin
  v_cli := pasajero_cliente();
  select * into r from reservas where id = p_reserva and cliente_id = v_cli and eliminada_en is null;
  if r.id is null then raise exception 'Reserva no encontrada'; end if;
  if r.cuenta_corporativa_id is not null then raise exception 'Este viaje es de su empresa: cámbielo en el portal de empresas'; end if;
  return cambiar_hora_cliente(r.id, p_fecha_hora, coalesce(r.nombre_pasajero, 'el pasajero') || ' (app)');
end $$;
revoke execute on function pasajero_cambiar_hora(uuid, timestamptz) from public, anon;
grant execute on function pasajero_cambiar_hora(uuid, timestamptz) to authenticated;
