-- Etapa 35: el portal de empresas muestra el mismo valor que la cobranza del panel (v_cobro):
-- taxímetro cuando el servicio se cobró con taxímetro, si no el precio fijo (o la tarifa web), más los gastos del viaje.
-- Antes solo miraba el precio fijo, y los servicios con taxímetro aparecían como "Valor por confirmar".
-- También el gasto mensual del presupuesto se calcula igual.
create or replace function valor_cobro(p_reserva uuid) returns int
language sql stable security definer set search_path = public as $$
  select (case when r.tipo_cobro = 'taximetro' then r.taxi_total else coalesce(r.precio, r.tarifa_web) end
          + coalesce((select sum(g.monto) from reserva_gastos g where g.reserva_id = r.id), 0))::int
  from reservas r where r.id = p_reserva
$$;
revoke execute on function valor_cobro(uuid) from public, anon, authenticated;

create or replace function convenio_gasto(p_cuenta uuid, p_cliente uuid, p_mes timestamptz) returns int
language sql stable security definer set search_path = public as $$
  select coalesce(sum(coalesce(valor_cobro(r.id), 0)), 0)::int from reservas r
  where r.cuenta_corporativa_id = p_cuenta and r.estado <> 'cancelada' and r.eliminada_en is null
    and (p_cliente is null or r.cliente_id = p_cliente)
    and date_trunc('month', r.fecha_hora at time zone 'America/Santiago') = date_trunc('month', p_mes at time zone 'America/Santiago')
$$;
revoke execute on function convenio_gasto(uuid, uuid, timestamptz) from public, anon, authenticated;

create or replace function convenio_reservas(p_desde timestamptz default now() - interval '60 days', p_como uuid default null)
returns table (o_id uuid, o_codigo text, o_estado estado_reserva, o_fecha_hora timestamptz, o_origen text, o_destino text,
               o_pasajero text, o_valor int, o_centro_costo text, o_aviso text, o_token uuid, o_conductor text,
               o_puede_cancelar boolean, o_tipo text)
language plpgsql stable security definer set search_path = public as $$
declare yo convenio_usuarios;
begin
  yo := convenio_yo_o_vista(p_como);
  if yo.id is null then return; end if;
  return query
  select r.id, r.codigo, r.estado, r.fecha_hora, r.origen, r.destino, r.nombre_pasajero,
         valor_cobro(r.id), r.centro_costo, r.convenio_aviso, r.token_seguimiento,
         (select p.nombre from perfiles p where p.id = r.conductor_id),
         r.cuenta_corporativa_id is not null
           and (yo.rol = 'encargado' or r.cliente_id = yo.cliente_id)
           and r.estado in ('recibida', 'confirmada', 'asignada') and r.fecha_hora > now() + interval '2 hours',
         case when r.cuenta_corporativa_id is null then 'particular' else 'empresa' end
  from reservas r
  where r.eliminada_en is null and r.fecha_hora >= p_desde
    and (
      (r.cuenta_corporativa_id = yo.cuenta_id and (yo.rol in ('encargado', 'directivo') or r.cliente_id = yo.cliente_id))
      or (r.cuenta_corporativa_id is null and yo.cliente_id is not null and r.cliente_id = yo.cliente_id)
    )
  order by r.fecha_hora desc limit 500;
end $$;
