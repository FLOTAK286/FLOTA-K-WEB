-- Etapa 37: ubicación del conductor con la app cerrada (servicio nativo de Android).
-- Al iniciar sesión, la app registra el teléfono y recibe una "llave de dispositivo" (secreta, solo se guarda su huella).
-- Con esa llave, el servicio nativo envía la ubicación aunque la app esté cerrada, hasta que el conductor cierre sesión
-- (cerrar sesión anula la llave). La llave solo permite enviar la ubicación de ESE conductor: no da acceso a datos.
-- También guarda el token de notificaciones (push) del teléfono, para la etapa de avisos con la app cerrada.

create table if not exists dispositivos_conductor (
  id uuid primary key default gen_random_uuid(),
  conductor_id uuid not null references perfiles(id),
  empresa_id uuid not null references empresas(id),
  llave_hash text not null unique,
  plataforma text check (length(plataforma) <= 30),
  push_token text check (length(push_token) <= 500),
  creado_en timestamptz not null default now(),
  ultimo_uso timestamptz,
  revocado_en timestamptz
);
create index if not exists dispositivos_conductor_cond on dispositivos_conductor (conductor_id) where revocado_en is null;
alter table dispositivos_conductor enable row level security;
-- El equipo ve qué teléfonos están conectados (sin la llave); los cambios van solo por funciones
create policy dispositivos_equipo_ver on dispositivos_conductor for select using (empresa_id = mi_empresa() and es_staff());

-- Registrar este teléfono (lo llama la app con la sesión del conductor). Devuelve la llave una sola vez.
-- Un conductor tiene un solo teléfono activo: registrar uno nuevo anula los anteriores.
create or replace function conductor_registrar_dispositivo(p_plataforma text default 'android')
returns text language plpgsql security definer set search_path = public, extensions as $$
declare v_emp uuid; v_llave text;
begin
  select empresa_id into v_emp from perfiles where id = auth.uid() and activo and (conduce or rol = 'conductor');
  if v_emp is null then raise exception 'Solo conductores'; end if;
  update dispositivos_conductor set revocado_en = now() where conductor_id = auth.uid() and revocado_en is null;
  v_llave := encode(gen_random_bytes(32), 'hex');
  insert into dispositivos_conductor (conductor_id, empresa_id, llave_hash, plataforma)
  values (auth.uid(), v_emp, encode(digest(v_llave, 'sha256'), 'hex'), left(coalesce(p_plataforma, 'android'), 30));
  return v_llave;
end $$;
revoke execute on function conductor_registrar_dispositivo(text) from public, anon;
grant execute on function conductor_registrar_dispositivo(text) to authenticated;

-- Ubicación enviada por el servicio nativo (sin sesión, con la llave del teléfono).
-- Devuelve cada cuántos segundos enviar la próxima: 15 en servicio, 60 conectado, 300 desconectado; 0 = detenerse.
create or replace function conductor_ubicacion_dispositivo(p_llave text, p_lat double precision, p_lng double precision,
  p_precision int default null, p_rumbo int default null, p_velocidad int default null)
returns int language plpgsql security definer set search_path = public, extensions as $$
declare d dispositivos_conductor; p perfiles; v_res uuid; v_ult timestamptz;
begin
  if length(coalesce(p_llave, '')) <> 64 then return 0; end if;
  select * into d from dispositivos_conductor where llave_hash = encode(digest(p_llave, 'sha256'), 'hex') and revocado_en is null;
  if d.id is null then return 0; end if;                      -- llave anulada (cerró sesión): el servicio se detiene
  select * into p from perfiles where id = d.conductor_id and activo and (conduce or rol = 'conductor');
  if p.id is null then return 0; end if;                       -- conductor dado de baja
  if p_lat is null or p_lng is null or p_lat not between -90 and 90 or p_lng not between -180 and 180 then return 60; end if;
  select id into v_res from reservas where conductor_id = d.conductor_id and estado in ('en_camino', 'en_lugar', 'a_bordo')
    order by fecha_hora limit 1;
  select actualizado_en into v_ult from ubicaciones where conductor_id = d.conductor_id;
  if v_ult is null or v_ult < now() - interval '5 seconds' then
    insert into ubicaciones (conductor_id, empresa_id, reserva_id, lat, lng, precision_m, rumbo, velocidad_kmh, actualizado_en)
    values (d.conductor_id, d.empresa_id, v_res, p_lat, p_lng, least(greatest(coalesce(p_precision, 0), 0), 100000),
            case when p_rumbo between 0 and 360 then p_rumbo end, case when p_velocidad between 0 and 300 then p_velocidad end, now())
    on conflict (conductor_id) do update set empresa_id = excluded.empresa_id, reserva_id = excluded.reserva_id, lat = excluded.lat,
      lng = excluded.lng, precision_m = excluded.precision_m, rumbo = excluded.rumbo, velocidad_kmh = excluded.velocidad_kmh,
      actualizado_en = excluded.actualizado_en;
    update dispositivos_conductor set ultimo_uso = now() where id = d.id;
  end if;
  return case when v_res is not null then 15 when p.disponible then 60 else 300 end;
end $$;
revoke execute on function conductor_ubicacion_dispositivo(text, double precision, double precision, int, int, int) from public;
grant execute on function conductor_ubicacion_dispositivo(text, double precision, double precision, int, int, int) to anon, authenticated;

-- Guardar el token de notificaciones del teléfono (para avisos con la app cerrada)
create or replace function conductor_guardar_push(p_llave text, p_push text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if length(coalesce(p_llave, '')) <> 64 or length(coalesce(p_push, '')) not between 10 and 500 then raise exception 'Datos no válidos'; end if;
  update dispositivos_conductor set push_token = p_push
   where llave_hash = encode(digest(p_llave, 'sha256'), 'hex') and revocado_en is null;
end $$;
revoke execute on function conductor_guardar_push(text, text) from public;
grant execute on function conductor_guardar_push(text, text) to anon, authenticated;

-- Cerrar sesión en el teléfono: anula la llave (el servicio deja de enviar la ubicación)
create or replace function conductor_cerrar_dispositivo(p_llave text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if length(coalesce(p_llave, '')) <> 64 then return; end if;
  update dispositivos_conductor set revocado_en = now()
   where llave_hash = encode(digest(p_llave, 'sha256'), 'hex') and revocado_en is null;
end $$;
revoke execute on function conductor_cerrar_dispositivo(text) from public;
grant execute on function conductor_cerrar_dispositivo(text) to anon, authenticated;

-- Administrador: desconectar todos los teléfonos de un conductor (por ejemplo, si pierde el celular)
create or replace function admin_cerrar_dispositivos(p_conductor uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if mi_rol() is distinct from 'admin' then raise exception 'Solo el administrador'; end if;
  update dispositivos_conductor set revocado_en = now()
   where conductor_id = p_conductor and empresa_id = mi_empresa() and revocado_en is null;
end $$;
revoke execute on function admin_cerrar_dispositivos(uuid) from public, anon;
grant execute on function admin_cerrar_dispositivos(uuid) to authenticated;
