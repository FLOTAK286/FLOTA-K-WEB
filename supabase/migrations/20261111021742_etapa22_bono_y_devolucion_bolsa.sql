-- Etapa 22: bono para servicios de la bolsa y devolución de servicios a la bolsa por el conductor.
alter table reservas add column if not exists bono_bolsa int check (bono_bolsa between 0 and 1000000);
alter table perfiles add column if not exists devoluciones_bolsa int not null default 0;

-- Despachador: liberar a la bolsa con un bono opcional para quien lo tome (0 o vacío = sin bono).
create or replace function liberar_a_bolsa_bono(p_reserva uuid, p_bono int)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform liberar_a_bolsa(p_reserva, true);
  update reservas set bono_bolsa = nullif(greatest(coalesce(p_bono, 0), 0), 0) where id = p_reserva and empresa_id = mi_empresa();
  if coalesce(p_bono, 0) > 0 then
    update reserva_eventos set nota = nota || ' · bono $' || to_char(p_bono, 'FM999G999G999') where id = (select max(id) from reserva_eventos where reserva_id = p_reserva);
  end if;
end $$;

-- Bolsa para el conductor, ahora con el bono.
create or replace function bolsa_servicios_v2()
returns table (o_id uuid, o_codigo text, o_fecha_hora timestamptz, o_tipo_servicio text, o_vehiculo text, o_zona_origen text, o_zona_destino text,
               o_pasajeros int, o_maletas int, o_vuelo text, o_valor int, o_duracion int, o_sirve boolean, o_choque boolean, o_desde timestamptz,
               o_bono int, o_km numeric)
language sql stable security definer set search_path = public as $$
  select b.*, r.bono_bolsa, r.km_ida from bolsa_servicios() b join reservas r on r.id = b.o_id
$$;

-- Conductor: devolver a la bolsa un servicio suyo que no podrá hacer (hasta 3 horas antes). Queda contado y la central recibe aviso.
create or replace function conductor_devolver_reserva(p_reserva uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_yo perfiles%rowtype; r reservas%rowtype; v_nota text;
begin
  select * into v_yo from perfiles where id = auth.uid() and activo;
  if not found then raise exception 'Sin permiso'; end if;
  select * into r from reservas where id = p_reserva and conductor_id = v_yo.id for update;
  if not found then raise exception 'Ese servicio no está a su cargo'; end if;
  if r.estado not in ('confirmada', 'asignada') then raise exception 'El servicio ya empezó: no se puede devolver'; end if;
  if r.fecha_hora < now() + interval '3 hours' then raise exception 'Faltan menos de 3 horas: llame a la central para que lo reasigne'; end if;
  update reservas set conductor_id = null, vehiculo_id = null, conductor_respuesta = null, estado = 'confirmada', en_bolsa = true, bolsa_desde = now() where id = r.id;
  v_nota := 'Devuelto a la bolsa por ' || coalesce('Móvil ' || v_yo.movil || ' · ', '') || v_yo.nombre;
  if r.estado <> 'confirmada' then
    update reserva_eventos set nota = v_nota where id = (select max(id) from reserva_eventos where reserva_id = r.id);
  else
    insert into reserva_eventos (reserva_id, estado, nota, usuario_id) values (r.id, 'confirmada', v_nota, auth.uid());
  end if;
  update perfiles set devoluciones_bolsa = devoluciones_bolsa + 1 where id = v_yo.id;
  insert into soporte_mensajes (empresa_id, conductor_id, autor, usuario_id, texto)
  values (r.empresa_id, v_yo.id, 'conductor', v_yo.id, '↩ Devolví a la bolsa el servicio ' || r.codigo || ' del ' || to_char(r.fecha_hora at time zone 'America/Santiago', 'DD/MM HH24:MI') || '. No podré realizarlo.');
end $$;

revoke execute on function liberar_a_bolsa_bono(uuid, int) from public, anon;
revoke execute on function bolsa_servicios_v2() from public, anon;
revoke execute on function conductor_devolver_reserva(uuid) from public, anon;
grant execute on function liberar_a_bolsa_bono(uuid, int) to authenticated;
grant execute on function bolsa_servicios_v2() to authenticated;
grant execute on function conductor_devolver_reserva(uuid) to authenticated;
