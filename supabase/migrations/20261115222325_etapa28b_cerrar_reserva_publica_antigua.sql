-- Etapa 28b: la reserva pública antigua (crear_reserva_publica) ya no la usa ninguna página y la reserva al público está pausada.
-- Se quita el permiso de usarla sin iniciar sesión o con cualquier cuenta. crear_reserva_app la sigue usando por dentro.
revoke execute on function crear_reserva_publica(text, text, text, text, timestamptz, text, text, text, int, text, int, text, text, text, int) from public, anon, authenticated;
