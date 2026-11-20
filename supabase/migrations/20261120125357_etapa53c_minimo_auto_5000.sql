-- Etapa 53c: tarifa mínima del auto en el cotizador punto a punto: $5.000 (pedido del dueño). Web (cotizador_publico) y app del pasajero (pasajero_inicio).
do $$
declare f text;
begin
  foreach f in array array['cotizador_publico(text)', 'pasajero_inicio()'] loop
    execute replace(pg_get_functiondef(f::regprocedure), '''minimo'', 12000', '''minimo'', 5000');
  end loop;
end $$;
