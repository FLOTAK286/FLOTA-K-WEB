-- Etapa 47b: para no contar dos veces, la empresa elige la fuente oficial de cada dato en Reportes:
-- gastos (combustible, peajes, otros): "manual" (lo que registra el admin) o "cierres" (cierre diario del conductor);
-- ingresos de Cabify y otras apps: "cierres" o "manual" (Otros ingresos). Lo que no es oficial se muestra solo como referencia.
alter table empresas add column if not exists reportes_config jsonb not null default '{"gastos": "manual", "ingresos_apps": "cierres"}'::jsonb;
