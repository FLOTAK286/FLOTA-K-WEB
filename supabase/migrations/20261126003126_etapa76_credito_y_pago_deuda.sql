-- Etapa 76: cuentas con crédito (pueden deber) con límite de deuda, y pago en línea de servicios pendientes.
-- • El admin marca qué clientes tienen "cuenta con crédito" y su límite: empresas con convenio (por empresa) y clientes
--   particulares o de la app (por persona). Si la deuda (servicios finalizados sin pagar) supera el límite, no pueden
--   agendar hasta pagar. Sin la marca, nada cambia.
-- • Toda persona con cuenta ve sus servicios pendientes de pago, elige cuáles pagar y paga con tarjeta (Flow).
--   Empresas: pagan el encargado de convenio o el directivo. Particulares y app: cada persona sus viajes.

alter table cuentas_corporativas add column if not exists credito boolean not null default false;
alter table cuentas_corporativas add column if not exists credito_limite integer check (credito_limite is null or credito_limite >= 0);
alter table clientes add column if not exists credito boolean not null default false;
alter table clientes add column if not exists credito_limite integer check (credito_limite is null or credito_limite >= 0);

-- Servicios pendientes de pago de una empresa (p_cuenta) o de una persona sin convenio (p_cliente)
create or replace function public.pendientes_de_pago(p_cuenta uuid, p_cliente uuid)
 returns table(o_id uuid, o_codigo text, o_fecha_hora timestamptz, o_pasajero text, o_origen text, o_destino text, o_total integer, o_en_pago boolean)
 language sql stable security definer set search_path to 'public' as $$
  select r.id, r.codigo, r.fecha_hora, r.nombre_pasajero, r.origen, r.destino, valor_cobro(r.id),
         exists (select 1 from solicitudes_pago s where s.estado = 'pendiente' and s.datos ->> 'tipo' = 'deuda'
                   and s.creada_en > now() - interval '35 minutes'
                   and s.datos -> 'reservas' @> jsonb_build_array(jsonb_build_object('id', r.id)))
  from reservas r
  where r.estado = 'finalizada' and not coalesce(r.pagado, false) and r.eliminada_en is null
    and ((p_cuenta is not null and r.cuenta_corporativa_id = p_cuenta)
      or (p_cuenta is null and p_cliente is not null and r.cliente_id = p_cliente and r.cuenta_corporativa_id is null))
  order by r.fecha_hora
$$;
revoke all on function public.pendientes_de_pago(uuid, uuid) from public, anon, authenticated;

create or replace function public.deuda_de(p_cuenta uuid, p_cliente uuid) returns integer
 language sql stable security definer set search_path to 'public' as $$
  select coalesce(sum(o_total), 0)::int from pendientes_de_pago(p_cuenta, p_cliente)
$$;
revoke all on function public.deuda_de(uuid, uuid) from public, anon, authenticated;

-- Mensaje de bloqueo si la cuenta tiene crédito y su deuda supera el límite (null = puede agendar)
create or replace function public.credito_bloqueo(p_cuenta uuid, p_cliente uuid) returns text
 language plpgsql stable security definer set search_path to 'public' as $$
declare v_cred boolean; v_lim int; v_deuda int;
  fmt constant text := 'FM999,999,999';
begin
  if p_cuenta is not null then select credito, credito_limite into v_cred, v_lim from cuentas_corporativas where id = p_cuenta;
  else select credito, credito_limite into v_cred, v_lim from clientes where id = p_cliente; end if;
  if not coalesce(v_cred, false) or v_lim is null then return null; end if;
  v_deuda := deuda_de(p_cuenta, case when p_cuenta is null then p_cliente end);
  if v_deuda <= v_lim then return null; end if;
  return format('Su cuenta tiene $%s en servicios pendientes de pago y superó su límite de $%s. Para volver a agendar, pague sus servicios pendientes en «Pagos» (con tarjeta, en línea) o escríbanos al WhatsApp +56 9 2227 5399.',
    replace(to_char(v_deuda, fmt), ',', '.'), replace(to_char(v_lim, fmt), ',', '.'));
end $$;
revoke all on function public.credito_bloqueo(uuid, uuid) from public, anon, authenticated;

-- A quién le cobra la persona conectada: empresa con convenio (encargado/directivo pagan) o la propia persona
create or replace function public.credito_alcance(p_como uuid default null,
  out o_cuenta uuid, out o_cliente uuid, out o_puede_pagar boolean, out o_nombre text, out o_correo text, out o_telefono text, out o_empresa uuid)
 language plpgsql stable security definer set search_path to 'public' as $$
declare yo convenio_usuarios; c cuentas_corporativas; cl clientes;
begin
  yo := case when p_como is null then convenio_yo() else convenio_yo_o_vista(p_como) end;
  if yo.id is not null then
    select * into c from cuentas_corporativas where id = yo.cuenta_id;
    o_empresa := c.empresa_id; o_nombre := yo.nombre; o_telefono := yo.telefono;
    if not c.es_particulares then
      o_cuenta := c.id; o_puede_pagar := yo.rol in ('encargado', 'directivo');
      o_correo := coalesce(nullif(c.correo_facturacion, ''), yo.correo); o_nombre := c.razon_social;
      return;
    end if;
    o_cliente := yo.cliente_id; o_puede_pagar := true; o_correo := yo.correo;
    return;
  end if;
  if p_como is not null then return; end if;
  select * into cl from clientes where user_id = auth.uid() order by creado_en limit 1;
  if cl.id is null then return; end if;
  o_cliente := cl.id; o_puede_pagar := true; o_nombre := cl.nombre; o_correo := cl.correo; o_telefono := cl.telefono; o_empresa := cl.empresa_id;
end $$;
revoke all on function public.credito_alcance(uuid) from public, anon, authenticated;

-- Portal y app: servicios pendientes de pago, deuda, límite y si está bloqueado
create or replace function public.mis_pendientes(p_como uuid default null) returns jsonb
 language plpgsql stable security definer set search_path to 'public' as $$
declare a record; v_cred boolean; v_lim int; v_deuda int;
begin
  if auth.uid() is null then raise exception 'Debe iniciar sesión'; end if;
  select * into a from credito_alcance(p_como);
  if a.o_cuenta is null and a.o_cliente is null then return null; end if;
  if a.o_cuenta is not null then select credito, credito_limite into v_cred, v_lim from cuentas_corporativas where id = a.o_cuenta;
  else select credito, credito_limite into v_cred, v_lim from clientes where id = a.o_cliente; end if;
  v_deuda := deuda_de(a.o_cuenta, case when a.o_cuenta is null then a.o_cliente end);
  return jsonb_build_object(
    'alcance', case when a.o_cuenta is not null then 'empresa' else 'personal' end,
    'puede_pagar', a.o_puede_pagar and p_como is null,
    'credito', coalesce(v_cred, false), 'limite', v_lim, 'deuda', v_deuda,
    'bloqueado', credito_bloqueo(a.o_cuenta, case when a.o_cuenta is null then a.o_cliente end) is not null,
    'viajes', case when a.o_puede_pagar or p_como is not null then coalesce((select jsonb_agg(jsonb_build_object('id', p.o_id, 'codigo', p.o_codigo, 'fecha', p.o_fecha_hora,
        'pasajero', p.o_pasajero, 'origen', p.o_origen, 'destino', p.o_destino, 'total', p.o_total, 'en_pago', p.o_en_pago) order by p.o_fecha_hora)
      from pendientes_de_pago(a.o_cuenta, case when a.o_cuenta is null then a.o_cliente end) p), '[]'::jsonb) else '[]'::jsonb end);
end $$;
revoke all on function public.mis_pendientes(uuid) from public, anon;
grant execute on function public.mis_pendientes(uuid) to authenticated;

-- Crea la solicitud de pago de los servicios elegidos (la Edge Function "flow" crea el cobro en Flow)
create or replace function public.deuda_crear_solicitud(p_ids uuid[], p_volver text)
 returns table(o_id uuid, o_orden text, o_monto integer, o_correo text, o_n integer)
 language plpgsql security definer set search_path to 'public' as $$
declare a record; v_items jsonb; v_total int; v_n int; v_orden text; v_id uuid; v_correo text;
begin
  if auth.uid() is null then raise exception 'Debe iniciar sesión'; end if;
  select * into a from credito_alcance(null);
  if a.o_cuenta is null and a.o_cliente is null then raise exception 'Su usuario no tiene una cuenta de cliente'; end if;
  if not a.o_puede_pagar then raise exception 'Los servicios de su empresa los paga el encargado de convenio'; end if;
  if p_ids is null or cardinality(p_ids) = 0 then raise exception 'Elija al menos un servicio para pagar'; end if;
  if cardinality(p_ids) > 60 then raise exception 'Puede pagar hasta 60 servicios a la vez'; end if;
  if (select count(*) from solicitudes_pago where datos ->> 'user_id' = auth.uid()::text and creada_en > now() - interval '1 hour') >= 10 then
    raise exception 'Recibimos varios intentos de pago seguidos. Espere unos minutos o escríbanos por WhatsApp';
  end if;
  select jsonb_agg(jsonb_build_object('id', p.o_id, 'codigo', p.o_codigo, 'monto', p.o_total) order by p.o_fecha_hora), sum(p.o_total), count(*)
    into v_items, v_total, v_n
  from pendientes_de_pago(a.o_cuenta, case when a.o_cuenta is null then a.o_cliente end) p
  where p.o_id = any (p_ids) and not p.o_en_pago;
  if coalesce(v_n, 0) <> cardinality(p_ids) then
    raise exception 'Alguno de los servicios elegidos ya está pagado o tiene un pago en curso. Actualice la página e intente de nuevo';
  end if;
  if v_total < 350 then raise exception 'El monto a pagar debe ser de al menos $350'; end if;
  v_correo := lower(trim(coalesce(a.o_correo, '')));
  if v_correo !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Su cuenta no tiene un correo válido para el comprobante. Escríbanos por WhatsApp'; end if;
  v_orden := 'FKD-' || upper(to_hex((extract(epoch from now()) * 1000)::bigint)) || '-' || upper(substr(gen_random_uuid()::text, 1, 4));
  insert into solicitudes_pago (empresa_id, orden, datos, monto, telefono, correo)
  values (a.o_empresa, v_orden,
          jsonb_build_object('tipo', 'deuda', 'reservas', v_items, 'user_id', auth.uid(), 'volver', case when p_volver = 'app' then 'app' else 'empresa' end,
                             'cuenta_id', a.o_cuenta, 'cliente_id', case when a.o_cuenta is null then a.o_cliente end,
                             'contacto', jsonb_build_object('nombre', a.o_nombre, 'correo', v_correo, 'telefono', a.o_telefono)),
          v_total, a.o_telefono, v_correo)
  returning id into v_id;
  o_id := v_id; o_orden := v_orden; o_monto := v_total; o_correo := v_correo; o_n := v_n; return next;
end $$;
revoke all on function public.deuda_crear_solicitud(uuid[], text) from public, anon;
grant execute on function public.deuda_crear_solicitud(uuid[], text) to authenticated;

-- Flow confirmó el pago: marca pagados los servicios (solo la Edge Function, con la clave de servicio)
create or replace function public.deuda_marcar_pagada(p_id uuid, p_flow_order bigint, p_medio text) returns void
 language plpgsql security definer set search_path to 'public' as $$
declare s solicitudes_pago%rowtype; t jsonb; v_cods text[] := '{}'; v_ya text[] := '{}'; v_pag boolean;
begin
  select * into s from solicitudes_pago where id = p_id for update;
  if not found or s.datos ->> 'tipo' <> 'deuda' then raise exception 'Solicitud no encontrada'; end if;
  if s.estado = 'pagada' then return; end if;
  for t in select * from jsonb_array_elements(s.datos -> 'reservas') loop
    select coalesce(pagado, false) into v_pag from reservas where id = (t ->> 'id')::uuid for update;
    if v_pag then v_ya := v_ya || (t ->> 'codigo'); continue; end if;
    update reservas set pagado = true, pagado_en = now(), pagado_medio = 'Flow' || coalesce(' · ' || p_medio, ''),
           forma_pago = coalesce(nullif(forma_pago, ''), 'Flow (pagado en línea)')
     where id = (t ->> 'id')::uuid;
    insert into reserva_eventos (reserva_id, estado, nota)
    values ((t ->> 'id')::uuid, 'finalizada', 'Pagado en línea por el cliente con Flow (orden ' || s.orden || ', N° Flow ' || coalesce(p_flow_order::text, '?') || '): $' ||
            replace(to_char((t ->> 'monto')::int, 'FM999,999,999'), ',', '.'));
    v_cods := v_cods || (t ->> 'codigo');
  end loop;
  update solicitudes_pago set estado = 'pagada', pagada_en = now(), flow_order = p_flow_order, flow_medio = p_medio, codigos = v_cods,
         error = case when cardinality(v_ya) > 0 then 'Ya estaban pagados antes de este pago (revisar devolución): ' || array_to_string(v_ya, ', ') end
   where id = p_id;
end $$;
revoke all on function public.deuda_marcar_pagada(uuid, bigint, text) from public, anon, authenticated;

-- Panel (solo admin): lista de empresas y clientes particulares con su crédito, límite y deuda
create or replace function public.admin_creditos() returns jsonb
 language plpgsql stable security definer set search_path to 'public' as $$
begin
  if coalesce(mi_rol()::text, '') not in ('admin', 'facturacion') then raise exception 'Sin permiso'; end if;
  return jsonb_build_object(
    'empresas', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'nombre', c.razon_social, 'credito', c.credito, 'limite', c.credito_limite,
        'deuda', deuda_de(c.id, null), 'activa', c.activa) order by c.razon_social)
      from cuentas_corporativas c where c.empresa_id = mi_empresa() and not c.es_particulares), '[]'::jsonb),
    'personas', coalesce((select jsonb_agg(x order by x ->> 'nombre') from (
        select distinct on (cl.id) jsonb_build_object('id', cl.id, 'nombre', cl.nombre, 'correo', cl.correo, 'telefono', cl.telefono,
          'credito', cl.credito, 'limite', cl.credito_limite, 'deuda', deuda_de(null, cl.id)) x
        from clientes cl
        where cl.empresa_id = mi_empresa()
          and (cl.credito or exists (select 1 from convenio_usuarios u join cuentas_corporativas c on c.id = u.cuenta_id
                                      where u.cliente_id = cl.id and c.es_particulares)
               or cl.user_id is not null)) q), '[]'::jsonb));
end $$;
revoke all on function public.admin_creditos() from public, anon;
grant execute on function public.admin_creditos() to authenticated;

create or replace function public.admin_credito_guardar(p_tipo text, p_id uuid, p_credito boolean, p_limite integer) returns void
 language plpgsql security definer set search_path to 'public' as $$
begin
  if coalesce(mi_rol()::text, '') <> 'admin' then raise exception 'Solo el administrador define el crédito de los clientes'; end if;
  if p_limite is not null and p_limite not between 0 and 100000000 then raise exception 'Límite no válido'; end if;
  if p_tipo = 'empresa' then
    update cuentas_corporativas set credito = coalesce(p_credito, false), credito_limite = p_limite where id = p_id and empresa_id = mi_empresa();
  elsif p_tipo = 'persona' then
    update clientes set credito = coalesce(p_credito, false), credito_limite = p_limite where id = p_id and empresa_id = mi_empresa();
  else raise exception 'Tipo no válido'; end if;
  if not found then raise exception 'Cliente no encontrado'; end if;
end $$;
revoke all on function public.admin_credito_guardar(text, uuid, boolean, integer) from public, anon;
grant execute on function public.admin_credito_guardar(text, uuid, boolean, integer) to authenticated;

-- Bloqueo al agendar: portal de empresas (convenio y particulares) y app del pasajero
create or replace function public.credito_revisar_reserva() returns trigger
 language plpgsql security definer set search_path to 'public' as $$
declare v_msg text;
begin
  -- Solo reservas que crea el cliente desde el portal o la app (el equipo puede agendar igual desde el panel)
  if new.canal not in ('convenio', 'portal', 'app') or es_staff() then return new; end if;
  v_msg := credito_bloqueo(new.cuenta_corporativa_id, case when new.cuenta_corporativa_id is null then new.cliente_id end);
  if v_msg is not null then raise exception '%', v_msg; end if;
  return new;
end $$;
drop trigger if exists reservas_credito_bloqueo on reservas;
create trigger reservas_credito_bloqueo before insert on reservas for each row execute function public.credito_revisar_reserva();
