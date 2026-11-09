create or replace function conductor_avanzar(p_reserva uuid, p_estado estado_reserva, p_nota text default null)
returns estado_reserva
language plpgsql security definer set search_path = public as $$
declare
  v_actual estado_reserva;
  v_orden estado_reserva[] := array['asignada','en_camino','en_lugar','a_bordo','finalizada']::estado_reserva[];
  v_nota text := nullif(left(trim(coalesce(p_nota, '')), 500), '');
begin
  select estado into v_actual from reservas
    where id = p_reserva and conductor_id = auth.uid()
      and exists (select 1 from perfiles where id = auth.uid() and activo)
    for update;
  if not found then raise exception 'Este servicio no está asignado a usted'; end if;
  if v_actual = 'cancelada' then raise exception 'Este servicio fue cancelado'; end if;
  if v_actual in ('recibida', 'confirmada') then v_actual := 'asignada'; end if;
  if array_position(v_orden, p_estado) is null
     or array_position(v_orden, p_estado) <= array_position(v_orden, v_actual) then
    raise exception 'Paso no válido: el servicio ya está en "%"', v_actual;
  end if;
  update reservas set estado = p_estado where id = p_reserva;
  if v_nota is not null then
    update reserva_eventos set nota = v_nota
      where id = (select max(id) from reserva_eventos where reserva_id = p_reserva);
  end if;
  return p_estado;
end $$;
revoke execute on function conductor_avanzar(uuid, estado_reserva, text) from public, anon;
grant execute on function conductor_avanzar(uuid, estado_reserva, text) to authenticated;
