-- Etapa 49c: tres categorías nuevas de vehículo: Particular sedán, Particular SUV y Particular VIP.
-- "Particular SUV" sirve para las reservas que piden SUV (igual que SUV y Van). En la inscripción el conductor elige la categoría.

alter table vehiculos drop constraint if exists vehiculos_categoria_check;
alter table vehiculos add constraint vehiculos_categoria_check check (categoria in
  ('taxi_basico', 'taxi_turismo', 'taxi_ejecutivo', 'suv', 'van', 'particular_sedan', 'particular_suv', 'particular_vip'));

alter table postulaciones_conductor add column if not exists categoria text check (categoria in
  ('taxi_basico', 'taxi_turismo', 'taxi_ejecutivo', 'suv', 'van', 'particular_sedan', 'particular_suv', 'particular_vip'));

-- Reservas que piden SUV: también la puede tomar un "Particular SUV"
do $$
declare f text;
begin
  foreach f in array array['bolsa_servicios', 'conductor_tomar_reserva', 'conductor_guardar_vehiculo'] loop
    execute replace(replace(replace(pg_get_functiondef(f::regproc),
      'in (''suv'', ''van'')', 'in (''suv'', ''van'', ''particular_suv'')'),
      'not in (''taxi_basico'', ''taxi_turismo'', ''taxi_ejecutivo'', ''suv'', ''van'')',
      'not in (''taxi_basico'', ''taxi_turismo'', ''taxi_ejecutivo'', ''suv'', ''van'', ''particular_sedan'', ''particular_suv'', ''particular_vip'')'),
      'when ''suv'' then ''suv'' else ''auto'' end', 'when ''suv'' then ''suv'' when ''particular_suv'' then ''suv'' else ''auto'' end');
  end loop;
end $$;

create or replace function conductor_postular(p_uid uuid, p_codigo text, p_correo text, p_datos jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v_emp uuid; v_nom text; v_tel text; v_veh boolean; v_cat text;
begin
  select id into v_emp from empresas where inscripcion_codigo = lower(trim(p_codigo)) and inscripcion_activa;
  if v_emp is null then raise exception 'El enlace de inscripción no es válido o fue desactivado'; end if;
  if exists (select 1 from perfiles where id = p_uid) then raise exception 'Esta cuenta ya está registrada'; end if;
  v_nom := left(trim(p_datos->>'nombre'), 120); v_tel := left(trim(p_datos->>'telefono'), 30);
  v_veh := coalesce((p_datos->>'tiene_vehiculo')::boolean, false);
  v_cat := case when v_veh and p_datos->>'categoria' in ('taxi_basico', 'taxi_turismo', 'taxi_ejecutivo', 'suv', 'van', 'particular_sedan', 'particular_suv', 'particular_vip')
                then p_datos->>'categoria' end;
  insert into perfiles (id, empresa_id, rol, nombre, telefono, activo, conduce, postulacion)
  values (p_uid, v_emp, 'conductor', v_nom, v_tel, false, false, 'pendiente');
  insert into postulaciones_conductor (id, empresa_id, correo, rut, comuna, licencia_clase, experiencia, tiene_vehiculo, patente, marca, modelo, anio, color, categoria)
  values (p_uid, v_emp, left(p_correo, 200), left(trim(p_datos->>'rut'), 20), left(trim(p_datos->>'comuna'), 80),
          left(trim(p_datos->>'licencia'), 20), nullif(left(trim(coalesce(p_datos->>'experiencia', '')), 500), ''), v_veh,
          case when v_veh then left(upper(regexp_replace(coalesce(p_datos->>'patente', ''), '[^A-Za-z0-9]', '', 'g')), 10) end,
          case when v_veh then left(trim(p_datos->>'marca'), 60) end, case when v_veh then left(trim(p_datos->>'modelo'), 60) end,
          case when v_veh then nullif(p_datos->>'anio', '')::int end, case when v_veh then left(trim(p_datos->>'color'), 40) end, v_cat);
  insert into avisos_equipo (empresa_id, tipo, titulo, texto, autor_id)
  values (v_emp, 'postulante', '🆕 Nuevo conductor inscrito',
          v_nom || ' · ' || coalesce(v_tel, '') || '. Revíselo y actívelo en Equipo y roles.', p_uid);
end $$;
revoke execute on function conductor_postular(uuid, text, text, jsonb) from public, anon, authenticated;

create or replace function aprobar_postulante(p_id uuid, p_aprobar boolean, p_nota text default null)
returns void language plpgsql security definer set search_path = public as $$
declare p postulaciones_conductor; v_cat text;
begin
  if mi_rol() is distinct from 'admin' then raise exception 'Solo el administrador'; end if;
  select * into p from postulaciones_conductor where id = p_id and empresa_id = mi_empresa();
  if p.id is null then raise exception 'Postulación no encontrada'; end if;
  if p_aprobar then
    update perfiles set activo = true, conduce = true, postulacion = 'aprobada' where id = p_id;
    if p.tiene_vehiculo and p.patente is not null and length(p.patente) between 5 and 6
       and not exists (select 1 from vehiculos where empresa_id = p.empresa_id and patente = p.patente) then
      v_cat := coalesce(p.categoria, 'particular_sedan');
      insert into vehiculos (empresa_id, patente, marca, modelo, anio, color, conductor_habitual, propio, descripcion, categoria, tipo, capacidad)
      values (p.empresa_id, p.patente, p.marca, p.modelo, p.anio, p.color, p_id, false,
              trim(coalesce(p.marca, '') || ' ' || coalesce(p.modelo, '')), v_cat,
              case when v_cat = 'van' then 'van' when v_cat in ('suv', 'particular_suv') then 'suv' else 'auto' end,
              case when v_cat = 'van' then 8 when v_cat in ('suv', 'particular_suv') then 6 else 4 end);
    end if;
  else
    update perfiles set activo = false, postulacion = 'rechazada' where id = p_id;
  end if;
  update postulaciones_conductor set revisado_por = auth.uid(), revisado_en = now(),
         nota = nullif(left(trim(coalesce(p_nota, '')), 500), '') where id = p_id;
end $$;
revoke execute on function aprobar_postulante(uuid, boolean, text) from public, anon;
grant execute on function aprobar_postulante(uuid, boolean, text) to authenticated;
