-- Etapa 20: punto exacto (pin) de origen y destino de cada reserva, para navegar con Waze o Google Maps.
alter table reservas add column if not exists origen_lat double precision check (origen_lat between -90 and 90);
alter table reservas add column if not exists origen_lng double precision check (origen_lng between -180 and 180);
alter table reservas add column if not exists destino_lat double precision check (destino_lat between -90 and 90);
alter table reservas add column if not exists destino_lng double precision check (destino_lng between -180 and 180);
