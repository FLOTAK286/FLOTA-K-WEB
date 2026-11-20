-- Etapa 61: pasajero no presentado ("negativo"). El conductor (en el lugar) lo informa; la central lo autoriza o rechaza;
-- con la autorización, el conductor cierra el servicio como "no presentado" con el valor del negativo:
-- $5.000 (incluye los 15 min de gracia) + espera después de la gracia hasta que lo informó ($180/min auto, $270/min SUV o van).
alter table reservas add column if not exists negativo_estado text check (negativo_estado in ('solicitado', 'autorizado', 'rechazado'));
alter table reservas add column if not exists negativo_solicitado_en timestamptz;
alter table reservas add column if not exists negativo_valor integer;
alter table reservas add column if not exists negativo_resuelto_por uuid references perfiles(id);
alter table reservas add column if not exists negativo_resuelto_en timestamptz;
alter table reservas add column if not exists no_presentado boolean not null default false;

alter table avisos_equipo drop constraint if exists avisos_equipo_tipo_check;
alter table avisos_equipo add constraint avisos_equipo_tipo_check
  check (tipo in ('nueva', 'cancelada', 'rechazo', 'tomada', 'cambio_hora', 'acepto', 'postulante', 'sin_tomar', 'auto_asignada', 'negativo'));
alter table avisos_conductor drop constraint if exists avisos_conductor_tipo_check;
alter table avisos_conductor add constraint avisos_conductor_tipo_check
  check (tipo in ('nuevo', 'quitado', 'cancelado', 'modificado', 'negativo'));

-- Valor del negativo: $5.000 + minutos de espera después de la gracia (desde la hora agendada + 15 min,
-- o desde la llegada si llegó después) hasta el momento en que lo informó
create or replace function negativo_calculo(p_reserva uuid)
returns table(o_valor integer, o_minutos integer, o_tarifa integer, o_desde timestamptz)
language sql stable security definer set search_path = public as $$
  with r as (
    select r.*, (select min(e.creado_en) from reserva_eventos e where e.reserva_id = r.id and e.estado = 'en_lugar') as llegada
    from reservas r where r.id = p_reserva
  ), c as (
    select greatest(r.fecha_hora + interval '15 minutes', coalesce(r.llegada, r.fecha_hora)) as desde,
           coalesce(r.negativo_solicitado_en, now()) as hasta,
           case when r.vehiculo in ('suv', 'van') then 270 else 180 end as tarifa
    from r
  )
  select (5000 + greatest(0, floor(extract(epoch from (hasta - desde)) / 60)) * tarifa)::int,
         greatest(0, floor(extract(epoch from (hasta - desde)) / 60))::int, tarifa, desde
  from c
$$;
revoke execute on function negativo_calculo(uuid) from public, anon;
grant execute on function negativo_calculo(uuid) to authenticated;

create or replace function negativo_texto(v integer)
returns text language sql immutable as $$ select '$' || replace(to_char(coalesce(v, 0), 'FM999,999,999'), ',', '.') $$;

-- 1) El conductor informa "pasajero no presentado"
create or replace function conductor_pedir_negativo(p_reserva uuid, p_nota text default null)
returns integer language plpgsql security definer set search_path = public as $$
declare r reservas; c record; v_det text;
begin
  select * into r from reservas where id = p_reserva and conductor_id = auth.uid() for update;
  if r.id is null then raise exception 'Servicio no encontrado'; end if;
  if r.estado <> 'en_lugar' then raise exception 'Primero marque "Llegué al lugar"'; end if;
  if r.negativo_estado in ('solicitado', 'autorizado') then raise exception 'Ya lo informó: espere la respuesta de la central'; end if;
  update reservas set negativo_estado = 'solicitado', negativo_solicitado_en = now(), negativo_valor = null,
         negativo_resuelto_por = null, negativo_resuelto_en = null where id = r.id;
  select * into c from negativo_calculo(r.id);
  v_det := r.codigo || ' · ' || to_char(r.fecha_hora at time zone 'America/Santiago', 'HH24:MI') || ' · ' || coalesce(r.nombre_pasajero, 'Pasajero')
           || ' · ' || left(coalesce(r.origen, ''), 60);
  insert into reserva_eventos (reserva_id, estado, nota, usuario_id)
  values (r.id, r.estado, left('Conductor informa pasajero no presentado · negativo calculado ' || negativo_texto(c.o_valor)
          || case when c.o_minutos > 0 then ' (incluye ' || c.o_minutos || ' min de espera)' else '' end
          || coalesce(' · ' || nullif(trim(p_nota), ''), ''), 1000), auth.uid());
  insert into avisos_equipo (empresa_id, reserva_id, tipo, titulo, texto, autor_id)
  values (r.empresa_id, r.id, 'negativo', '🚫 Pasajero no presentado: autorice el negativo',
          'Valor ' || negativo_texto(c.o_valor) || case when c.o_minutos > 0 then ' (' || c.o_minutos || ' min de espera)' else '' end
          || '. ' || v_det || '. Autorícelo o recházelo en la ficha.', auth.uid());
  return c.o_valor;
end $$;
revoke execute on function conductor_pedir_negativo(uuid, text) from public, anon;
grant execute on function conductor_pedir_negativo(uuid, text) to authenticated;

-- 2) La central autoriza (con el valor calculado o uno que indique) o rechaza
create or replace function staff_resolver_negativo(p_reserva uuid, p_autorizar boolean, p_valor integer default null, p_nota text default null)
returns integer language plpgsql security definer set search_path = public as $$
declare r reservas; c record; v integer; v_quien text;
begin
  if not es_staff() then raise exception 'Sin permiso'; end if;
  select * into r from reservas where id = p_reserva and empresa_id = mi_empresa() for update;
  if r.id is null then raise exception 'Reserva no encontrada'; end if;
  if r.negativo_estado is distinct from 'solicitado' then raise exception 'No hay un "pasajero no presentado" por autorizar'; end if;
  if r.estado not in ('en_lugar', 'en_camino') then raise exception 'El servicio ya no está en el lugar'; end if;
  select nombre into v_quien from perfiles where id = auth.uid();
  if p_autorizar then
    select * into c from negativo_calculo(r.id);
    v := coalesce(p_valor, c.o_valor);
    if v < 0 or v > 1000000 then raise exception 'Valor no válido'; end if;
    update reservas set negativo_estado = 'autorizado', negativo_valor = v, negativo_resuelto_por = auth.uid(), negativo_resuelto_en = now() where id = r.id;
    insert into reserva_eventos (reserva_id, estado, nota, usuario_id)
    values (r.id, r.estado, left('Negativo autorizado por ' || coalesce(v_quien, 'la central') || ': ' || negativo_texto(v) || coalesce(' · ' || nullif(trim(p_nota), ''), ''), 1000), auth.uid());
    insert into avisos_conductor (conductor_id, empresa_id, reserva_id, tipo, titulo, texto)
    values (r.conductor_id, r.empresa_id, r.id, 'negativo', '✅ Negativo autorizado',
            'Pasajero no presentado: puede cerrar el servicio ' || r.codigo || ' por ' || negativo_texto(v) || '.');
  else
    update reservas set negativo_estado = 'rechazado', negativo_valor = null, negativo_resuelto_por = auth.uid(), negativo_resuelto_en = now() where id = r.id;
    insert into reserva_eventos (reserva_id, estado, nota, usuario_id)
    values (r.id, r.estado, left('Negativo no autorizado por ' || coalesce(v_quien, 'la central') || coalesce(' · ' || nullif(trim(p_nota), ''), ''), 1000), auth.uid());
    insert into avisos_conductor (conductor_id, empresa_id, reserva_id, tipo, titulo, texto)
    values (r.conductor_id, r.empresa_id, r.id, 'negativo', '⛔ Negativo no autorizado',
            'La central no autorizó cerrar ' || r.codigo || ' como no presentado' || coalesce(': ' || nullif(trim(p_nota), ''), '') || '. Siga esperando o comuníquese con la central.');
  end if;
  return v;
end $$;
revoke execute on function staff_resolver_negativo(uuid, boolean, integer, text) from public, anon;
grant execute on function staff_resolver_negativo(uuid, boolean, integer, text) to authenticated;

-- 3) Con la autorización, el conductor cierra el servicio como "no presentado" (finalizado, tarifa fija = valor del negativo)
create or replace function conductor_cerrar_negativo(p_reserva uuid)
returns integer language plpgsql security definer set search_path = public as $$
declare r reservas;
begin
  select * into r from reservas where id = p_reserva and (conductor_id = auth.uid() or (es_staff() and empresa_id = mi_empresa())) for update;
  if r.id is null then raise exception 'Servicio no encontrado'; end if;
  if r.negativo_estado is distinct from 'autorizado' then raise exception 'La central aún no autoriza el negativo'; end if;
  if r.estado = 'finalizada' then return r.negativo_valor; end if;
  update reservas set tipo_cobro = 'fija', precio = r.negativo_valor, no_presentado = true, estado = 'finalizada' where id = r.id;
  update reserva_eventos set nota = 'Cerrado como pasajero no presentado (negativo ' || negativo_texto(r.negativo_valor) || ')'
   where id = (select max(id) from reserva_eventos where reserva_id = r.id);
  return r.negativo_valor;
end $$;
revoke execute on function conductor_cerrar_negativo(uuid) from public, anon;
grant execute on function conductor_cerrar_negativo(uuid) to authenticated;
