-- Etapa 70: reserva por enlace (fk-servicios.com/reservar), el enlace que envía el agente de WhatsApp.
-- El pasajero completa sus datos sin crear cuenta. La reserva queda "recibida" (la central la confirma),
-- con canal 'whatsapp' y aviso "📅 Reserva nueva" a Operaciones (trigger avisar_equipo_reserva).
-- Reutiliza crear_reserva_app (validaciones de fecha, punto en el mapa, tipo y vehículo), que sigue sin permiso público.
-- Control de abuso: máx. 6 por hora por teléfono y 30 por hora en total por este canal.
create or replace function public.crear_reserva_enlace(
  p_nombre text, p_telefono text, p_correo text, p_fecha_hora timestamptz,
  p_origen text, p_destino text, p_origen_lat double precision, p_origen_lng double precision,
  p_destino_lat double precision default null, p_destino_lng double precision default null,
  p_vuelo text default null, p_pasajeros integer default 1, p_maletas integer default null,
  p_tipo_servicio text default null, p_vehiculo text default null, p_comuna text default null,
  p_tarifa integer default null, p_tarifa_estimada boolean default false, p_comentarios text default null,
  p_retiro_detalle text default null, p_pasajero_nombre text default null, p_pasajero_telefono text default null,
  p_como_nos_conocio text default null)
returns table(o_codigo text, o_token uuid)
language plpgsql security definer set search_path to 'public' as $function$
declare
  v_tel text := regexp_replace(coalesce(p_telefono, ''), '\D', '', 'g');
  v_otro boolean := nullif(trim(coalesce(p_pasajero_nombre, '')), '') is not null;
  v_cod text; v_tok uuid; v_com text;
begin
  if length(trim(coalesce(p_nombre, ''))) < 2 or length(p_nombre) > 120 then raise exception 'Escriba su nombre'; end if;
  if length(v_tel) < 8 or length(v_tel) > 15 then raise exception 'Escriba un teléfono válido'; end if;
  if p_correo is not null and p_correo <> '' and (length(p_correo) > 200 or p_correo !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$') then
    raise exception 'El correo no es válido';
  end if;
  if v_otro and (length(p_pasajero_nombre) > 120 or length(regexp_replace(coalesce(p_pasajero_telefono, ''), '\D', '', 'g')) < 8) then
    raise exception 'Escriba el nombre y el teléfono de la persona que viaja';
  end if;
  if length(coalesce(p_comentarios, '')) > 500 then raise exception 'Los comentarios son demasiado largos'; end if;
  if p_como_nos_conocio is not null and p_como_nos_conocio not in
     ('google', 'web', 'instagram', 'facebook', 'tiktok', 'linkedin', 'recomendacion', 'cliente_frecuente', 'otro') then
    p_como_nos_conocio := null;
  end if;
  if (select count(*) from reservas where canal = 'whatsapp' and creada_en > now() - interval '1 hour'
        and comentarios like 'Formulario por enlace%'
        and regexp_replace(coalesce(coalesce(solicitante_telefono, telefono), ''), '\D', '', 'g') = v_tel) >= 6 then
    raise exception 'Recibimos varias solicitudes seguidas desde este teléfono. Para más reservas, escríbanos por WhatsApp';
  end if;
  if (select count(*) from reservas where canal = 'whatsapp' and creada_en > now() - interval '1 hour'
        and comentarios like 'Formulario por enlace%') >= 30 then
    raise exception 'En este momento no podemos recibir más solicitudes en línea. Escríbanos por WhatsApp al +56 9 2227 5399';
  end if;

  v_com := concat_ws(' ', 'Formulario por enlace (WhatsApp).',
                     case when p_tarifa_estimada then 'Valor estimado por la página, por confirmar.' end,
                     nullif(trim(coalesce(p_comentarios, '')), ''));

  -- Si viaja otra persona: la reserva queda a nombre del pasajero y quien reservó como solicitante
  select c.o_codigo, c.o_token into v_cod, v_tok
  from crear_reserva_app(
    case when v_otro then trim(p_pasajero_nombre) else trim(p_nombre) end,
    case when v_otro then trim(p_pasajero_telefono) else trim(p_telefono) end,
    nullif(trim(coalesce(p_correo, '')), ''), p_fecha_hora, p_origen, p_destino,
    p_origen_lat, p_origen_lng, p_destino_lat, p_destino_lng, nullif(trim(coalesce(p_vuelo, '')), ''),
    p_pasajeros, p_maletas, p_tipo_servicio, p_vehiculo, p_comuna, p_tarifa, v_com, p_retiro_detalle) c;

  update reservas set canal = 'whatsapp', como_nos_conocio = p_como_nos_conocio,
         solicitante_nombre = case when v_otro then trim(p_nombre) end,
         solicitante_telefono = case when v_otro then trim(p_telefono) end,
         solicitante_correo = case when v_otro then nullif(trim(coalesce(p_correo, '')), '') end
  where token_seguimiento = v_tok;

  o_codigo := v_cod; o_token := v_tok;
  return next;
end $function$;

revoke all on function public.crear_reserva_enlace(text, text, text, timestamptz, text, text, double precision, double precision,
  double precision, double precision, text, integer, integer, text, text, text, integer, boolean, text, text, text, text, text) from public;
grant execute on function public.crear_reserva_enlace(text, text, text, timestamptz, text, text, double precision, double precision,
  double precision, double precision, text, integer, integer, text, text, text, integer, boolean, text, text, text, text, text) to anon, authenticated;
