-- Etapa 27b: la reserva en línea del pasajero queda pausada (las reservas las crea el equipo).
-- La función se mantiene; solo se quita el permiso de usarla desde la app. Para activarla: volver a dar el grant.
revoke execute on function crear_reserva_app(text, text, text, timestamptz, text, text, double precision, double precision, double precision, double precision, text, int, int, text, text, text, int, text, text) from anon, authenticated, public;
