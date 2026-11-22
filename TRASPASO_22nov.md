# Traspaso de sesión · 22 nov 2026 (Flota-K)

Para otro chat de Claude Code. Repo `flota-k-web` (GitHub `FLOTAK286/FLOTA-K-WEB`), rama de trabajo `reserva-por-enlace`. Supabase `iejhmplstveockkjjbks`. El dueño (Juan) no es programador: explicarle en español simple. Reglas del proyecto en `CLAUDE.md`; detalle de cada cambio en `CAMBIOS.md`.

## Estado de publicación
- `main` (sitio publicado): commit `457fe7f`, que incluye la página /reservar nueva (publicada con aprobación de Juan).
- Rama `reserva-por-enlace`: va 1 commit adelante (`0341765`): CAMBIOS.md, migración etapa 72 y el archivo de `importar-osm` desactivada. No toca páginas públicas. Para publicarlo en `main` hay que pedirle aprobación a Juan.
- Edge Function `flow` en producción: **v13**. `importar-osm`: v7 (desactivada). `sector-prueba`: v4 (desactivada; Juan puede borrarla en el panel).
- Migraciones aplicadas hoy: etapa70 (pago Flow), etapa71a (`osm_datos`), etapa71b (`pg_net`) y etapa72 (ajustes de la revisión).

## Lo que se hizo y SÍ funciona
1. **Pago antes de reservar (Flow), página `/reservar/`:**
   - La reserva solo se crea después de que Flow confirma el pago (`solicitudes_pago` → `crear_reservas_pagadas`).
   - Claves de producción ya cargadas como secretos (`FLOW_API_KEY`, `FLOW_SECRET_KEY`).
   - Probado con un pago real de $1.000 (reserva FK-1AC585, cancelada; Juan debe devolver el dinero en Flow, orden N° 189598213).
2. **Precio calculado en el servidor:** acción `cotizar` de `flow`. Si el monto que vio el pasajero no coincide con el del servidor, responde 409 y la página muestra el valor correcto.
3. **Tarifa al aeropuerto según el punto del mapa (el pasajero no elige):**
   - Las reglas están en `supabase/functions/flow/sector.ts`. Los datos de mapa están en la tabla `osm_datos`:
     - `comunas_compactas`: 56 comunas, unos 2 MB. **No cargar `comunas_rm`** (8 MB): provocó timeouts.
     - `divisiones`: 958 tramos de calles límite.
     - `localidades` y `localidades_sur`.
   - Todas las comunas de la RM, más Valparaíso, Viña, Rancagua y Los Andes.
   - Los sectores con varias tarifas se deciden por calles límite. Límites aprobados por Juan para Pirque, Lo Barnechea y Chicureo (ver CAMBIOS.md).
   - Farellones, la cordillera, el interior del Cajón del Maipo y las comunas fuera del tarifario: no se cobran en línea, se derivan a WhatsApp.
4. **Con más de 4 pasajeros se cobra van**, aunque se elija auto.
5. Si el texto de la dirección dice otra comuna que la del punto del mapa, la reserva queda con la nota "REVISAR: …" para Operaciones.
6. **TAG en punto a punto, SOLO en `/reservar/` (cobro en línea):**
   - La ruta sale de OSRM. Se cuentan los pórticos de OpenStreetMap (`osm_datos.porticos`: 157 pórticos + 13 casetas) que quedan a menos de 25 m de la ruta y en el mismo sentido.
   - Se cobran **$900 por pórtico** (`empresas.valor_tag`, criterio Servimóvil).
   - Las casetas de peaje troncal (por ejemplo, Lo Prado) se anotan pero **no se cobran**: está pendiente preguntarle a Juan.

## TAG: lo que NO está resuelto (por eso el otro chat dice que falta)
- **Panel /equipo y app del conductor:** el TAG se ingresa a mano ("Agregar gasto → TAG", cantidad × `valor_tag`). No hay conteo automático de pórticos al cerrar un servicio con taxímetro. Era una tarea ofrecida y no se hizo: prellenar los pórticos en el cierre del conductor a partir de la ruta real o del origen y destino.
- **App del pasajero `/app/` y portal `/empresa/`:** su cotizador punto a punto no suma TAG; solo lo hace `/reservar/`.
- La lógica de conteo está solo en la Edge Function `flow` (`porticos()` y `porticosEnRuta()` en `index.ts`). Para usarla en otras partes conviene exponer una acción, por ejemplo `flow?accion=cotizar` (ya existe y es pública), o moverla a una función compartida.

## Pendientes
- **Papelera:** la tarea `flotak-purgar-eliminadas` falla cada hora (FK desde `avisos_equipo` y otros).
  - La función `purgar_reservas_eliminadas` debe borrar antes `avisos_equipo`, `avisos_conductor`, `bolsa_avisos` y `reserva_paradas_espera`.
  - Hay 4 reservas en la papelera. Corregirla las borra definitivamente: **pedir aprobación a Juan ("vacía la papelera")**.
- **Zona "Camino Lonquén (Veterquímica)":** no se asigna sola; cae en la tarifa de Maipú.
- **Casetas de peaje troncal:** preguntarle a Juan si se cobran.
- **Juan:** actualizar las instrucciones del agente de WhatsApp (que mande el enlace `/reservar/` en vez de crear eventos en Google Calendar) y activar "Leaked password protection" en Supabase → Authentication.

## Notas técnicas útiles
- Desde el entorno de Claude no se puede llamar a Supabase por HTTP (el proxy lo bloquea). Para probar las funciones se usa `pg_net` desde SQL:
  - Envío: `net.http_post(...)`.
  - Respuesta: se lee después en `net._http_response`.
- Overpass (para reimportar datos de mapa) se llama con `net.http_get` y solo con consultas espaciales; las búsquedas por nombre se quedan sin respuesta.
- El clasificador de seguridad exige una aprobación explícita de Juan para publicar en `main`, borrar datos o aplicar migraciones delicadas.
