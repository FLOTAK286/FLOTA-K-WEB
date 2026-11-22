-- Etapa 70: reserva por enlace con PAGO ANTES de crear la reserva (Flow).
-- El agente de WhatsApp envía fk-servicios.com/reservar. El pasajero completa sus datos y paga en Flow.
-- Mientras no pague, sus datos son una "solicitud de pago" (no es reserva: no aparece en el panel ni avisa).
-- Cuando Flow confirma el pago (Edge Function "flow"), crear_reservas_pagadas crea la(s) reserva(s)
-- confirmadas y pagadas, con aviso "📅 Reserva nueva" a Operaciones.
-- El precio lo calcula el servidor con estas tablas (no el teléfono del pasajero).
-- OJO: si cambia el tarifario, cambiarlo en assets/tarifas.js (lo que se muestra) Y en estas tablas (lo que se cobra).

create table if not exists public.tarifas_aeropuerto (
  empresa_id uuid not null references public.empresas(id),
  zona text not null,
  ida integer not null check (ida > 0),
  regreso integer not null check (regreso > 0),
  van integer not null check (van > 0),
  primary key (empresa_id, zona)
);
alter table public.tarifas_aeropuerto enable row level security;
create policy tarifas_aeropuerto_ver on public.tarifas_aeropuerto for select using (true);
create policy tarifas_aeropuerto_admin on public.tarifas_aeropuerto for all
  using (es_staff() and mi_rol()::text = 'admin') with check (es_staff() and mi_rol()::text = 'admin');

insert into public.tarifas_aeropuerto (empresa_id, zona, ida, regreso, van)
select e.id, t.zona, t.ida, t.regreso, t.van from public.empresas e,
(values
  ('Buin', 46000, 49000, 63000),
  ('Maipo', 49000, 51000, 63000),
  ('Linderos', 49000, 51000, 63000),
  ('Paine', 54000, 57000, 69000),
  ('Huelquén', 62000, 64000, 79000),
  ('Champa', 63000, 65000, 84000),
  ('Calera de Tango', 38000, 40000, 53000),
  ('Camino Lonquén (Veterquímica)', 24000, 26000, 32000),
  ('Cerrillos', 21000, 23000, 34000),
  ('Cerro Navia', 19000, 20000, 30000),
  ('Colina centro hasta Esmeralda', 44000, 46000, 58000),
  ('Colina sector Peldehue - Chacabuco', 60000, 62000, 69000),
  ('Conchalí', 23000, 25000, 34000),
  ('Curacaví', 49000, 51000, 69000),
  ('María Pinto', 52000, 54000, 69000),
  ('Chicureo hasta Piedra Roja (vía normal)', 38000, 40000, 53000),
  ('Chicureo desde Los Pioneros - Lo Arcaya', 40000, 43000, 58000),
  ('El Bosque', 31000, 33000, 42000),
  ('El Monte', 53000, 57000, 69000),
  ('Estación Central', 19000, 21000, 28000),
  ('Farellones (temporada baja)', 108000, 108000, 158000),
  ('Huechuraba', 29000, 31000, 37000),
  ('Independencia', 22000, 24000, 32000),
  ('Isla de Maipo', 57000, 59000, 74000),
  ('La Cisterna', 29000, 31000, 37000),
  ('La Florida hasta Av. La Florida', 37000, 39000, 53000),
  ('La Florida desde Av. La Florida', 39000, 42000, 55000),
  ('La Florida Alto Macul, Las Perdices al oriente', 43000, 45000, 58000),
  ('La Granja', 32000, 34000, 42000),
  ('La Pintana', 36000, 38000, 48000),
  ('La Reina (Vicente Pérez Rosales)', 37000, 39000, 53000),
  ('La Reina (Padre Hurtado - Las Perdices)', 39000, 42000, 55000),
  ('La Reina Alta (Álvaro Casanova)', 43000, 45000, 63000),
  ('Lampa Pueblo (centro)', 30000, 32000, 42000),
  ('Lampa Chicauma', 33000, 35000, 48000),
  ('Lampa Valle Grande', 32000, 34000, 48000),
  ('Lampa Batuco', 40000, 43000, 53000),
  ('Las Condes hasta Manquehue', 34000, 36000, 48000),
  ('Las Condes desde Manquehue hasta Paul Harris', 37000, 39000, 50000),
  ('Lo Barnechea hasta el Golf de Manquehue', 43000, 45000, 58000),
  ('Lo Barnechea hasta P.L. Urqueta y B.L. Cotapos', 44000, 46000, 60000),
  ('Lo Barnechea Pie Andino (Paseo Los Bravos)', 49000, 51000, 63000),
  ('El Arrayán', 49000, 51000, 69000),
  ('Lo Espejo', 29000, 31000, 38000),
  ('Lo Prado', 18000, 20000, 29000),
  ('Lonquén (Pueblo)', 46000, 48000, 63000),
  ('Los Andes', 98000, 98000, 137000),
  ('Macul', 36000, 38000, 48000),
  ('Maipú hasta Plaza de Maipú', 22000, 24000, 32000),
  ('Maipú desde Plaza de Maipú', 27000, 30000, 37000),
  ('Maipú Ciudad Satélite', 31000, 33000, 42000),
  ('Melipilla', 76000, 78000, 100000),
  ('Ñuñoa por Costanera', 33000, 35000, 48000),
  ('Ñuñoa por Vespucio Sur', 35000, 37000, 48000),
  ('Padre Hurtado', 32000, 34000, 42000),
  ('Pedro Aguirre Cerda', 27000, 30000, 37000),
  ('Peñaflor', 39000, 42000, 51000),
  ('Peñalolén hasta Tobalaba', 39000, 42000, 51000),
  ('Peñalolén Alto hasta Las Perdices', 42000, 44000, 53000),
  ('Peñalolén Diagonal Las Torres', 44000, 46000, 58000),
  ('Pirque hasta Virginia Subercaseaux', 48000, 50000, 61000),
  ('Pirque El Principal - Club de Golf', 54000, 57000, 74000),
  ('Providencia', 30000, 32000, 42000),
  ('Pudahuel', 18000, 19000, 25000),
  ('Puente Alto', 43000, 45000, 58000),
  ('Puente Alto Las Vizcachas', 45000, 47000, 60000),
  ('Quilicura', 22000, 24000, 34000),
  ('Quinta Normal', 19000, 22000, 30000),
  ('Rancagua', 103000, 103000, 137000),
  ('Recoleta', 29000, 31000, 40000),
  ('Renca', 19000, 22000, 26000),
  ('San Bernardo', 35000, 38000, 46000),
  ('San Bernardo - Nos', 37000, 39000, 48000),
  ('San Carlos de Apoquindo hasta C. Otoñal, San Damián', 37000, 39000, 48000),
  ('San Carlos de Apoquindo hasta Av. La Plaza', 39000, 42000, 51000),
  ('San Carlos de Apoquindo, Av. La Plaza a cordillera', 42000, 44000, 55000),
  ('San Felipe', 108000, 108000, 153000),
  ('San Joaquín', 31000, 33000, 42000),
  ('San José de Maipo', 71000, 73000, 100000),
  ('San Miguel', 30000, 32000, 40000),
  ('San Ramón', 32000, 33000, 42000),
  ('Santiago Centro', 26000, 28000, 37000),
  ('Talagante', 47000, 49000, 61000),
  ('Til Til', 65000, 67000, 84000),
  ('Valparaíso - Viña del Mar', 130000, 130000, 168000),
  ('Vitacura hasta Manquehue', 34000, 36000, 46000),
  ('Vitacura hasta Tabancura', 37000, 39000, 48000)
) as t(zona, ida, regreso, van)
where e.slug = 'flota-k'
on conflict (empresa_id, zona) do update set ida = excluded.ida, regreso = excluded.regreso, van = excluded.van;

-- Tramos con tarifa fija fuera del aeropuerto (igual que FK_INTERURBANOS)
create table if not exists public.tarifas_tramos (
  id bigint generated always as identity primary key,
  empresa_id uuid not null references public.empresas(id),
  nombre text not null,
  auto integer not null, van integer not null,
  lado_a text[] not null, lado_b text[] not null
);
alter table public.tarifas_tramos enable row level security;
create policy tarifas_tramos_ver on public.tarifas_tramos for select using (true);
insert into public.tarifas_tramos (empresa_id, nombre, auto, van, lado_a, lado_b)
select id, 'Sector Oriente de Santiago ↔ Viña del Mar / Valparaíso', 170000, 240000,
       array['las condes','vitacura','lo barnechea','providencia','la reina','nunoa'], array['vina del mar','valparaiso']
from public.empresas where slug = 'flota-k'
  and not exists (select 1 from public.tarifas_tramos);

-- Solicitudes en espera de pago (solo las maneja el servidor: RLS sin políticas)
create table if not exists public.solicitudes_pago (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id),
  orden text not null unique,                  -- commerceOrder enviado a Flow
  datos jsonb not null,                        -- {contacto, tramos:[...]}
  monto integer not null check (monto > 0),
  telefono text, correo text,
  estado text not null default 'pendiente' check (estado in ('pendiente', 'pagada', 'rechazada', 'vencida', 'error')),
  flow_token text, flow_order bigint, flow_medio text,
  codigos text[], token_seguimiento uuid,
  error text,
  creada_en timestamptz not null default now(),
  vence_en timestamptz not null default now() + interval '40 minutes',
  pagada_en timestamptz
);
alter table public.solicitudes_pago enable row level security;
create index if not exists solicitudes_pago_tel on public.solicitudes_pago (telefono, creada_en);

-- Crea las reservas de una solicitud pagada. Idempotente: si ya se crearon, devuelve las mismas.
-- Solo la llama la Edge Function "flow" (service_role). No exige las 2 horas de anticipación
-- (ya se validaron al iniciar el pago): una reserva pagada nunca se pierde.
create or replace function public.crear_reservas_pagadas(p_id uuid, p_flow_order bigint, p_medio text)
returns table(o_codigos text[], o_token uuid)
language plpgsql security definer set search_path to 'public' as $function$
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
revoke all on function public.crear_reservas_pagadas(uuid, bigint, text) from public, anon, authenticated;
grant execute on function public.crear_reservas_pagadas(uuid, bigint, text) to service_role;

-- Las solicitudes no pagadas vencen solas (no se borran: quedan como respaldo)
select cron.schedule('flotak-solicitudes-vencer', '*/10 * * * *',
  $$update public.solicitudes_pago set estado = 'vencida' where estado = 'pendiente' and vence_en < now()$$);
