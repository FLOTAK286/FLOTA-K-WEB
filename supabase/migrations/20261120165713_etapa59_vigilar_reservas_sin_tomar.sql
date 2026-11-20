-- Etapa 59: vigilancia de las reservas publicadas que nadie toma (cada 2 minutos, pg_cron).
--  * 90 min antes: aviso a Operaciones "⚠️ Nadie ha tomado …".
--  * <bolsa_autoasignar_min> antes (por defecto 60; null = apagado): se asigna sola al conductor más cercano que cumpla
--    los requisitos, tenga el vehículo que pide el servicio y no tenga otro servicio a esa hora. Al conductor le llega
--    "🚗 Servicio nuevo" (como cuando asigna la central) y a Operaciones "🤖 … asignada sola a …".
--  * 45 min antes, si sigue sin conductor: aviso urgente "🚨".
--  Una reserva recién publicada tiene al menos 10 minutos en Reservas antes de avisar o asignar.
alter table empresas add column if not exists bolsa_autoasignar_min integer default 60 check (bolsa_autoasignar_min between 15 and 240);
alter table reservas add column if not exists bolsa_alerta1 timestamptz;
alter table reservas add column if not exists bolsa_alerta2 timestamptz;
alter table reservas add column if not exists bolsa_auto_intento timestamptz;

alter table avisos_equipo drop constraint if exists avisos_equipo_tipo_check;
alter table avisos_equipo add constraint avisos_equipo_tipo_check
  check (tipo in ('nueva', 'cancelada', 'rechazo', 'tomada', 'cambio_hora', 'acepto', 'postulante', 'sin_tomar', 'auto_asignada'));

create or replace function distancia_km(lat1 double precision, lng1 double precision, lat2 double precision, lng2 double precision)
returns double precision language sql immutable as $$
  select 6371 * 2 * asin(sqrt(power(sin(radians(lat2 - lat1) / 2), 2) + cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)))
$$;

-- Conductor más cercano que puede hacer esta reserva (null si no hay)
create or replace function conductor_mas_cercano(r reservas)
returns table(o_conductor uuid, o_vehiculo uuid, o_nombre text, o_km double precision)
language sql stable security definer set search_path = public as $$
  select p.id, v.id, p.nombre,
         case when u.lat is not null and r.origen_lat is not null then distancia_km(u.lat, u.lng, r.origen_lat, r.origen_lng) end
  from perfiles p
  join lateral (select * from vehiculos x where x.conductor_habitual = p.id and x.activo order by x.creado_en limit 1) v on true
  left join ubicaciones u on u.conductor_id = p.id
  where p.empresa_id = r.empresa_id and p.activo and (p.conduce or p.rol = 'conductor')
    and motivo_requisitos_bolsa(r, p.id) is null
    and case coalesce(r.vehiculo, 'auto') when 'van' then v.categoria = 'van'
             when 'suv' then v.categoria in ('suv', 'van', 'particular_suv') else true end
    and not exists (select 1 from reservas o where o.conductor_id = p.id and o.id <> r.id and o.eliminada_en is null
                    and o.estado not in ('cancelada', 'finalizada')
                    and o.fecha_hora < r.fecha_hora + make_interval(mins => coalesce(r.duracion_min, 90) + 15)
                    and r.fecha_hora < o.fecha_hora + make_interval(mins => coalesce(o.duracion_min, 90) + 15))
    and not coalesce(p.otro_servicio_hasta > r.fecha_hora - interval '15 minutes', false)
  order by p.disponible desc,                                              -- primero los conectados
           (u.actualizado_en is null or u.actualizado_en < now() - interval '2 hours'),  -- con ubicación reciente
           case when u.lat is not null and r.origen_lat is not null then distancia_km(u.lat, u.lng, r.origen_lat, r.origen_lng) end nulls last
  limit 1
$$;
revoke execute on function conductor_mas_cercano(reservas) from public, anon, authenticated;

create or replace function bolsa_vigilar()
returns integer language plpgsql security definer set search_path = public as $$
declare r reservas; v_min int; v_auto int; v_det text; c record; n int := 0; v_estado_antes estado_reserva;
begin
  for r in select res.* from reservas res
            where res.en_bolsa and res.conductor_id is null and res.derivado_a is null and res.eliminada_en is null
              and res.estado in ('recibida', 'confirmada', 'asignada') and res.fecha_hora > now()
              and res.fecha_hora <= now() + interval '90 minutes'
            for update skip locked
  loop
    v_min := ceil(extract(epoch from (r.fecha_hora - now())) / 60)::int;
    v_det := r.codigo || ' · ' || to_char(r.fecha_hora at time zone 'America/Santiago', 'HH24:MI') || ' · '
             || left(coalesce(r.origen, ''), 60) || ' → ' || left(coalesce(r.destino, ''), 60);
    select bolsa_autoasignar_min into v_auto from empresas where id = r.empresa_id;

    -- Recién publicada: se le dan al menos 10 minutos en Reservas antes de avisar o asignar
    if r.bolsa_desde is not null and r.bolsa_desde > now() - interval '10 minutes' then continue; end if;

    -- 1) Asignación automática al más cercano que cumple
    if v_auto is not null and v_min <= v_auto and r.bolsa_auto_intento is null then
      update reservas set bolsa_auto_intento = now() where id = r.id;
      select * into c from conductor_mas_cercano(r);
      if c.o_conductor is not null then
        v_estado_antes := r.estado;
        update reservas set conductor_id = c.o_conductor, vehiculo_id = c.o_vehiculo, en_bolsa = false, bolsa_desde = null,
               conductor_respuesta = null, estado = case when estado in ('recibida', 'confirmada') then 'asignada'::estado_reserva else estado end
         where id = r.id;
        if v_estado_antes <> 'asignada' then
          update reserva_eventos set nota = 'Asignada automáticamente (nadie la tomó en Reservas) a ' || c.o_nombre
                 || coalesce(' · a ' || replace(to_char(c.o_km, 'FM990.0'), '.', ',') || ' km', '')
           where id = (select max(id) from reserva_eventos where reserva_id = r.id);
        else
          insert into reserva_eventos (reserva_id, estado, nota) values (r.id, r.estado,
            'Asignada automáticamente (nadie la tomó en Reservas) a ' || c.o_nombre || coalesce(' · a ' || replace(to_char(c.o_km, 'FM990.0'), '.', ',') || ' km', ''));
        end if;
        insert into avisos_equipo (empresa_id, reserva_id, tipo, titulo, texto)
        values (r.empresa_id, r.id, 'auto_asignada', '🤖 Asignada sola a ' || c.o_nombre,
                'Nadie la tomó en Reservas: se asignó al conductor más cercano que cumple' || coalesce(' (' || replace(to_char(c.o_km, 'FM990.0'), '.', ',') || ' km)', '') || '. ' || v_det);
        n := n + 1;
        continue;
      else
        insert into avisos_equipo (empresa_id, reserva_id, tipo, titulo, texto)
        values (r.empresa_id, r.id, 'sin_tomar', '🚨 Nadie puede tomar ' || r.codigo,
                'Ningún conductor disponible cumple los requisitos o tiene libre esa hora. Asígnela a mano. ' || v_det);
        update reservas set bolsa_alerta1 = coalesce(bolsa_alerta1, now()) where id = r.id;
        r.bolsa_alerta1 := coalesce(r.bolsa_alerta1, now());
      end if;
    end if;

    -- 2) Avisos a Operaciones: 90 y 45 minutos antes
    if r.bolsa_alerta1 is null then
      insert into avisos_equipo (empresa_id, reserva_id, tipo, titulo, texto)
      values (r.empresa_id, r.id, 'sin_tomar', '⚠️ Nadie ha tomado ' || r.codigo,
              'Faltan ' || v_min || ' min.' || case when v_auto is not null and v_min > v_auto then ' Si nadie la toma, se asignará sola ' || v_auto || ' min antes.' else '' end || ' ' || v_det);
      update reservas set bolsa_alerta1 = now() where id = r.id;
    elsif v_min <= 45 and r.bolsa_alerta2 is null then
      insert into avisos_equipo (empresa_id, reserva_id, tipo, titulo, texto)
      values (r.empresa_id, r.id, 'sin_tomar', '🚨 ' || r.codigo || ' sigue sin conductor', 'Faltan ' || v_min || ' min: asígnela a mano. ' || v_det);
      update reservas set bolsa_alerta2 = now() where id = r.id;
    end if;
  end loop;
  return n;
end $$;
revoke execute on function bolsa_vigilar() from public, anon, authenticated;

-- Al volver a publicar, las alertas y el intento automático parten de cero
do $$
declare f text;
begin
  f := pg_get_functiondef('liberar_a_bolsa(uuid, boolean)'::regprocedure);
  if position('bolsa_categorias = null, bolsa_corporativo = false, bolsa_calif_min = null, bolsa_sin_calif = false where id = r.id;' in f) = 0 then
    raise exception 'liberar_a_bolsa cambió: revisar la migración';
  end if;
  execute replace(f, 'bolsa_categorias = null, bolsa_corporativo = false, bolsa_calif_min = null, bolsa_sin_calif = false where id = r.id;',
    'bolsa_categorias = null, bolsa_corporativo = false, bolsa_calif_min = null, bolsa_sin_calif = false,
         bolsa_alerta1 = null, bolsa_alerta2 = null, bolsa_auto_intento = null where id = r.id;');
end $$;

select cron.schedule('flotak-bolsa-vigilar', '*/2 * * * *', 'select public.bolsa_vigilar()');
