-- Etapa 14: cierre diario solo para vehículos propios de Flota-K (no prestadores).
-- El conductor registra odómetro, lo hecho en Cabify u otras apps y sus gastos; lo de Flota-K se calcula solo.

alter table vehiculos add column if not exists propio boolean not null default true;

create table if not exists cierres_diarios (
  id              bigint generated always as identity primary key,
  empresa_id      uuid not null references empresas(id),
  vehiculo_id     uuid not null references vehiculos(id),
  conductor_id    uuid references auth.users(id),
  fecha           date not null,
  km_inicio       int check (km_inicio >= 0),
  km_fin          int check (km_fin >= 0),
  km_recorridos   int not null default 0 check (km_recorridos between 0 and 3000),
  cabify_ingreso  int not null default 0 check (cabify_ingreso >= 0),
  cabify_viajes   int not null default 0 check (cabify_viajes between 0 and 200),
  cabify_peajes   int not null default 0 check (cabify_peajes >= 0),
  otras_ingreso   int not null default 0 check (otras_ingreso >= 0),
  otras_detalle   text check (length(otras_detalle) <= 200),
  combustible     int not null default 0 check (combustible >= 0),
  otros_gastos    int not null default 0 check (otros_gastos >= 0),
  notas           text check (length(notas) <= 1000),
  creado_en       timestamptz not null default now(),
  actualizado_en  timestamptz not null default now(),
  unique (vehiculo_id, fecha)
);
create index if not exists cierres_fecha on cierres_diarios (empresa_id, fecha);
alter table cierres_diarios enable row level security;
create policy cierres_equipo_ver on cierres_diarios for select using (empresa_id = mi_empresa() and es_staff());
create policy cierres_admin on cierres_diarios for all
  using (empresa_id = mi_empresa() and mi_rol() = 'admin') with check (empresa_id = mi_empresa() and mi_rol() = 'admin');
create policy cierres_conductor_ver on cierres_diarios for select using (conductor_id = auth.uid());

-- El conductor guarda (o corrige) el cierre de un día, solo con su vehículo fijo y solo si es propio de Flota-K.
create or replace function guardar_cierre(p_fecha date, p_km_inicio int, p_km_fin int,
  p_cabify_ingreso int default 0, p_cabify_viajes int default 0, p_cabify_peajes int default 0,
  p_otras_ingreso int default 0, p_otras_detalle text default null,
  p_combustible int default 0, p_otros_gastos int default 0, p_notas text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v record; v_km int;
begin
  select id, empresa_id into v from vehiculos
   where conductor_habitual = auth.uid() and activo and propio order by creado_en limit 1;
  if not found then raise exception 'El cierre diario está disponible solo para vehículos propios de Flota-K'; end if;
  if p_fecha is null or p_fecha > (now() at time zone 'America/Santiago')::date or p_fecha < (now() at time zone 'America/Santiago')::date - 7 then
    raise exception 'Puede registrar el cierre de hoy o de los últimos 7 días';
  end if;
  if p_km_inicio is null or p_km_fin is null then raise exception 'Ingrese el odómetro al inicio y al final del día'; end if;
  v_km := p_km_fin - p_km_inicio;
  if v_km < 0 then raise exception 'El odómetro final no puede ser menor que el inicial'; end if;
  if v_km > 3000 then raise exception 'Revise el odómetro: más de 3.000 km en un día'; end if;
  insert into cierres_diarios (empresa_id, vehiculo_id, conductor_id, fecha, km_inicio, km_fin, km_recorridos,
    cabify_ingreso, cabify_viajes, cabify_peajes, otras_ingreso, otras_detalle, combustible, otros_gastos, notas)
  values (v.empresa_id, v.id, auth.uid(), p_fecha, p_km_inicio, p_km_fin, v_km,
    greatest(coalesce(p_cabify_ingreso, 0), 0), greatest(coalesce(p_cabify_viajes, 0), 0), greatest(coalesce(p_cabify_peajes, 0), 0),
    greatest(coalesce(p_otras_ingreso, 0), 0), nullif(left(trim(coalesce(p_otras_detalle, '')), 200), ''),
    greatest(coalesce(p_combustible, 0), 0), greatest(coalesce(p_otros_gastos, 0), 0), nullif(left(trim(coalesce(p_notas, '')), 1000), ''))
  on conflict (vehiculo_id, fecha) do update set
    conductor_id = excluded.conductor_id, km_inicio = excluded.km_inicio, km_fin = excluded.km_fin, km_recorridos = excluded.km_recorridos,
    cabify_ingreso = excluded.cabify_ingreso, cabify_viajes = excluded.cabify_viajes, cabify_peajes = excluded.cabify_peajes,
    otras_ingreso = excluded.otras_ingreso, otras_detalle = excluded.otras_detalle, combustible = excluded.combustible,
    otros_gastos = excluded.otros_gastos, notas = excluded.notas, actualizado_en = now();
end $$;
revoke execute on function guardar_cierre(date, int, int, int, int, int, int, text, int, int, text) from public, anon;
grant execute on function guardar_cierre(date, int, int, int, int, int, int, text, int, int, text) to authenticated;

-- ¿Este conductor puede hacer cierre? (vehículo fijo propio) y último odómetro registrado
create or replace function mi_cierre_info()
returns table (o_vehiculo_id uuid, o_patente text, o_ultimo_km int)
language sql stable security definer set search_path = public as $$
  select v.id, v.patente, (select c.km_fin from cierres_diarios c where c.vehiculo_id = v.id order by c.fecha desc limit 1)
  from vehiculos v where v.conductor_habitual = auth.uid() and v.activo and v.propio order by v.creado_en limit 1
$$;
revoke execute on function mi_cierre_info() from public, anon;
grant execute on function mi_cierre_info() to authenticated;
