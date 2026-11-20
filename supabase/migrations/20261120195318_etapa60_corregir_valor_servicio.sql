-- Etapa 60: el administrador corrige el valor de un servicio finalizado (taxímetro o tarifa fija).
-- Se guarda el valor original (la primera vez), quién y cuándo lo corrigió, y una nota en el historial.
alter table reservas add column if not exists valor_original integer;
alter table reservas add column if not exists valor_corregido_por uuid references perfiles(id);
alter table reservas add column if not exists valor_corregido_en timestamptz;

create or replace function admin_corregir_valor(p_reserva uuid, p_valor integer, p_motivo text default null)
returns void language plpgsql security definer set search_path = public as $$
declare r reservas; v_antes integer; v_quien text;
begin
  if mi_rol() is distinct from 'admin' then raise exception 'Solo el administrador puede corregir el valor'; end if;
  select * into r from reservas where id = p_reserva and empresa_id = mi_empresa() for update;
  if r.id is null then raise exception 'Reserva no encontrada'; end if;
  if r.estado <> 'finalizada' then raise exception 'Solo se corrige el valor de servicios finalizados (los demás se editan en la ficha)'; end if;
  if p_valor is null or p_valor < 0 or p_valor > 5000000 then raise exception 'Escriba un valor válido'; end if;
  v_antes := case when r.tipo_cobro = 'taximetro' then r.taxi_total else coalesce(r.precio, r.tarifa_web) end;
  if p_valor = v_antes then raise exception 'Es el mismo valor que ya tiene'; end if;
  if r.tipo_cobro = 'taximetro' then
    update reservas set taxi_total = p_valor where id = r.id;
  else
    update reservas set precio = p_valor where id = r.id;
  end if;
  update reservas set valor_original = coalesce(valor_original, v_antes), valor_corregido_por = auth.uid(), valor_corregido_en = now()
   where id = r.id;
  select nombre into v_quien from perfiles where id = auth.uid();
  insert into reserva_eventos (reserva_id, estado, nota, usuario_id)
  values (r.id, r.estado, left('Valor corregido por ' || coalesce(v_quien, 'el administrador') || ': '
    || '$' || replace(to_char(coalesce(v_antes, 0), 'FM999,999,999'), ',', '.') || ' → $' || replace(to_char(p_valor, 'FM999,999,999'), ',', '.')
    || coalesce(' · ' || nullif(trim(p_motivo), ''), ''), 1000), auth.uid());
end $$;
revoke execute on function admin_corregir_valor(uuid, integer, text) from public, anon;
grant execute on function admin_corregir_valor(uuid, integer, text) to authenticated;
