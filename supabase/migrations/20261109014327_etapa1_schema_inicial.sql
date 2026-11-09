-- Flota-K Plataforma · Etapa 1: clientes, reservas, equipo con roles
-- Basado en el schema.sql original (carpeta FLOTA-K IA) con ajustes:
--   + reservas: tipo_servicio, vehiculo, comuna, maletas, tarifa_web
--   + invitaciones de equipo por correo (el admin asigna el rol)
--   + cambiar_estado_reserva con nota en el historial

-- ============ Tipos ============
create type rol_usuario as enum ('admin', 'despachador', 'telefonista', 'conductor');
create type estado_reserva as enum (
  'recibida', 'confirmada', 'asignada', 'en_camino',
  'en_lugar', 'a_bordo', 'finalizada', 'cancelada'
);

-- ============ Tablas ============
create table empresas (
  id         uuid primary key default gen_random_uuid(),
  nombre     text not null,
  slug       text not null unique,
  creada_en  timestamptz not null default now()
);

-- Equipo interno (admin, despachador, telefonista, conductor)
create table perfiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  empresa_id  uuid not null references empresas(id),
  rol         rol_usuario not null,
  nombre      text not null,
  telefono    text,
  activo      boolean not null default true,
  creado_en   timestamptz not null default now()
);

-- Invitaciones: el admin invita por correo; al iniciar sesión la persona queda con su rol
create table invitaciones (
  id          bigint generated always as identity primary key,
  empresa_id  uuid not null references empresas(id),
  correo      text not null,
  nombre      text not null,
  rol         rol_usuario not null,
  creada_por  uuid references auth.users(id),
  aceptada_en timestamptz,
  creada_en   timestamptz not null default now(),
  unique (empresa_id, correo)
);

create table cuentas_corporativas (
  id                 uuid primary key default gen_random_uuid(),
  empresa_id         uuid not null references empresas(id),
  razon_social       text not null,
  rut                text,
  contacto           text,
  correo_facturacion text,
  notas              text,
  creada_en          timestamptz not null default now()
);

-- Clientes (con o sin cuenta)
create table clientes (
  id                    uuid primary key default gen_random_uuid(),
  empresa_id            uuid not null references empresas(id),
  user_id               uuid references auth.users(id) on delete set null,
  cuenta_corporativa_id uuid references cuentas_corporativas(id),
  nombre                text not null,
  telefono              text,
  correo                text,
  notas                 text,
  creado_en             timestamptz not null default now(),
  unique (empresa_id, user_id)
);

create table reservas (
  id                uuid primary key default gen_random_uuid(),
  empresa_id        uuid not null references empresas(id),
  codigo            text not null unique default ('FK-' || upper(substr(md5(gen_random_uuid()::text), 1, 6))),
  cliente_id        uuid references clientes(id),
  nombre_pasajero   text not null,
  telefono          text not null,
  correo            text,
  fecha_hora        timestamptz not null,
  origen            text not null,
  destino           text not null,
  vuelo             text,
  pasajeros         int not null default 1 check (pasajeros between 1 and 20),
  maletas           int check (maletas between 0 and 30),
  tipo_servicio     text check (tipo_servicio in ('ida', 'regreso', 'ida_vuelta', 'punto_a_punto', 'por_hora')),
  vehiculo          text check (vehiculo in ('auto', 'suv', 'van')),
  comuna            text,
  tarifa_web        int check (tarifa_web >= 0),
  comentarios       text,
  estado            estado_reserva not null default 'recibida',
  conductor_id      uuid references perfiles(id),
  precio            int check (precio >= 0),
  km_ida            numeric(7,1),
  retorno_vacio     boolean not null default true,
  forma_pago        text,
  pagado            boolean not null default false,
  canal             text not null default 'web',
  token_seguimiento uuid not null unique default gen_random_uuid(),
  creada_en         timestamptz not null default now(),
  actualizada_en    timestamptz not null default now()
);
create index reservas_empresa_fecha on reservas (empresa_id, fecha_hora);
create index reservas_conductor on reservas (conductor_id, fecha_hora);
create index reservas_correo on reservas (lower(correo));
create index reservas_cliente on reservas (cliente_id);

-- Historial de cada cambio de estado
create table reserva_eventos (
  id          bigint generated always as identity primary key,
  reserva_id  uuid not null references reservas(id) on delete cascade,
  estado      estado_reserva not null,
  nota        text,
  usuario_id  uuid references auth.users(id),
  creado_en   timestamptz not null default now()
);
create index reserva_eventos_reserva on reserva_eventos (reserva_id, creado_en);

-- Reportes de fallas y sugerencias del equipo
create table reportes (
  id          bigint generated always as identity primary key,
  empresa_id  uuid not null references empresas(id),
  usuario_id  uuid references auth.users(id),
  pantalla    text,
  texto       text not null check (length(texto) <= 2000),
  estado      text not null default 'nuevo',
  creado_en   timestamptz not null default now()
);

-- ============ Funciones de apoyo para permisos ============
create or replace function mi_empresa() returns uuid
language sql stable security definer set search_path = public as $$
  select empresa_id from perfiles where id = auth.uid() and activo
$$;

create or replace function mi_rol() returns rol_usuario
language sql stable security definer set search_path = public as $$
  select rol from perfiles where id = auth.uid() and activo
$$;

create or replace function es_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select rol in ('admin', 'despachador', 'telefonista') from perfiles where id = auth.uid() and activo),
    false)
$$;

-- ============ Triggers ============
create or replace function tocar_actualizada() returns trigger
language plpgsql set search_path = public as $$
begin
  new.actualizada_en := now();
  return new;
end $$;

create trigger reservas_actualizada before update on reservas
  for each row execute function tocar_actualizada();

create or replace function registrar_evento() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' or new.estado is distinct from old.estado then
    insert into reserva_eventos (reserva_id, estado, usuario_id)
    values (new.id, new.estado, auth.uid());
  end if;
  return new;
end $$;

create trigger reservas_evento after insert or update on reservas
  for each row execute function registrar_evento();

-- ============ Seguridad por filas (RLS) ============
alter table empresas             enable row level security;
alter table perfiles             enable row level security;
alter table invitaciones         enable row level security;
alter table cuentas_corporativas enable row level security;
alter table clientes             enable row level security;
alter table reservas             enable row level security;
alter table reserva_eventos      enable row level security;
alter table reportes             enable row level security;

create policy empresas_equipo on empresas for select
  using (id = mi_empresa());

create policy perfiles_ver on perfiles for select
  using (id = auth.uid() or (empresa_id = mi_empresa() and es_staff()));
create policy perfiles_admin_insert on perfiles for insert
  with check (empresa_id = mi_empresa() and mi_rol() = 'admin');
create policy perfiles_admin_update on perfiles for update
  using (empresa_id = mi_empresa() and mi_rol() = 'admin')
  with check (empresa_id = mi_empresa() and mi_rol() = 'admin');

create policy invitaciones_admin on invitaciones for all
  using (empresa_id = mi_empresa() and mi_rol() = 'admin')
  with check (empresa_id = mi_empresa() and mi_rol() = 'admin');

create policy corporativas_equipo on cuentas_corporativas for all
  using (empresa_id = mi_empresa() and es_staff())
  with check (empresa_id = mi_empresa() and es_staff());

create policy clientes_equipo on clientes for all
  using (empresa_id = mi_empresa() and es_staff())
  with check (empresa_id = mi_empresa() and es_staff());
create policy clientes_propio on clientes for select
  using (user_id = auth.uid());

create policy reservas_equipo_ver on reservas for select
  using (empresa_id = mi_empresa() and es_staff());
create policy reservas_equipo_crear on reservas for insert
  with check (empresa_id = mi_empresa() and es_staff());
create policy reservas_equipo_editar on reservas for update
  using (empresa_id = mi_empresa() and es_staff())
  with check (empresa_id = mi_empresa() and es_staff());
-- Sin política de borrado: las reservas no se borran, se cancelan.
create policy reservas_conductor_ver on reservas for select
  using (conductor_id = auth.uid());
create policy reservas_cliente_ver on reservas for select
  using (cliente_id in (select id from clientes where user_id = auth.uid()));

create policy eventos_ver on reserva_eventos for select
  using (reserva_id in (select id from reservas));

create policy reportes_crear on reportes for insert
  with check (empresa_id = mi_empresa() and usuario_id = auth.uid());
create policy reportes_ver on reportes for select
  using (empresa_id = mi_empresa() and es_staff());

-- ============ Funciones públicas (las llama la página) ============

-- Crear una reserva desde la web, con o sin cuenta
create or replace function crear_reserva_publica(
  p_empresa       text,
  p_nombre        text,
  p_telefono      text,
  p_correo        text,
  p_fecha_hora    timestamptz,
  p_origen        text,
  p_destino       text,
  p_vuelo         text default null,
  p_pasajeros     int  default 1,
  p_comentarios   text default null,
  p_maletas       int  default null,
  p_tipo_servicio text default null,
  p_vehiculo      text default null,
  p_comuna        text default null,
  p_tarifa_web    int  default null
) returns table (o_codigo text, o_token uuid)
language plpgsql security definer set search_path = public as $$
declare
  v_empresa uuid;
  v_cliente uuid;
begin
  select id into v_empresa from empresas where slug = p_empresa;
  if v_empresa is null then raise exception 'Empresa no encontrada'; end if;
  if p_fecha_hora < now() then raise exception 'La fecha del servicio debe ser futura'; end if;
  if length(trim(coalesce(p_nombre, ''))) < 2 then raise exception 'Ingrese su nombre'; end if;
  if length(regexp_replace(coalesce(p_telefono, ''), '\D', '', 'g')) < 8 then raise exception 'Ingrese un teléfono válido'; end if;
  if coalesce(p_correo, '') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Ingrese un correo válido'; end if;
  if length(trim(coalesce(p_origen, ''))) < 3 or length(trim(coalesce(p_destino, ''))) < 3 then
    raise exception 'Ingrese origen y destino';
  end if;
  if length(coalesce(p_comentarios, '')) > 1000 then raise exception 'El comentario es demasiado largo'; end if;
  if coalesce(p_pasajeros, 1) not between 1 and 20 then raise exception 'Número de pasajeros no válido'; end if;

  if auth.uid() is not null then
    select id into v_cliente from clientes where empresa_id = v_empresa and user_id = auth.uid();
    if v_cliente is null then
      insert into clientes (empresa_id, user_id, nombre, telefono, correo)
      values (v_empresa, auth.uid(), trim(p_nombre), trim(p_telefono), lower(trim(p_correo)))
      returning id into v_cliente;
    end if;
  end if;

  insert into reservas (empresa_id, cliente_id, nombre_pasajero, telefono, correo, fecha_hora,
                        origen, destino, vuelo, pasajeros, comentarios, canal,
                        maletas, tipo_servicio, vehiculo, comuna, tarifa_web)
  values (v_empresa, v_cliente, trim(p_nombre), trim(p_telefono), lower(trim(p_correo)), p_fecha_hora,
          trim(p_origen), trim(p_destino), nullif(trim(coalesce(p_vuelo, '')), ''),
          coalesce(p_pasajeros, 1), p_comentarios, 'web',
          p_maletas, p_tipo_servicio, p_vehiculo, p_comuna, p_tarifa_web)
  returning reservas.codigo, reservas.token_seguimiento into o_codigo, o_token;
  return next;
end $$;

-- Seguimiento sin iniciar sesión, con el enlace del cliente
create or replace function ver_reserva_publica(p_token uuid)
returns table (o_codigo text, o_estado estado_reserva, o_fecha_hora timestamptz,
               o_origen text, o_destino text, o_conductor text)
language sql stable security definer set search_path = public as $$
  select r.codigo, r.estado, r.fecha_hora, r.origen, r.destino, p.nombre
  from reservas r
  left join perfiles p on p.id = r.conductor_id
  where r.token_seguimiento = p_token
$$;

-- Al iniciar sesión, asocia al cliente sus reservas hechas como invitado con el mismo correo
create or replace function vincular_cuenta_cliente(p_empresa text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_empresa uuid;
  v_correo  text;
  v_cliente uuid;
begin
  if auth.uid() is null then raise exception 'Debe iniciar sesión'; end if;
  select id into v_empresa from empresas where slug = p_empresa;
  select lower(email) into v_correo from auth.users where id = auth.uid();
  if v_empresa is null or v_correo is null then return; end if;

  select id into v_cliente from clientes where empresa_id = v_empresa and user_id = auth.uid();
  if v_cliente is null then
    select id into v_cliente from clientes
      where empresa_id = v_empresa and user_id is null and lower(correo) = v_correo limit 1;
    if v_cliente is not null then
      update clientes set user_id = auth.uid() where id = v_cliente;
    else
      insert into clientes (empresa_id, user_id, nombre, correo)
      values (v_empresa, auth.uid(), split_part(v_correo, '@', 1), v_correo)
      returning id into v_cliente;
    end if;
  end if;

  update reservas set cliente_id = v_cliente
    where empresa_id = v_empresa and cliente_id is null and lower(correo) = v_correo;
end $$;

-- El admin invita a una persona del equipo por correo y le asigna un rol
create or replace function invitar_miembro(p_correo text, p_nombre text, p_rol rol_usuario)
returns text
language plpgsql security definer set search_path = public as $$
declare
  v_empresa uuid := mi_empresa();
  v_correo  text := lower(trim(coalesce(p_correo, '')));
  v_uid     uuid;
begin
  if mi_rol() is distinct from 'admin' then raise exception 'Solo el administrador puede invitar'; end if;
  if v_correo !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Correo no válido'; end if;
  if length(trim(coalesce(p_nombre, ''))) < 2 then raise exception 'Ingrese el nombre'; end if;

  select id into v_uid from auth.users where lower(email) = v_correo;
  if v_uid is not null then
    if exists (select 1 from perfiles where id = v_uid and empresa_id <> v_empresa) then
      raise exception 'Ese correo ya pertenece a otra empresa';
    end if;
    insert into perfiles (id, empresa_id, rol, nombre)
    values (v_uid, v_empresa, p_rol, trim(p_nombre))
    on conflict (id) do update set rol = excluded.rol, nombre = excluded.nombre, activo = true;
    insert into invitaciones (empresa_id, correo, nombre, rol, creada_por, aceptada_en)
    values (v_empresa, v_correo, trim(p_nombre), p_rol, auth.uid(), now())
    on conflict (empresa_id, correo) do update
      set nombre = excluded.nombre, rol = excluded.rol, aceptada_en = now();
    return 'agregado';
  end if;

  insert into invitaciones (empresa_id, correo, nombre, rol, creada_por)
  values (v_empresa, v_correo, trim(p_nombre), p_rol, auth.uid())
  on conflict (empresa_id, correo) do update
    set nombre = excluded.nombre, rol = excluded.rol, aceptada_en = null;
  return 'invitado';
end $$;

-- Al iniciar sesión en /equipo: si la persona tiene una invitación pendiente, queda con su rol
create or replace function aceptar_invitacion()
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_correo text;
  v_inv    invitaciones%rowtype;
begin
  if auth.uid() is null then return false; end if;
  if exists (select 1 from perfiles where id = auth.uid()) then return true; end if;
  select lower(email) into v_correo from auth.users
    where id = auth.uid() and (email_confirmed_at is not null);
  if v_correo is null then return false; end if;
  select * into v_inv from invitaciones
    where correo = v_correo and aceptada_en is null order by creada_en desc limit 1;
  if not found then return false; end if;
  insert into perfiles (id, empresa_id, rol, nombre) values (auth.uid(), v_inv.empresa_id, v_inv.rol, v_inv.nombre);
  update invitaciones set aceptada_en = now() where id = v_inv.id;
  return true;
end $$;

-- Cambiar el estado de una reserva dejando nota en el historial
create or replace function cambiar_estado_reserva(p_reserva uuid, p_estado estado_reserva, p_nota text default null)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_actual estado_reserva;
  v_nota   text := nullif(left(trim(coalesce(p_nota, '')), 1000), '');
begin
  if not es_staff() then raise exception 'Sin permiso'; end if;
  select estado into v_actual from reservas
    where id = p_reserva and empresa_id = mi_empresa() for update;
  if not found then raise exception 'Reserva no encontrada'; end if;

  if v_actual is distinct from p_estado then
    update reservas set estado = p_estado where id = p_reserva;
    if v_nota is not null then
      update reserva_eventos set nota = v_nota
        where id = (select max(id) from reserva_eventos where reserva_id = p_reserva);
    end if;
  elsif v_nota is not null then
    insert into reserva_eventos (reserva_id, estado, nota, usuario_id)
    values (p_reserva, p_estado, v_nota, auth.uid());
  end if;
end $$;

-- Permisos de ejecución
revoke execute on all functions in schema public from public, anon;
grant execute on function crear_reserva_publica(text, text, text, text, timestamptz, text, text, text, int, text, int, text, text, text, int) to anon, authenticated;
grant execute on function ver_reserva_publica(uuid) to anon, authenticated;
grant execute on function vincular_cuenta_cliente(text) to authenticated;
grant execute on function invitar_miembro(text, text, rol_usuario) to authenticated;
grant execute on function aceptar_invitacion() to authenticated;
grant execute on function cambiar_estado_reserva(uuid, estado_reserva, text) to authenticated;
grant execute on function mi_empresa() to authenticated;
grant execute on function mi_rol() to authenticated;
grant execute on function es_staff() to authenticated;

-- ============ Datos iniciales ============
insert into empresas (nombre, slug) values ('Flota-K', 'flota-k');
