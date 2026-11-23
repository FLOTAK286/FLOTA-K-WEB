-- Etapa 72: ajustes de la revisión general (22 nov 2026)
-- 1) Funciones con search_path fijo (alerta de seguridad de Supabase)
alter function public.negativo_texto(integer) set search_path = public;
alter function public.distancia_km(double precision, double precision, double precision, double precision) set search_path = public;
-- 2) Índice duplicado en reservas (idéntico a reservas_conductor_fecha)
drop index if exists public.reservas_conductor;
-- 3) Índices para que avisos y papelera no recorran tablas completas
create index if not exists avisos_equipo_reserva on public.avisos_equipo (reserva_id);
create index if not exists avisos_conductor_reserva on public.avisos_conductor (reserva_id);
create index if not exists bolsa_avisos_reserva on public.bolsa_avisos (reserva_id);
