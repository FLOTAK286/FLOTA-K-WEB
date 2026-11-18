-- Etapa 43a: nuevo tipo de aviso para Operaciones: el cliente cambió la hora de su reserva.
alter table avisos_equipo drop constraint if exists avisos_equipo_tipo_check;
alter table avisos_equipo add constraint avisos_equipo_tipo_check
  check (tipo in ('nueva', 'cancelada', 'rechazo', 'tomada', 'cambio_hora'));
