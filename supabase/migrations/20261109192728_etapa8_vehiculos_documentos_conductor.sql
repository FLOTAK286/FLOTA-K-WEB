-- Etapa 8: ficha del vehículo, fotos, documentos con vencimiento, conductor conectado/desconectado y chat con la central.

alter table vehiculos add column if not exists marca text check (length(marca) <= 60);
alter table vehiculos add column if not exists modelo text check (length(modelo) <= 60);
alter table vehiculos add column if not exists anio int check (anio between 1980 and 2100);
alter table vehiculos add column if not exists color text check (length(color) <= 40);
alter table vehiculos add column if not exists foto_path text check (length(foto_path) <= 300);
alter table perfiles add column if not exists foto_path text check (length(foto_path) <= 300);
alter table perfiles add column if not exists telefono text check (length(telefono) <= 30);
alter table perfiles add column if not exists disponible boolean not null default false;
alter table perfiles add column if not exists disponible_desde timestamptz;

-- Documentos del conductor y del vehículo
create table if not exists documentos (
  id           bigint generated always as identity primary key,
  empresa_id   uuid not null references empresas(id),
  conductor_id uuid references auth.users(id),
  vehiculo_id  uuid references vehiculos(id),
  tipo         text not null check (tipo in ('licencia','cedula','antecedentes','hoja_vida','permiso_circulacion','revision_tecnica','soap','seguro','padron','otro')),
  numero       text check (length(numero) <= 80),
  vence        date,
  archivo_path text check (length(archivo_path) <= 300),
  notas        text check (length(notas) <= 500),
  estado       text not null default 'pendiente' check (estado in ('pendiente','aprobado','rechazado')),
  creado_por   uuid references auth.users(id),
  creado_en    timestamptz not null default now(),
  check ((conductor_id is not null) <> (vehiculo_id is not null))
);
create index if not exists documentos_conductor on documentos (conductor_id);
create index if not exists documentos_vehiculo on documentos (vehiculo_id);
alter table documentos enable row level security;
create policy documentos_equipo_ver on documentos for select using (empresa_id = mi_empresa() and es_staff());
create policy documentos_admin on documentos for all
  using (empresa_id = mi_empresa() and mi_rol() = 'admin') with check (empresa_id = mi_empresa() and mi_rol() = 'admin');
create policy documentos_conductor_ver on documentos for select
  using (conductor_id = auth.uid() or vehiculo_id in (select id from vehiculos where conductor_habitual = auth.uid()));
-- El conductor sube sus propios documentos; quedan "pendiente" hasta que el administrador los revise.
create policy documentos_conductor_subir on documentos for insert
  with check (conductor_id = auth.uid() and empresa_id = mi_empresa() and estado = 'pendiente');

-- Archivos: "fotos" es público (se mostrarán al pasajero más adelante); "documentos" es privado.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('fotos', 'fotos', true, 5242880, array['image/jpeg','image/png','image/webp']),
       ('documentos', 'documentos', false, 10485760, array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict (id) do nothing;
create policy fotos_admin_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'fotos' and mi_rol() = 'admin' and (storage.foldername(name))[1] = mi_empresa()::text);
create policy documentos_equipo_leer on storage.objects for select to authenticated
  using (bucket_id = 'documentos' and es_staff() and (storage.foldername(name))[1] = mi_empresa()::text);
create policy documentos_admin_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'documentos' and mi_rol() = 'admin' and (storage.foldername(name))[1] = mi_empresa()::text);
-- Carpeta propia del conductor: <empresa>/<conductor>/...
create policy documentos_conductor_leer on storage.objects for select to authenticated
  using (bucket_id = 'documentos' and (storage.foldername(name))[1] = mi_empresa()::text and (storage.foldername(name))[2] = auth.uid()::text);
create policy documentos_conductor_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'documentos' and (storage.foldername(name))[1] = mi_empresa()::text and (storage.foldername(name))[2] = auth.uid()::text);

-- Conectado / desconectado
create or replace function conductor_disponible(p_disponible boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  update perfiles set disponible = p_disponible, disponible_desde = now()
   where id = auth.uid() and activo and (conduce or rol = 'conductor');
  if not found then raise exception 'Solo conductores'; end if;
end $$;
revoke execute on function conductor_disponible(boolean) from public, anon;
grant execute on function conductor_disponible(boolean) to authenticated;

-- Chat del conductor con la central
create table if not exists soporte_mensajes (
  id           bigint generated always as identity primary key,
  empresa_id   uuid not null references empresas(id),
  conductor_id uuid not null references auth.users(id),
  autor        text not null check (autor in ('conductor', 'central')),
  usuario_id   uuid references auth.users(id),
  texto        text not null check (length(texto) between 1 and 1000),
  leido        boolean not null default false,
  creado_en    timestamptz not null default now()
);
create index if not exists soporte_conductor on soporte_mensajes (conductor_id, id);
alter table soporte_mensajes enable row level security;
create policy soporte_equipo_ver on soporte_mensajes for select using (empresa_id = mi_empresa() and es_staff());
create policy soporte_equipo_leido on soporte_mensajes for update
  using (empresa_id = mi_empresa() and es_staff()) with check (empresa_id = mi_empresa() and es_staff());
create policy soporte_conductor_ver on soporte_mensajes for select using (conductor_id = auth.uid());

create or replace function enviar_soporte(p_texto text, p_conductor uuid default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_t text := nullif(left(trim(coalesce(p_texto, '')), 1000), ''); v_emp uuid := mi_empresa();
begin
  if v_t is null then raise exception 'Escriba un mensaje'; end if;
  if p_conductor is null or p_conductor = auth.uid() then
    if not exists (select 1 from perfiles where id = auth.uid() and activo and (conduce or rol = 'conductor')) then
      raise exception 'Solo conductores'; end if;
    insert into soporte_mensajes (empresa_id, conductor_id, autor, usuario_id, texto) values (v_emp, auth.uid(), 'conductor', auth.uid(), v_t);
  else
    if not es_staff() then raise exception 'Solo el equipo puede responder'; end if;
    if not exists (select 1 from perfiles where id = p_conductor and empresa_id = v_emp) then raise exception 'Conductor no encontrado'; end if;
    insert into soporte_mensajes (empresa_id, conductor_id, autor, usuario_id, texto) values (v_emp, p_conductor, 'central', auth.uid(), v_t);
  end if;
end $$;
revoke execute on function enviar_soporte(text, uuid) from public, anon;
grant execute on function enviar_soporte(text, uuid) to authenticated;
