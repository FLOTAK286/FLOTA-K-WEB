-- Etapa 4: cobro (tarifa fija / taxímetro), gastos, observación del conductor, pagos (solo admin), ficha de cliente automática.

-- ============ Tarifas del taxímetro por empresa (configurables) ============
alter table empresas add column if not exists taxi_bajada int not null default 2400 check (taxi_bajada >= 0);
alter table empresas add column if not exists taxi_cada_200m int not null default 180 check (taxi_cada_200m >= 0);
alter table empresas add column if not exists taxi_cada_60s int not null default 180 check (taxi_cada_60s >= 0);
alter table empresas add column if not exists valor_tag int not null default 900 check (valor_tag >= 0);
create policy empresas_admin_update on empresas for update
  using (id = mi_empresa() and mi_rol() = 'admin') with check (id = mi_empresa() and mi_rol() = 'admin');

-- ============ Cobro en la reserva ============
alter table reservas add column if not exists tipo_cobro text not null default 'fija' check (tipo_cobro in ('fija', 'taximetro'));
alter table reservas add column if not exists taxi_metros int check (taxi_metros >= 0);
alter table reservas add column if not exists taxi_segundos int check (taxi_segundos >= 0);
alter table reservas add column if not exists taxi_total int check (taxi_total >= 0);
alter table reservas add column if not exists observacion_conductor text;
alter table reservas add column if not exists observacion_revisada boolean not null default false;
alter table reservas add column if not exists pagado_en timestamptz;
alter table reservas add column if not exists pagado_medio text;
alter table reservas add column if not exists pagado_por uuid references auth.users(id);
-- Efectivo bloqueado por ahora (se quita esta regla cuando se habilite)
alter table reservas add constraint reservas_sin_efectivo
  check (forma_pago is null or forma_pago not ilike 'efectivo%') not valid;

create table if not exists reserva_gastos (
  id          bigint generated always as identity primary key,
  empresa_id  uuid not null references empresas(id),
  reserva_id  uuid not null references reservas(id) on delete cascade,
  tipo        text not null check (tipo in ('tag', 'peaje', 'estacionamiento', 'otro')),
  cantidad    int not null default 1 check (cantidad between 1 and 50),
  monto       int not null check (monto >= 0),
  descripcion text,
  creado_por  uuid references auth.users(id),
  creado_en   timestamptz not null default now()
);
create index if not exists reserva_gastos_reserva on reserva_gastos (reserva_id);
alter table reserva_gastos enable row level security;
create policy gastos_equipo_ver on reserva_gastos for select
  using (empresa_id = mi_empresa() and es_staff());
create policy gastos_admin on reserva_gastos for all
  using (empresa_id = mi_empresa() and mi_rol() = 'admin')
  with check (empresa_id = mi_empresa() and mi_rol() = 'admin');
create policy gastos_conductor_ver on reserva_gastos for select
  using (reserva_id in (select id from reservas where conductor_id = auth.uid()));

create or replace function proteger_pago() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (new.pagado is distinct from old.pagado or new.pagado_en is distinct from old.pagado_en
      or new.pagado_medio is distinct from old.pagado_medio)
     and coalesce(mi_rol()::text, '') <> 'admin' and auth.uid() is not null then
    raise exception 'Solo el administrador puede marcar servicios como pagados';
  end if;
  return new;
end $$;
create trigger reservas_proteger_pago before update on reservas
  for each row execute function proteger_pago();

-- ============ Ficha de cliente automática ============
create or replace function asegurar_cliente() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_tel text := right(regexp_replace(coalesce(new.telefono, ''), '\D', '', 'g'), 8);
  v_correo text := lower(trim(coalesce(new.correo, '')));
begin
  if new.cliente_id is not null then return new; end if;
  select id into new.cliente_id from clientes c
   where c.empresa_id = new.empresa_id
     and ((v_correo <> '' and lower(c.correo) = v_correo)
       or (length(v_tel) = 8 and right(regexp_replace(coalesce(c.telefono, ''), '\D', '', 'g'), 8) = v_tel))
   order by c.creado_en limit 1;
  if new.cliente_id is null then
    insert into clientes (empresa_id, nombre, telefono, correo)
    values (new.empresa_id, new.nombre_pasajero, new.telefono, nullif(v_correo, ''))
    returning id into new.cliente_id;
  end if;
  return new;
end $$;
create trigger reservas_asegurar_cliente before insert on reservas
  for each row execute function asegurar_cliente();

create or replace view v_cobro with (security_invoker = true) as
select r.id, r.empresa_id, r.cliente_id, r.codigo, r.fecha_hora, r.estado, r.nombre_pasajero, r.origen, r.destino,
       r.tipo_cobro, r.taxi_metros, r.taxi_segundos,
       case when r.tipo_cobro = 'taximetro' then r.taxi_total else coalesce(r.precio, r.tarifa_web) end as valor_base,
       coalesce((select sum(g.monto) from reserva_gastos g where g.reserva_id = r.id), 0)::int as gastos,
       (coalesce(case when r.tipo_cobro = 'taximetro' then r.taxi_total else coalesce(r.precio, r.tarifa_web) end, 0)
        + coalesce((select sum(g.monto) from reserva_gastos g where g.reserva_id = r.id), 0))::int as total,
       r.forma_pago, r.pagado, r.pagado_en, r.pagado_medio, r.observacion_conductor, r.observacion_revisada,
       r.token_seguimiento, r.conductor_id, r.vuelo
from reservas r;

-- ============ Funciones ============
create or replace function conductor_observacion(p_reserva uuid, p_texto text)
returns void
language plpgsql security definer set search_path = public as $$
declare v_t text := nullif(left(trim(coalesce(p_texto, '')), 1000), '');
begin
  if v_t is null then raise exception 'Escriba la observación'; end if;
  update reservas set observacion_conductor = trim(both E'\n' from coalesce(observacion_conductor || E'\n', '') || v_t),
                      observacion_revisada = false
   where id = p_reserva and conductor_id = auth.uid();
  if not found then raise exception 'Este servicio no está asignado a usted'; end if;
  insert into reserva_eventos (reserva_id, estado, nota, usuario_id)
  values (p_reserva, (select estado from reservas where id = p_reserva), 'Observación del conductor: ' || v_t, auth.uid());
end $$;

create or replace function conductor_finalizar(p_reserva uuid, p_metros int default null, p_segundos int default null,
                                               p_gastos jsonb default '[]'::jsonb, p_observacion text default null)
returns int
language plpgsql security definer set search_path = public as $$
declare
  r reservas%rowtype;
  e empresas%rowtype;
  g jsonb;
  v_total int;
  v_tipo text; v_cant int; v_monto int;
begin
  select * into r from reservas where id = p_reserva and conductor_id = auth.uid() for update;
  if not found then raise exception 'Este servicio no está asignado a usted'; end if;
  if r.estado in ('finalizada', 'cancelada') then raise exception 'Este servicio ya está cerrado'; end if;
  select * into e from empresas where id = r.empresa_id;

  if r.tipo_cobro = 'taximetro' then
    if p_metros is null or p_metros < 0 or p_metros > 1000000 then raise exception 'Ingrese los metros recorridos'; end if;
    if coalesce(p_segundos, 0) < 0 or coalesce(p_segundos, 0) > 86400 then raise exception 'Tiempo de espera no válido'; end if;
    v_total := e.taxi_bajada + (p_metros / 200) * e.taxi_cada_200m + (coalesce(p_segundos, 0) / 60) * e.taxi_cada_60s;
    update reservas set taxi_metros = p_metros, taxi_segundos = coalesce(p_segundos, 0), taxi_total = v_total where id = r.id;
    for g in select * from jsonb_array_elements(coalesce(p_gastos, '[]'::jsonb)) loop
      v_tipo := g->>'tipo';
      v_cant := greatest(1, coalesce((g->>'cantidad')::int, 1));
      v_monto := case when v_tipo = 'tag' then v_cant * e.valor_tag else coalesce((g->>'monto')::int, 0) end;
      if v_tipo not in ('tag', 'peaje', 'estacionamiento', 'otro') or v_monto < 0 then raise exception 'Gasto no válido'; end if;
      if v_monto > 0 then
        insert into reserva_gastos (empresa_id, reserva_id, tipo, cantidad, monto, descripcion, creado_por)
        values (r.empresa_id, r.id, v_tipo, v_cant, v_monto, nullif(left(trim(coalesce(g->>'descripcion', '')), 200), ''), auth.uid());
      end if;
    end loop;
  end if;

  if nullif(trim(coalesce(p_observacion, '')), '') is not null then
    update reservas set observacion_conductor = trim(both E'\n' from coalesce(observacion_conductor || E'\n', '') || left(trim(p_observacion), 1000)),
                        observacion_revisada = false where id = r.id;
  end if;

  update reservas set estado = 'finalizada' where id = r.id;
  update reserva_eventos set nota = 'Finalizado' || coalesce(': ' || nullif(left(trim(coalesce(p_observacion, '')), 300), ''), '')
    where id = (select max(id) from reserva_eventos where reserva_id = r.id);
  select total into v_total from v_cobro where id = r.id;
  return v_total;
end $$;

create or replace function marcar_pagado(p_reservas uuid[], p_pagado boolean, p_medio text default null, p_fecha date default null)
returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if mi_rol() is distinct from 'admin' then raise exception 'Solo el administrador puede marcar pagos'; end if;
  if p_pagado and p_medio ilike 'efectivo%' then raise exception 'Los pagos en efectivo están deshabilitados por ahora'; end if;
  update reservas set pagado = p_pagado,
         pagado_en = case when p_pagado then coalesce(p_fecha::timestamptz, now()) else null end,
         pagado_medio = case when p_pagado then nullif(trim(coalesce(p_medio, '')), '') else null end,
         pagado_por = case when p_pagado then auth.uid() else null end
   where id = any(p_reservas) and empresa_id = mi_empresa();
  get diagnostics n = row_count;
  return n;
end $$;

revoke execute on function conductor_observacion(uuid, text) from public, anon;
revoke execute on function conductor_finalizar(uuid, int, int, jsonb, text) from public, anon;
revoke execute on function marcar_pagado(uuid[], boolean, text, date) from public, anon;
revoke execute on function proteger_pago() from public, anon, authenticated;
revoke execute on function asegurar_cliente() from public, anon, authenticated;
grant execute on function conductor_observacion(uuid, text) to authenticated;
grant execute on function conductor_finalizar(uuid, int, int, jsonb, text) to authenticated;
grant execute on function marcar_pagado(uuid[], boolean, text, date) to authenticated;

-- Fichas para reservas ya existentes sin cliente
do $$
declare x record; v uuid;
begin
  for x in select * from reservas where cliente_id is null loop
    select id into v from clientes c where c.empresa_id = x.empresa_id
      and ((coalesce(x.correo,'') <> '' and lower(c.correo) = lower(x.correo))
        or right(regexp_replace(coalesce(c.telefono,''), '\D', '', 'g'), 8) = right(regexp_replace(coalesce(x.telefono,''), '\D', '', 'g'), 8))
      limit 1;
    if v is null then
      insert into clientes (empresa_id, nombre, telefono, correo) values (x.empresa_id, x.nombre_pasajero, x.telefono, nullif(lower(x.correo),'')) returning id into v;
    end if;
    update reservas set cliente_id = v where id = x.id;
  end loop;
end $$;
