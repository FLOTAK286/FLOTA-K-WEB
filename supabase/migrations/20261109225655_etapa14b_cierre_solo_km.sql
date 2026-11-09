-- Etapa 14b: el cierre diario se registra con los km recorridos del día (sin odómetro inicial/final).
create or replace function guardar_cierre_km(p_fecha date, p_km int,
  p_cabify_ingreso int default 0, p_cabify_viajes int default 0, p_cabify_peajes int default 0,
  p_otras_ingreso int default 0, p_otras_detalle text default null,
  p_combustible int default 0, p_otros_gastos int default 0, p_notas text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v record;
begin
  select id, empresa_id into v from vehiculos
   where conductor_habitual = auth.uid() and activo and propio order by creado_en limit 1;
  if not found then raise exception 'El cierre diario está disponible solo para vehículos propios de Flota-K'; end if;
  if p_fecha is null or p_fecha > (now() at time zone 'America/Santiago')::date or p_fecha < (now() at time zone 'America/Santiago')::date - 7 then
    raise exception 'Puede registrar el cierre de hoy o de los últimos 7 días';
  end if;
  if p_km is null or p_km < 0 then raise exception 'Ingrese los kilómetros recorridos del día'; end if;
  if p_km > 3000 then raise exception 'Revise los kilómetros: más de 3.000 km en un día'; end if;
  insert into cierres_diarios (empresa_id, vehiculo_id, conductor_id, fecha, km_inicio, km_fin, km_recorridos,
    cabify_ingreso, cabify_viajes, cabify_peajes, otras_ingreso, otras_detalle, combustible, otros_gastos, notas)
  values (v.empresa_id, v.id, auth.uid(), p_fecha, null, null, p_km,
    greatest(coalesce(p_cabify_ingreso, 0), 0), greatest(coalesce(p_cabify_viajes, 0), 0), greatest(coalesce(p_cabify_peajes, 0), 0),
    greatest(coalesce(p_otras_ingreso, 0), 0), nullif(left(trim(coalesce(p_otras_detalle, '')), 200), ''),
    greatest(coalesce(p_combustible, 0), 0), greatest(coalesce(p_otros_gastos, 0), 0), nullif(left(trim(coalesce(p_notas, '')), 1000), ''))
  on conflict (vehiculo_id, fecha) do update set
    conductor_id = excluded.conductor_id, km_inicio = null, km_fin = null, km_recorridos = excluded.km_recorridos,
    cabify_ingreso = excluded.cabify_ingreso, cabify_viajes = excluded.cabify_viajes, cabify_peajes = excluded.cabify_peajes,
    otras_ingreso = excluded.otras_ingreso, otras_detalle = excluded.otras_detalle, combustible = excluded.combustible,
    otros_gastos = excluded.otros_gastos, notas = excluded.notas, actualizado_en = now();
end $$;
revoke execute on function guardar_cierre_km(date, int, int, int, int, int, text, int, int, text) from public, anon;
grant execute on function guardar_cierre_km(date, int, int, int, int, int, text, int, int, text) to authenticated;
