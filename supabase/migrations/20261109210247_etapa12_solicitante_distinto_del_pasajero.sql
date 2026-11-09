-- Etapa 12: quien pide y paga (solicitante) puede ser distinto de quien viaja (pasajero), también para particulares.
-- nombre_pasajero / telefono / correo siguen siendo del pasajero (el conductor y el seguimiento son para él).
-- El cliente (cliente_id, cobranza) se toma del solicitante si existe.

alter table reservas add column if not exists solicitante_nombre text check (length(solicitante_nombre) <= 200);
alter table reservas add column if not exists solicitante_telefono text check (length(solicitante_telefono) <= 30);
alter table reservas add column if not exists solicitante_correo text check (length(solicitante_correo) <= 200);

create or replace function asegurar_cliente() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_nom text := coalesce(nullif(trim(new.solicitante_nombre), ''), new.nombre_pasajero);
  v_tel text := right(regexp_replace(coalesce(nullif(new.solicitante_telefono, ''), new.telefono, ''), '\D', '', 'g'), 8);
  v_correo text := lower(trim(coalesce(nullif(new.solicitante_correo, ''), new.correo, '')));
  v_tel_full text := coalesce(nullif(new.solicitante_telefono, ''), new.telefono);
begin
  if new.cliente_id is not null then return new; end if;
  select id into new.cliente_id from clientes c
   where c.empresa_id = new.empresa_id
     and ((v_correo <> '' and lower(c.correo) = v_correo)
       or (length(v_tel) = 8 and right(regexp_replace(coalesce(c.telefono, ''), '\D', '', 'g'), 8) = v_tel))
   order by c.creado_en limit 1;
  if new.cliente_id is null then
    insert into clientes (empresa_id, nombre, telefono, correo)
    values (new.empresa_id, v_nom, v_tel_full, nullif(v_correo, ''))
    returning id into new.cliente_id;
  end if;
  return new;
end $$;
