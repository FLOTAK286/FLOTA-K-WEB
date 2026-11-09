-- Etapa 7: cuentas de empresa. Cada reserva guarda a qué empresa se le cobra (se toma del pasajero al crearla) y su centro de costo.
alter table cuentas_corporativas add column if not exists dias_pago int not null default 30 check (dias_pago between 0 and 120);
alter table cuentas_corporativas add column if not exists activa boolean not null default true;
alter table reservas add column if not exists cuenta_corporativa_id uuid references cuentas_corporativas(id);
alter table reservas add column if not exists centro_costo text check (length(centro_costo) <= 100);
create index if not exists reservas_cuenta on reservas (cuenta_corporativa_id);

create or replace function asignar_cuenta_corporativa() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.cuenta_corporativa_id is null and new.cliente_id is not null then
    select cuenta_corporativa_id into new.cuenta_corporativa_id from clientes where id = new.cliente_id;
  end if;
  return new;
end $$;
-- Corre después de reservas_asegurar_cliente (orden alfabético), cuando ya existe cliente_id.
create trigger reservas_cuenta_corporativa before insert on reservas
  for each row execute function asignar_cuenta_corporativa();
revoke execute on function asignar_cuenta_corporativa() from public, anon, authenticated;

create or replace view v_cobro with (security_invoker = true) as
select r.id, r.empresa_id, r.cliente_id, r.codigo, r.fecha_hora, r.estado, r.nombre_pasajero, r.origen, r.destino,
       r.tipo_cobro, r.taxi_metros, r.taxi_segundos,
       case when r.tipo_cobro = 'taximetro' then r.taxi_total else coalesce(r.precio, r.tarifa_web) end as valor_base,
       coalesce((select sum(g.monto) from reserva_gastos g where g.reserva_id = r.id), 0)::int as gastos,
       (coalesce(case when r.tipo_cobro = 'taximetro' then r.taxi_total else coalesce(r.precio, r.tarifa_web) end, 0)
        + coalesce((select sum(g.monto) from reserva_gastos g where g.reserva_id = r.id), 0))::int as total,
       r.forma_pago, r.pagado, r.pagado_en, r.pagado_medio, r.observacion_conductor, r.observacion_revisada,
       r.token_seguimiento, r.conductor_id, r.vuelo,
       r.cuenta_corporativa_id, r.centro_costo
from reservas r;
