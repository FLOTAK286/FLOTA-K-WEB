-- Etapa 41b: las reservas de clientes particulares del portal (canal 'portal') nunca se cargan a un convenio,
-- aunque la ficha del cliente tenga uno de antes (igual que las de la app, canal 'app').
create or replace function asignar_cuenta_corporativa()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.canal in ('app', 'portal') then return new; end if;
  if new.cuenta_corporativa_id is null and new.cliente_id is not null and not es_staff() then
    select cuenta_corporativa_id into new.cuenta_corporativa_id from clientes where id = new.cliente_id;
  end if;
  return new;
end $$;
