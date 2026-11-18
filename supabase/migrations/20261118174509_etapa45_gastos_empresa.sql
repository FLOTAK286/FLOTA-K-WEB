-- Etapa 45: gastos de la empresa (generales o de un móvil) para los reportes: combustible, peajes/TAG, cuota del auto, etc.
-- Nada se borra: un gasto mal ingresado se anula (queda registrado quién y cuándo).
create table if not exists gastos (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id),
  fecha date not null,
  categoria text not null check (categoria in ('combustible', 'peajes_tag', 'cuota_auto', 'mantencion', 'neumaticos', 'seguro',
    'permiso_circulacion', 'revision_tecnica', 'estacionamiento', 'lavado', 'sueldos', 'partners', 'oficina', 'telefonia',
    'publicidad', 'contabilidad', 'impuestos', 'otros')),
  monto integer not null check (monto > 0 and monto <= 1000000000),
  descripcion text check (length(descripcion) <= 500),
  vehiculo_id uuid references vehiculos(id),
  fijo boolean not null default false,              -- se repite todos los meses (ej.: cuota del auto, seguro)
  creado_por uuid references perfiles(id),
  creado_en timestamptz not null default now(),
  anulado_en timestamptz,
  anulado_por uuid references perfiles(id)
);
create index if not exists gastos_empresa_fecha on gastos (empresa_id, fecha);
alter table gastos enable row level security;
create policy gastos_admin_ver on gastos for select using (empresa_id = mi_empresa() and mi_rol() = 'admin');
create policy gastos_admin_crear on gastos for insert with check (empresa_id = mi_empresa() and mi_rol() = 'admin' and anulado_en is null);
create policy gastos_admin_editar on gastos for update using (empresa_id = mi_empresa() and mi_rol() = 'admin')
  with check (empresa_id = mi_empresa() and mi_rol() = 'admin');
