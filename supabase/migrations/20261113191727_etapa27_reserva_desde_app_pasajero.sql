-- Etapa 27: reservas desde la app del pasajero (con el punto exacto de retiro en el mapa).
-- Usa crear_reserva_publica (mismas validaciones) y además guarda las coordenadas.
-- Límites contra abuso: hasta 6 solicitudes por teléfono en 1 hora; mínimo 2 horas de anticipación
-- (para antes, el pasajero escribe por WhatsApp).
create or replace function crear_reserva_app(
  p_nombre text, p_telefono text, p_correo text, p_fecha_hora timestamptz,
  p_origen text, p_destino text,
  p_origen_lat double precision, p_origen_lng double precision,
  p_destino_lat double precision default null, p_destino_lng double precision default null,
  p_vuelo text default null, p_pasajeros int default 1, p_maletas int default null,
  p_tipo_servicio text default null, p_vehiculo text default null, p_comuna text default null,
  p_tarifa_web int default null, p_comentarios text default null, p_retiro_detalle text default null
) returns table (o_codigo text, o_token uuid)
language plpgsql security definer set search_path = public as $$
declare
  v_tel text := regexp_replace(coalesce(p_telefono, ''), '\D', '', 'g');
  v_cod text; v_tok uuid;
begin
  if p_fecha_hora < now() + interval '2 hours' then
    raise exception 'Para viajes en menos de 2 horas, escríbanos por WhatsApp al +56 9 2227 5399';
  end if;
  if p_fecha_hora > now() + interval '365 days' then raise exception 'La fecha es demasiado lejana'; end if;
  if p_origen_lat is null or p_origen_lng is null
     or p_origen_lat not between -56 and -17 or p_origen_lng not between -76 and -66 then
    raise exception 'Marque en el mapa el punto exacto de retiro';
  end if;
  if p_destino_lat is not null and (p_destino_lat not between -56 and -17 or p_destino_lng not between -76 and -66) then
    raise exception 'El destino marcado no es válido';
  end if;
  if p_tipo_servicio is not null and p_tipo_servicio not in ('ida', 'regreso', 'punto_a_punto') then
    raise exception 'Tipo de servicio no válido';
  end if;
  if p_vehiculo is not null and p_vehiculo not in ('auto', 'van') then raise exception 'Vehículo no válido'; end if;
  if coalesce(p_tarifa_web, 0) not between 0 and 2000000 then raise exception 'Tarifa no válida'; end if;
  if length(coalesce(p_retiro_detalle, '')) > 200 then raise exception 'El detalle del retiro es demasiado largo'; end if;
  if (select count(*) from reservas
      where canal = 'app' and creada_en > now() - interval '1 hour'
        and regexp_replace(coalesce(telefono, ''), '\D', '', 'g') = v_tel) >= 6 then
    raise exception 'Recibimos varias solicitudes seguidas desde este teléfono. Para más reservas, escríbanos por WhatsApp';
  end if;

  select c.o_codigo, c.o_token into v_cod, v_tok
  from crear_reserva_publica('flota-k', p_nombre, p_telefono, p_correo, p_fecha_hora, p_origen, p_destino,
                             p_vuelo, p_pasajeros, p_comentarios, p_maletas, p_tipo_servicio, p_vehiculo,
                             p_comuna, p_tarifa_web) c;

  update reservas set canal = 'app',
         origen_lat = p_origen_lat, origen_lng = p_origen_lng,
         destino_lat = p_destino_lat, destino_lng = p_destino_lng,
         retiro_detalle = nullif(trim(coalesce(p_retiro_detalle, '')), '')
  where token_seguimiento = v_tok;

  o_codigo := v_cod; o_token := v_tok;
  return next;
end $$;
revoke execute on function crear_reserva_app(text, text, text, timestamptz, text, text, double precision, double precision, double precision, double precision, text, int, int, text, text, text, int, text, text) from public;
grant execute on function crear_reserva_app(text, text, text, timestamptz, text, text, double precision, double precision, double precision, double precision, text, int, int, text, text, text, int, text, text) to anon, authenticated;
