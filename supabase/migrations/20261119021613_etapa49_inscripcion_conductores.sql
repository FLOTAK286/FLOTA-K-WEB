-- Etapa 49: inscripción de conductores con enlace. El admin envía el enlace (con un código de la empresa);
-- la persona crea su cuenta (correo y contraseña), llena sus datos y sube sus documentos. Queda "por activar":
-- no ve servicios hasta que el admin la apruebe con un toque en Equipo y roles. A Operaciones le llega un aviso.

alter table perfiles add column if not exists postulacion text check (postulacion in ('pendiente', 'aprobada', 'rechazada'));

alter table empresas add column if not exists inscripcion_codigo text not null default encode(extensions.gen_random_bytes(5), 'hex');
alter table empresas add column if not exists inscripcion_activa boolean not null default true;
create unique index if not exists empresas_inscripcion_codigo_idx on empresas (inscripcion_codigo);

create table if not exists postulaciones_conductor (
  id uuid primary key references perfiles(id),
  empresa_id uuid not null references empresas(id),
  correo text,
  rut text check (length(rut) <= 20),
  comuna text check (length(comuna) <= 80),
  licencia_clase text check (length(licencia_clase) <= 20),
  experiencia text check (length(experiencia) <= 500),
  tiene_vehiculo boolean not null default false,
  patente text check (length(patente) <= 10),
  marca text check (length(marca) <= 60),
  modelo text check (length(modelo) <= 60),
  anio integer check (anio between 1990 and 2100),
  color text check (length(color) <= 40),
  creado_en timestamptz not null default now(),
  revisado_por uuid references perfiles(id),
  revisado_en timestamptz,
  nota text check (length(nota) <= 500)
);
alter table postulaciones_conductor enable row level security;
create policy postulaciones_ver on postulaciones_conductor for select
  using (id = auth.uid() or (empresa_id = mi_empresa() and es_staff()));

-- Aviso a Operaciones
alter table avisos_equipo drop constraint if exists avisos_equipo_tipo_check;
alter table avisos_equipo add constraint avisos_equipo_tipo_check
  check (tipo in ('nueva', 'cancelada', 'rechazo', 'tomada', 'cambio_hora', 'acepto', 'postulante'));

-- ¿El código del enlace es válido? (lo usa el formulario para mostrar el nombre de la empresa)
create or replace function inscripcion_empresa(p_codigo text)
returns text language sql stable security definer set search_path = public as $$
  select nombre from empresas where inscripcion_codigo = lower(trim(p_codigo)) and inscripcion_activa
$$;
revoke execute on function inscripcion_empresa(text) from public;
grant execute on function inscripcion_empresa(text) to anon, authenticated;

-- Límite de intentos (solo la función registro-conductor): 5 por IP y 3 por correo cada hora
create or replace function registro_conductor_permitido(p_ip text, p_correo text)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from registro_intentos where ip = 'cond:' || p_ip and creado_en > now() - interval '1 hour') >= 5
     or (select count(*) from registro_intentos where correo = 'cond:' || p_correo and creado_en > now() - interval '1 hour') >= 3 then
    return false;
  end if;
  insert into registro_intentos (ip, correo) values ('cond:' || p_ip, 'cond:' || p_correo);
  return true;
end $$;
revoke execute on function registro_conductor_permitido(text, text) from public, anon, authenticated;

-- Crea el perfil "por activar" y la postulación (solo la función registro-conductor, con la clave de servicio)
create or replace function conductor_postular(p_uid uuid, p_codigo text, p_correo text, p_datos jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v_emp uuid; v_nom text; v_tel text; v_veh boolean;
begin
  select id into v_emp from empresas where inscripcion_codigo = lower(trim(p_codigo)) and inscripcion_activa;
  if v_emp is null then raise exception 'El enlace de inscripción no es válido o fue desactivado'; end if;
  if exists (select 1 from perfiles where id = p_uid) then raise exception 'Esta cuenta ya está registrada'; end if;
  v_nom := left(trim(p_datos->>'nombre'), 120); v_tel := left(trim(p_datos->>'telefono'), 30);
  v_veh := coalesce((p_datos->>'tiene_vehiculo')::boolean, false);
  insert into perfiles (id, empresa_id, rol, nombre, telefono, activo, conduce, postulacion)
  values (p_uid, v_emp, 'conductor', v_nom, v_tel, false, false, 'pendiente');
  insert into postulaciones_conductor (id, empresa_id, correo, rut, comuna, licencia_clase, experiencia, tiene_vehiculo, patente, marca, modelo, anio, color)
  values (p_uid, v_emp, left(p_correo, 200), left(trim(p_datos->>'rut'), 20), left(trim(p_datos->>'comuna'), 80),
          left(trim(p_datos->>'licencia'), 20), nullif(left(trim(coalesce(p_datos->>'experiencia', '')), 500), ''), v_veh,
          case when v_veh then left(upper(regexp_replace(coalesce(p_datos->>'patente', ''), '[^A-Za-z0-9]', '', 'g')), 10) end,
          case when v_veh then left(trim(p_datos->>'marca'), 60) end, case when v_veh then left(trim(p_datos->>'modelo'), 60) end,
          case when v_veh then nullif(p_datos->>'anio', '')::int end, case when v_veh then left(trim(p_datos->>'color'), 40) end);
  insert into avisos_equipo (empresa_id, tipo, titulo, texto, autor_id)
  values (v_emp, 'postulante', '🆕 Nuevo conductor inscrito',
          v_nom || ' · ' || coalesce(v_tel, '') || '. Revíselo y actívelo en Equipo y roles.', p_uid);
end $$;
revoke execute on function conductor_postular(uuid, text, text, jsonb) from public, anon, authenticated;

-- Empresa de quien está postulando (para subir sus documentos antes de ser activado)
create or replace function mi_empresa_postulante()
returns uuid language sql stable security definer set search_path = public as $$
  select empresa_id from perfiles where id = auth.uid() and postulacion = 'pendiente' and not activo
$$;
revoke execute on function mi_empresa_postulante() from public, anon;
grant execute on function mi_empresa_postulante() to authenticated;

create policy documentos_postulante_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'documentos' and (storage.foldername(name))[1] = (mi_empresa_postulante())::text
              and (storage.foldername(name))[2] = (auth.uid())::text);

create or replace function postulante_documento(p_tipo text, p_numero text, p_vence date, p_path text)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_emp uuid; v_id bigint;
begin
  v_emp := mi_empresa_postulante();
  if v_emp is null then raise exception 'Su cuenta no está en revisión'; end if;
  if p_tipo not in ('licencia', 'cedula', 'antecedentes', 'hoja_vida', 'permiso_circulacion', 'revision_tecnica', 'soap', 'seguro', 'padron', 'otro') then
    raise exception 'Tipo de documento no válido';
  end if;
  if p_path is null or p_path not like v_emp::text || '/' || auth.uid()::text || '/%' then raise exception 'Archivo no válido'; end if;
  if (select count(*) from documentos where conductor_id = auth.uid()) >= 20 then raise exception 'Ya subió muchos documentos'; end if;
  insert into documentos (empresa_id, conductor_id, tipo, numero, vence, archivo_path, estado, creado_por)
  values (v_emp, auth.uid(), p_tipo, nullif(left(trim(coalesce(p_numero, '')), 60), ''), p_vence, p_path, 'pendiente', auth.uid())
  returning id into v_id;
  return v_id;
end $$;
revoke execute on function postulante_documento(text, text, date, text) from public, anon;
grant execute on function postulante_documento(text, text, date, text) to authenticated;

-- Aprobar o rechazar (solo admin). Al aprobar: queda activo como conductor y, si informó vehículo propio, se crea.
create or replace function aprobar_postulante(p_id uuid, p_aprobar boolean, p_nota text default null)
returns void language plpgsql security definer set search_path = public as $$
declare p postulaciones_conductor;
begin
  if mi_rol() is distinct from 'admin' then raise exception 'Solo el administrador'; end if;
  select * into p from postulaciones_conductor where id = p_id and empresa_id = mi_empresa();
  if p.id is null then raise exception 'Postulación no encontrada'; end if;
  if p_aprobar then
    update perfiles set activo = true, postulacion = 'aprobada' where id = p_id;
    if p.tiene_vehiculo and p.patente is not null and length(p.patente) between 5 and 6
       and not exists (select 1 from vehiculos where empresa_id = p.empresa_id and patente = p.patente) then
      insert into vehiculos (empresa_id, patente, marca, modelo, anio, color, conductor_habitual, propio, descripcion)
      values (p.empresa_id, p.patente, p.marca, p.modelo, p.anio, p.color, p_id, false,
              trim(coalesce(p.marca, '') || ' ' || coalesce(p.modelo, '')));
    end if;
  else
    update perfiles set activo = false, postulacion = 'rechazada' where id = p_id;
  end if;
  update postulaciones_conductor set revisado_por = auth.uid(), revisado_en = now(),
         nota = nullif(left(trim(coalesce(p_nota, '')), 500), '') where id = p_id;
end $$;
revoke execute on function aprobar_postulante(uuid, boolean, text) from public, anon;
grant execute on function aprobar_postulante(uuid, boolean, text) to authenticated;

-- Enlace: ver, cambiar el código (el enlace anterior deja de servir) o pausar la inscripción (solo admin)
create or replace function inscripcion_config(p_activa boolean default null, p_nuevo_codigo boolean default false)
returns table(codigo text, activa boolean) language plpgsql security definer set search_path = public, extensions as $$
begin
  if mi_rol() is distinct from 'admin' then raise exception 'Solo el administrador'; end if;
  if p_nuevo_codigo then update empresas set inscripcion_codigo = encode(gen_random_bytes(5), 'hex') where id = mi_empresa(); end if;
  if p_activa is not null then update empresas set inscripcion_activa = p_activa where id = mi_empresa(); end if;
  return query select e.inscripcion_codigo, e.inscripcion_activa from empresas e where e.id = mi_empresa();
end $$;
revoke execute on function inscripcion_config(boolean, boolean) from public, anon;
grant execute on function inscripcion_config(boolean, boolean) to authenticated;
