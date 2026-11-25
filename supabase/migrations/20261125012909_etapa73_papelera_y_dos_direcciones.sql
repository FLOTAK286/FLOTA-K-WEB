-- Etapa 73: papelera completa + segunda dirección en las reservas pagadas en línea
-- 1) Papelera: al purgar, se borran también los datos ligados (avisos, esperas en paradas) y las ubicaciones quedan sin reserva.
--    reserva_eventos y reserva_gastos se borran solos (on delete cascade).
create or replace function public.purgar_reservas_eliminadas()
 returns integer
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_ids uuid[];
begin
  select coalesce(array_agg(id), '{}') into v_ids
  from reservas
  where eliminada_en is not null and eliminada_en < now() - interval '24 hours';
  if cardinality(v_ids) = 0 then return 0; end if;
  update ubicaciones set reserva_id = null where reserva_id = any(v_ids);
  delete from calificaciones         where reserva_id = any(v_ids);
  delete from mensajes               where reserva_id = any(v_ids);
  delete from reserva_cambios        where reserva_id = any(v_ids);
  delete from reserva_paradas_espera where reserva_id = any(v_ids);
  delete from avisos_conductor       where reserva_id = any(v_ids);
  delete from avisos_equipo          where reserva_id = any(v_ids);
  delete from bolsa_avisos           where reserva_id = any(v_ids);
  delete from reservas where id = any(v_ids);
  return cardinality(v_ids);
end $function$;
revoke all on function public.purgar_reservas_eliminadas() from public, anon, authenticated;

-- 2) Reservas pagadas con dos direcciones (aeropuerto): la dirección principal queda como parada (reservas.paradas)
create or replace function public.crear_reservas_pagadas(p_id uuid, p_flow_order bigint, p_medio text)
 returns table(o_codigos text[], o_token uuid)
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  s solicitudes_pago%rowtype; t jsonb; c jsonb; v_cod text; v_tok uuid; v_cods text[] := '{}'; v_tok1 uuid;
  v_otro boolean; v_n int := 0;
begin
  select * into s from solicitudes_pago where id = p_id for update;
  if not found then raise exception 'Solicitud no encontrada'; end if;
  if s.estado = 'pagada' then o_codigos := s.codigos; o_token := s.token_seguimiento; return next; return; end if;
  c := s.datos -> 'contacto';
  v_otro := nullif(trim(coalesce(c ->> 'pasajero_nombre', '')), '') is not null;
  for t in select * from jsonb_array_elements(s.datos -> 'tramos') loop
    v_n := v_n + 1;
    select r.o_codigo, r.o_token into v_cod, v_tok
    from crear_reserva_publica('flota-k',
      case when v_otro then c ->> 'pasajero_nombre' else c ->> 'nombre' end,
      case when v_otro then c ->> 'pasajero_telefono' else c ->> 'telefono' end,
      c ->> 'correo', greatest((t ->> 'fecha_hora')::timestamptz, now() + interval '1 minute'),
      t ->> 'origen', t ->> 'destino', t ->> 'vuelo', coalesce((t ->> 'pasajeros')::int, 1),
      concat_ws(' ', 'PAGADA EN LÍNEA con Flow (orden ' || s.orden || ', N° Flow ' || coalesce(p_flow_order::text, '?') || ').',
                case when (t ->> 'estimado')::boolean then 'Valor calculado por ruta (' || (t ->> 'km') || ' km).' end,
                nullif(t ->> 'comentarios', '')),
      (t ->> 'maletas')::int, t ->> 'tipo_servicio', t ->> 'vehiculo', t ->> 'comuna', (t ->> 'monto')::int) r;
    update reservas set canal = 'whatsapp', estado = 'confirmada',
           precio = (t ->> 'monto')::int, tipo_cobro = 'fija',
           pagado = true, pagado_en = now(), pagado_medio = 'Flow' || coalesce(' · ' || p_medio, ''), forma_pago = 'Flow (pagado en línea)',
           origen_lat = (t ->> 'origen_lat')::float8, origen_lng = (t ->> 'origen_lng')::float8,
           destino_lat = (t ->> 'destino_lat')::float8, destino_lng = (t ->> 'destino_lng')::float8,
           paradas = case when jsonb_typeof(t -> 'paradas') = 'array' then t -> 'paradas' else paradas end,
           retiro_detalle = nullif(t ->> 'retiro_detalle', ''),
           como_nos_conocio = nullif(c ->> 'como', ''),
           solicitante_nombre = case when v_otro then c ->> 'nombre' end,
           solicitante_telefono = case when v_otro then c ->> 'telefono' end,
           solicitante_correo = case when v_otro then c ->> 'correo' end
    where token_seguimiento = v_tok;
    v_cods := v_cods || v_cod; if v_tok1 is null then v_tok1 := v_tok; end if;
  end loop;
  update solicitudes_pago set estado = 'pagada', pagada_en = now(), flow_order = p_flow_order, flow_medio = p_medio,
         codigos = v_cods, token_seguimiento = v_tok1, error = null where id = p_id;
  o_codigos := v_cods; o_token := v_tok1; return next;
end $function$;

-- 3) Vaciar la papelera ahora (autorizado por el dueño, 23 nov 2026)
select public.purgar_reservas_eliminadas();
