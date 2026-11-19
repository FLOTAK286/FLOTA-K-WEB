-- Etapa 48: Operaciones también recibe un aviso cuando el conductor ACEPTA un servicio (el rechazo ya avisaba).
alter table avisos_equipo drop constraint if exists avisos_equipo_tipo_check;
alter table avisos_equipo add constraint avisos_equipo_tipo_check
  check (tipo in ('nueva', 'cancelada', 'rechazo', 'tomada', 'cambio_hora', 'acepto'));

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
    select coalesce(nombre, 'El conductor') into v_cond from perfiles where id = coalesce(new.conductor_id, old.conductor_id);
    insert into avisos_equipo (empresa_id, reserva_id, tipo, titulo, texto, autor_id)
    values (new.empresa_id, new.id, 'rechazo', '⚠️ ' || coalesce(v_cond, 'El conductor') || ' no puede', 'Reasigne este servicio. ' || v_det, auth.uid());
  end if;
  -- Aceptó el servicio que le asignaron (no cuando lo toma él mismo desde Reservas: eso avisa "tomó una reserva")
  if new.conductor_respuesta = 'aceptado' and old.conductor_respuesta is distinct from 'aceptado'
     and new.conductor_id is not null and old.conductor_id is not distinct from new.conductor_id then
    select coalesce(nombre, 'El conductor') into v_cond from perfiles where id = new.conductor_id;
    insert into avisos_equipo (empresa_id, reserva_id, tipo, titulo, texto, autor_id)
    values (new.empresa_id, new.id, 'acepto', '✅ ' || coalesce(v_cond, 'El conductor') || ' aceptó el servicio', v_det, auth.uid());
  end if;
  if old.en_bolsa and new.conductor_id is not null and old.conductor_id is null and new.conductor_id = auth.uid() then
    select coalesce(nombre, 'Un conductor') into v_cond from perfiles where id = new.conductor_id;
    insert into avisos_equipo (empresa_id, reserva_id, tipo, titulo, texto, autor_id)
    values (new.empresa_id, new.id, 'tomada', '✅ ' || coalesce(v_cond, 'Un conductor') || ' tomó una reserva', v_det, auth.uid());
  end if;
  return new;
end $$;
