-- Etapa 9: categoría del vehículo y número de móvil por conductor.
-- La categoría que pide el servicio ya existe en reservas.vehiculo: auto (cualquiera), suv (SUV o van), van (solo van).
-- Si no calza, el panel advierte y el despachador decide (no se bloquea).

alter table vehiculos add column if not exists categoria text not null default 'taxi_basico'
  check (categoria in ('taxi_basico','taxi_turismo','taxi_ejecutivo','suv','van'));

alter table perfiles add column if not exists movil text check (length(movil) <= 10);
create unique index if not exists perfiles_movil_unico on perfiles (empresa_id, movil) where movil is not null;

-- Asignación: igual que antes, y la nota del historial incluye el número de móvil.
create or replace function asignar_reserva(p_reserva uuid, p_conductor uuid, p_vehiculo uuid default null, p_derivado_a text default null, p_costo_partner integer default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_emp uuid := mi_empresa();
  v_estado estado_reserva;
  v_nombre text;
  v_nota text;
  v_veh uuid := p_vehiculo;
begin
  if not es_staff() then raise exception 'Sin permiso'; end if;
  select estado into v_estado from reservas where id = p_reserva and empresa_id = v_emp for update;
  if not found then raise exception 'Reserva no encontrada'; end if;
  if p_conductor is not null and not exists (select 1 from perfiles where id = p_conductor and empresa_id = v_emp and activo) then
    raise exception 'Conductor no válido';
  end if;
  if v_veh is null and p_conductor is not null then
    select id into v_veh from vehiculos
      where empresa_id = v_emp and conductor_habitual = p_conductor and activo order by creado_en limit 1;
  end if;
  if v_veh is not null and not exists (select 1 from vehiculos where id = v_veh and empresa_id = v_emp) then
    raise exception 'Vehículo no válido';
  end if;

  update reservas set conductor_id = p_conductor, vehiculo_id = v_veh,
         derivado_a = nullif(trim(coalesce(p_derivado_a, '')), ''), costo_partner = p_costo_partner
   where id = p_reserva;

  select coalesce('Móvil ' || movil || ' · ', '') || nombre into v_nombre from perfiles where id = p_conductor;
  v_nota := case
    when nullif(trim(coalesce(p_derivado_a, '')), '') is not null then 'Derivado a ' || trim(p_derivado_a)
    when p_conductor is null then 'Sin conductor asignado'
    else 'Asignado a ' || v_nombre || coalesce(' · ' || (select patente from vehiculos where id = v_veh), '') end;

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
