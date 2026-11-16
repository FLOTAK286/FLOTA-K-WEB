-- Etapa 29: las reservas eliminadas quedan 24 horas en la papelera y después se borran solas.
create or replace function public.purgar_reservas_eliminadas()
returns integer
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_ids uuid[];
begin
  select coalesce(array_agg(id), '{}') into v_ids
  from reservas
  where eliminada_en is not null and eliminada_en < now() - interval '24 hours';
  if cardinality(v_ids) = 0 then return 0; end if;
  -- Datos ligados a la reserva que no se borran solos
  delete from ubicaciones     where reserva_id = any(v_ids);
  delete from calificaciones  where reserva_id = any(v_ids);
  delete from mensajes        where reserva_id = any(v_ids);
  delete from reserva_cambios where reserva_id = any(v_ids);
  -- reserva_eventos y reserva_gastos se borran junto con la reserva
  delete from reservas where id = any(v_ids);
  return cardinality(v_ids);
end $$;

-- Solo la tarea programada la ejecuta; nadie puede llamarla desde la web
revoke all on function public.purgar_reservas_eliminadas() from public, anon, authenticated;

-- Revisa cada hora
select cron.unschedule('flotak-purgar-eliminadas') where exists (select 1 from cron.job where jobname = 'flotak-purgar-eliminadas');
select cron.schedule('flotak-purgar-eliminadas', '17 * * * *', 'select public.purgar_reservas_eliminadas()');
