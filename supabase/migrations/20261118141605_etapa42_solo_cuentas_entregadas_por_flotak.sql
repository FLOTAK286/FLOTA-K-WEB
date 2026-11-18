-- Etapa 42: para asegurar el pago, por ahora solo reservan los clientes a quienes Flota-K les entregó la cuenta
-- (pestaña "Cuentas de clientes": particulares o personas de empresas con convenio).
-- 1) Se cierra el registro libre de la app del pasajero (/app): la Edge Function registro-pasajero ya no crea cuentas.
create or replace function public.registro_permitido(p_ip text, p_correo text)
returns boolean language plpgsql security definer set search_path to 'public' as $$
begin
  return false; -- registro libre pausado: las cuentas las crea Flota-K
end $$;

-- 2) Una reserva desde la app (canal 'app') solo se acepta si la persona tiene acceso activo entregado por Flota-K.
create or replace function public.reserva_app_autorizada()
returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
  if new.canal = 'app' and not es_staff()
     and not exists (select 1 from convenio_usuarios where user_id = auth.uid() and activo) then
    raise exception 'Su cuenta aún no está habilitada para reservar. Escríbanos por WhatsApp al +56 9 2227 5399 y la activamos.';
  end if;
  return new;
end $$;
revoke execute on function public.reserva_app_autorizada() from public, anon, authenticated;
create trigger reservas_app_autorizada before insert on reservas
  for each row execute function reserva_app_autorizada();
