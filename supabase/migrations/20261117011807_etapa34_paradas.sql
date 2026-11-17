-- Etapa 34: servicios con paradas intermedias.
-- reservas.paradas = lista ordenada de paradas entre el origen y el destino: [{ "direccion": "...", "lat": -33.4, "lng": -70.6 }]
alter table public.reservas add column if not exists paradas jsonb not null default '[]'::jsonb;
alter table public.reservas drop constraint if exists reservas_paradas_check;
alter table public.reservas add constraint reservas_paradas_check
  check (jsonb_typeof(paradas) = 'array' and jsonb_array_length(paradas) <= 8);

-- Revisa y limpia una lista de paradas que llega de una página (la usan las funciones de reserva)
create or replace function public.paradas_limpias(p jsonb)
returns jsonb language plpgsql immutable set search_path to 'public'
as $$
declare x jsonb; v jsonb := '[]'::jsonb; d text; la double precision; ln double precision;
begin
  if p is null or jsonb_typeof(p) <> 'array' then return '[]'::jsonb; end if;
  if jsonb_array_length(p) > 8 then raise exception 'Máximo 8 paradas por servicio'; end if;
  for x in select * from jsonb_array_elements(p) loop
    d := left(trim(coalesce(x->>'direccion', '')), 300);
    la := (x->>'lat')::double precision; ln := (x->>'lng')::double precision;
    if length(d) < 3 then raise exception 'Escriba la dirección de cada parada'; end if;
    if la is null or la not between -56 and -17 or ln not between -76 and -66 then
      raise exception 'Marque en el mapa el punto exacto de la parada "%"', d;
    end if;
    v := v || jsonb_build_array(jsonb_build_object('direccion', d, 'lat', la, 'lng', ln));
  end loop;
  return v;
end $$;

-- Portal de empresas: la misma función de antes, ahora con paradas
drop function if exists public.crear_reserva_convenio(uuid, uuid, timestamptz, text, text, text, double precision, double precision, double precision, double precision, text, integer, text, text, integer, integer, text, text, text);
create function public.crear_reserva_convenio(p_habitual uuid, p_para uuid, p_fecha_hora timestamptz, p_tipo_servicio text default null, p_origen text default null, p_destino text default null, p_origen_lat double precision default null, p_origen_lng double precision default null, p_destino_lat double precision default null, p_destino_lng double precision default null, p_vehiculo text default 'auto', p_tarifa integer default null, p_comuna text default null, p_vuelo text default null, p_pasajeros integer default 1, p_maletas integer default null, p_centro_costo text default null, p_comentarios text default null, p_retiro_detalle text default null, p_paradas jsonb default '[]'::jsonb)
 returns table(o_codigo text, o_token uuid, o_aviso text)
 language plpgsql security definer set search_path to 'public'
as $function$
declare
  yo convenio_usuarios; pax convenio_usuarios; c cuentas_corporativas; s servicios_habituales;
  v_precio int; v_aviso text; g_emp int; g_pax int;
  v_tipo text; v_ori text; v_des text; v_olat double precision; v_olng double precision; v_dlat double precision; v_dlng double precision; v_veh text;
  v_cod text; v_tok uuid; v_par jsonb;
begin
  yo := convenio_yo();
  if yo.id is null then raise exception 'Su usuario no tiene acceso al convenio'; end if;
  select * into c from cuentas_corporativas where id = yo.cuenta_id;
  if c.datos_completos_en is null then raise exception 'Antes de agendar, el encargado de convenio debe completar los datos de facturación'; end if;
  if p_para is null or p_para = yo.id then pax := yo;
  else
    if yo.rol <> 'encargado' then raise exception 'Solo el encargado de convenio puede agendar para otra persona'; end if;
    select * into pax from convenio_usuarios where id = p_para and cuenta_id = yo.cuenta_id and activo;
    if pax.id is null then raise exception 'Pasajero no encontrado'; end if;
  end if;
  if p_fecha_hora < now() + interval '60 minutes' then raise exception 'Para traslados en menos de 1 hora, escríbanos por WhatsApp al +56 9 2227 5399'; end if;
  if p_fecha_hora > now() + interval '365 days' then raise exception 'La fecha es demasiado lejana'; end if;
  if coalesce(p_pasajeros, 1) not between 1 and 20 then raise exception 'Número de pasajeros no válido'; end if;
  if p_maletas is not null and p_maletas not between 0 and 30 then raise exception 'Número de maletas no válido'; end if;
  if p_centro_costo is not null and array_length(c.centros_costo, 1) > 0 and not (p_centro_costo = any (c.centros_costo)) then
    raise exception 'Centro de costo no válido';
  end if;
  if length(coalesce(p_comentarios, '')) > 1000 then raise exception 'El comentario es demasiado largo'; end if;
  v_par := paradas_limpias(p_paradas);

  if p_habitual is not null then
    select * into s from servicios_habituales where id = p_habitual and cuenta_id = c.id and activo;
    if s.id is null then raise exception 'Servicio habitual no encontrado'; end if;
    v_tipo := s.tipo_servicio; v_ori := s.origen; v_des := s.destino; v_veh := s.vehiculo; v_precio := s.precio;
    v_olat := s.origen_lat; v_olng := s.origen_lng; v_dlat := s.destino_lat; v_dlng := s.destino_lng;
    v_par := '[]'::jsonb; -- los servicios habituales tienen precio fijo para su trayecto: sin paradas
  else
    if p_tipo_servicio not in ('ida', 'regreso', 'punto_a_punto') then raise exception 'Tipo de servicio no válido'; end if;
    if length(trim(coalesce(p_origen, ''))) < 3 or length(trim(coalesce(p_destino, ''))) < 3 then raise exception 'Ingrese origen y destino'; end if;
    if p_origen_lat is null or p_origen_lat not between -56 and -17 or p_origen_lng not between -76 and -66 then raise exception 'Marque en el mapa el punto exacto de retiro'; end if;
    if p_vehiculo not in ('auto', 'van') then raise exception 'Vehículo no válido'; end if;
    if p_tarifa is not null and p_tarifa not between 0 and 2000000 then raise exception 'Tarifa no válida'; end if;
    v_tipo := p_tipo_servicio; v_ori := trim(p_origen); v_des := trim(p_destino); v_veh := p_vehiculo; v_precio := p_tarifa;
    v_olat := p_origen_lat; v_olng := p_origen_lng; v_dlat := p_destino_lat; v_dlng := p_destino_lng;
    if jsonb_array_length(v_par) > 0 then v_precio := null; end if; -- con paradas, el valor lo confirma Flota-K
  end if;

  g_emp := convenio_gasto(c.id, null, p_fecha_hora) + coalesce(v_precio, 0);
  g_pax := convenio_gasto(c.id, pax.cliente_id, p_fecha_hora) + coalesce(v_precio, 0);
  if pax.presupuesto_mensual is not null and g_pax > pax.presupuesto_mensual then
    v_aviso := format('Supera el presupuesto mensual de %s ($%s de $%s)', pax.nombre,
      replace(to_char(g_pax, 'FM999,999,999'), ',', '.'), replace(to_char(pax.presupuesto_mensual, 'FM999,999,999'), ',', '.'));
  elsif c.presupuesto_mensual is not null and g_emp > c.presupuesto_mensual then
    v_aviso := format('Supera el presupuesto mensual de la empresa ($%s de $%s)',
      replace(to_char(g_emp, 'FM999,999,999'), ',', '.'), replace(to_char(c.presupuesto_mensual, 'FM999,999,999'), ',', '.'));
  end if;
  if v_aviso is not null and c.presupuesto_modo = 'bloqueo' then
    raise exception '%. Su empresa tiene bloqueadas las reservas sobre el presupuesto: pida al encargado de convenio que lo ajuste.', v_aviso;
  end if;

  insert into reservas (empresa_id, cliente_id, cuenta_corporativa_id, centro_costo, nombre_pasajero, telefono, correo, fecha_hora,
                        origen, destino, vuelo, pasajeros, comentarios, canal, maletas, tipo_servicio, vehiculo, comuna, tarifa_web, precio,
                        origen_lat, origen_lng, destino_lat, destino_lng, retiro_detalle, servicio_habitual_id, convenio_aviso,
                        solicitante_nombre, solicitante_telefono, solicitante_correo, paradas)
  values (c.empresa_id, pax.cliente_id, c.id, nullif(trim(coalesce(p_centro_costo, '')), ''), pax.nombre, coalesce(pax.telefono, yo.telefono), pax.correo, p_fecha_hora,
          v_ori, v_des, case when v_tipo in ('ida', 'regreso') then nullif(trim(coalesce(p_vuelo, '')), '') end, coalesce(p_pasajeros, 1),
          nullif(trim(concat_ws(' · ', case when s.id is not null then 'Servicio habitual: ' || s.nombre end, nullif(trim(coalesce(p_comentarios, '')), ''))), ''),
          'convenio', p_maletas, v_tipo, v_veh, p_comuna, v_precio, case when s.id is not null then s.precio end,
          v_olat, v_olng, v_dlat, v_dlng, nullif(left(trim(coalesce(p_retiro_detalle, '')), 200), ''), s.id, v_aviso,
          case when pax.id <> yo.id then yo.nombre end, case when pax.id <> yo.id then yo.telefono end, case when pax.id <> yo.id then yo.correo end, v_par)
  returning reservas.codigo, reservas.token_seguimiento into v_cod, v_tok;
  o_codigo := v_cod; o_token := v_tok; o_aviso := v_aviso;
  return next;
end $function$;
revoke all on function public.crear_reserva_convenio(uuid, uuid, timestamptz, text, text, text, double precision, double precision, double precision, double precision, text, integer, text, text, integer, integer, text, text, text, jsonb) from public, anon;
grant execute on function public.crear_reserva_convenio(uuid, uuid, timestamptz, text, text, text, double precision, double precision, double precision, double precision, text, integer, text, text, integer, integer, text, text, text, jsonb) to authenticated;

-- Enlace de seguimiento: paradas del viaje (solo con el token)
create or replace function public.ver_paradas_publica(p_token uuid)
returns jsonb language sql stable security definer set search_path to 'public'
as $$ select coalesce((select paradas from reservas where token_seguimiento = p_token and eliminada_en is null), '[]'::jsonb) $$;
grant execute on function public.ver_paradas_publica(uuid) to anon, authenticated;

-- Toda lista de paradas que se guarde (panel incluido) pasa por la misma revisión
create or replace function public.reservas_paradas_revisar()
returns trigger language plpgsql set search_path to 'public'
as $$
begin
  if tg_op = 'INSERT' or new.paradas is distinct from old.paradas then
    new.paradas := paradas_limpias(new.paradas);
  end if;
  return new;
end $$;
drop trigger if exists reservas_paradas_revisar on public.reservas;
create trigger reservas_paradas_revisar before insert or update of paradas on public.reservas
  for each row execute function public.reservas_paradas_revisar();

-- Espera en paradas intermedias: 5 min sin costo por parada; después la misma tarifa por minuto
-- ($180 auto, $270 SUV o van). Corre desde que el conductor marca "Llegué a la parada" hasta "Seguimos".
-- No aplica a servicios por hora ni con taxímetro (ya cobran por tiempo).
create table if not exists public.reserva_paradas_espera (
  reserva_id uuid not null references public.reservas(id),
  indice integer not null check (indice between 0 and 7),
  empresa_id uuid not null references public.empresas(id),
  llegada_en timestamptz not null default now(),
  salida_en timestamptz,
  primary key (reserva_id, indice)
);
alter table public.reserva_paradas_espera enable row level security;
-- Sin políticas: solo se lee y escribe con las funciones de abajo.

create or replace function public.paradas_espera_calculo(p_reserva uuid)
returns table (indice integer, direccion text, llegada_en timestamptz, salida_en timestamptz, gratis_hasta timestamptz,
               tarifa_min integer, minutos integer, monto integer, aplica boolean, ahora timestamptz)
language sql stable security definer set search_path to 'public'
as $$
  select x.indice, r.paradas->x.indice->>'direccion', x.llegada_en, x.salida_en, x.llegada_en + interval '5 minutes',
         case when r.vehiculo in ('suv', 'van') then 270 else 180 end,
         case when ap.v then greatest(0, floor(extract(epoch from (coalesce(x.salida_en, now()) - x.llegada_en - interval '5 minutes')) / 60))::int else 0 end,
         case when ap.v then (greatest(0, floor(extract(epoch from (coalesce(x.salida_en, now()) - x.llegada_en - interval '5 minutes')) / 60))
                              * case when r.vehiculo in ('suv', 'van') then 270 else 180 end)::int else 0 end,
         ap.v, now()
  from reservas r
  join reserva_paradas_espera x on x.reserva_id = r.id
  cross join lateral (select coalesce(r.tipo_cobro, '') <> 'taximetro' and coalesce(r.tipo_servicio::text, '') <> 'por_hora' as v) ap
  where r.id = p_reserva and x.indice < jsonb_array_length(r.paradas)
  order by x.indice
$$;
revoke all on function public.paradas_espera_calculo(uuid) from public, anon, authenticated;

-- Deja (o actualiza) el gasto de espera de una parada en la reserva
create or replace function public.registrar_espera_parada(p_reserva uuid, p_indice integer)
returns void language plpgsql security definer set search_path to 'public'
as $$
declare x record; emp uuid;
begin
  select empresa_id into emp from reservas where id = p_reserva;
  delete from reserva_gastos where reserva_id = p_reserva and tipo = 'espera' and descripcion like 'Espera en parada ' || (p_indice + 1) || ':%';
  select * into x from paradas_espera_calculo(p_reserva) c where c.indice = p_indice;
  if found and x.aplica and x.monto > 0 then
    insert into reserva_gastos (empresa_id, reserva_id, tipo, cantidad, monto, descripcion, creado_por)
    values (emp, p_reserva, 'espera', 1, x.monto,
            'Espera en parada ' || (p_indice + 1) || ': ' || x.minutos || ' min x $' || x.tarifa_min || ' (5 min sin costo)', auth.uid());
  end if;
end $$;
revoke all on function public.registrar_espera_parada(uuid, integer) from public, anon, authenticated;

-- App del conductor: "llegue" o "salgo" en la parada p_indice (0 = primera). Solo con el pasajero a bordo.
create or replace function public.conductor_parada(p_reserva uuid, p_indice integer, p_accion text)
returns void language plpgsql security definer set search_path to 'public'
as $$
declare r reservas; o record;
begin
  select * into r from reservas where id = p_reserva;
  if r.id is null or r.conductor_id is distinct from auth.uid() then raise exception 'Este servicio no es suyo'; end if;
  if r.estado <> 'a_bordo' then raise exception 'Las paradas se marcan con el pasajero a bordo'; end if;
  if p_indice is null or p_indice < 0 or p_indice >= jsonb_array_length(r.paradas) then raise exception 'Parada no válida'; end if;
  if p_accion = 'llegue' then
    -- si quedó otra parada abierta, se cierra ahora
    for o in select indice from reserva_paradas_espera where reserva_id = r.id and salida_en is null and indice <> p_indice loop
      update reserva_paradas_espera set salida_en = now() where reserva_id = r.id and indice = o.indice;
      perform registrar_espera_parada(r.id, o.indice);
    end loop;
    insert into reserva_paradas_espera (reserva_id, indice, empresa_id) values (r.id, p_indice, r.empresa_id)
    on conflict (reserva_id, indice) do nothing;
  elsif p_accion = 'salgo' then
    update reserva_paradas_espera set salida_en = now() where reserva_id = r.id and indice = p_indice and salida_en is null;
    if not found then raise exception 'Primero marque que llegó a la parada'; end if;
    perform registrar_espera_parada(r.id, p_indice);
  else
    raise exception 'Acción no válida';
  end if;
end $$;
revoke all on function public.conductor_parada(uuid, integer, text) from public, anon;
grant execute on function public.conductor_parada(uuid, integer, text) to authenticated;

-- Lectura: conductor del servicio y equipo
create or replace function public.ver_paradas_espera(p_reserva uuid)
returns table (indice integer, direccion text, llegada_en timestamptz, salida_en timestamptz, gratis_hasta timestamptz,
               tarifa_min integer, minutos integer, monto integer, aplica boolean, ahora timestamptz)
language sql stable security definer set search_path to 'public'
as $$
  select c.* from reservas r, lateral paradas_espera_calculo(r.id) c
  where r.id = p_reserva and (r.conductor_id = auth.uid() or (r.empresa_id = mi_empresa() and es_staff()))
$$;
revoke all on function public.ver_paradas_espera(uuid) from public, anon;
grant execute on function public.ver_paradas_espera(uuid) to authenticated;

-- Lectura: enlace del pasajero (con el token)
create or replace function public.ver_paradas_espera_publica(p_token uuid)
returns table (indice integer, direccion text, llegada_en timestamptz, salida_en timestamptz, gratis_hasta timestamptz,
               tarifa_min integer, minutos integer, monto integer, aplica boolean, ahora timestamptz)
language sql stable security definer set search_path to 'public'
as $$
  select c.* from reservas r, lateral paradas_espera_calculo(r.id) c
  where r.token_seguimiento = p_token and r.eliminada_en is null
$$;
grant execute on function public.ver_paradas_espera_publica(uuid) to anon, authenticated;

-- Al finalizar, si quedó una parada abierta se cierra y se cobra
create or replace function public.cerrar_paradas_al_finalizar()
returns trigger language plpgsql security definer set search_path to 'public'
as $$
declare o record;
begin
  if new.estado = 'finalizada' and old.estado is distinct from 'finalizada' then
    for o in select indice from reserva_paradas_espera where reserva_id = new.id and salida_en is null loop
      update reserva_paradas_espera set salida_en = now() where reserva_id = new.id and indice = o.indice;
      perform registrar_espera_parada(new.id, o.indice);
    end loop;
  end if;
  return new;
end $$;
drop trigger if exists reservas_zz_cerrar_paradas on public.reservas;
create trigger reservas_zz_cerrar_paradas after update on public.reservas
  for each row execute function public.cerrar_paradas_al_finalizar();

-- Panel del despacho: cambiar las paradas de una reserva ya creada (queda nota en el historial)
create or replace function public.editar_paradas(p_reserva uuid, p_paradas jsonb)
returns jsonb language plpgsql security definer set search_path to 'public'
as $$
declare r reservas; v jsonb; antes int;
begin
  if not es_staff() then raise exception 'Solo el equipo puede cambiar las paradas'; end if;
  select * into r from reservas where id = p_reserva and empresa_id = mi_empresa();
  if r.id is null then raise exception 'Reserva no encontrada'; end if;
  if r.estado in ('finalizada', 'cancelada') then raise exception 'La reserva ya está %: no se pueden cambiar las paradas', r.estado; end if;
  v := paradas_limpias(p_paradas);
  if v = r.paradas then return v; end if;
  antes := jsonb_array_length(r.paradas);
  update reservas set paradas = v where id = r.id;
  -- esperas de paradas que ya no existen dejan de contar
  delete from reserva_paradas_espera where reserva_id = r.id and indice >= jsonb_array_length(v);
  delete from reserva_gastos g where g.reserva_id = r.id and g.tipo = 'espera' and g.descripcion like 'Espera en parada %'
    and not exists (select 1 from reserva_paradas_espera x where x.reserva_id = r.id and g.descripcion like 'Espera en parada ' || (x.indice + 1) || ':%');
  insert into reserva_eventos (reserva_id, estado, nota, usuario_id)
  values (r.id, r.estado, 'Paradas cambiadas: ' || antes || ' → ' || jsonb_array_length(v) ||
          coalesce(' (' || (select string_agg(p->>'direccion', ' · ') from jsonb_array_elements(v) p) || ')', ''), auth.uid());
  return v;
end $$;
revoke all on function public.editar_paradas(uuid, jsonb) from public, anon;
grant execute on function public.editar_paradas(uuid, jsonb) to authenticated;
