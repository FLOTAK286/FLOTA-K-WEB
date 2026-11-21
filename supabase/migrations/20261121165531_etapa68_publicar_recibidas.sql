-- Etapa 68: se puede publicar en Reservas una reserva "recibida" (por confirmar); al publicarla queda confirmada.
do $$
declare f text;
begin
  f := pg_get_functiondef('liberar_a_bolsa(uuid, boolean)'::regprocedure);
  if position('if r.estado not in (''confirmada'', ''asignada'') then raise exception ''Solo se pueden liberar reservas confirmadas que aún no empiezan''; end if;' in f) = 0
     or position('update reserva_eventos set nota = ''Liberada a Reservas'' where id' in f) = 0 then
    raise exception 'liberar_a_bolsa cambió: revisar la migración';
  end if;
  f := replace(f, 'if r.estado not in (''confirmada'', ''asignada'') then raise exception ''Solo se pueden liberar reservas confirmadas que aún no empiezan''; end if;',
                  'if r.estado not in (''recibida'', ''confirmada'', ''asignada'') then raise exception ''Solo se pueden liberar reservas que aún no empiezan''; end if;');
  f := replace(f, 'update reserva_eventos set nota = ''Liberada a Reservas'' where id',
                  'update reserva_eventos set nota = case when r.estado = ''recibida'' then ''Confirmada y liberada a Reservas'' else ''Liberada a Reservas'' end where id');
  execute f;
end $$;
