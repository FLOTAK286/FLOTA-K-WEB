-- Etapa 16: etiquetas de cliente (VIP, empresa, paga tarde, etc.), visibles para el equipo al tomar sus reservas.
alter table clientes add column if not exists etiquetas text[] not null default '{}'
  check (cardinality(etiquetas) <= 12);
