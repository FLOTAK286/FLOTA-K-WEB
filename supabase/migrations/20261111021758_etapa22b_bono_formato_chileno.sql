-- Etapa 22b: el bono se anota en el historial con punto de miles ($5.000).
create or replace function liberar_a_bolsa_bono(p_reserva uuid, p_bono int)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform liberar_a_bolsa(p_reserva, true);
  update reservas set bono_bolsa = nullif(greatest(coalesce(p_bono, 0), 0), 0) where id = p_reserva and empresa_id = mi_empresa();
  if coalesce(p_bono, 0) > 0 then
    update reserva_eventos set nota = nota || ' · bono $' || replace(to_char(p_bono, 'FM999,999,999'), ',', '.') where id = (select max(id) from reserva_eventos where reserva_id = p_reserva);
  end if;
end $$;
