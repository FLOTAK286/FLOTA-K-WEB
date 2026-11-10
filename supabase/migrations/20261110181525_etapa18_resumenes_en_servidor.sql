-- Etapa 18: totales calculados en la base de datos (no se traen miles de filas al navegador).
-- Usan la seguridad de quien consulta (security invoker): cada uno ve solo lo que ya podía ver.

-- Cobros por cliente y por empresa con convenio: servicios no cancelados, total, pagado y pendiente.
create or replace function resumen_cobros()
returns table (o_tipo text, o_id uuid, o_servicios int, o_total bigint, o_pagado bigint, o_pendiente bigint)
language sql stable security invoker set search_path = public as $$
  select 'cliente', cliente_id, count(*)::int, coalesce(sum(total), 0), coalesce(sum(total) filter (where pagado), 0), coalesce(sum(total) filter (where not pagado), 0)
  from v_cobro where estado <> 'cancelada' and cliente_id is not null group by cliente_id
  union all
  select 'cuenta', cuenta_corporativa_id, count(*)::int, coalesce(sum(total), 0), coalesce(sum(total) filter (where pagado), 0), coalesce(sum(total) filter (where not pagado), 0)
  from v_cobro where estado <> 'cancelada' and cuenta_corporativa_id is not null group by cuenta_corporativa_id
$$;

-- Calificaciones que los conductores dan a cada cliente (promedio).
create or replace function resumen_calif_clientes()
returns table (o_cliente uuid, o_n int, o_suma int)
language sql stable security invoker set search_path = public as $$
  select cliente_id, count(*)::int, sum(estrellas)::int from calificaciones where autor = 'conductor' and cliente_id is not null group by cliente_id
$$;

-- Total por cobrar de servicios ya realizados (para el resumen del despacho).
create or replace function total_por_cobrar()
returns bigint language sql stable security invoker set search_path = public as $$
  select coalesce(sum(total), 0) from v_cobro where estado = 'finalizada' and not pagado
$$;

revoke execute on function resumen_cobros() from public, anon;
revoke execute on function resumen_calif_clientes() from public, anon;
revoke execute on function total_por_cobrar() from public, anon;
grant execute on function resumen_cobros() to authenticated;
grant execute on function resumen_calif_clientes() to authenticated;
grant execute on function total_por_cobrar() to authenticated;

-- Índices para que las búsquedas sigan rápidas con muchos datos
create index if not exists reservas_cliente_estado on reservas (cliente_id) where estado <> 'cancelada';
create index if not exists reservas_conductor_fecha on reservas (conductor_id, fecha_hora);
create index if not exists reserva_eventos_fecha on reserva_eventos (creado_en);
create index if not exists calificaciones_conductor on calificaciones (conductor_id, creado_en);
create index if not exists calificaciones_cliente on calificaciones (cliente_id);
create index if not exists mensajes_creado on mensajes (creado_en);
create index if not exists soporte_conductor on soporte_mensajes (conductor_id, id);
create index if not exists cierres_conductor_fecha on cierres_diarios (conductor_id, fecha);
