-- Etapa 71a: datos geográficos de OpenStreetMap (pórticos TAG, calles que dividen sectores de tarifa y localidades).
-- Se importan con la Edge Function "importar-osm" (solo servidor). RLS sin políticas: no se leen desde la web.
create table if not exists public.osm_datos (
  clave text primary key,
  datos jsonb not null,
  importado_en timestamptz not null default now()
);
alter table public.osm_datos enable row level security;
