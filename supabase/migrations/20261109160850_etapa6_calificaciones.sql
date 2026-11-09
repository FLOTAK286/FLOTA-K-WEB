-- Etapa 6: calificaciones. El pasajero califica al conductor (desde su enlace de seguimiento)
-- y el conductor califica al pasajero (desde su app). Una calificación por servicio y por lado.
create table if not exists calificaciones (
  id          bigint generated always as identity primary key,
  empresa_id  uuid not null references empresas(id),
  reserva_id  uuid not null references reservas(id),
  autor       text not null check (autor in ('pasajero', 'conductor')),
  conductor_id uuid references auth.users(id),
  cliente_id  uuid references clientes(id),
  estrellas   int not null check (estrellas between 1 and 5),
  comentario  text check (length(comentario) <= 1000),
  revisada    boolean not null default false,
  creado_en   timestamptz not null default now(),
  unique (reserva_id, autor)
);
create index if not exists calificaciones_conductor on calificaciones (conductor_id);
create index if not exists calificaciones_cliente on calificaciones (cliente_id);
alter table calificaciones enable row level security;
create policy calif_equipo_ver on calificaciones for select using (empresa_id = mi_empresa() and es_staff());
create policy calif_admin_revisar on calificaciones for update
  using (empresa_id = mi_empresa() and es_staff()) with check (empresa_id = mi_empresa() and es_staff());
create policy calif_conductor_ver on calificaciones for select using (conductor_id = auth.uid());

-- Pasajero: solo con su enlace, solo servicios finalizados, hasta 30 días después, una vez.
create or replace function calificar_conductor_publico(p_token uuid, p_estrellas int, p_comentario text default null)
returns void language plpgsql security definer set search_path = public as $$
declare r reservas%rowtype;
begin
  select * into r from reservas where token_seguimiento = p_token;
  if not found then raise exception 'Reserva no encontrada'; end if;
  if r.estado <> 'finalizada' then raise exception 'Podrá calificar cuando el servicio haya finalizado'; end if;
  if r.fecha_hora < now() - interval '30 days' then raise exception 'El plazo para calificar este servicio terminó'; end if;
  if p_estrellas is null or p_estrellas not between 1 and 5 then raise exception 'Elija de 1 a 5 estrellas'; end if;
  if exists (select 1 from calificaciones where reserva_id = r.id and autor = 'pasajero') then
    raise exception 'Este servicio ya fue calificado. ¡Gracias!';
  end if;
  insert into calificaciones (empresa_id, reserva_id, autor, conductor_id, cliente_id, estrellas, comentario)
  values (r.empresa_id, r.id, 'pasajero', r.conductor_id, r.cliente_id, p_estrellas,
          nullif(left(trim(coalesce(p_comentario, '')), 1000), ''));
end $$;

create or replace function ver_calificacion_publica(p_token uuid)
returns table (o_estrellas int, o_comentario text)
language sql stable security definer set search_path = public as $$
  select c.estrellas, c.comentario from calificaciones c join reservas r on r.id = c.reserva_id
  where r.token_seguimiento = p_token and c.autor = 'pasajero'
$$;

-- Conductor: solo sus servicios finalizados, una vez.
create or replace function conductor_calificar(p_reserva uuid, p_estrellas int, p_comentario text default null)
returns void language plpgsql security definer set search_path = public as $$
declare r reservas%rowtype;
begin
  select * into r from reservas where id = p_reserva and conductor_id = auth.uid();
  if not found then raise exception 'Este servicio no está asignado a usted'; end if;
  if r.estado <> 'finalizada' then raise exception 'Podrá calificar cuando el servicio haya finalizado'; end if;
  if p_estrellas is null or p_estrellas not between 1 and 5 then raise exception 'Elija de 1 a 5 estrellas'; end if;
  if exists (select 1 from calificaciones where reserva_id = r.id and autor = 'conductor') then
    raise exception 'Ya calificó a este pasajero';
  end if;
  insert into calificaciones (empresa_id, reserva_id, autor, conductor_id, cliente_id, estrellas, comentario)
  values (r.empresa_id, r.id, 'conductor', r.conductor_id, r.cliente_id, p_estrellas,
          nullif(left(trim(coalesce(p_comentario, '')), 1000), ''));
end $$;

revoke execute on function calificar_conductor_publico(uuid, int, text) from public;
grant execute on function calificar_conductor_publico(uuid, int, text) to anon, authenticated;
revoke execute on function ver_calificacion_publica(uuid) from public;
grant execute on function ver_calificacion_publica(uuid) to anon, authenticated;
revoke execute on function conductor_calificar(uuid, int, text) from public, anon;
grant execute on function conductor_calificar(uuid, int, text) to authenticated;
