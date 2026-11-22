-- Etapa 69: formulario de solicitud para clientes que llegan por WhatsApp (/reservar/).
-- El asistente de WhatsApp le envía al cliente el enlace; el cliente completa sus datos y la reserva
-- entra al panel como "recibida" (por confirmar), con aviso a Operaciones. La central confirma.
-- No reabre la reserva al público con cuenta: es una puerta aparte, solo deja solicitudes por confirmar,
-- con límites para evitar abusos.

alter table reservas add column if not exists creada_por_formulario boolean not null default false;

create or replace function solicitar_reserva_whatsapp(
  p_nombre text, p_telefono text, p_correo text,
  p_fecha_hora timestamptz, p_tipo_servicio text, p_vehiculo text,
  p_origen text, p_destino text,
  p_origen_lat double precision, p_origen_lng double precision,
  p_destino_lat double precision, p_destino_lng double precision,
  p_vuelo text default null, p_pasajeros int default 1, p_maletas int default null,
  p_comuna text default null, p_tarifa int default null, p_tarifa_estimada boolean default false,
  p_km numeric default null, p_retiro_detalle text default null, p_comentarios text default null
) returns table(o_id uuid, o_codigo text, o_token uuid)
language plpgsql security definer set search_path = public as $$
declare
  v_emp uuid;
  v_tel text := regexp_replace(coalesce(p_telefono, ''), '\D', '', 'g');
  v_correo text := nullif(lower(trim(coalesce(p_correo, ''))), '');
  v_id uuid; v_cod text; v_tok uuid;
begin
  select id into v_emp from empresas where slug = 'flota-k';
  if v_emp is null then raise exception 'Empresa no encontrada'; end if;

  if length(trim(coalesce(p_nombre, ''))) < 2 or length(p_nombre) > 120 then raise exception 'Escriba su nombre'; end if;
  if length(v_tel) < 8 or length(p_telefono) > 30 then raise exception 'Escriba un teléfono válido'; end if;
  if v_correo is not null and (v_correo !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(v_correo) > 200) then
    raise exception 'El correo no es válido (puede dejarlo en blanco)';
  end if;
  if p_fecha_hora < now() + interval '2 hours' then
    raise exception 'Para viajes en menos de 2 horas, escríbanos directamente por WhatsApp al +56 9 2227 5399';
  end if;
  if p_fecha_hora > now() + interval '365 days' then raise exception 'La fecha es demasiado lejana'; end if;
  if p_tipo_servicio not in ('ida', 'regreso', 'punto_a_punto') then raise exception 'Tipo de servicio no válido'; end if;
  if p_vehiculo not in ('auto', 'van') then raise exception 'Vehículo no válido'; end if;
  if p_origen_lat is null or p_origen_lat not between -56 and -17 or p_origen_lng not between -76 and -66 then
    raise exception 'Marque en el mapa el punto exacto de retiro';
  end if;
  if p_destino_lat is null or p_destino_lat not between -56 and -17 or p_destino_lng not between -76 and -66 then
    raise exception 'Marque en el mapa el punto exacto de destino';
  end if;
  if length(trim(coalesce(p_origen, ''))) < 3 or length(trim(coalesce(p_destino, ''))) < 3
     or length(p_origen) > 300 or length(p_destino) > 300 then raise exception 'Ingrese origen y destino'; end if;
  if coalesce(p_pasajeros, 1) not between 1 and 15 then raise exception 'Número de pasajeros no válido'; end if;
  if coalesce(p_maletas, 0) not between 0 and 30 then raise exception 'Número de maletas no válido'; end if;
  if coalesce(p_tarifa, 0) not between 0 and 2000000 then raise exception 'Tarifa no válida'; end if;
  if length(coalesce(p_comentarios, '')) > 500 or length(coalesce(p_retiro_detalle, '')) > 200
     or length(coalesce(p_vuelo, '')) > 12 or length(coalesce(p_comuna, '')) > 120 then raise exception 'Texto demasiado largo'; end if;

  -- Límites contra abusos: por teléfono y en total
  if (select count(*) from reservas
      where canal = 'whatsapp' and creada_por_formulario and creada_en > now() - interval '1 hour'
        and right(regexp_replace(coalesce(telefono, ''), '\D', '', 'g'), 8) = right(v_tel, 8)) >= 4 then
    raise exception 'Recibimos varias solicitudes seguidas desde este teléfono. Para más reservas, escríbanos por WhatsApp';
  end if;
  if (select count(*) from reservas
      where canal = 'whatsapp' and creada_por_formulario and creada_en > now() - interval '1 hour') >= 30 then
    raise exception 'En este momento no podemos recibir más solicitudes por aquí. Escríbanos por WhatsApp al +56 9 2227 5399';
  end if;

  insert into reservas (empresa_id, nombre_pasajero, telefono, correo, fecha_hora, origen, destino,
                        origen_lat, origen_lng, destino_lat, destino_lng, vuelo, pasajeros, maletas,
                        tipo_servicio, vehiculo, comuna, tarifa_web, comentarios, retiro_detalle, canal,
                        km_ida, creada_por_formulario)
  values (v_emp, trim(p_nombre), trim(p_telefono), v_correo, p_fecha_hora, trim(p_origen), trim(p_destino),
          p_origen_lat, p_origen_lng, p_destino_lat, p_destino_lng,
          case when p_tipo_servicio in ('ida', 'regreso') then nullif(upper(trim(coalesce(p_vuelo, ''))), '') end,
          coalesce(p_pasajeros, 1), p_maletas, p_tipo_servicio, p_vehiculo, nullif(trim(coalesce(p_comuna, '')), ''), p_tarifa,
          nullif(concat_ws(' ',
            'Solicitud por WhatsApp (formulario): confirmar con el cliente.',
            case when p_tarifa_estimada then 'Valor estimado por el cotizador punto a punto, por confirmar.' end,
            nullif(trim(coalesce(p_comentarios, '')), '')), ''),
          nullif(trim(coalesce(p_retiro_detalle, '')), ''), 'whatsapp',
          case when p_km between 0 and 2000 then p_km end, true)
  returning reservas.id, reservas.codigo, reservas.token_seguimiento into v_id, v_cod, v_tok;

  -- El aviso automático de "reserva nueva" se marca como solicitud por confirmar
  update avisos_equipo
     set titulo = '📲 Solicitud por WhatsApp: confirme',
         texto = replace(texto, 'Agendada desde la web o el portal', 'Llegó por el formulario de WhatsApp') || ' · Tel. ' || trim(p_telefono)
   where reserva_id = v_id and tipo = 'nueva';

  o_id := v_id; o_codigo := v_cod; o_token := v_tok;
  return next;
end $$;

revoke execute on function solicitar_reserva_whatsapp(text, text, text, timestamptz, text, text, text, text, double precision, double precision, double precision, double precision, text, int, int, text, int, boolean, numeric, text, text) from public;
grant execute on function solicitar_reserva_whatsapp(text, text, text, timestamptz, text, text, text, text, double precision, double precision, double precision, double precision, text, int, int, text, int, boolean, numeric, text, text) to anon, authenticated;
