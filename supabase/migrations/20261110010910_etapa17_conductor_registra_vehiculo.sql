-- Etapa 17: el conductor registra (o actualiza) su propio vehículo desde la app, con foto y documentos.
-- No puede tocar vehículos de Flota-K (propios) ni usar una patente ya registrada. La central recibe un aviso.

create or replace function conductor_guardar_vehiculo(p_patente text, p_marca text, p_modelo text, p_anio int, p_color text,
  p_categoria text, p_capacidad int, p_foto_path text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_emp uuid; v_id uuid; v_propio boolean; v_otro uuid; v_nuevo boolean := false;
  v_pat text := upper(regexp_replace(coalesce(p_patente, ''), '[^A-Za-z0-9]', '', 'g'));
  v_marca text := nullif(left(trim(coalesce(p_marca, '')), 60), '');
  v_modelo text := nullif(left(trim(coalesce(p_modelo, '')), 60), '');
  v_color text := nullif(left(trim(coalesce(p_color, '')), 40), '');
begin
  select empresa_id into v_emp from perfiles where id = auth.uid() and activo and (conduce or rol = 'conductor');
  if v_emp is null then raise exception 'Solo los conductores pueden registrar su vehículo'; end if;
  if v_pat !~ '^[A-Z]{2,4}[0-9]{2,4}$' or length(v_pat) not between 5 and 6 then raise exception 'Revise la patente (ej.: ABCD12 o AB1234)'; end if;
  if v_marca is null or v_modelo is null then raise exception 'Ingrese la marca y el modelo'; end if;
  if p_anio is null or p_anio < 1980 or p_anio > extract(year from now())::int + 1 then raise exception 'Revise el año del vehículo'; end if;
  if p_categoria is null or p_categoria not in ('taxi_basico', 'taxi_turismo', 'taxi_ejecutivo', 'suv', 'van') then raise exception 'Elija la categoría del vehículo'; end if;
  if p_capacidad is null or p_capacidad < 1 or p_capacidad > 20 then raise exception 'Revise la cantidad de pasajeros'; end if;
  if p_foto_path is not null and p_foto_path not like v_emp::text || '/' || auth.uid()::text || '/%' then raise exception 'Foto no válida'; end if;

  select id, propio into v_id, v_propio from vehiculos where conductor_habitual = auth.uid() and empresa_id = v_emp order by activo desc, creado_en limit 1;
  if v_id is not null and v_propio then raise exception 'Su vehículo es de Flota-K: los cambios los hace la central'; end if;
  select id into v_otro from vehiculos where empresa_id = v_emp and patente = v_pat and id is distinct from v_id;
  if v_otro is not null then raise exception 'La patente % ya está registrada en Flota-K. Pida a la central que se la asigne.', v_pat; end if;

  if v_id is null then
    insert into vehiculos (empresa_id, patente, marca, modelo, anio, color, descripcion, categoria, tipo, capacidad, conductor_habitual, foto_path, propio, activo)
    values (v_emp, v_pat, v_marca, v_modelo, p_anio, v_color, concat_ws(' ', v_marca, v_modelo, lower(v_color)), p_categoria,
            case p_categoria when 'van' then 'van' when 'suv' then 'suv' else 'auto' end, p_capacidad, auth.uid(), p_foto_path, false, true)
    returning id into v_id;
    v_nuevo := true;
  else
    update vehiculos set patente = v_pat, marca = v_marca, modelo = v_modelo, anio = p_anio, color = v_color,
           descripcion = concat_ws(' ', v_marca, v_modelo, lower(v_color)), categoria = p_categoria,
           tipo = case p_categoria when 'van' then 'van' when 'suv' then 'suv' else 'auto' end,
           capacidad = p_capacidad, foto_path = coalesce(p_foto_path, foto_path)
     where id = v_id;
  end if;

  insert into soporte_mensajes (empresa_id, conductor_id, autor, usuario_id, texto)
  values (v_emp, auth.uid(), 'conductor', auth.uid(),
    (case when v_nuevo then '🚗 Registré mi vehículo: ' else '🚗 Actualicé los datos de mi vehículo: ' end)
    || concat_ws(' ', v_marca, v_modelo, p_anio::text, v_color) || ' · patente ' || v_pat || '. Por favor revíselo en Flota.');
  return v_id;
end $$;
revoke execute on function conductor_guardar_vehiculo(text, text, text, int, text, text, int, text) from public, anon;
grant execute on function conductor_guardar_vehiculo(text, text, text, int, text, text, int, text) to authenticated;

-- El conductor puede subir fotos solo en su carpeta: fotos/<empresa>/<su id>/...
create policy fotos_conductor_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'fotos' and (storage.foldername(name))[1] = (mi_empresa())::text and (storage.foldername(name))[2] = (auth.uid())::text);

-- Documentos de vehículo subidos por un conductor: solo de su propio vehículo.
create policy documentos_solo_vehiculo_propio on documentos as restrictive for insert to authenticated
  with check (mi_rol() = 'admin' or vehiculo_id is null or vehiculo_id in (select id from vehiculos where conductor_habitual = auth.uid()));
