-- Etapa 47: saldo de la(s) cuenta(s) bancaria(s) de la empresa, registrado a mano con su fecha (historial).
-- Nada se borra: un saldo mal ingresado se anula.
create table if not exists saldos_cuenta (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id),
  cuenta text not null default 'Cuenta corriente' check (length(cuenta) between 2 and 80),
  fecha date not null,
  saldo bigint not null check (saldo between -100000000000 and 100000000000),
  nota text check (length(nota) <= 300),
  creado_por uuid references perfiles(id),
  creado_en timestamptz not null default now(),
  anulado_en timestamptz,
  anulado_por uuid references perfiles(id)
);
create index if not exists saldos_cuenta_empresa on saldos_cuenta (empresa_id, cuenta, fecha desc);
alter table saldos_cuenta enable row level security;
create policy saldos_admin_ver on saldos_cuenta for select using (empresa_id = mi_empresa() and mi_rol() = 'admin');
create policy saldos_admin_crear on saldos_cuenta for insert with check (empresa_id = mi_empresa() and mi_rol() = 'admin' and anulado_en is null);
create policy saldos_admin_editar on saldos_cuenta for update using (empresa_id = mi_empresa() and mi_rol() = 'admin')
  with check (empresa_id = mi_empresa() and mi_rol() = 'admin');
