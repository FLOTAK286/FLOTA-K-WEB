-- Etapa 63a: rol "facturacion" (solo ve la pestaña Facturación del panel).
alter type rol_usuario add value if not exists 'facturacion';
