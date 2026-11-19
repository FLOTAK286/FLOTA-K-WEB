-- Etapa 49b: al aprobar, el conductor también queda marcado "Conduce" (así aparece en las listas del panel para asignarle servicios).
create or replace function aprobar_postulante(p_id uuid, p_aprobar boolean, p_nota text default null)
returns void language plpgsql security definer set search_path = public as $$
declare p postulaciones_conductor;
begin
  if mi_rol() is distinct from 'admin' then raise exception 'Solo el administrador'; end if;
  select * into p from postulaciones_conductor where id = p_id and empresa_id = mi_empresa();
  if p.id is null then raise exception 'Postulación no encontrada'; end if;
  if p_aprobar then
    update perfiles set activo = true, conduce = true, postulacion = 'aprobada' where id = p_id;
    if p.tiene_vehiculo and p.patente is not null and length(p.patente) between 5 and 6
       and not exists (select 1 from vehiculos where empresa_id = p.empresa_id and patente = p.patente) then
      insert into vehiculos (empresa_id, patente, marca, modelo, anio, color, conductor_habitual, propio, descripcion)
      values (p.empresa_id, p.patente, p.marca, p.modelo, p.anio, p.color, p_id, false,
              trim(coalesce(p.marca, '') || ' ' || coalesce(p.modelo, '')));
    end if;
  else
    update perfiles set activo = false, postulacion = 'rechazada' where id = p_id;
  end if;
  update postulaciones_conductor set revisado_por = auth.uid(), revisado_en = now(),
         nota = nullif(left(trim(coalesce(p_nota, '')), 500), '') where id = p_id;
end $$;
revoke execute on function aprobar_postulante(uuid, boolean, text) from public, anon;
grant execute on function aprobar_postulante(uuid, boolean, text) to authenticated;
