-- Etapa 38: avisos al conductor con la app cerrada (sin Firebase).
-- Cada cambio que le importa al conductor (servicio nuevo, quitado, cancelado o modificado) queda en avisos_conductor.
-- El servicio de ubicación del teléfono pregunta cada 15-60 s (conductor_latido) y, si hay avisos, suena y muestra la notificación.

create table if not exists avisos_conductor (
  id bigint generated always as identity primary key,
  conductor_id uuid not null references perfiles(id),
  empresa_id uuid not null references empresas(id),
  reserva_id uuid references reservas(id),
  tipo text not null check (tipo in ('nuevo', 'quitado', 'cancelado', 'modificado')),
  titulo text not null,
  texto text not null,
  creado_en timestamptz not null default now(),
  entregado_en timestamptz
);
create index if not exists avisos_conductor_pend on avisos_conductor (conductor_id) where entregado_en is null;
alter table avisos_conductor enable row level security;
create policy avisos_conductor_ver on avisos_conductor for select
  using (empresa_id = mi_empresa() and (es_staff() or conductor_id = auth.uid()));

create or replace function avisar_conductor_reserva()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_det text;
begin
  if new.eliminada_en is not null then return new; end if;
  v_det := to_char(new.fecha_hora at time zone 'America/Santiago', 'DD/MM HH24:MI') || ' · ' ||
           coalesce(new.nombre_pasajero, 'Pasajero') || ': ' || left(coalesce(new.origen, ''), 80) || ' → ' || left(coalesce(new.destino, ''), 80);
  if tg_op = 'INSERT' then
    if new.conductor_id is not null and new.estado not in ('cancelada', 'finalizada') then
      insert into avisos_conductor (conductor_id, empresa_id, reserva_id, tipo, titulo, texto)
      values (new.conductor_id, new.empresa_id, new.id, 'nuevo', '🚗 Servicio nuevo', v_det);
    end if;
    return new;
  end if;
  -- El propio conductor hizo el cambio (tomó una reserva, avanzó el estado): no se le avisa a él mismo
  if new.conductor_id is distinct from old.conductor_id then
    if old.conductor_id is not null and old.conductor_id is distinct from auth.uid() and old.estado not in ('cancelada', 'finalizada') then
      insert into avisos_conductor (conductor_id, empresa_id, reserva_id, tipo, titulo, texto)
      values (old.conductor_id, new.empresa_id, new.id, 'quitado', '↩️ Servicio quitado', 'La central le quitó este servicio. ' || v_det);
    end if;
    if new.conductor_id is not null and new.conductor_id is distinct from auth.uid() and new.estado not in ('cancelada', 'finalizada') then
      insert into avisos_conductor (conductor_id, empresa_id, reserva_id, tipo, titulo, texto)
      values (new.conductor_id, new.empresa_id, new.id, 'nuevo', '🚗 Servicio nuevo', v_det);
    end if;
  elsif new.conductor_id is not null and new.conductor_id is distinct from auth.uid() then
    if new.estado = 'cancelada' and old.estado <> 'cancelada' then
      insert into avisos_conductor (conductor_id, empresa_id, reserva_id, tipo, titulo, texto)
      values (new.conductor_id, new.empresa_id, new.id, 'cancelado', '❌ Servicio cancelado', v_det);
    elsif new.estado not in ('cancelada', 'finalizada') and (new.fecha_hora is distinct from old.fecha_hora
          or new.origen is distinct from old.origen or new.destino is distinct from old.destino
          or new.paradas is distinct from old.paradas or new.vuelo is distinct from old.vuelo) then
      insert into avisos_conductor (conductor_id, empresa_id, reserva_id, tipo, titulo, texto)
      values (new.conductor_id, new.empresa_id, new.id, 'modificado', '✏️ Servicio modificado', v_det);
    end if;
  end if;
  return new;
end $$;
revoke execute on function avisar_conductor_reserva() from public, anon, authenticated;
create trigger reservas_zz_avisar_conductor after insert or update on reservas
  for each row execute function avisar_conductor_reserva();

-- Latido del teléfono (sin sesión, con la llave del dispositivo): guarda la ubicación y entrega los avisos pendientes.
-- Ubicación: en servicio y conectado, en cada latido; desconectado, cada 5 minutos (como antes).
-- Devuelve { cada: segundos al próximo latido (15 en servicio, 30 conectado, 60 desconectado; 0 = detenerse), avisos: [...] }
create or replace function conductor_latido(p_llave text, p_lat double precision, p_lng double precision,
  p_precision int default null, p_rumbo int default null, p_velocidad int default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare d dispositivos_conductor; p perfiles; v_res uuid; v_ult timestamptz; v_cada int; v_min interval;
  v_av jsonb := '[]'::jsonb; a record;
begin
  if length(coalesce(p_llave, '')) <> 64 then return jsonb_build_object('cada', 0); end if;
  select * into d from dispositivos_conductor where llave_hash = encode(digest(p_llave, 'sha256'), 'hex') and revocado_en is null;
  if d.id is null then return jsonb_build_object('cada', 0); end if;
  select * into p from perfiles where id = d.conductor_id and activo and (conduce or rol = 'conductor');
  if p.id is null then return jsonb_build_object('cada', 0); end if;
  select id into v_res from reservas where conductor_id = d.conductor_id and estado in ('en_camino', 'en_lugar', 'a_bordo')
    and eliminada_en is null order by fecha_hora limit 1;
  v_cada := case when v_res is not null then 15 when p.disponible then 30 else 60 end;
  v_min := case when v_res is null and not coalesce(p.disponible, false) then interval '290 seconds' else interval '5 seconds' end;
  if p_lat is not null and p_lng is not null and p_lat between -90 and 90 and p_lng between -180 and 180 then
    select actualizado_en into v_ult from ubicaciones where conductor_id = d.conductor_id;
    if v_ult is null or v_ult < now() - v_min then
      insert into ubicaciones (conductor_id, empresa_id, reserva_id, lat, lng, precision_m, rumbo, velocidad_kmh, actualizado_en)
      values (d.conductor_id, d.empresa_id, v_res, p_lat, p_lng, least(greatest(coalesce(p_precision, 0), 0), 100000),
              case when p_rumbo between 0 and 360 then p_rumbo end, case when p_velocidad between 0 and 300 then p_velocidad end, now())
      on conflict (conductor_id) do update set empresa_id = excluded.empresa_id, reserva_id = excluded.reserva_id, lat = excluded.lat,
        lng = excluded.lng, precision_m = excluded.precision_m, rumbo = excluded.rumbo, velocidad_kmh = excluded.velocidad_kmh,
        actualizado_en = excluded.actualizado_en;
    end if;
  end if;
  update dispositivos_conductor set ultimo_uso = now() where id = d.id;
  -- Avisos pendientes: se marcan entregados; solo se muestran los de las últimas 2 horas
  for a in update avisos_conductor set entregado_en = now()
            where conductor_id = d.conductor_id and entregado_en is null
            returning id, tipo, titulo, texto, creado_en loop
    if a.creado_en > now() - interval '2 hours' then
      v_av := v_av || jsonb_build_array(jsonb_build_object('id', a.id, 'tipo', a.tipo, 'titulo', a.titulo, 'texto', a.texto));
    end if;
  end loop;
  return jsonb_build_object('cada', v_cada, 'avisos', v_av);
end $$;
revoke execute on function conductor_latido(text, double precision, double precision, int, int, int) from public;
grant execute on function conductor_latido(text, double precision, double precision, int, int, int) to anon, authenticated;
