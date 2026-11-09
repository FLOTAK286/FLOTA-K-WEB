-- Etapa 2: asignación de conductor y vehículo, duración estimada, derivación a la red.
alter table perfiles add column if not exists conduce boolean not null default false;
update perfiles set conduce = true where rol = 'conductor';

create table if not exists vehiculos (
  id          uuid primary key default gen_random_uuid(),
  empresa_id  uuid not null references empresas(id),
  patente     text not null,
  descripcion text,
  tipo        text not null default 'auto' check (tipo in ('auto', 'suv', 'van')),
  capacidad   int not null default 4 check (capacidad between 1 and 20),
  conductor_habitual uuid references perfiles(id),
  activo      boolean not null default true,
  creado_en   timestamptz not null default now(),
  unique (empresa_id, patente)
);
alter table vehiculos enable row level security;
create policy vehiculos_ver on vehiculos for select
  using (empresa_id = mi_empresa());
create policy vehiculos_admin on vehiculos for all
  using (empresa_id = mi_empresa() and mi_rol() = 'admin')
  with check (empresa_id = mi_empresa() and mi_rol() = 'admin');

alter table reservas add column if not exists vehiculo_id uuid references vehiculos(id);
alter table reservas add column if not exists duracion_min int not null default 90 check (duracion_min between 15 and 1440);
alter table reservas add column if not exists derivado_a text;
alter table reservas add column if not exists costo_partner int check (costo_partner >= 0);

create or replace function asignar_reserva(p_reserva uuid, p_conductor uuid, p_vehiculo uuid default null, p_derivado_a text default null, p_costo_partner int default null)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_emp uuid := mi_empresa();
  v_estado estado_reserva;
  v_nombre text;
  v_nota text;
begin
  if not es_staff() then raise exception 'Sin permiso'; end if;
  select estado into v_estado from reservas where id = p_reserva and empresa_id = v_emp for update;
  if not found then raise exception 'Reserva no encontrada'; end if;
  if p_conductor is not null and not exists (select 1 from perfiles where id = p_conductor and empresa_id = v_emp and activo) then
    raise exception 'Conductor no válido';
  end if;
  if p_vehiculo is not null and not exists (select 1 from vehiculos where id = p_vehiculo and empresa_id = v_emp) then
    raise exception 'Vehículo no válido';
  end if;

  update reservas set conductor_id = p_conductor, vehiculo_id = p_vehiculo,
         derivado_a = nullif(trim(coalesce(p_derivado_a, '')), ''), costo_partner = p_costo_partner
   where id = p_reserva;

  select nombre into v_nombre from perfiles where id = p_conductor;
  v_nota := case
    when nullif(trim(coalesce(p_derivado_a, '')), '') is not null then 'Derivado a ' || trim(p_derivado_a)
    when p_conductor is null then 'Sin conductor asignado'
    else 'Asignado a ' || v_nombre end;

  if p_conductor is not null or nullif(trim(coalesce(p_derivado_a, '')), '') is not null then
    if v_estado in ('recibida', 'confirmada') then
      update reservas set estado = 'asignada' where id = p_reserva;
      update reserva_eventos set nota = v_nota
        where id = (select max(id) from reserva_eventos where reserva_id = p_reserva);
      return;
    end if;
  end if;
  insert into reserva_eventos (reserva_id, estado, nota, usuario_id)
  values (p_reserva, (select estado from reservas where id = p_reserva), v_nota, auth.uid());
end $$;

revoke execute on function asignar_reserva(uuid, uuid, uuid, text, int) from public, anon;
grant execute on function asignar_reserva(uuid, uuid, uuid, text, int) to authenticated;

update perfiles set conduce = true where rol = 'admin';
