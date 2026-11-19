-- Etapa 51: un propietario que también conduce (rol propietario + "También conduce") registra su vehículo desde la app del conductor
-- (Perfil → Mi vehículo) y queda automáticamente como su propietario, así lo ve en /propietario con sus reportes.
do $$
declare f text;
begin
  f := pg_get_functiondef('conductor_guardar_vehiculo'::regproc);
  if position('foto_path, propio, activo)' in f) = 0 or position('auth.uid(), p_foto_path, false, true)' in f) = 0
     or position('foto_path = coalesce(p_foto_path, foto_path)' in f) = 0 then
    raise exception 'conductor_guardar_vehiculo cambió: revisar la migración';
  end if;
  f := replace(f, 'foto_path, propio, activo)', 'foto_path, propio, activo, propietario_id)');
  f := replace(f, 'auth.uid(), p_foto_path, false, true)',
    'auth.uid(), p_foto_path, false, true, (select case when rol = ''propietario'' then auth.uid() end from perfiles where id = auth.uid()))');
  f := replace(f, 'foto_path = coalesce(p_foto_path, foto_path)',
    'foto_path = coalesce(p_foto_path, foto_path), propietario_id = coalesce(propietario_id, (select case when rol = ''propietario'' then auth.uid() end from perfiles where id = auth.uid()))');
  execute f;
end $$;
