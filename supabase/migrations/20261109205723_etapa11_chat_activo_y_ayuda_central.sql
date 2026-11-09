-- Etapa 11: el chat pasajero-conductor solo funciona con el servicio activo (en camino, en el lugar, a bordo).
-- Nuevo canal "central": el pasajero escribe a la central (objeto perdido, necesito ayuda, otro) y la central responde.
-- El conductor no ve el canal central.

alter table mensajes add column if not exists canal text not null default 'viaje' check (canal in ('viaje', 'central'));
alter table mensajes add column if not exists tema text check (tema in ('objeto_perdido', 'ayuda', 'otro'));
alter table mensajes add column if not exists atendido boolean not null default false;
create index if not exists mensajes_canal on mensajes (canal, atendido);

alter policy mensajes_conductor_ver on mensajes
  using (canal = 'viaje' and reserva_id in (select id from reservas where conductor_id = auth.uid()));
create policy mensajes_equipo_atender on mensajes for update
  using (empresa_id = mi_empresa() and es_staff()) with check (empresa_id = mi_empresa() and es_staff());

-- Chat del viaje: solo mientras el servicio está en curso.
create or replace function chat_abierto(r reservas) returns boolean
language sql stable set search_path = public as $$
  select r.conductor_id is not null and r.estado in ('en_camino', 'en_lugar', 'a_bordo')
$$;

-- Despacho y conductor en el chat del viaje (el conductor solo con el servicio en curso; el despacho siempre).
create or replace function enviar_mensaje(p_reserva uuid, p_texto text)
returns void language plpgsql security definer set search_path = public as $$
declare r reservas%rowtype; v_t text := nullif(left(trim(coalesce(p_texto, '')), 500), ''); v_autor text;
begin
  select * into r from reservas where id = p_reserva;
  if not found then raise exception 'Reserva no encontrada'; end if;
  if r.conductor_id = auth.uid() then v_autor := 'conductor';
  elsif r.empresa_id = mi_empresa() and es_staff() then v_autor := 'despacho';
  else raise exception 'No puede escribir en este servicio'; end if;
  if v_t is null then raise exception 'Escriba un mensaje'; end if;
  if v_autor = 'conductor' and not chat_abierto(r) then raise exception 'El chat con el pasajero se abre cuando va en camino y se cierra al finalizar. Para otros temas, escriba a la central.'; end if;
  insert into mensajes (empresa_id, reserva_id, autor, usuario_id, texto, canal) values (r.empresa_id, r.id, v_autor, auth.uid(), v_t, 'viaje');
end $$;

-- La central responde al pasajero en el canal central (cualquier momento).
create or replace function enviar_mensaje_central(p_reserva uuid, p_texto text)
returns void language plpgsql security definer set search_path = public as $$
declare r reservas%rowtype; v_t text := nullif(left(trim(coalesce(p_texto, '')), 1000), '');
begin
  select * into r from reservas where id = p_reserva and empresa_id = mi_empresa();
  if not found or not es_staff() then raise exception 'Sin permiso'; end if;
  if v_t is null then raise exception 'Escriba un mensaje'; end if;
  insert into mensajes (empresa_id, reserva_id, autor, usuario_id, texto, canal) values (r.empresa_id, r.id, 'despacho', auth.uid(), v_t, 'central');
  update mensajes set atendido = true where reserva_id = r.id and canal = 'central' and autor = 'pasajero';
end $$;
revoke execute on function enviar_mensaje_central(uuid, text) from public, anon;
grant execute on function enviar_mensaje_central(uuid, text) to authenticated;

-- El pasajero escribe a la central desde su enlace (hasta 60 días después del servicio).
create or replace function enviar_central_publico(p_token uuid, p_texto text, p_tema text default 'otro')
returns void language plpgsql security definer set search_path = public as $$
declare r reservas%rowtype; v_t text := nullif(left(trim(coalesce(p_texto, '')), 1000), '');
begin
  select * into r from reservas where token_seguimiento = p_token;
  if not found then raise exception 'Reserva no encontrada'; end if;
  if v_t is null then raise exception 'Escriba su mensaje'; end if;
  if coalesce(p_tema, 'otro') not in ('objeto_perdido', 'ayuda', 'otro') then raise exception 'Tema no válido'; end if;
  if r.fecha_hora < now() - interval '60 days' then raise exception 'Para este servicio, escríbanos por WhatsApp al +56 9 2227 5399.'; end if;
  if (select count(*) from mensajes where reserva_id = r.id and canal = 'central' and autor = 'pasajero' and creado_en > now() - interval '1 hour') >= 20 then
    raise exception 'Demasiados mensajes. Si es urgente, escríbanos por WhatsApp.';
  end if;
  insert into mensajes (empresa_id, reserva_id, autor, texto, canal, tema) values (r.empresa_id, r.id, 'pasajero', v_t, 'central', coalesce(p_tema, 'otro'));
end $$;
revoke execute on function enviar_central_publico(uuid, text, text) from public;
grant execute on function enviar_central_publico(uuid, text, text) to anon, authenticated;

-- Mensajes para el enlace del pasajero, con canal y tema (la versión anterior sigue igual).
create or replace function ver_mensajes_publico_v2(p_token uuid)
returns table (o_id bigint, o_autor text, o_texto text, o_creado timestamptz, o_canal text, o_tema text, o_abierto boolean)
language sql stable security definer set search_path = public as $$
  select m.id, m.autor, m.texto, m.creado_en, m.canal, m.tema, chat_abierto(r)
  from reservas r left join mensajes m on m.reserva_id = r.id
  where r.token_seguimiento = p_token
  order by m.id
$$;
revoke execute on function ver_mensajes_publico_v2(uuid) from public;
grant execute on function ver_mensajes_publico_v2(uuid) to anon, authenticated;
