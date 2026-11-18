-- Etapa 47c: (1) los gastos del cierre diario pueden "descontar" de lo que la empresa ya compró (p. ej. combustible)
-- o "sumar" como gasto nuevo, por concepto; (2) el administrador puede corregir un cierre (queda quién, cuándo y los valores
-- originales); (3) presupuestos mensuales por concepto (y opcionalmente por patente).
alter table cierres_diarios add column if not exists editado_por uuid references perfiles(id);
alter table cierres_diarios add column if not exists editado_en timestamptz;
alter table cierres_diarios add column if not exists original jsonb;

create or replace function cierres_guardar_original()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and auth.uid() is distinct from old.conductor_id and mi_rol() = 'admin' then
    new.editado_por := auth.uid(); new.editado_en := now();
    if old.original is null then
      new.original := jsonb_build_object('km_recorridos', old.km_recorridos, 'cabify_ingreso', old.cabify_ingreso, 'cabify_viajes', old.cabify_viajes,
        'cabify_peajes', old.cabify_peajes, 'otras_ingreso', old.otras_ingreso, 'combustible', old.combustible, 'otros_gastos', old.otros_gastos);
    end if;
  end if;
  return new;
end $$;
create trigger cierres_guardar_original before update on cierres_diarios
  for each row execute function cierres_guardar_original();

-- Configuración por concepto ("descuenta" de lo comprado o "suma" como gasto) + fuente de los ingresos de apps
alter table empresas alter column reportes_config set default
  '{"combustible": "descuenta", "peajes": "descuenta", "otros": "descuenta", "ingresos_apps": "cierres"}'::jsonb;
update empresas set reportes_config = jsonb_build_object(
  'combustible', case when reportes_config->>'gastos' = 'cierres' then 'suma' else 'descuenta' end,
  'peajes', case when reportes_config->>'gastos' = 'cierres' then 'suma' else 'descuenta' end,
  'otros', case when reportes_config->>'gastos' = 'cierres' then 'suma' else 'descuenta' end,
  'ingresos_apps', coalesce(reportes_config->>'ingresos_apps', 'cierres'))
 where slug = 'flota-k' and reportes_config ? 'gastos';

-- Presupuestos mensuales por concepto (vehiculo_id vacío = para toda la empresa)
create table if not exists presupuestos (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id),
  categoria text not null,
  vehiculo_id uuid references vehiculos(id),
  monto_mensual integer not null check (monto_mensual > 0 and monto_mensual <= 1000000000),
  activo boolean not null default true,
  creado_por uuid references perfiles(id),
  creado_en timestamptz not null default now()
);
alter table presupuestos enable row level security;
create policy presupuestos_admin_ver on presupuestos for select using (empresa_id = mi_empresa() and mi_rol() = 'admin');
create policy presupuestos_admin_crear on presupuestos for insert with check (empresa_id = mi_empresa() and mi_rol() = 'admin');
create policy presupuestos_admin_editar on presupuestos for update using (empresa_id = mi_empresa() and mi_rol() = 'admin')
  with check (empresa_id = mi_empresa() and mi_rol() = 'admin');
