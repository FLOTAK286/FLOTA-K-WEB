-- Etapa 40: app del pasajero con cuenta obligatoria.
-- Registro con correo verificado (Edge Function registro-pasajero), reservas propias, direcciones favoritas,
-- cancelar hasta 2 h antes, calificar y cotizador punto a punto (parámetros del taxímetro de la empresa).

-- ---------- Direcciones favoritas ----------
create table if not exists pasajero_favoritos (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id) on delete cascade,
  cliente_id uuid not null references clientes(id) on delete cascade,
  nombre text not null check (length(trim(nombre)) between 1 and 40),
  texto text not null check (length(trim(texto)) between 3 and 300),
  detalle text check (length(coalesce(detalle, '')) <= 200),
  lat double precision not null check (lat between -56 and -17),
  lng double precision not null check (lng between -76 and -66),
  creado_en timestamptz not null default now()
);
create index if not exists pasajero_favoritos_cliente on pasajero_favoritos(cliente_id);
alter table pasajero_favoritos enable row level security;
-- Sin acceso directo: todo pasa por las funciones de abajo.

-- ---------- Registro: control de abuso ----------
create table if not exists registro_intentos (
  id bigint generated always as identity primary key,
  ip text,
  correo text,
  creado_en timestamptz not null default now()
);
create index if not exists registro_intentos_fecha on registro_intentos(creado_en);
alter table registro_intentos enable row level security;

-- ---------- Ficha del pasajero que usa la app ----------
-- Devuelve el id de cliente de la persona conectada. La crea o la vincula por su correo VERIFICADO.
create or replace function pasajero_cliente()
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_emp uuid; v_cli uuid; u auth.users;
begin
  if auth.uid() is null then raise exception 'Debe iniciar sesión'; end if;
  select id into v_emp from empresas where slug = 'flota-k';
  select id into v_cli from clientes where empresa_id = v_emp and user_id = auth.uid() order by creado_en limit 1;
  if v_cli is not null then return v_cli; end if;
  select * into u from auth.users where id = auth.uid();
  if u.email_confirmed_at is null then raise exception 'Confirme su correo antes de continuar'; end if;
  -- Ficha existente con el mismo correo (verificado) y sin cuenta: se vincula y conserva su historial
  select id into v_cli from clientes
   where empresa_id = v_emp and user_id is null and lower(correo) = lower(u.email)
   order by creado_en limit 1;
  if v_cli is not null then
    update clientes set user_id = auth.uid(),
           telefono = coalesce(telefono, nullif(u.raw_user_meta_data->>'telefono', ''))
     where id = v_cli;
  else
    insert into clientes (empresa_id, user_id, nombre, telefono, correo)
    values (v_emp, auth.uid(),
            coalesce(nullif(trim(u.raw_user_meta_data->>'nombre'), ''), split_part(u.email, '@', 1)),
            nullif(trim(u.raw_user_meta_data->>'telefono'), ''), lower(u.email))
    returning id into v_cli;
  end if;
  -- Reservas anteriores hechas con ese mismo correo
  update reservas set cliente_id = v_cli
   where empresa_id = v_emp and cliente_id is null and lower(correo) = lower(u.email);
  return v_cli;
end $$;

-- Datos para abrir la app: perfil, favoritos y parámetros del cotizador
create or replace function pasajero_inicio()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_cli uuid; c clientes; e empresas;
begin
  v_cli := pasajero_cliente();
  select * into c from clientes where id = v_cli;
  select * into e from empresas where id = c.empresa_id;
  return jsonb_build_object(
    'yo', jsonb_build_object('nombre', c.nombre, 'telefono', c.telefono, 'correo', c.correo),
    'favoritos', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'nombre', f.nombre, 'texto', f.texto,
                  'detalle', f.detalle, 'lat', f.lat, 'lng', f.lng) order by f.creado_en)
                  from pasajero_favoritos f where f.cliente_id = v_cli), '[]'::jsonb),
    'cotizador', jsonb_build_object('bajada', e.taxi_bajada, 'cada_200m', e.taxi_cada_200m, 'minimo', 12000)
  );
end $$;

create or replace function pasajero_actualizar_perfil(p_nombre text, p_telefono text)
returns void language plpgsql security definer set search_path = public as $$
declare v_cli uuid;
begin
  v_cli := pasajero_cliente();
  if length(trim(coalesce(p_nombre, ''))) < 2 then raise exception 'Escriba su nombre'; end if;
  if length(regexp_replace(coalesce(p_telefono, ''), '\D', '', 'g')) < 8 then raise exception 'Escriba un teléfono válido'; end if;
  update clientes set nombre = left(trim(p_nombre), 120), telefono = left(trim(p_telefono), 30) where id = v_cli;
end $$;

-- ---------- Favoritos ----------
create or replace function pasajero_guardar_favorito(p_id uuid, p_nombre text, p_texto text, p_detalle text, p_lat double precision, p_lng double precision)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_cli uuid; v_emp uuid; v_id uuid;
begin
  v_cli := pasajero_cliente();
  select empresa_id into v_emp from clientes where id = v_cli;
  if p_lat is null or p_lng is null then raise exception 'Marque el punto en el mapa'; end if;
  if p_id is null then
    if (select count(*) from pasajero_favoritos where cliente_id = v_cli) >= 15 then
      raise exception 'Puede guardar hasta 15 direcciones';
    end if;
    insert into pasajero_favoritos (empresa_id, cliente_id, nombre, texto, detalle, lat, lng)
    values (v_emp, v_cli, trim(p_nombre), trim(p_texto), nullif(trim(coalesce(p_detalle, '')), ''), p_lat, p_lng)
    returning id into v_id;
  else
    update pasajero_favoritos set nombre = trim(p_nombre), texto = trim(p_texto),
           detalle = nullif(trim(coalesce(p_detalle, '')), ''), lat = p_lat, lng = p_lng
     where id = p_id and cliente_id = v_cli returning id into v_id;
    if v_id is null then raise exception 'Dirección no encontrada'; end if;
  end if;
  return v_id;
end $$;

create or replace function pasajero_borrar_favorito(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from pasajero_favoritos where id = p_id and cliente_id = pasajero_cliente();
end $$;

-- ---------- Reservar ----------
-- Las reservas de la app son particulares: no se cargan a un convenio aunque el cliente tenga uno.
create or replace function asignar_cuenta_corporativa()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.canal = 'app' then return new; end if;
  if new.cuenta_corporativa_id is null and new.cliente_id is not null and not es_staff() then
    select cuenta_corporativa_id into new.cuenta_corporativa_id from clientes where id = new.cliente_id;
  end if;
  return new;
end $$;

create or replace function pasajero_reservar(
  p_fecha_hora timestamptz, p_tipo_servicio text, p_vehiculo text,
  p_origen text, p_destino text,
  p_origen_lat double precision, p_origen_lng double precision,
  p_destino_lat double precision, p_destino_lng double precision,
  p_vuelo text default null, p_pasajeros int default 1, p_maletas int default null,
  p_comuna text default null, p_tarifa int default null, p_tarifa_estimada boolean default false,
  p_km numeric default null, p_retiro_detalle text default null, p_comentarios text default null,
  p_pasajero_nombre text default null, p_pasajero_telefono text default null)
returns table(o_id uuid, o_codigo text, o_token uuid)
language plpgsql security definer set search_path = public as $$
declare
  v_cli uuid; c clientes; otro boolean;
begin
  v_cli := pasajero_cliente();
  select * into c from clientes where id = v_cli;
  if length(regexp_replace(coalesce(c.telefono, ''), '\D', '', 'g')) < 8 then
    raise exception 'Agregue su teléfono en "Mi cuenta" antes de reservar';
  end if;
  if p_fecha_hora < now() + interval '2 hours' then
    raise exception 'Para viajes en menos de 2 horas, escríbanos por WhatsApp al +56 9 2227 5399';
  end if;
  if p_fecha_hora > now() + interval '365 days' then raise exception 'La fecha es demasiado lejana'; end if;
  if p_tipo_servicio not in ('ida', 'regreso', 'punto_a_punto') then raise exception 'Tipo de servicio no válido'; end if;
  if p_vehiculo not in ('auto', 'van') then raise exception 'Vehículo no válido'; end if;
  if p_origen_lat is null or p_origen_lat not between -56 and -17 or p_origen_lng not between -76 and -66 then
    raise exception 'Marque en el mapa el punto exacto de retiro';
  end if;
  if p_destino_lat is null or p_destino_lat not between -56 and -17 or p_destino_lng not between -76 and -66 then
    raise exception 'Marque en el mapa el punto exacto de destino';
  end if;
  if length(trim(coalesce(p_origen, ''))) < 3 or length(trim(coalesce(p_destino, ''))) < 3 then raise exception 'Ingrese origen y destino'; end if;
  if coalesce(p_pasajeros, 1) not between 1 and 15 then raise exception 'Número de pasajeros no válido'; end if;
  if coalesce(p_maletas, 0) not between 0 and 30 then raise exception 'Número de maletas no válido'; end if;
  if coalesce(p_tarifa, 0) not between 0 and 2000000 then raise exception 'Tarifa no válida'; end if;
  if length(coalesce(p_comentarios, '')) > 500 or length(coalesce(p_retiro_detalle, '')) > 200 then raise exception 'Texto demasiado largo'; end if;
  if (select count(*) from reservas where cliente_id = v_cli and creada_en > now() - interval '1 hour') >= 8 then
    raise exception 'Recibimos varias solicitudes seguidas. Para más reservas, escríbanos por WhatsApp';
  end if;
  otro := length(trim(coalesce(p_pasajero_nombre, ''))) >= 2;
  if otro and length(regexp_replace(coalesce(p_pasajero_telefono, ''), '\D', '', 'g')) < 8 then
    raise exception 'Escriba el teléfono del pasajero';
  end if;

  return query
  insert into reservas (empresa_id, cliente_id, nombre_pasajero, telefono, correo, fecha_hora, origen, destino,
                        origen_lat, origen_lng, destino_lat, destino_lng, vuelo, pasajeros, maletas,
                        tipo_servicio, vehiculo, comuna, tarifa_web, comentarios, retiro_detalle, canal,
                        km_ida, solicitante_nombre, solicitante_telefono, solicitante_correo)
  values (c.empresa_id, v_cli,
          case when otro then trim(p_pasajero_nombre) else c.nombre end,
          case when otro then trim(p_pasajero_telefono) else c.telefono end,
          c.correo, p_fecha_hora, trim(p_origen), trim(p_destino),
          p_origen_lat, p_origen_lng, p_destino_lat, p_destino_lng,
          case when p_tipo_servicio in ('ida', 'regreso') then nullif(upper(trim(coalesce(p_vuelo, ''))), '') end,
          coalesce(p_pasajeros, 1), p_maletas, p_tipo_servicio, p_vehiculo, p_comuna, p_tarifa,
          nullif(concat_ws(' ',
            case when p_tarifa_estimada then 'Valor estimado por la app (cotizador punto a punto), por confirmar.' end,
            nullif(trim(coalesce(p_comentarios, '')), '')), ''),
          nullif(trim(coalesce(p_retiro_detalle, '')), ''), 'app',
          case when p_km between 0 and 2000 then p_km end,
          case when otro then c.nombre end, case when otro then c.telefono end, case when otro then c.correo end)
  returning reservas.id, reservas.codigo, reservas.token_seguimiento;
end $$;

-- ---------- Mis viajes ----------
create or replace function pasajero_viajes()
returns table(o_id uuid, o_token uuid, o_codigo text, o_estado estado_reserva, o_fecha_hora timestamptz,
              o_tipo text, o_vehiculo text, o_origen text, o_destino text,
              o_origen_lat double precision, o_origen_lng double precision, o_destino_lat double precision, o_destino_lng double precision,
              o_vuelo text, o_pasajeros int, o_maletas int, o_pasajero text, o_valor int, o_conductor text, o_movil text,
              o_auto text, o_patente text, o_calificado boolean, o_puede_cancelar boolean, o_puede_calificar boolean,
              o_retiro_detalle text, o_comuna text)
language sql stable security definer set search_path = public as $$
  select r.id, r.token_seguimiento, r.codigo, r.estado, r.fecha_hora, r.tipo_servicio, r.vehiculo, r.origen, r.destino,
         r.origen_lat, r.origen_lng, r.destino_lat, r.destino_lng, r.vuelo, r.pasajeros, r.maletas, r.nombre_pasajero,
         valor_cobro(r.id), p.nombre, p.movil,
         coalesce(nullif(trim(concat_ws(' ', v.marca, v.modelo)), ''), v.descripcion), v.patente,
         exists (select 1 from calificaciones k where k.reserva_id = r.id and k.autor = 'pasajero'),
         r.estado in ('recibida', 'confirmada', 'asignada') and r.fecha_hora > now() + interval '2 hours',
         r.estado = 'finalizada' and r.fecha_hora > now() - interval '30 days'
           and not exists (select 1 from calificaciones k where k.reserva_id = r.id and k.autor = 'pasajero'),
         r.retiro_detalle, r.comuna
  from reservas r
  left join perfiles p on p.id = r.conductor_id
  left join vehiculos v on v.id = coalesce(r.vehiculo_id,
       (select id from vehiculos where conductor_habitual = r.conductor_id and activo order by creado_en limit 1))
  where r.cliente_id = (select id from clientes where user_id = auth.uid() order by creado_en limit 1)
    and r.eliminada_en is null
    and r.cuenta_corporativa_id is null
    and r.fecha_hora > now() - interval '12 months'
  order by r.fecha_hora desc
  limit 200
$$;

create or replace function pasajero_cancelar(p_reserva uuid, p_motivo text default null)
returns void language plpgsql security definer set search_path = public as $$
declare r reservas; v_cli uuid;
begin
  v_cli := pasajero_cliente();
  select * into r from reservas where id = p_reserva and cliente_id = v_cli and eliminada_en is null for update;
  if r.id is null then raise exception 'Reserva no encontrada'; end if;
  if r.cuenta_corporativa_id is not null then raise exception 'Este viaje es de su empresa: cancélelo en el portal de empresas'; end if;
  if r.estado not in ('recibida', 'confirmada', 'asignada') then raise exception 'Esta reserva ya no se puede cancelar desde la app'; end if;
  if r.fecha_hora <= now() + interval '2 hours' then
    raise exception 'Faltan menos de 2 horas: para cancelar, escríbanos por WhatsApp al +56 9 2227 5399';
  end if;
  update reservas set estado = 'cancelada' where id = r.id;
  update reserva_eventos set nota = left('Cancelada por el pasajero desde la app' || coalesce(': ' || nullif(trim(p_motivo), ''), ''), 1000)
   where id = (select max(id) from reserva_eventos where reserva_id = r.id);
end $$;

-- ---------- Registro (solo la Edge Function, con la llave de servicio) ----------
create or replace function registro_permitido(p_ip text, p_correo text)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  delete from registro_intentos where creado_en < now() - interval '2 days';
  if (select count(*) from registro_intentos where ip = p_ip and creado_en > now() - interval '1 hour') >= 5 then return false; end if;
  if (select count(*) from registro_intentos where creado_en > now() - interval '1 hour') >= 40 then return false; end if;
  insert into registro_intentos (ip, correo) values (p_ip, lower(p_correo));
  return true;
end $$;

-- ---------- Permisos ----------
revoke all on function pasajero_cliente() from public, anon;
revoke all on function pasajero_inicio() from public, anon;
revoke all on function pasajero_actualizar_perfil(text, text) from public, anon;
revoke all on function pasajero_guardar_favorito(uuid, text, text, text, double precision, double precision) from public, anon;
revoke all on function pasajero_borrar_favorito(uuid) from public, anon;
revoke all on function pasajero_reservar(timestamptz, text, text, text, text, double precision, double precision, double precision, double precision, text, int, int, text, int, boolean, numeric, text, text, text, text) from public, anon;
revoke all on function pasajero_viajes() from public, anon;
revoke all on function pasajero_cancelar(uuid, text) from public, anon;
revoke all on function registro_permitido(text, text) from public, anon, authenticated;
grant execute on function pasajero_cliente() to authenticated;
grant execute on function pasajero_inicio() to authenticated;
grant execute on function pasajero_actualizar_perfil(text, text) to authenticated;
grant execute on function pasajero_guardar_favorito(uuid, text, text, text, double precision, double precision) to authenticated;
grant execute on function pasajero_borrar_favorito(uuid) to authenticated;
grant execute on function pasajero_reservar(timestamptz, text, text, text, text, double precision, double precision, double precision, double precision, text, int, int, text, int, boolean, numeric, text, text, text, text) to authenticated;
grant execute on function pasajero_viajes() to authenticated;
grant execute on function pasajero_cancelar(uuid, text) to authenticated;
grant execute on function registro_permitido(text, text) to service_role;
