-- Etapa 31b: al dar acceso al portal de empresas, si la persona ya era cliente se reutiliza su ficha
-- (por correo o, si no tiene correo, por los últimos 8 dígitos del teléfono), para no perder su historial.
create or replace function public.convenio_registrar_usuario(p_cuenta uuid, p_user uuid, p_rol text, p_nombre text, p_correo text, p_telefono text, p_por uuid)
 returns uuid language plpgsql security definer set search_path to 'public'
as $function$
declare c cuentas_corporativas; v_cli uuid; v_id uuid; v_correo text := lower(trim(p_correo));
  v_tel8 text := right(regexp_replace(coalesce(p_telefono, ''), '\D', '', 'g'), 8);
begin
  select * into c from cuentas_corporativas where id = p_cuenta;
  if c.id is null then raise exception 'Empresa no encontrada'; end if;
  if p_rol not in ('encargado', 'pasajero', 'directivo') then raise exception 'Rol no válido'; end if;
  if exists (select 1 from perfiles where id = p_user) then raise exception 'Ese correo ya pertenece al equipo de Flota-K'; end if;
  if exists (select 1 from convenio_usuarios where user_id = p_user and cuenta_id <> p_cuenta) then raise exception 'Ese correo ya está en otra empresa con convenio'; end if;
  select id into v_cli from clientes where empresa_id = c.empresa_id and user_id = p_user;
  if v_cli is null then
    select id into v_cli from clientes where empresa_id = c.empresa_id and user_id is null and v_correo <> '' and lower(correo) = v_correo order by creado_en limit 1;
  end if;
  if v_cli is null and length(v_tel8) = 8 then
    select id into v_cli from clientes where empresa_id = c.empresa_id and user_id is null
      and right(regexp_replace(coalesce(telefono, ''), '\D', '', 'g'), 8) = v_tel8 order by creado_en limit 1;
  end if;
  if v_cli is not null then
    update clientes set user_id = p_user, cuenta_corporativa_id = c.id, correo = coalesce(correo, nullif(v_correo, '')) where id = v_cli;
  else
    insert into clientes (empresa_id, user_id, cuenta_corporativa_id, nombre, telefono, correo)
    values (c.empresa_id, p_user, c.id, trim(p_nombre), nullif(trim(coalesce(p_telefono, '')), ''), v_correo) returning id into v_cli;
  end if;
  insert into convenio_usuarios (empresa_id, cuenta_id, user_id, cliente_id, rol, nombre, correo, telefono, creado_por)
  values (c.empresa_id, c.id, p_user, v_cli, p_rol, trim(p_nombre), v_correo, nullif(trim(coalesce(p_telefono, '')), ''), p_por)
  on conflict (user_id) do update set rol = excluded.rol, nombre = excluded.nombre, telefono = coalesce(excluded.telefono, convenio_usuarios.telefono), activo = true
  returning id into v_id;
  return v_id;
end $function$;
