-- Etapa 66: lista de empresas por contactar (ventas) dentro del panel. Estado, próximo seguimiento y notas.
-- Nada se borra: una empresa que no interesa queda "descartada".
create table if not exists prospectos (
  id bigint generated always as identity primary key,
  empresa_id uuid not null references empresas(id),
  empresa text not null check (length(empresa) between 1 and 200),
  rubro text check (length(rubro) <= 100),
  contacto text check (length(contacto) <= 200),
  cargo text check (length(cargo) <= 100),
  correo text check (length(correo) <= 200),
  telefono text check (length(telefono) <= 40),
  linkedin text check (length(linkedin) <= 300),
  canal text check (length(canal) <= 40),
  estado text not null default 'por_contactar' check (estado in ('por_contactar', 'contactado', 'respondio', 'propuesta', 'prueba', 'convenio', 'descartado')),
  proximo_contacto date,
  notas text check (length(notas) <= 3000),
  creado_por uuid references perfiles(id),
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);
alter table prospectos enable row level security;
create policy prospectos_ver on prospectos for select using (empresa_id = mi_empresa() and mi_rol() = 'admin');
create policy prospectos_crear on prospectos for insert with check (empresa_id = mi_empresa() and mi_rol() = 'admin');
create policy prospectos_editar on prospectos for update using (empresa_id = mi_empresa() and mi_rol() = 'admin') with check (empresa_id = mi_empresa() and mi_rol() = 'admin');
create index if not exists prospectos_empresa_idx on prospectos (empresa_id, estado, proximo_contacto);

create or replace function prospectos_tocar() returns trigger language plpgsql as $$
begin new.actualizado_en := now(); return new; end $$;
create trigger prospectos_actualizado before update on prospectos for each row execute function prospectos_tocar();
