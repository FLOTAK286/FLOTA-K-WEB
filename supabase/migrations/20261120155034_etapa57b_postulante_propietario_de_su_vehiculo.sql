-- Etapa 57b: al aprobar una inscripción con vehículo propio, el conductor queda también como propietario de ese vehículo
-- (antes quedaba solo como conductor habitual y el vehículo figuraba como de Flota-K en el selector de propietario).
do $$
declare f text;
begin
  f := pg_get_functiondef('aprobar_postulante(uuid, boolean, text)'::regprocedure);
  if position('insert into vehiculos (empresa_id, patente, marca, modelo, anio, color, conductor_habitual, propio, descripcion, categoria, tipo, capacidad)' in f) = 0
     or position('values (p.empresa_id, p.patente, p.marca, p.modelo, p.anio, p.color, p_id, false,' in f) = 0 then
    raise exception 'aprobar_postulante cambió: revisar la migración';
  end if;
  f := replace(f, 'insert into vehiculos (empresa_id, patente, marca, modelo, anio, color, conductor_habitual, propio, descripcion, categoria, tipo, capacidad)',
                  'insert into vehiculos (empresa_id, patente, marca, modelo, anio, color, conductor_habitual, propietario_id, propio, descripcion, categoria, tipo, capacidad)');
  f := replace(f, 'values (p.empresa_id, p.patente, p.marca, p.modelo, p.anio, p.color, p_id, false,',
                  'values (p.empresa_id, p.patente, p.marca, p.modelo, p.anio, p.color, p_id, p_id, false,');
  execute f;
end $$;

-- Corrige los vehículos ya creados por una inscripción aprobada que quedaron sin propietario (caso Bruno Oliveri, KKLJ80)
update vehiculos v set propietario_id = v.conductor_habitual
  from postulaciones_conductor pc
 where pc.id = v.conductor_habitual and pc.tiene_vehiculo and pc.patente = v.patente
   and v.propietario_id is null and v.propio = false;
