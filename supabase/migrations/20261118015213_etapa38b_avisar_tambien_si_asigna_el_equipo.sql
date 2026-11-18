-- Etapa 38b: el aviso se omitía cuando quien asigna es el mismo conductor (el dueño es admin y conductor).
-- Ahora solo se omite si el cambio lo hizo el conductor sin rol de equipo (tomar reserva, avanzar estado).
create or replace function avisar_conductor_reserva()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_det text; v_equipo boolean := es_staff();
begin
  if new.eliminada_en is not null then return new; end if;
  v_det := to_char(new.fecha_hora at time zone 'America/Santiago', 'DD/MM HH24:MI') || ' · ' ||
           coalesce(new.nombre_pasajero, 'Pasajero') || ': ' || left(coalesce(new.origen, ''), 80) || ' → ' || left(coalesce(new.destino, ''), 80);
  if tg_op = 'INSERT' then
    if new.conductor_id is not null and new.estado not in ('cancelada', 'finalizada') then
      insert into avisos_conductor (conductor_id, empresa_id, reserva_id, tipo, titulo, texto)
      values (new.conductor_id, new.empresa_id, new.id, 'nuevo', '🚗 Servicio nuevo', v_det);
    end if;
    return new;
  end if;
  if new.conductor_id is distinct from old.conductor_id then
    if old.conductor_id is not null and (v_equipo or old.conductor_id is distinct from auth.uid()) and old.estado not in ('cancelada', 'finalizada') then
      insert into avisos_conductor (conductor_id, empresa_id, reserva_id, tipo, titulo, texto)
      values (old.conductor_id, new.empresa_id, new.id, 'quitado', '↩️ Servicio quitado', 'La central le quitó este servicio. ' || v_det);
    end if;
    if new.conductor_id is not null and (v_equipo or new.conductor_id is distinct from auth.uid()) and new.estado not in ('cancelada', 'finalizada') then
      insert into avisos_conductor (conductor_id, empresa_id, reserva_id, tipo, titulo, texto)
      values (new.conductor_id, new.empresa_id, new.id, 'nuevo', '🚗 Servicio nuevo', v_det);
    end if;
  elsif new.conductor_id is not null and (v_equipo or new.conductor_id is distinct from auth.uid()) then
    if new.estado = 'cancelada' and old.estado <> 'cancelada' then
      insert into avisos_conductor (conductor_id, empresa_id, reserva_id, tipo, titulo, texto)
      values (new.conductor_id, new.empresa_id, new.id, 'cancelado', '❌ Servicio cancelado', v_det);
    elsif new.estado not in ('cancelada', 'finalizada') and (new.fecha_hora is distinct from old.fecha_hora
          or new.origen is distinct from old.origen or new.destino is distinct from old.destino
          or new.paradas is distinct from old.paradas or new.vuelo is distinct from old.vuelo) then
      insert into avisos_conductor (conductor_id, empresa_id, reserva_id, tipo, titulo, texto)
      values (new.conductor_id, new.empresa_id, new.id, 'modificado', '✏️ Servicio modificado', v_det);
    end if;
  end if;
  return new;
end $$;
revoke execute on function avisar_conductor_reserva() from public, anon, authenticated;
