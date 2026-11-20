-- Etapa 58: el dueño de vehículo (rol propietario) inscribe a sus propios conductores con un enlace personal
-- (/conductor/?dueno=<código>) y les asigna sus vehículos desde /propietario. Flota-K igual aprueba a cada conductor
-- en Equipo y roles antes de que reciba servicios.
alter table perfiles add column if not exists codigo_dueno text unique;
alter table postulaciones_conductor add column if not exists invitado_por uuid references perfiles(id);

-- Código personal del dueño (se crea la primera vez)
create or replace function propietario_codigo()
returns text language plpgsql security definer set search_path = public, extensions as $$
declare v text;
begin
  select codigo_dueno into v from perfiles where id = auth.uid() and activo and rol = 'propietario';
  if not found then raise exception 'Solo dueños de vehículos'; end if;
  if v is null then
    v := encode(gen_random_bytes(6), 'hex');
    update perfiles set codigo_dueno = v where id = auth.uid();
  end if;
  return v;
end $$;
revoke execute on function propietario_codigo() from public, anon;
grant execute on function propietario_codigo() to authenticated;

-- ¿El enlace de un dueño es válido? (para el formulario: "Flota-K · conductor de <dueño>")
create or replace function inscripcion_dueno(p_codigo text)
returns text language sql stable security definer set search_path = public as $$
  select e.nombre || ' · conductor de ' || p.nombre from perfiles p join empresas e on e.id = p.empresa_id
   where p.codigo_dueno = lower(trim(p_codigo)) and p.activo and p.rol = 'propietario'
$$;
revoke execute on function inscripcion_dueno(text) from public;
grant execute on function inscripcion_dueno(text) to anon, authenticated;

-- Inscripción: acepta el código de la empresa o el de un dueño (en ese caso el conductor queda ligado al dueño y sin vehículo propio)
do $$
declare f text;
begin
  f := pg_get_functiondef('conductor_postular(uuid, text, text, jsonb)'::regprocedure);
  if position('  select id into v_emp from empresas where inscripcion_codigo = lower(trim(p_codigo)) and inscripcion_activa;' in f) = 0
     or position('v_cat, v_veh and coalesce((p_datos->>''decreto80'')::boolean, false));' in f) = 0
     or position('declare v_emp uuid; v_nom text; v_tel text; v_veh boolean; v_cat text;' in f) = 0
     or position('  v_veh := coalesce((p_datos->>''tiene_vehiculo'')::boolean, false);' in f) = 0
     or position('v_nom || '' · '' || coalesce(v_tel, '''') || ''. Revíselo y actívelo en Equipo y roles.''' in f) = 0 then
    raise exception 'conductor_postular cambió: revisar la migración';
  end if;
  f := replace(f, 'declare v_emp uuid; v_nom text; v_tel text; v_veh boolean; v_cat text;',
                  'declare v_emp uuid; v_nom text; v_tel text; v_veh boolean; v_cat text; v_dueno perfiles;');
  f := replace(f, '  select id into v_emp from empresas where inscripcion_codigo = lower(trim(p_codigo)) and inscripcion_activa;',
'  if p_datos->>''dueno'' is not null then
    select * into v_dueno from perfiles where codigo_dueno = lower(trim(p_datos->>''dueno'')) and activo and rol = ''propietario'';
    v_emp := v_dueno.empresa_id;
  else
    select id into v_emp from empresas where inscripcion_codigo = lower(trim(p_codigo)) and inscripcion_activa;
  end if;');
  f := replace(f, '  v_veh := coalesce((p_datos->>''tiene_vehiculo'')::boolean, false);',
                  '  v_veh := coalesce((p_datos->>''tiene_vehiculo'')::boolean, false) and v_dueno.id is null;');
  f := replace(f, 'v_cat, v_veh and coalesce((p_datos->>''decreto80'')::boolean, false));',
'v_cat, v_veh and coalesce((p_datos->>''decreto80'')::boolean, false));
  if v_dueno.id is not null then update postulaciones_conductor set invitado_por = v_dueno.id where id = p_uid; end if;');
  f := replace(f, 'v_nom || '' · '' || coalesce(v_tel, '''') || ''. Revíselo y actívelo en Equipo y roles.''',
                  'v_nom || '' · '' || coalesce(v_tel, '''') || coalesce('' · inscrito por el dueño '' || v_dueno.nombre, '''') || ''. Revíselo y actívelo en Equipo y roles.''');
  execute f;
end $$;

-- Conductores del dueño: él mismo (si conduce) y los que inscribió con su enlace
create or replace function propietario_conductores()
returns table(o_id uuid, o_nombre text, o_telefono text, o_estado text, o_patente text, o_es_yo boolean)
language sql stable security definer set search_path = public as $$
  select p.id, p.nombre, p.telefono,
         case when p.activo then 'activo' when p.postulacion = 'pendiente' then 'pendiente' when p.postulacion = 'rechazada' then 'rechazado' else 'inactivo' end,
         (select v.patente from vehiculos v where v.conductor_habitual = p.id and v.propietario_id = auth.uid() order by v.patente limit 1),
         p.id = auth.uid()
  from perfiles p
  where (p.id = auth.uid() and p.conduce)
     or p.id in (select pc.id from postulaciones_conductor pc where pc.invitado_por = auth.uid())
  order by p.id = auth.uid() desc, p.nombre
$$;
revoke execute on function propietario_conductores() from public, anon;
grant execute on function propietario_conductores() to authenticated;

-- El dueño asigna el conductor de uno de sus vehículos (él mismo o uno de sus conductores; null = sin conductor)
create or replace function propietario_asignar_conductor(p_vehiculo uuid, p_conductor uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v vehiculos; v_nom text;
begin
  select * into v from vehiculos where id = p_vehiculo and propietario_id = auth.uid();
  if v.id is null then raise exception 'Vehículo no encontrado'; end if;
  if p_conductor is not null and not exists (select 1 from propietario_conductores() c where c.o_id = p_conductor and c.o_estado <> 'rechazado') then
    raise exception 'Ese conductor no está entre los suyos';
  end if;
  if p_conductor is not null then  -- un conductor maneja un solo vehículo del dueño a la vez
    update vehiculos set conductor_habitual = null where propietario_id = auth.uid() and conductor_habitual = p_conductor and id <> v.id;
  end if;
  update vehiculos set conductor_habitual = p_conductor where id = v.id;
  select nombre into v_nom from perfiles where id = p_conductor;
  insert into soporte_mensajes (empresa_id, conductor_id, autor, usuario_id, texto)
  select v.empresa_id, auth.uid(), 'conductor', auth.uid(),
         '🚗 Cambié el conductor de mi vehículo ' || v.patente || ': ' || coalesce(v_nom, 'sin conductor fijo') || '.'
   where exists (select 1 from perfiles where id = auth.uid() and (conduce or rol = 'conductor'));
end $$;
revoke execute on function propietario_asignar_conductor(uuid, uuid) from public, anon;
grant execute on function propietario_asignar_conductor(uuid, uuid) to authenticated;
