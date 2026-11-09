-- Etapa 5: ubicación en vivo del conductor (última posición por conductor).
create table if not exists ubicaciones (
  conductor_id   uuid primary key references auth.users(id),
  empresa_id     uuid not null references empresas(id),
  reserva_id     uuid references reservas(id),
  lat            double precision not null check (lat between -90 and 90),
  lng            double precision not null check (lng between -180 and 180),
  precision_m    int check (precision_m >= 0),
  rumbo          int check (rumbo between 0 and 360),
  velocidad_kmh  int check (velocidad_kmh between 0 and 300),
  actualizado_en timestamptz not null default now()
);
alter table ubicaciones enable row level security;
create policy ubicaciones_equipo_ver on ubicaciones for select using (empresa_id = mi_empresa() and es_staff());
create policy ubicaciones_propia_ver on ubicaciones for select using (conductor_id = auth.uid());

create or replace function conductor_ubicacion(p_lat double precision, p_lng double precision,
  p_precision int default null, p_rumbo int default null, p_velocidad int default null)
returns void
language plpgsql security definer set search_path = public as $$
declare v_emp uuid; v_res uuid;
begin
  select empresa_id into v_emp from perfiles
   where id = auth.uid() and activo and (conduce or rol = 'conductor');
  if v_emp is null then raise exception 'Solo conductores pueden compartir ubicación'; end if;
  if p_lat is null or p_lng is null or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    raise exception 'Ubicación no válida';
  end if;
  select id into v_res from reservas
   where conductor_id = auth.uid() and estado in ('en_camino', 'en_lugar', 'a_bordo')
   order by fecha_hora limit 1;
  insert into ubicaciones (conductor_id, empresa_id, reserva_id, lat, lng, precision_m, rumbo, velocidad_kmh, actualizado_en)
  values (auth.uid(), v_emp, v_res, p_lat, p_lng,
          least(greatest(p_precision, 0), 100000),
          case when p_rumbo between 0 and 360 then p_rumbo end,
          case when p_velocidad between 0 and 300 then p_velocidad end, now())
  on conflict (conductor_id) do update set
    empresa_id = excluded.empresa_id, reserva_id = excluded.reserva_id, lat = excluded.lat, lng = excluded.lng,
    precision_m = excluded.precision_m, rumbo = excluded.rumbo, velocidad_kmh = excluded.velocidad_kmh,
    actualizado_en = excluded.actualizado_en;
end $$;

-- El pasajero solo ve la ubicación mientras su servicio está en curso y si es reciente (15 min).
create or replace function ver_ubicacion_publica(p_token uuid)
returns table (o_lat double precision, o_lng double precision, o_precision int, o_rumbo int, o_actualizado timestamptz)
language sql stable security definer set search_path = public as $$
  select u.lat, u.lng, u.precision_m, u.rumbo, u.actualizado_en
  from reservas r join ubicaciones u on u.conductor_id = r.conductor_id
  where r.token_seguimiento = p_token
    and r.estado in ('en_camino', 'en_lugar', 'a_bordo')
    and u.actualizado_en > now() - interval '15 minutes'
$$;

revoke execute on function conductor_ubicacion(double precision, double precision, int, int, int) from public, anon;
grant execute on function conductor_ubicacion(double precision, double precision, int, int, int) to authenticated;
revoke execute on function ver_ubicacion_publica(uuid) from public;
grant execute on function ver_ubicacion_publica(uuid) to anon, authenticated;
