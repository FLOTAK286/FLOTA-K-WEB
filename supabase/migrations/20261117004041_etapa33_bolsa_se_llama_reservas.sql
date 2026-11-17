-- Etapa 33: en pantalla la "bolsa de servicios" pasa a llamarse "Reservas" (solo textos; los nombres internos no cambian)
do $$
declare f record; d text;
begin
  for f in select oid from pg_proc where pronamespace = 'public'::regnamespace
            and proname in ('liberar_a_bolsa', 'bolsa_automatica', 'conductor_devolver_reserva', 'conductor_tomar_reserva') loop
    d := pg_get_functiondef(f.oid);
    d := replace(d, 'a la bolsa de servicios', 'a Reservas');
    d := replace(d, 'automáticamente a la bolsa', 'automáticamente a Reservas');
    d := replace(d, 'Devolví a la bolsa', 'Devolví a Reservas');
    d := replace(d, 'Tomado desde la bolsa', 'Tomado desde Reservas');
    d := replace(d, 'de la bolsa', 'de Reservas');
    execute d;
  end loop;
end $$;
