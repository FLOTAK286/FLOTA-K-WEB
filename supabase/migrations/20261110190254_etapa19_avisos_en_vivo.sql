-- Etapa 19: avisos en vivo (Supabase Realtime) para reservas y mensajes.
-- Cada pantalla recibe solo los cambios que su seguridad (RLS) ya le permite ver.
-- Las ubicaciones GPS NO se publican aquí (serían millones de avisos al mes); siguen consultándose cada 15 s.
alter publication supabase_realtime add table reservas, mensajes, soporte_mensajes;
