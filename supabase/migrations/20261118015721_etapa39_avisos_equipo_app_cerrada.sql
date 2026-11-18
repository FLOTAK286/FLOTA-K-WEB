-- Etapa 39: avisos a la app Flota-K Operaciones con la app cerrada (sin Firebase).
-- Reserva nueva (la agenda otra persona: equipo, empresa con convenio o cliente), cancelada por alguien fuera del equipo,
-- conductor que no puede tomar un servicio y conductor que tomó una reserva publicada.
-- El teléfono del equipo pregunta cada 60 s (equipo_latido) con una llave de dispositivo y suena si hay algo nuevo.

create table if not exists avisos_equipo (
  id bigint generated always as identity primary key,
  empresa_id uuid not null references empresas(id),
  reserva_id uuid references reservas(id),
  tipo text not null check (tipo in ('nueva', 'cancelada', 'rechazo', 'tomada')),
  titulo text not null,
  texto text not null,
  autor_id uuid,
  creado_en timestamptz not null default now()
);
create index if not exists avisos_equipo_emp on avisos_equipo (empresa_id, id);
alter table avisos_equipo enable row level security;
create policy avisos_equipo_ver on avisos_equipo for select using (empresa_id = mi_empresa() and es_staff());

create table if not exists dispositivos_equipo (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references perfiles(id),
  empresa_id uuid not null references empresas(id),
  llave_hash text not null unique,
  plataforma text check (length(plataforma) <= 30),
  ultimo_aviso_id bigint not null default 0,
  creado_en timestamptz not null default now(),
  ultimo_uso timestamptz,
  revocado_en timestamptz
);
alter table dispositivos_equipo enable row level security;
create policy dispositivos_equipo_ver on dispositivos_equipo for select using (empresa_id = mi_empresa() and es_staff());

create or replace function avisar_equipo_reserva()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_det text; v_quien text; v_cond text;
begin
  if new.eliminada_en is not null then return new; end if;
  v_det := to_char(new.fecha_hora at time zone 'America/Santiago', 'DD/MM HH24:MI') || ' · ' ||
           coalesce(new.nombre_pasajero, 'Pasajero') || ': ' || left(coalesce(new.origen, ''), 80) || ' → ' || left(coalesce(new.destino, ''), 80);
  if tg_op = 'INSERT' then
    select case when es_staff() then 'Agendada por ' || coalesce(nombre, 'el equipo') else 'Agendada por ' || coalesce(nombre, 'el cliente') end
      into v_quien from perfiles where id = auth.uid();
    insert into avisos_equipo (empresa_id, reserva_id, tipo, titulo, texto, autor_id)
    values (new.empresa_id, new.id, 'nueva', '📅 Reserva nueva', v_det || '. ' || coalesce(v_quien, 'Agendada desde la web o el portal'), auth.uid());
    return new;
  end if;
  if new.estado = 'cancelada' and old.estado <> 'cancelada' and not es_staff() then
    insert into avisos_equipo (empresa_id, reserva_id, tipo, titulo, texto, autor_id)
    values (new.empresa_id, new.id, 'cancelada', '❌ Reserva cancelada por el cliente', v_det, auth.uid());
  end if;
  if new.conductor_respuesta = 'rechazado' and old.conductor_respuesta is distinct from 'rechazado' then
    select coalesce(nombre, 'El conductor') into v_cond from perfiles where id = new.conductor_id;
    insert into avisos_equipo (empresa_id, reserva_id, tipo, titulo, texto, autor_id)
    values (new.empresa_id, new.id, 'rechazo', '⚠️ ' || coalesce(v_cond, 'El conductor') || ' no puede', 'Reasigne este servicio. ' || v_det, auth.uid());
  end if;
  if old.en_bolsa and new.conductor_id is not null and old.conductor_id is null and new.conductor_id = auth.uid() then
    select coalesce(nombre, 'Un conductor') into v_cond from perfiles where id = new.conductor_id;
    insert into avisos_equipo (empresa_id, reserva_id, tipo, titulo, texto, autor_id)
    values (new.empresa_id, new.id, 'tomada', '✅ ' || coalesce(v_cond, 'Un conductor') || ' tomó una reserva', v_det, auth.uid());
  end if;
  return new;
end $$;
revoke execute on function avisar_equipo_reserva() from public, anon, authenticated;
create trigger reservas_zz_avisar_equipo after insert or update on reservas
  for each row execute function avisar_equipo_reserva();

-- Registrar el teléfono del equipo (con sesión). Devuelve la llave una sola vez; empieza sin avisos atrasados.
create or replace function equipo_registrar_dispositivo(p_plataforma text default 'android')
returns text language plpgsql security definer set search_path = public, extensions as $$
declare v_emp uuid; v_llave text;
begin
  if not es_staff() then raise exception 'Solo el equipo'; end if;
  v_emp := mi_empresa();
  update dispositivos_equipo set revocado_en = now() where usuario_id = auth.uid() and revocado_en is null;
  v_llave := encode(gen_random_bytes(32), 'hex');
  insert into dispositivos_equipo (usuario_id, empresa_id, llave_hash, plataforma, ultimo_aviso_id)
  values (auth.uid(), v_emp, encode(digest(v_llave, 'sha256'), 'hex'), left(coalesce(p_plataforma, 'android'), 30),
          coalesce((select max(id) from avisos_equipo where empresa_id = v_emp), 0));
  return v_llave;
end $$;
revoke execute on function equipo_registrar_dispositivo(text) from public, anon;
grant execute on function equipo_registrar_dispositivo(text) to authenticated;

-- Latido (sin sesión, con la llave): devuelve { cada: 60 (0 = detenerse), avisos: [...] } sin los que hizo la misma persona
create or replace function equipo_latido(p_llave text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare d dispositivos_equipo; v_ok boolean; v_av jsonb := '[]'::jsonb; v_max bigint; a record;
begin
  if length(coalesce(p_llave, '')) <> 64 then return jsonb_build_object('cada', 0); end if;
  select * into d from dispositivos_equipo where llave_hash = encode(digest(p_llave, 'sha256'), 'hex') and revocado_en is null;
  if d.id is null then return jsonb_build_object('cada', 0); end if;
  select activo and rol in ('admin', 'despachador', 'telefonista') into v_ok from perfiles where id = d.usuario_id;
  if not coalesce(v_ok, false) then return jsonb_build_object('cada', 0); end if;
  v_max := d.ultimo_aviso_id;
  for a in select id, tipo, titulo, texto, autor_id, creado_en from avisos_equipo
            where empresa_id = d.empresa_id and id > d.ultimo_aviso_id order by id loop
    v_max := a.id;
    if a.autor_id is distinct from d.usuario_id and a.creado_en > now() - interval '2 hours' then
      v_av := v_av || jsonb_build_array(jsonb_build_object('id', a.id, 'tipo', a.tipo, 'titulo', a.titulo, 'texto', a.texto));
    end if;
  end loop;
  update dispositivos_equipo set ultimo_aviso_id = v_max, ultimo_uso = now() where id = d.id;
  return jsonb_build_object('cada', 60, 'avisos', v_av);
end $$;
revoke execute on function equipo_latido(text) from public;
grant execute on function equipo_latido(text) to anon, authenticated;

-- Cerrar sesión en el teléfono del equipo: anula la llave
create or replace function equipo_cerrar_dispositivo(p_llave text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if length(coalesce(p_llave, '')) <> 64 then return; end if;
  update dispositivos_equipo set revocado_en = now()
   where llave_hash = encode(digest(p_llave, 'sha256'), 'hex') and revocado_en is null;
end $$;
revoke execute on function equipo_cerrar_dispositivo(text) from public;
grant execute on function equipo_cerrar_dispositivo(text) to anon, authenticated;
