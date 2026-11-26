-- Etapa 79: Instagram automático propio (reemplaza a ManyChat).
-- Si un comentario en CUALQUIER publicación trae una palabra clave (aeropuerto, precio, tarifa),
-- la Edge Function "ig-webhook" responde en el comentario y manda un mensaje privado con el enlace de reserva.
-- El permiso (token) de Instagram se guarda en ig_cuentas, que NO tiene políticas: solo la lee el servidor.

-- 1) Conexión con Instagram (solo servidor)
create table if not exists ig_cuentas (
  empresa_id uuid primary key references empresas(id),
  ig_user_id text not null,
  usuario text,
  token text not null,
  token_vence timestamptz,
  token_renovado_en timestamptz not null default now(),
  conectado_en timestamptz not null default now(),
  conectado_por uuid references perfiles(id),
  ultima_revision timestamptz, -- evita que la revisión corra más de una vez cada 4 minutos
  ultimo_error text check (length(ultimo_error) <= 1000)
);
alter table ig_cuentas enable row level security;
-- sin políticas: ni anon ni usuarios conectados pueden leer el token

-- Estados temporales del botón "Conectar Instagram" (protegen el regreso desde Instagram)
create table if not exists ig_oauth_estado (
  estado text primary key,
  empresa_id uuid not null references empresas(id),
  creado_por uuid references perfiles(id),
  creado_en timestamptz not null default now()
);
alter table ig_oauth_estado enable row level security;

-- 2) Configuración editable desde el panel (solo admin)
create table if not exists ig_config (
  empresa_id uuid primary key references empresas(id),
  activo boolean not null default false,
  palabras text[] not null default array['aeropuerto', 'precio', 'tarifa'],
  respuesta_publica text not null default '¡Hola! Le enviamos su tarifa por mensaje privado 📩 Comprometidos con su traslado.' check (length(respuesta_publica) between 1 and 900),
  mensaje_privado text not null default 'Hola, gracias por escribirnos. Vea su tarifa fija y reserve con pago en línea aquí: https://fk-servicios.com/reservar/?utm_source=instagram (peajes y TAG incluidos en la Región Metropolitana). Si viaja fuera de Santiago, escríbanos por WhatsApp al +56 9 2227 5399. Comprometidos con su traslado.' check (length(mensaje_privado) between 1 and 900),
  actualizado_en timestamptz not null default now(),
  actualizado_por uuid references perfiles(id)
);
alter table ig_config enable row level security;
create policy ig_config_ver on ig_config for select using (empresa_id = mi_empresa() and mi_rol() = 'admin');
create policy ig_config_editar on ig_config for update using (empresa_id = mi_empresa() and mi_rol() = 'admin') with check (empresa_id = mi_empresa() and mi_rol() = 'admin');

create or replace function ig_config_tocar() returns trigger language plpgsql set search_path = public as $$
begin
  new.actualizado_en := now();
  new.actualizado_por := coalesce(auth.uid(), new.actualizado_por);
  new.palabras := array(select distinct lower(trim(x)) from unnest(new.palabras) x where length(trim(x)) between 2 and 40);
  if coalesce(array_length(new.palabras, 1), 0) = 0 then raise exception 'Escriba al menos una palabra clave.'; end if;
  if array_length(new.palabras, 1) > 20 then raise exception 'Máximo 20 palabras clave.'; end if;
  return new;
end $$;
create trigger ig_config_actualizado before update on ig_config for each row execute function ig_config_tocar();

insert into ig_config (empresa_id) select id from empresas where slug = 'flota-k' on conflict do nothing;

-- 3) Registro de comentarios recibidos y qué se hizo (solo admin lo ve)
create table if not exists ig_comentarios (
  id bigint generated always as identity primary key,
  empresa_id uuid not null references empresas(id),
  comentario_id text not null unique,
  publicacion_id text,
  autor_id text,
  autor text,
  texto text check (length(texto) <= 2200),
  palabra text,
  respondido boolean not null default false,
  mensaje_enviado boolean not null default false,
  resultado text check (length(resultado) <= 1000),
  origen text not null default 'webhook' check (origen in ('webhook', 'revision')),
  creado_en timestamptz not null default now()
);
alter table ig_comentarios enable row level security;
create policy ig_comentarios_ver on ig_comentarios for select using (empresa_id = mi_empresa() and mi_rol() = 'admin');
create index if not exists ig_comentarios_empresa_idx on ig_comentarios (empresa_id, creado_en desc);
create index if not exists ig_comentarios_autor_idx on ig_comentarios (empresa_id, autor_id, creado_en desc);

-- 4) Estado de la conexión para el panel (sin mostrar el token)
create or replace function ig_estado()
returns table (o_conectado boolean, o_usuario text, o_conectado_en timestamptz, o_vence timestamptz, o_error text)
language sql stable security definer set search_path = public as $$
  select c.ig_user_id is not null, c.usuario, c.conectado_en, c.token_vence, c.ultimo_error
  from (select mi_empresa() e) yo
  left join ig_cuentas c on c.empresa_id = yo.e
  where mi_rol() = 'admin'
$$;
revoke all on function ig_estado() from public, anon;
grant execute on function ig_estado() to authenticated;

-- 5) Tarea programada: cada 10 minutos la función renueva el permiso si le faltan menos de 15 días
--    (vence a los 60) y, si el automático está activo, revisa los comentarios recientes por si algún aviso no llegó.
--    La llamada no lleva datos ni claves: la función solo hace esas dos cosas.
select cron.schedule('flotak-instagram', '*/10 * * * *', $$
  select net.http_post(
    url := 'https://iejhmplstveockkjjbks.supabase.co/functions/v1/ig-webhook/tarea',
    headers := '{"Content-Type": "application/json"}'::jsonb,
    body := '{}'::jsonb)
$$);
