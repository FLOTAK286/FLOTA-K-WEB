-- Indica si un correo puede ingresar al panel del equipo (invitación pendiente o perfil activo).
create or replace function puede_ingresar_equipo(p_correo text)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from invitaciones where correo = lower(trim(p_correo)) and aceptada_en is null
  ) or exists (
    select 1 from perfiles p join auth.users u on u.id = p.id
    where lower(u.email) = lower(trim(p_correo)) and p.activo
  )
$$;
revoke execute on function puede_ingresar_equipo(text) from public;
grant execute on function puede_ingresar_equipo(text) to anon, authenticated;
