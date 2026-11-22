-- Etapa 69: editar datos de una reserva desde la ficha. El historial de cambios registra también pasajero, contacto,
-- tipo de servicio, indicaciones, maletas y comentarios.
create or replace function public.registrar_cambios_reserva()
returns trigger language plpgsql security definer set search_path to 'public' as $function$
declare c text; a text; d text;
begin
  foreach c in array array['fecha_hora','origen','destino','precio','forma_pago','tipo_cobro','conductor_id','vehiculo_id','derivado_a','pagado','vehiculo','pasajeros','vuelo','centro_costo',
                           'nombre_pasajero','telefono','correo','tipo_servicio','retiro_detalle','maletas','comentarios'] loop
    execute format('select ($1).%I::text, ($2).%I::text', c, c) into a, d using old, new;
    if a is distinct from d then
      insert into reserva_cambios (reserva_id, campo, antes, despues, usuario_id) values (new.id, c, a, d, auth.uid());
    end if;
  end loop;
  return new;
end $function$;
