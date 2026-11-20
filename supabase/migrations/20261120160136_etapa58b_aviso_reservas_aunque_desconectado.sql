-- Etapa 58b: el aviso de "Nueva reserva disponible" llega aunque el conductor esté desconectado (pedido del dueño).
do $$
declare f text;
begin
  f := pg_get_functiondef('conductor_latido(text, double precision, double precision, integer, integer, integer)'::regprocedure);
  if position('  -- Reservas publicadas que ya puede ver y que aún no se le avisaron (solo conectado)
  if coalesce(p.disponible, false) then' in f) = 0 then raise exception 'conductor_latido cambió: revisar la migración'; end if;
  execute replace(f, '  -- Reservas publicadas que ya puede ver y que aún no se le avisaron (solo conectado)
  if coalesce(p.disponible, false) then', '  -- Reservas publicadas que ya puede ver y que aún no se le avisaron (conectado o no)
  if true then');
end $$;
