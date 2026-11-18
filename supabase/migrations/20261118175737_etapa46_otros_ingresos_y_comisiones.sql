-- Etapa 46: otros ingresos (Cabify, Servimóvil, Uber, etc.) con su comisión, para el resultado de la empresa y por patente.
-- Cada plataforma tiene un % de comisión por defecto (editable); cada ingreso guarda el % que se usó.
create table if not exists fuentes_ingreso (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id),
  nombre text not null check (length(nombre) between 2 and 60),
  comision_pct numeric(5,2) not null default 0 check (comision_pct >= 0 and comision_pct <= 100),
  activo boolean not null default true,
  orden int not null default 0,
  unique (empresa_id, nombre)
);
alter table fuentes_ingreso enable row level security;
create policy fuentes_admin_ver on fuentes_ingreso for select using (empresa_id = mi_empresa() and mi_rol() = 'admin');
create policy fuentes_admin_crear on fuentes_ingreso for insert with check (empresa_id = mi_empresa() and mi_rol() = 'admin');
create policy fuentes_admin_editar on fuentes_ingreso for update using (empresa_id = mi_empresa() and mi_rol() = 'admin')
  with check (empresa_id = mi_empresa() and mi_rol() = 'admin');

insert into fuentes_ingreso (empresa_id, nombre, comision_pct, orden)
select e.id, f.nombre, f.pct, f.orden from empresas e
cross join (values ('Cabify', 0, 1), ('Servimóvil', 23, 2), ('Uber', 0, 3), ('DiDi', 0, 4), ('Particular (fuera de la plataforma)', 0, 5), ('Otra', 0, 6)) as f(nombre, pct, orden)
where e.slug = 'flota-k'
on conflict (empresa_id, nombre) do nothing;

create table if not exists ingresos_externos (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id),
  fecha date not null,
  fuente_id uuid not null references fuentes_ingreso(id),
  vehiculo_id uuid references vehiculos(id),
  monto_bruto integer not null check (monto_bruto > 0 and monto_bruto <= 1000000000),
  comision_pct numeric(5,2) not null default 0 check (comision_pct >= 0 and comision_pct <= 100),
  comision integer not null default 0 check (comision >= 0),
  neto integer not null,
  viajes integer check (viajes between 0 and 10000),
  descripcion text check (length(descripcion) <= 500),
  creado_por uuid references perfiles(id),
  creado_en timestamptz not null default now(),
  anulado_en timestamptz,
  anulado_por uuid references perfiles(id)
);
create index if not exists ingresos_externos_empresa_fecha on ingresos_externos (empresa_id, fecha);
alter table ingresos_externos enable row level security;
create policy ingext_admin_ver on ingresos_externos for select using (empresa_id = mi_empresa() and mi_rol() = 'admin');
create policy ingext_admin_crear on ingresos_externos for insert with check (empresa_id = mi_empresa() and mi_rol() = 'admin' and anulado_en is null);
create policy ingext_admin_editar on ingresos_externos for update using (empresa_id = mi_empresa() and mi_rol() = 'admin')
  with check (empresa_id = mi_empresa() and mi_rol() = 'admin');

-- La comisión y el neto se calculan siempre en la base de datos (no se pueden descuadrar)
create or replace function ingresos_externos_calcular()
returns trigger language plpgsql set search_path = public as $$
begin
  new.comision := round(new.monto_bruto * new.comision_pct / 100.0);
  new.neto := new.monto_bruto - new.comision;
  return new;
end $$;
create trigger ingresos_externos_calcular before insert or update of monto_bruto, comision_pct on ingresos_externos
  for each row execute function ingresos_externos_calcular();
