-- Etapa 15: "Eliminar" reservas (pruebas, duplicadas, errores) sin borrarlas: quedan canceladas y ocultas en todas partes,
-- con papelera para restaurarlas. Respeta la regla "nada se borra".

alter table reservas add column if not exists eliminada_en timestamptz;
alter table reservas add column if not exists eliminada_por uuid references auth.users(id);
alter table reservas add column if not exists eliminada_motivo text check (length(eliminada_motivo) <= 300);
alter table reservas add column if not exists estado_antes_eliminar estado_reserva;

-- Política restrictiva: ninguna consulta normal ve reservas eliminadas (se suma a las políticas existentes).
create policy reservas_ocultar_eliminadas on reservas as restrictive for select using (eliminada_en is null);

create or replace function eliminar_reserva(p_reserva uuid, p_motivo text default null)
returns void language plpgsql security definer set search_path = public as $$
declare r reservas%rowtype;
begin
  if mi_rol() is distinct from 'admin' then raise exception 'Solo el administrador puede eliminar reservas'; end if;
  select * into r from reservas where id = p_reserva and empresa_id = mi_empresa() for update;
  if not found then raise exception 'Reserva no encontrada'; end if;
  if r.eliminada_en is not null then return; end if;
  if r.estado in ('en_camino', 'en_lugar', 'a_bordo') then raise exception 'El servicio está en curso: no se puede eliminar'; end if;
  update reservas set estado_antes_eliminar = r.estado, estado = 'cancelada', eliminada_en = now(), eliminada_por = auth.uid(),
         eliminada_motivo = nullif(left(trim(coalesce(p_motivo, '')), 300), '') where id = r.id;
  insert into reserva_eventos (reserva_id, estado, nota, usuario_id)
  values (r.id, 'cancelada', 'Reserva eliminada' || coalesce(': ' || nullif(trim(p_motivo), ''), ''), auth.uid());
end $$;

create or replace function restaurar_reserva(p_reserva uuid)
returns void language plpgsql security definer set search_path = public as $$
declare r reservas%rowtype;
begin
  if mi_rol() is distinct from 'admin' then raise exception 'Solo el administrador puede restaurar reservas'; end if;
  select * into r from reservas where id = p_reserva and empresa_id = mi_empresa() for update;
  if not found or r.eliminada_en is null then raise exception 'Reserva no encontrada en la papelera'; end if;
  update reservas set estado = coalesce(r.estado_antes_eliminar, 'confirmada'), eliminada_en = null, eliminada_por = null,
         eliminada_motivo = null, estado_antes_eliminar = null where id = r.id;
  insert into reserva_eventos (reserva_id, estado, nota, usuario_id)
  values (r.id, coalesce(r.estado_antes_eliminar, 'confirmada'), 'Reserva restaurada desde la papelera', auth.uid());
end $$;

create or replace function reservas_eliminadas()
returns table (o_id uuid, o_codigo text, o_fecha_hora timestamptz, o_pasajero text, o_origen text, o_destino text,
               o_eliminada_en timestamptz, o_motivo text, o_por text)
language sql stable security definer set search_path = public as $$
  select r.id, r.codigo, r.fecha_hora, r.nombre_pasajero, r.origen, r.destino, r.eliminada_en, r.eliminada_motivo, p.nombre
  from reservas r left join perfiles p on p.id = r.eliminada_por
  where r.empresa_id = mi_empresa() and r.eliminada_en is not null and mi_rol() = 'admin'
  order by r.eliminada_en desc limit 500
$$;

revoke execute on function eliminar_reserva(uuid, text) from public, anon;
grant execute on function eliminar_reserva(uuid, text) to authenticated;
revoke execute on function restaurar_reserva(uuid) from public, anon;
grant execute on function restaurar_reserva(uuid) to authenticated;
revoke execute on function reservas_eliminadas() from public, anon;
grant execute on function reservas_eliminadas() to authenticated;
