-- Etapa 50b: en pantalla la casilla "Decreto 80" se llama "Corporativo" (vehículo con autorización ministerial). Solo cambia el texto del mensaje.
do $$
begin
  execute replace(pg_get_functiondef('conductor_tomar_reserva'::regproc),
    'exige un vehículo con Decreto 80 vigente', 'exige un vehículo corporativo (con autorización ministerial vigente)');
end $$;
