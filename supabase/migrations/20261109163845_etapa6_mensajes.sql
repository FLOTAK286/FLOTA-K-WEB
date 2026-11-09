-- Etapa 6: mensajes entre pasajero, conductor y despacho, por servicio (sin compartir números de teléfono).
create table if not exists mensajes (
  id          bigint generated always as identity primary key,
  empresa_id  uuid not null references empresas(id),
  reserva_id  uuid not null references reservas(id),
  autor       text not null check (autor in ('pasajero', 'conductor', 'despacho')),
  usuario_id  uuid references auth.users(id),
  texto       text not null check (length(texto) between 1 and 500),
  creado_en   timestamptz not null default now()
);
create index if not exists mensajes_reserva on mensajes (reserva_id, id);
alter table mensajes enable row level security;
create policy mensajes_equipo_ver on mensajes for select using (empresa_id = mi_empresa() and es_staff());
create policy mensajes_conductor_ver on mensajes for select
  using (reserva_id in (select id from reservas where conductor_id = auth.uid()));

-- El chat está abierto desde que hay conductor asignado hasta 3 horas después de finalizar.
create or replace function chat_abierto(r reservas) returns boolean
language sql stable set search_path = public as $$
  select r.conductor_id is not null and r.estado <> 'cancelada'
     and (r.estado <> 'finalizada' or coalesce(
          (select max(creado_en) from reserva_eventos e where e.reserva_id = r.id and e.estado = 'finalizada'), r.fecha_hora)
          > now() - interval '3 hours')
$$;

create or replace function enviar_mensaje_publico(p_token uuid, p_texto text)
returns void language plpgsql security definer set search_path = public as $$
declare r reservas%rowtype; v_t text := nullif(left(trim(coalesce(p_texto, '')), 500), '');
begin
  select * into r from reservas where token_seguimiento = p_token;
  if not found then raise exception 'Reserva no encontrada'; end if;
  if v_t is null then raise exception 'Escriba un mensaje'; end if;
  if not chat_abierto(r) then raise exception 'El chat se abre cuando hay conductor asignado y se cierra 3 horas después del servicio'; end if;
  if (select count(*) from mensajes where reserva_id = r.id and autor = 'pasajero' and creado_en > now() - interval '1 hour') >= 30 then
    raise exception 'Demasiados mensajes. Si es urgente, escríbanos por WhatsApp.';
  end if;
  insert into mensajes (empresa_id, reserva_id, autor, texto) values (r.empresa_id, r.id, 'pasajero', v_t);
end $$;

create or replace function ver_mensajes_publico(p_token uuid)
returns table (o_id bigint, o_autor text, o_texto text, o_creado timestamptz, o_abierto boolean)
language sql stable security definer set search_path = public as $$
  select m.id, m.autor, m.texto, m.creado_en, chat_abierto(r)
  from reservas r left join mensajes m on m.reserva_id = r.id
  where r.token_seguimiento = p_token
  order by m.id
$$;

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
  if v_autor = 'conductor' and not chat_abierto(r) then raise exception 'El chat de este servicio ya está cerrado'; end if;
  insert into mensajes (empresa_id, reserva_id, autor, usuario_id, texto) values (r.empresa_id, r.id, v_autor, auth.uid(), v_t);
end $$;

revoke execute on function chat_abierto(reservas) from public, anon;
grant execute on function chat_abierto(reservas) to authenticated;
revoke execute on function enviar_mensaje_publico(uuid, text) from public;
grant execute on function enviar_mensaje_publico(uuid, text) to anon, authenticated;
revoke execute on function ver_mensajes_publico(uuid) from public;
grant execute on function ver_mensajes_publico(uuid) to anon, authenticated;
revoke execute on function enviar_mensaje(uuid, text) from public, anon;
grant execute on function enviar_mensaje(uuid, text) to authenticated;
