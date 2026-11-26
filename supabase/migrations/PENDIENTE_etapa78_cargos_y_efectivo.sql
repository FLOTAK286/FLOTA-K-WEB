-- Etapa 78: saldos anteriores (cargos manuales) y clientes que pagan en efectivo.
-- • Cargos manuales: el admin agrega a un cliente una deuda que no es un viaje del sistema (ej.: saldo anterior de
--   $40.000). Aparece en «💳 Pagos» del cliente, suma a su deuda y a su límite de crédito, y se paga con tarjeta igual.
--   No cuenta como viaje en los reportes.
-- • Pago en efectivo: el admin puede marcar servicios como pagados «Efectivo» (antes estaba deshabilitado) y activar en
--   un cliente «Paga en efectivo al conductor»: sus reservas quedan con forma de pago «Efectivo» (el conductor lo ve) y
--   no aparecen como deuda para pagar con tarjeta.

create table if not exists public.cargos_cliente (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id),
  cuenta_id uuid references cuentas_corporativas(id),
  cliente_id uuid references clientes(id),
  descripcion text not null check (length(trim(descripcion)) between 3 and 200),
  monto integer not null check (monto > 0 and monto <= 100000000),
  creado_en timestamptz not null default now(),
  creado_por uuid,
  pagado boolean not null default false,
  pagado_en timestamptz,
  pagado_medio text,
  anulado boolean not null default false,
  check ((cuenta_id is null) <> (cliente_id is null))
);
alter table public.cargos_cliente enable row level security;
drop policy if exists cargos_cliente_staff_ver on public.cargos_cliente;
create policy cargos_cliente_staff_ver on public.cargos_cliente for select to authenticated using (es_staff() and empresa_id = mi_empresa());

alter table cuentas_corporativas add column if not exists paga_efectivo boolean not null default false;
alter table clientes add column if not exists paga_efectivo boolean not null default false;

-- Efectivo habilitado (solo el administrador marca pagos)
create or replace function public.marcar_pagado(p_reservas uuid[], p_pagado boolean, p_medio text default null, p_fecha date default null)
 returns integer language plpgsql security definer set search_path to 'public' as $function$
declare n int;
begin
  if mi_rol() is distinct from 'admin' then raise exception 'Solo el administrador puede marcar pagos'; end if;
  update reservas set pagado = p_pagado,
         pagado_en = case when p_pagado then coalesce(p_fecha::timestamptz, now()) else null end,
         pagado_medio = case when p_pagado then nullif(trim(coalesce(p_medio, '')), '') else null end,
         pagado_por = case when p_pagado then auth.uid() else null end
   where id = any(p_reservas) and empresa_id = mi_empresa();
  get diagnostics n = row_count;
  return n;
end $function$;

-- Pendientes de pago: viajes finalizados sin pagar (salvo clientes que pagan en efectivo) + cargos manuales
drop function if exists public.pendientes_de_pago(uuid, uuid);
create function public.pendientes_de_pago(p_cuenta uuid, p_cliente uuid)
 returns table(o_id uuid, o_tipo text, o_codigo text, o_fecha_hora timestamptz, o_pasajero text, o_origen text, o_destino text, o_total integer, o_en_pago boolean)
 language sql stable security definer set search_path to 'public' as $$
  select r.id, 'reserva', r.codigo, r.fecha_hora, r.nombre_pasajero, r.origen, r.destino, valor_cobro(r.id),
         exists (select 1 from solicitudes_pago s where s.estado = 'pendiente' and s.datos ->> 'tipo' = 'deuda'
                   and s.creada_en > now() - interval '35 minutes'
                   and s.datos -> 'reservas' @> jsonb_build_array(jsonb_build_object('id', r.id)))
  from reservas r
  where r.estado = 'finalizada' and not coalesce(r.pagado, false) and r.eliminada_en is null
    and ((p_cuenta is not null and r.cuenta_corporativa_id = p_cuenta
          and not coalesce((select paga_efectivo from cuentas_corporativas where id = p_cuenta), false))
      or (p_cuenta is null and p_cliente is not null and r.cliente_id = p_cliente and r.cuenta_corporativa_id is null
          and not coalesce((select paga_efectivo from clientes where id = p_cliente), false)))
  union all
  select g.id, 'cargo', 'Saldo', g.creado_en, null, g.descripcion, null, g.monto,
         exists (select 1 from solicitudes_pago s where s.estado = 'pendiente' and s.datos ->> 'tipo' = 'deuda'
                   and s.creada_en > now() - interval '35 minutes'
                   and s.datos -> 'reservas' @> jsonb_build_array(jsonb_build_object('id', g.id)))
  from cargos_cliente g
  where not g.pagado and not g.anulado
    and ((p_cuenta is not null and g.cuenta_id = p_cuenta) or (p_cuenta is null and p_cliente is not null and g.cliente_id = p_cliente))
  order by 4
$$;
revoke all on function public.pendientes_de_pago(uuid, uuid) from public, anon, authenticated;

create or replace function public.deuda_de(p_cuenta uuid, p_cliente uuid) returns integer
 language sql stable security definer set search_path to 'public' as $$
  select coalesce(sum(o_total), 0)::int from pendientes_de_pago(p_cuenta, p_cliente)
$$;
revoke all on function public.deuda_de(uuid, uuid) from public, anon, authenticated;

create or replace function public.mis_pendientes(p_como uuid default null) returns jsonb
 language plpgsql stable security definer set search_path to 'public' as $$
declare a record; v_cred boolean; v_lim int; v_deuda int; v_efe boolean;
begin
  if auth.uid() is null then raise exception 'Debe iniciar sesión'; end if;
  select * into a from credito_alcance(p_como);
  if a.o_cuenta is null and a.o_cliente is null then return null; end if;
  if a.o_cuenta is not null then select credito, credito_limite, paga_efectivo into v_cred, v_lim, v_efe from cuentas_corporativas where id = a.o_cuenta;
  else select credito, credito_limite, paga_efectivo into v_cred, v_lim, v_efe from clientes where id = a.o_cliente; end if;
  v_deuda := deuda_de(a.o_cuenta, case when a.o_cuenta is null then a.o_cliente end);
  return jsonb_build_object(
    'alcance', case when a.o_cuenta is not null then 'empresa' else 'personal' end,
    'puede_pagar', a.o_puede_pagar and p_como is null,
    'credito', coalesce(v_cred, false), 'limite', v_lim, 'deuda', v_deuda, 'efectivo', coalesce(v_efe, false),
    'bloqueado', credito_bloqueo(a.o_cuenta, case when a.o_cuenta is null then a.o_cliente end) is not null,
    'viajes', case when a.o_puede_pagar or p_como is not null then coalesce((select jsonb_agg(jsonb_build_object('id', p.o_id, 'tipo', p.o_tipo, 'codigo', p.o_codigo, 'fecha', p.o_fecha_hora,
        'pasajero', p.o_pasajero, 'origen', p.o_origen, 'destino', p.o_destino, 'total', p.o_total, 'en_pago', p.o_en_pago) order by p.o_fecha_hora)
      from pendientes_de_pago(a.o_cuenta, case when a.o_cuenta is null then a.o_cliente end) p), '[]'::jsonb) else '[]'::jsonb end);
end $$;
revoke all on function public.mis_pendientes(uuid) from public, anon;
grant execute on function public.mis_pendientes(uuid) to authenticated;

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
  select jsonb_agg(jsonb_build_object('id', p.o_id, 'tipo', p.o_tipo, 'codigo', case when p.o_tipo = 'cargo' then p.o_origen else p.o_codigo end, 'monto', p.o_total) order by p.o_fecha_hora),
         sum(p.o_total), count(*)
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

create or replace function public.deuda_marcar_pagada(p_id uuid, p_flow_order bigint, p_medio text) returns void
 language plpgsql security definer set search_path to 'public' as $$
declare s solicitudes_pago%rowtype; t jsonb; v_cods text[] := '{}'; v_ya text[] := '{}'; v_pag boolean; v_medio text;
begin
  select * into s from solicitudes_pago where id = p_id for update;
  if not found or s.datos ->> 'tipo' <> 'deuda' then raise exception 'Solicitud no encontrada'; end if;
  if s.estado = 'pagada' then return; end if;
  v_medio := 'Flow' || coalesce(' · ' || p_medio, '');
  for t in select * from jsonb_array_elements(s.datos -> 'reservas') loop
    if coalesce(t ->> 'tipo', 'reserva') = 'cargo' then
      select pagado into v_pag from cargos_cliente where id = (t ->> 'id')::uuid for update;
      if coalesce(v_pag, true) then v_ya := v_ya || (t ->> 'codigo'); continue; end if;
      update cargos_cliente set pagado = true, pagado_en = now(), pagado_medio = v_medio || ' (orden ' || s.orden || ')' where id = (t ->> 'id')::uuid;
      v_cods := v_cods || (t ->> 'codigo');
      continue;
    end if;
    select coalesce(pagado, false) into v_pag from reservas where id = (t ->> 'id')::uuid for update;
    if v_pag then v_ya := v_ya || (t ->> 'codigo'); continue; end if;
    update reservas set pagado = true, pagado_en = now(), pagado_medio = v_medio,
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

-- Panel: lista con crédito, efectivo, deuda y cargos manuales
create or replace function public.admin_creditos() returns jsonb
 language plpgsql stable security definer set search_path to 'public' as $$
begin
  if coalesce(mi_rol()::text, '') not in ('admin', 'facturacion') then raise exception 'Sin permiso'; end if;
  return jsonb_build_object(
    'empresas', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'nombre', c.razon_social, 'credito', c.credito, 'limite', c.credito_limite,
        'efectivo', c.paga_efectivo, 'deuda', deuda_de(c.id, null), 'activa', c.activa,
        'cargos', coalesce((select jsonb_agg(jsonb_build_object('id', g.id, 'descripcion', g.descripcion, 'monto', g.monto, 'pagado', g.pagado, 'medio', g.pagado_medio) order by g.creado_en)
                   from cargos_cliente g where g.cuenta_id = c.id and not g.anulado), '[]'::jsonb)) order by c.razon_social)
      from cuentas_corporativas c where c.empresa_id = mi_empresa() and not c.es_particulares), '[]'::jsonb),
    'personas', coalesce((select jsonb_agg(x order by x ->> 'nombre') from (
        select distinct on (cl.id) jsonb_build_object('id', cl.id, 'nombre', cl.nombre, 'correo', cl.correo, 'telefono', cl.telefono,
          'credito', cl.credito, 'limite', cl.credito_limite, 'efectivo', cl.paga_efectivo, 'deuda', deuda_de(null, cl.id),
          'cargos', coalesce((select jsonb_agg(jsonb_build_object('id', g.id, 'descripcion', g.descripcion, 'monto', g.monto, 'pagado', g.pagado, 'medio', g.pagado_medio) order by g.creado_en)
                     from cargos_cliente g where g.cliente_id = cl.id and not g.anulado), '[]'::jsonb)) x
        from clientes cl
        where cl.empresa_id = mi_empresa()
          and (cl.credito or cl.paga_efectivo or cl.user_id is not null
               or exists (select 1 from convenio_usuarios u join cuentas_corporativas c on c.id = u.cuenta_id where u.cliente_id = cl.id and c.es_particulares)
               or exists (select 1 from cargos_cliente g where g.cliente_id = cl.id))) q), '[]'::jsonb));
end $$;
revoke all on function public.admin_creditos() from public, anon;
grant execute on function public.admin_creditos() to authenticated;

drop function if exists public.admin_credito_guardar(text, uuid, boolean, integer);
create function public.admin_credito_guardar(p_tipo text, p_id uuid, p_credito boolean, p_limite integer, p_efectivo boolean default false) returns void
 language plpgsql security definer set search_path to 'public' as $$
begin
  if coalesce(mi_rol()::text, '') <> 'admin' then raise exception 'Solo el administrador define el crédito de los clientes'; end if;
  if p_limite is not null and p_limite not between 0 and 100000000 then raise exception 'Límite no válido'; end if;
  if p_tipo = 'empresa' then
    update cuentas_corporativas set credito = coalesce(p_credito, false), credito_limite = p_limite, paga_efectivo = coalesce(p_efectivo, false)
     where id = p_id and empresa_id = mi_empresa();
  elsif p_tipo = 'persona' then
    update clientes set credito = coalesce(p_credito, false), credito_limite = p_limite, paga_efectivo = coalesce(p_efectivo, false)
     where id = p_id and empresa_id = mi_empresa();
  else raise exception 'Tipo no válido'; end if;
  if not found then raise exception 'Cliente no encontrado'; end if;
end $$;
revoke all on function public.admin_credito_guardar(text, uuid, boolean, integer, boolean) from public, anon;
grant execute on function public.admin_credito_guardar(text, uuid, boolean, integer, boolean) to authenticated;

-- Cargos manuales (solo admin): crear, marcar pagado a mano (efectivo o transferencia) y anular
create or replace function public.admin_cargo(p_accion text, p_tipo text, p_id uuid, p_descripcion text default null, p_monto integer default null, p_medio text default null)
 returns void language plpgsql security definer set search_path to 'public' as $$
begin
  if coalesce(mi_rol()::text, '') <> 'admin' then raise exception 'Solo el administrador maneja los cargos'; end if;
  if p_accion = 'crear' then
    if p_monto is null or p_monto <= 0 then raise exception 'Escriba el monto'; end if;
    if length(trim(coalesce(p_descripcion, ''))) < 3 then raise exception 'Escriba de qué es el cargo'; end if;
    if p_tipo = 'empresa' and exists (select 1 from cuentas_corporativas where id = p_id and empresa_id = mi_empresa()) then
      insert into cargos_cliente (empresa_id, cuenta_id, descripcion, monto, creado_por) values (mi_empresa(), p_id, trim(p_descripcion), p_monto, auth.uid());
    elsif p_tipo = 'persona' and exists (select 1 from clientes where id = p_id and empresa_id = mi_empresa()) then
      insert into cargos_cliente (empresa_id, cliente_id, descripcion, monto, creado_por) values (mi_empresa(), p_id, trim(p_descripcion), p_monto, auth.uid());
    else raise exception 'Cliente no encontrado'; end if;
  elsif p_accion = 'pagado' then
    update cargos_cliente set pagado = true, pagado_en = now(), pagado_medio = coalesce(nullif(trim(coalesce(p_medio, '')), ''), 'Efectivo')
     where id = p_id and empresa_id = mi_empresa() and not pagado and not anulado;
    if not found then raise exception 'Cargo no encontrado o ya pagado'; end if;
  elsif p_accion = 'anular' then
    update cargos_cliente set anulado = true where id = p_id and empresa_id = mi_empresa() and not pagado;
    if not found then raise exception 'Cargo no encontrado o ya pagado'; end if;
  else raise exception 'Acción no válida'; end if;
end $$;
revoke all on function public.admin_cargo(text, text, uuid, text, integer, text) from public, anon;
grant execute on function public.admin_cargo(text, text, uuid, text, integer, text) to authenticated;

-- Cliente que paga en efectivo: sus reservas nuevas quedan con forma de pago «Efectivo» (la ve el conductor)
create or replace function public.reserva_forma_pago_efectivo() returns trigger
 language plpgsql security definer set search_path to 'public' as $$
begin
  if nullif(trim(coalesce(new.forma_pago, '')), '') is null and not coalesce(new.pagado, false) and (
       (new.cuenta_corporativa_id is not null and coalesce((select paga_efectivo from cuentas_corporativas where id = new.cuenta_corporativa_id), false))
    or (new.cuenta_corporativa_id is null and new.cliente_id is not null and coalesce((select paga_efectivo from clientes where id = new.cliente_id), false))) then
    new.forma_pago := 'Efectivo';
  end if;
  return new;
end $$;
drop trigger if exists reservas_forma_pago_efectivo on reservas;
create trigger reservas_forma_pago_efectivo before insert on reservas for each row execute function public.reserva_forma_pago_efectivo();
