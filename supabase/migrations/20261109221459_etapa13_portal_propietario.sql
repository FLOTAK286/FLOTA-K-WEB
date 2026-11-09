-- Etapa 13 (parte 2): portal del propietario. Cada vehículo puede tener un propietario (usuario) y una comisión de Flota-K.
-- El propietario solo ve sus vehículos y los servicios hechos con ellos, sin datos personales de pasajeros.

alter table vehiculos add column if not exists propietario_id uuid references auth.users(id);
alter table vehiculos add column if not exists comision_pct numeric(5,2) check (comision_pct between 0 and 100);
create index if not exists vehiculos_propietario on vehiculos (propietario_id);

-- Sus vehículos, con conductor fijo y estado de documentos
create or replace function propietario_vehiculos()
returns table (o_id uuid, o_patente text, o_marca text, o_modelo text, o_anio int, o_color text, o_categoria text, o_activo boolean,
               o_conductor text, o_movil text, o_comision numeric, o_docs_vencidos int, o_docs_por_vencer int, o_foto text)
language sql stable security definer set search_path = public as $$
  select v.id, v.patente, v.marca, v.modelo, v.anio, v.color, v.categoria, v.activo, p.nombre, p.movil, v.comision_pct,
         (select count(*)::int from documentos d where d.vehiculo_id = v.id and d.vence < current_date),
         (select count(*)::int from documentos d where d.vehiculo_id = v.id and d.vence between current_date and current_date + 30),
         v.foto_path
  from vehiculos v left join perfiles p on p.id = v.conductor_habitual
  where v.propietario_id = auth.uid()
  order by v.patente
$$;

-- Servicios hechos con sus vehículos (solo la comuna del origen y destino; sin nombre ni teléfono del pasajero)
create or replace function propietario_servicios(p_desde timestamptz, p_hasta timestamptz)
returns table (o_codigo text, o_fecha_hora timestamptz, o_estado estado_reserva, o_vehiculo_id uuid, o_patente text,
               o_conductor text, o_movil text, o_origen text, o_destino text, o_tipo_servicio text, o_tipo_cobro text,
               o_km numeric, o_total int, o_gastos int, o_pagado boolean, o_comision numeric)
language sql stable security definer set search_path = public as $$
  select r.codigo, r.fecha_hora, r.estado, v.id, v.patente, p.nombre, p.movil,
         case when position(',' in r.origen) > 0 then trim(split_part(r.origen, ',', -1)) else r.origen end,
         case when position(',' in r.destino) > 0 then trim(split_part(r.destino, ',', -1)) else r.destino end,
         r.tipo_servicio::text, r.tipo_cobro, round(r.taxi_metros / 1000.0, 1),
         c.total, c.gastos, r.pagado, v.comision_pct
  from reservas r
  join vehiculos v on v.id = r.vehiculo_id
  join v_cobro c on c.id = r.id
  left join perfiles p on p.id = r.conductor_id
  where v.propietario_id = auth.uid()
    and r.estado <> 'cancelada'
    and r.fecha_hora >= p_desde and r.fecha_hora < p_hasta
  order by r.fecha_hora
$$;

revoke execute on function propietario_vehiculos() from public, anon;
grant execute on function propietario_vehiculos() to authenticated;
revoke execute on function propietario_servicios(timestamptz, timestamptz) from public, anon;
grant execute on function propietario_servicios(timestamptz, timestamptz) to authenticated;
