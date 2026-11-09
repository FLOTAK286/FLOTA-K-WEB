-- Etapa 13 (parte 1): nuevo rol "propietario" (dueño de vehículo o gestor de flota).
alter type rol_usuario add value if not exists 'propietario';
