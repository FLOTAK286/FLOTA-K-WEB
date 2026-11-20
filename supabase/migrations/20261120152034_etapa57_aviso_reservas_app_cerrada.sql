-- Etapa 57: aviso de "Nueva reserva disponible" también con la app cerrada (app Android 2.0+, sin armar una versión nueva).
-- En cada latido del teléfono (conductor_latido) se revisan las reservas publicadas que ese conductor ya puede ver según
-- su prioridad; las que aún no se le avisaron van en "avisos" (el servicio nativo las muestra si la app no está a la vista).
-- Se avisa a todos, cumplan o no los requisitos, solo si el conductor está conectado (igual que con la app abierta).
create table if not exists bolsa_avisos (
  conductor_id uuid not null references perfiles(id),
  reserva_id uuid not null references reservas(id),
  creado_en timestamptz not null default now(),
  primary key (conductor_id, reserva_id)
);
alter table bolsa_avisos enable row level security;
-- Sin políticas: solo la usan funciones internas.

do $$
declare f text;
begin
  f := pg_get_functiondef('conductor_latido(text, double precision, double precision, integer, integer, integer)'::regprocedure);
  if position('  return jsonb_build_object(''cada'', v_cada, ''avisos'', v_av);' in f) = 0 then
    raise exception 'conductor_latido cambió: revisar la migración';
  end if;
  f := replace(f, '  return jsonb_build_object(''cada'', v_cada, ''avisos'', v_av);',
'  -- Reservas publicadas que ya puede ver y que aún no se le avisaron (solo conectado)
  if coalesce(p.disponible, false) then
    for a in select r.id, r.fecha_hora, r.origen, r.destino from reservas r
              where r.empresa_id = d.empresa_id and r.en_bolsa and r.conductor_id is null and r.eliminada_en is null
                and r.estado in (''recibida'', ''confirmada'', ''asignada'') and r.fecha_hora > now()
                and bolsa_visible(r, nivel_bolsa(p.id))
                and not exists (select 1 from bolsa_avisos b where b.conductor_id = p.id and b.reserva_id = r.id)
              order by r.fecha_hora limit 5 loop
      insert into bolsa_avisos (conductor_id, reserva_id) values (p.id, a.id) on conflict do nothing;
      v_av := v_av || jsonb_build_array(jsonb_build_object(''id'', 900000 + (hashtext(a.id::text) & 65535), ''tipo'', ''reserva_disponible'',
        ''titulo'', ''Nueva reserva disponible · '' || to_char(a.fecha_hora at time zone ''America/Santiago'', ''DD/MM HH24:MI''),
        ''texto'', coalesce(case when array_length(string_to_array(a.origen, '',''), 1) > 1 then trim(array_to_string((string_to_array(a.origen, '',''))[2:3], '','')) else a.origen end, '''')
          || '' → '' || coalesce(case when array_length(string_to_array(a.destino, '',''), 1) > 1 then trim(array_to_string((string_to_array(a.destino, '',''))[2:3], '','')) else a.destino end, '''')
          || ''. Ábrala en Reservas: el primero que la toma se la queda.''));
    end loop;
  end if;
  return jsonb_build_object(''cada'', v_cada, ''avisos'', v_av);');
  execute f;
end $$;
