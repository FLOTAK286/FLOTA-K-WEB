-- Etapa 10: el conductor acepta o rechaza el servicio asignado; historial de cambios; reservas recurrentes;
-- y una versión nueva del enlace del pasajero con fotos y calificación (la anterior sigue igual).

alter table reservas add column if not exists conductor_respuesta text check (conductor_respuesta in ('aceptado', 'rechazado'));
alter table reservas add column if not exists respuesta_en timestamptz;
alter table reservas add column if not exists serie_id uuid;
create index if not exists reservas_serie on reservas (serie_id);

-- Al cambiar de conductor, la respuesta anterior deja de valer.
create or replace function limpiar_respuesta_conductor() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.conductor_id is distinct from old.conductor_id then
    new.conductor_respuesta := null; new.respuesta_en := null;
  end if;
  return new;
end $$;
create trigger reservas_limpiar_respuesta before update of conductor_id on reservas
  for each row execute function limpiar_respuesta_conductor();

create or replace function conductor_responder(p_reserva uuid, p_acepta boolean, p_motivo text default null)
returns void language plpgsql security definer set search_path = public as $$
declare r reservas%rowtype; v_m text := nullif(left(trim(coalesce(p_motivo, '')), 300), '');
begin
  select * into r from reservas where id = p_reserva and conductor_id = auth.uid() for update;
  if not found then raise exception 'Este servicio no está asignado a usted'; end if;
  if r.estado in ('finalizada', 'cancelada') then raise exception 'Este servicio ya está cerrado'; end if;
  if p_acepta then
    update reservas set conductor_respuesta = 'aceptado', respuesta_en = now() where id = r.id;
    insert into reserva_eventos (reserva_id, estado, nota, usuario_id) values (r.id, r.estado, 'El conductor aceptó el servicio', auth.uid());
  else
    if r.estado in ('en_camino', 'en_lugar', 'a_bordo') then raise exception 'El servicio ya está en curso: avise a la central'; end if;
    -- Queda sin conductor para que el despacho lo reasigne; el trigger limpia la respuesta, por eso se marca después.
    update reservas set conductor_id = null, vehiculo_id = null,
           estado = case when estado = 'asignada' then 'confirmada'::estado_reserva else estado end where id = r.id;
    update reservas set conductor_respuesta = 'rechazado', respuesta_en = now() where id = r.id;
    insert into reserva_eventos (reserva_id, estado, nota, usuario_id)
    values (r.id, (select estado from reservas where id = r.id), 'El conductor no puede tomar el servicio' || coalesce(': ' || v_m, ''), auth.uid());
  end if;
end $$;
revoke execute on function conductor_responder(uuid, boolean, text) from public, anon;
grant execute on function conductor_responder(uuid, boolean, text) to authenticated;

-- Historial de cambios importantes de cada reserva (quién y cuándo)
create table if not exists reserva_cambios (
  id          bigint generated always as identity primary key,
  reserva_id  uuid not null references reservas(id),
  campo       text not null,
  antes       text,
  despues     text,
  usuario_id  uuid,
  creado_en   timestamptz not null default now()
);
create index if not exists reserva_cambios_reserva on reserva_cambios (reserva_id, id);
alter table reserva_cambios enable row level security;
create policy cambios_equipo_ver on reserva_cambios for select
  using (reserva_id in (select id from reservas where empresa_id = mi_empresa()) and es_staff());

create or replace function registrar_cambios_reserva() returns trigger
language plpgsql security definer set search_path = public as $$
declare c text; a text; d text;
begin
  foreach c in array array['fecha_hora','origen','destino','precio','forma_pago','tipo_cobro','conductor_id','vehiculo_id','derivado_a','pagado','vehiculo','pasajeros','vuelo','centro_costo'] loop
    execute format('select ($1).%I::text, ($2).%I::text', c, c) into a, d using old, new;
    if a is distinct from d then
      insert into reserva_cambios (reserva_id, campo, antes, despues, usuario_id) values (new.id, c, a, d, auth.uid());
    end if;
  end loop;
  return new;
end $$;
create trigger reservas_historial after update on reservas for each row execute function registrar_cambios_reserva();
revoke execute on function registrar_cambios_reserva() from public, anon, authenticated;

-- Enlace del pasajero, versión con fotos (nombre nuevo: la función anterior no se toca).
create or replace function ver_reserva_publica_v2(p_token uuid)
returns table (o_codigo text, o_estado estado_reserva, o_fecha_hora timestamptz, o_origen text, o_destino text,
               o_conductor text, o_movil text, o_vehiculo text, o_patente text, o_color text, o_anio int,
               o_foto_conductor text, o_foto_vehiculo text, o_calificacion numeric, o_n_calif int, o_tipo_servicio text, o_vuelo text)
language sql stable security definer set search_path = public as $$
  select r.codigo, r.estado, r.fecha_hora, r.origen, r.destino, p.nombre, p.movil,
         coalesce(nullif(trim(concat_ws(' ', v.marca, v.modelo)), ''), v.descripcion, initcap(v.tipo)), v.patente, v.color, v.anio,
         p.foto_path, v.foto_path,
         (select round(avg(c.estrellas)::numeric, 1) from calificaciones c where c.conductor_id = r.conductor_id and c.autor = 'pasajero'),
         (select count(*)::int from calificaciones c where c.conductor_id = r.conductor_id and c.autor = 'pasajero'),
         r.tipo_servicio::text, r.vuelo
  from reservas r
  left join perfiles p on p.id = r.conductor_id
  left join vehiculos v on v.id = coalesce(r.vehiculo_id,
       (select id from vehiculos where conductor_habitual = r.conductor_id and activo order by creado_en limit 1))
  where r.token_seguimiento = p_token
$$;
revoke execute on function ver_reserva_publica_v2(uuid) from public;
grant execute on function ver_reserva_publica_v2(uuid) to anon, authenticated;
