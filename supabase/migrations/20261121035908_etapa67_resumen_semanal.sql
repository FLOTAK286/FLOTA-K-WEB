-- Etapa 67: resumen semanal automático. Cada lunes (≈ 9:00 de Chile) llega a Operaciones un aviso con la semana anterior:
-- servicios, ingresos, negativos, cancelaciones, de dónde llegaron los clientes y ventas. También se ve en Reportes.
alter table avisos_equipo drop constraint if exists avisos_equipo_tipo_check;
alter table avisos_equipo add constraint avisos_equipo_tipo_check
  check (tipo in ('nueva', 'cancelada', 'rechazo', 'tomada', 'cambio_hora', 'acepto', 'postulante', 'sin_tomar', 'auto_asignada', 'negativo', 'resumen'));

create or replace function prospectos_tocar() returns trigger language plpgsql set search_path = public as $$
begin new.actualizado_en := now(); return new; end $$;

create or replace function resumen_semana(p_empresa uuid, p_desde date)
returns jsonb language sql stable security definer set search_path = public as $$
  with r as (
    select r.*, c.total from reservas r left join v_cobro c on c.id = r.id
    where r.empresa_id = p_empresa and r.eliminada_en is null
      and (r.fecha_hora at time zone 'America/Santiago')::date between p_desde and p_desde + 6
  ), ant as (
    select coalesce(sum(c.total), 0) total, count(*) n from reservas r join v_cobro c on c.id = r.id
    where r.empresa_id = p_empresa and r.eliminada_en is null and r.estado = 'finalizada'
      and (r.fecha_hora at time zone 'America/Santiago')::date between p_desde - 7 and p_desde - 1
  )
  select jsonb_build_object(
    'desde', p_desde, 'hasta', p_desde + 6,
    'finalizados', (select count(*) from r where estado = 'finalizada'),
    'ingresos', (select coalesce(sum(total), 0) from r where estado = 'finalizada'),
    'ingresos_ant', (select total from ant), 'finalizados_ant', (select n from ant),
    'negativos', (select count(*) from r where no_presentado),
    'cancelados', (select count(*) from r where estado = 'cancelada'),
    'convenio', (select count(*) from r where estado = 'finalizada' and cuenta_corporativa_id is not null),
    'por_cobrar', (select coalesce(sum(total), 0) from r where estado = 'finalizada' and not pagado),
    'origen', (select coalesce(jsonb_object_agg(coalesce(como_nos_conocio, 'sin_dato'), n), '{}'::jsonb) from (select como_nos_conocio, count(*) n from r where estado <> 'cancelada' group by 1) x),
    'prospectos_nuevos', (select count(*) from prospectos where empresa_id = p_empresa and (creado_en at time zone 'America/Santiago')::date between p_desde and p_desde + 6),
    'convenios_nuevos', (select count(*) from prospectos where empresa_id = p_empresa and estado = 'convenio' and (actualizado_en at time zone 'America/Santiago')::date between p_desde and p_desde + 6))
$$;
revoke execute on function resumen_semana(uuid, date) from public, anon, authenticated;

-- Para la tarjeta de Reportes (solo admin)
create or replace function mi_resumen_semana(p_desde date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if mi_rol() is distinct from 'admin' then raise exception 'Solo el administrador'; end if;
  return resumen_semana(mi_empresa(), p_desde);
end $$;
revoke execute on function mi_resumen_semana(date) from public, anon;
grant execute on function mi_resumen_semana(date) to authenticated;

-- Aviso de cada lunes (semana anterior, de lunes a domingo)
create or replace function enviar_resumen_semanal()
returns integer language plpgsql security definer set search_path = public as $$
declare e record; j jsonb; v_lunes date := date_trunc('week', (now() at time zone 'America/Santiago'))::date - 7; n int := 0; v_dif text;
begin
  for e in select id from empresas loop
    j := resumen_semana(e.id, v_lunes);
    if (j->>'finalizados')::int = 0 and (j->>'cancelados')::int = 0 and (j->>'prospectos_nuevos')::int = 0 then continue; end if;
    v_dif := case when (j->>'ingresos_ant')::int > 0 then ' (' || case when (j->>'ingresos')::int >= (j->>'ingresos_ant')::int then '+' else '' end
                  || round(((j->>'ingresos')::numeric / (j->>'ingresos_ant')::numeric - 1) * 100) || ' % vs. semana anterior)' else '' end;
    insert into avisos_equipo (empresa_id, tipo, titulo, texto)
    values (e.id, 'resumen', '📊 Resumen de la semana ' || to_char(v_lunes, 'DD/MM') || '–' || to_char(v_lunes + 6, 'DD/MM'),
      (j->>'finalizados') || ' servicios · ' || negativo_texto((j->>'ingresos')::int) || v_dif
      || ' · ' || (j->>'convenio') || ' de empresas · ' || (j->>'negativos') || ' no presentados · ' || (j->>'cancelados') || ' cancelados'
      || ' · por cobrar ' || negativo_texto((j->>'por_cobrar')::int)
      || ' · ventas: ' || (j->>'prospectos_nuevos') || ' empresas nuevas contactadas (meta 10)'
      || case when (j->>'convenios_nuevos')::int > 0 then ', ' || (j->>'convenios_nuevos') || ' convenio(s) nuevo(s)' else '' end
      || '. Detalle en Reportes.');
    n := n + 1;
  end loop;
  return n;
end $$;
revoke execute on function enviar_resumen_semanal() from public, anon, authenticated;

select cron.schedule('flotak-resumen-semanal', '7 12 * * 1', 'select public.enviar_resumen_semanal()');
