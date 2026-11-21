-- Etapa 63: facturación mensual por empresa con convenio.
-- Panel (admin o rol "facturacion"): viajes finalizados del período por empresa, marcar como facturados con número de
-- factura (no se factura dos veces), anular una factura (los viajes vuelven a "por facturar") y marcarla pagada.
-- Portal de empresas (encargado o directivo): estado de cuenta con viajes del período y facturas.
create table if not exists facturas (
  id bigint generated always as identity primary key,
  empresa_id uuid not null references empresas(id),
  cuenta_id uuid not null references cuentas_corporativas(id),
  numero text not null check (length(numero) between 1 and 40),
  fecha date not null default (now() at time zone 'America/Santiago')::date,
  periodo_desde date, periodo_hasta date,
  monto integer not null default 0,
  viajes integer not null default 0,
  nota text check (length(nota) <= 500),
  pagada boolean not null default false,
  pagada_en timestamptz,
  anulada boolean not null default false,
  anulada_motivo text,
  creado_por uuid references perfiles(id),
  creado_en timestamptz not null default now()
);
alter table facturas enable row level security;
create policy facturas_ver on facturas for select using (empresa_id = mi_empresa() and coalesce(mi_rol()::text, '') in ('admin', 'facturacion'));
alter table reservas add column if not exists factura_id bigint references facturas(id);

create or replace function puede_facturar()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select activo and rol::text in ('admin', 'facturacion') from perfiles where id = auth.uid()), false)
$$;
revoke execute on function puede_facturar() from public, anon;
grant execute on function puede_facturar() to authenticated;

-- Pago: también lo puede marcar el rol facturación
create or replace function proteger_pago()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (new.pagado is distinct from old.pagado or new.pagado_en is distinct from old.pagado_en
      or new.pagado_medio is distinct from old.pagado_medio)
     and coalesce(mi_rol()::text, '') not in ('admin', 'facturacion') and auth.uid() is not null then
    raise exception 'Solo el administrador o facturación pueden marcar servicios como pagados';
  end if;
  return new;
end $$;

-- Resumen del período por empresa
create or replace function facturacion_resumen(p_desde date, p_hasta date)
returns table(o_cuenta uuid, o_razon text, o_rut text, o_viajes integer, o_total integer, o_facturado integer, o_por_facturar integer, o_por_cobrar integer)
language sql stable security definer set search_path = public as $$
  select c.id, c.razon_social, c.rut, count(r.id)::int, coalesce(sum(v.total), 0)::int,
         coalesce(sum(v.total) filter (where r.factura_id is not null), 0)::int,
         coalesce(sum(v.total) filter (where r.factura_id is null), 0)::int,
         coalesce(sum(v.total) filter (where not r.pagado), 0)::int
  from cuentas_corporativas c
  join reservas r on r.cuenta_corporativa_id = c.id and r.estado = 'finalizada' and r.eliminada_en is null
   and (r.fecha_hora at time zone 'America/Santiago')::date between p_desde and p_hasta
  join v_cobro v on v.id = r.id
  where puede_facturar() and c.empresa_id = mi_empresa()
  group by c.id, c.razon_social, c.rut
  order by 5 desc
$$;
revoke execute on function facturacion_resumen(date, date) from public, anon;
grant execute on function facturacion_resumen(date, date) to authenticated;

-- Detalle de viajes de una empresa en el período
create or replace function facturacion_viajes(p_cuenta uuid, p_desde date, p_hasta date)
returns table(o_id uuid, o_codigo text, o_fecha timestamptz, o_pasajero text, o_solicitante text, o_origen text, o_destino text,
              o_centro_costo text, o_servicio text, o_valor integer, o_gastos integer, o_total integer, o_no_presentado boolean,
              o_pagado boolean, o_factura_id bigint, o_factura_numero text)
language sql stable security definer set search_path = public as $$
  select r.id, r.codigo, r.fecha_hora, r.nombre_pasajero, r.solicitante_nombre, r.origen, r.destino, r.centro_costo,
         r.tipo_servicio::text, v.valor_base, v.gastos, v.total, r.no_presentado, r.pagado, r.factura_id, f.numero
  from reservas r join v_cobro v on v.id = r.id left join facturas f on f.id = r.factura_id
  where puede_facturar() and r.empresa_id = mi_empresa() and r.cuenta_corporativa_id = p_cuenta
    and r.estado = 'finalizada' and r.eliminada_en is null
    and (r.fecha_hora at time zone 'America/Santiago')::date between p_desde and p_hasta
  order by r.fecha_hora
$$;
revoke execute on function facturacion_viajes(uuid, date, date) from public, anon;
grant execute on function facturacion_viajes(uuid, date, date) to authenticated;

-- Facturar viajes (solo los que aún no tienen factura)
create or replace function facturar_viajes(p_cuenta uuid, p_reservas uuid[], p_numero text, p_fecha date default null,
                                           p_desde date default null, p_hasta date default null, p_nota text default null)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint; v_n int; v_monto int; v_emp uuid := mi_empresa();
begin
  if not puede_facturar() then raise exception 'Solo administración o facturación'; end if;
  if nullif(trim(coalesce(p_numero, '')), '') is null then raise exception 'Escriba el número de la factura'; end if;
  if not exists (select 1 from cuentas_corporativas where id = p_cuenta and empresa_id = v_emp) then raise exception 'Empresa no encontrada'; end if;
  select count(*), coalesce(sum(v.total), 0) into v_n, v_monto from reservas r join v_cobro v on v.id = r.id
   where r.id = any (p_reservas) and r.cuenta_corporativa_id = p_cuenta and r.estado = 'finalizada' and r.factura_id is null and r.eliminada_en is null;
  if v_n = 0 then raise exception 'No hay viajes por facturar en la selección'; end if;
  insert into facturas (empresa_id, cuenta_id, numero, fecha, periodo_desde, periodo_hasta, monto, viajes, nota, creado_por)
  values (v_emp, p_cuenta, trim(p_numero), coalesce(p_fecha, (now() at time zone 'America/Santiago')::date), p_desde, p_hasta, v_monto, v_n,
          nullif(trim(coalesce(p_nota, '')), ''), auth.uid())
  returning id into v_id;
  update reservas set factura_id = v_id
   where id = any (p_reservas) and cuenta_corporativa_id = p_cuenta and estado = 'finalizada' and factura_id is null and eliminada_en is null;
  return v_id;
end $$;
revoke execute on function facturar_viajes(uuid, uuid[], text, date, date, date, text) from public, anon;
grant execute on function facturar_viajes(uuid, uuid[], text, date, date, date, text) to authenticated;

create or replace function facturas_de(p_cuenta uuid)
returns table(o_id bigint, o_numero text, o_fecha date, o_desde date, o_hasta date, o_monto integer, o_viajes integer, o_pagada boolean, o_anulada boolean, o_nota text)
language sql stable security definer set search_path = public as $$
  select id, numero, fecha, periodo_desde, periodo_hasta, monto, viajes, pagada, anulada, coalesce(anulada_motivo, nota)
  from facturas where puede_facturar() and empresa_id = mi_empresa() and cuenta_id = p_cuenta
  order by fecha desc, id desc limit 100
$$;
revoke execute on function facturas_de(uuid) from public, anon;
grant execute on function facturas_de(uuid) to authenticated;

-- Marcar factura pagada (marca pagados sus viajes) o anularla (los viajes vuelven a "por facturar")
create or replace function factura_accion(p_factura bigint, p_accion text, p_motivo text default null)
returns void language plpgsql security definer set search_path = public as $$
declare f facturas;
begin
  if not puede_facturar() then raise exception 'Solo administración o facturación'; end if;
  select * into f from facturas where id = p_factura and empresa_id = mi_empresa() for update;
  if f.id is null then raise exception 'Factura no encontrada'; end if;
  if f.anulada then raise exception 'La factura está anulada'; end if;
  if p_accion = 'pagada' then
    update facturas set pagada = true, pagada_en = now() where id = f.id;
    update reservas set pagado = true, pagado_en = coalesce(pagado_en, now()), pagado_medio = coalesce(pagado_medio, 'Factura ' || f.numero)
     where factura_id = f.id and not pagado;
  elsif p_accion = 'anular' then
    update facturas set anulada = true, anulada_motivo = nullif(trim(coalesce(p_motivo, '')), '') where id = f.id;
    update reservas set factura_id = null where factura_id = f.id;
  else raise exception 'Acción no válida'; end if;
end $$;
revoke execute on function factura_accion(bigint, text, text) from public, anon;
grant execute on function factura_accion(bigint, text, text) to authenticated;

-- Portal de empresas: estado de cuenta (encargado o directivo)
create or replace function convenio_estado_cuenta(p_desde date, p_hasta date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare yo convenio_usuarios; v jsonb; f jsonb;
begin
  yo := convenio_yo();
  if yo.id is null or yo.rol not in ('encargado', 'directivo') or yo.cuenta_id is null then raise exception 'Sin permiso'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('codigo', r.codigo, 'fecha', r.fecha_hora, 'pasajero', r.nombre_pasajero, 'origen', r.origen,
           'destino', r.destino, 'centro_costo', r.centro_costo, 'total', c.total, 'no_presentado', r.no_presentado, 'pagado', r.pagado,
           'factura', fa.numero) order by r.fecha_hora), '[]'::jsonb)
    into v
  from reservas r join v_cobro c on c.id = r.id left join facturas fa on fa.id = r.factura_id
  where r.cuenta_corporativa_id = yo.cuenta_id and r.estado = 'finalizada' and r.eliminada_en is null
    and (r.fecha_hora at time zone 'America/Santiago')::date between p_desde and p_hasta;
  select coalesce(jsonb_agg(jsonb_build_object('numero', numero, 'fecha', fecha, 'monto', monto, 'viajes', viajes, 'pagada', pagada) order by fecha desc), '[]'::jsonb)
    into f
  from facturas where cuenta_id = yo.cuenta_id and not anulada and fecha > (now() - interval '18 months')::date;
  return jsonb_build_object('viajes', v, 'facturas', f);
end $$;
revoke execute on function convenio_estado_cuenta(date, date) from public, anon;
grant execute on function convenio_estado_cuenta(date, date) to authenticated;
