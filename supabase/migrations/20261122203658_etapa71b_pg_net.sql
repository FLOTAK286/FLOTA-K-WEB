-- Etapa 71b: extensión pg_net (llamadas HTTP desde la base), para importar datos de OpenStreetMap sin abrir enlaces a mano.
create extension if not exists pg_net with schema extensions;
