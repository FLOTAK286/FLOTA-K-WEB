# Cambios

## 23 nov 2026 · Vespucio Oriente: 2 pórticos fijos
- Regla del dueño: si la ruta pasa por **Autopista Vespucio Oriente (AVO)** se cobran **2 pórticos fijos** (entrada y salida, $900 c/u), en vez de los pórticos del mapa (AVO cobra por km y en OpenStreetMap tiene uno solo).
- Datos: `osm_datos` clave `avo` (507 nodos de 63 tramos de calzada de AVO, OpenStreetMap, 23 nov). Función `flow` v18: si la ruta (nodos de OSRM) recorre AVO, quita el pórtico de AVO y agrega "Vespucio Oriente · entrada" y "· salida" (también en `accion=porticos`, cierre del conductor y panel). Ej.: La Reina → Huechuraba: P101 + entrada + salida = 3 pórticos ($2.700).

## 22 nov 2026 · Ruta con pórticos, opción sin autopista y TAG automático al cerrar
- **Tiempo extra sin autopista** (función `flow` v17, aprobado por el dueño 23 nov): la diferencia de minutos respecto de la ruta con autopista se cobra como la espera ($180/min auto, $270/min van). "Sin autopista" solo se ofrece si tiene menos pórticos **y** sale más barata. Ej.: Vitacura → Maipú $31.100 con autopista / $30.500 sin (incluye 34 min extra = $6.120); La Florida → Santiago Centro $18.700 / $16.000; Las Condes → Quilicura no ofrece "sin autopista".
- Publicado en `main` el 23 nov 2026 con aprobación del dueño.
- Función `flow` v16 (publicada): `cotizar` punto a punto entrega dos opciones en `alternativas`: **con autopista** (OSRM, la más rápida; pórticos exactos por nodos) y **sin autopista** (Valhalla de OpenStreetMap con `use_tolls: 0, use_highways: 0`; pórticos por cercanía < 8 m y mismo sentido). Cada opción trae valor, km, minutos, pórticos (nombres y posición) y la ruta para el mapa. "Sin autopista" solo se ofrece si tiene menos pórticos. Con `sin_autopista: true` se cobra esa opción; la reserva pagada queda con "RUTA SIN AUTOPISTAS…" y la lista de pórticos.
- Acción nueva `flow?accion=porticos` ({ puntos: [origen, paradas…, destino] }) → pórticos de la ruta, para el cierre con taxímetro.
- El sentido de cada pórtico se toma del tramo de calzada que pasa por él (las vías guardadas traen geometría, no lista de nodos).
- `assets/cotizar.js`: `FKCotizar.vista()` dibuja el mapa (Leaflet, se carga solo si falta) con la ruta elegida, la otra punteada, los pórticos en naranjo y los botones **🛣 Con autopista / 🏙 Sin autopista** con su valor. Lo usan la portada, la app del pasajero y /reservar (que envía `sin_autopista` al pagar). `FKCotizar.porticosRuta()` para el cierre.
- App del conductor: al finalizar con taxímetro, el campo TAG viene **rellenado** con los pórticos de la ruta (origen, paradas, destino) y sus nombres; el conductor corrige si tomó otra ruta.
- Panel, ficha → cobro: botón **"🛣 Calcular TAG de la ruta"** que rellena la cantidad y el detalle del gasto TAG.
- Ejemplos reales: Vitacura → Maipú con autopista $31.100 (27,7 km, ~40 min, 4 pórticos) / sin autopista $24.000 (23,7 km, ~74 min). Las Condes → Quilicura $19.700 (3 pórticos) / $20.000. La Florida → Santiago Centro $18.700 (3 pórticos) / $13.500.

## 22 nov 2026 · TAG exacto y el mismo valor en todos los cotizadores
- **Error corregido en el cobro de TAG** (función `flow` v14, ya publicada): las calles guardadas de `porticos` no traen la lista de nodos, así que nunca se sabía el sentido de cada pórtico y se cobraba todo pórtico a menos de 25 m de la ruta, incluido el de la calzada contraria (15-20 m). Ejemplo: Vitacura → Maipú cobraba 8 pórticos ($7.200) y son 4 ($3.600). Ahora se usa el método exacto: OSRM entrega los nodos de OpenStreetMap de la ruta (`annotations=nodes`) y se cuentan los pórticos que son esos nodos (solo la calzada y el sentido recorridos). Respaldo si faltan nodos: cercanía < 8 m. Probado: Vitacura → Maipú 4, Maipú → Vitacura 6, Las Condes → Quilicura 3; sector al aeropuerto sin cambios (Apoquindo → "Las Condes hasta Manquehue").
- **Portada, app del pasajero y portal de empresas** cotizan los punto a punto con el servidor (`assets/cotizar.js`, `FKCotizar.puntoAPunto` → `flow?accion=cotizar`): mismo valor que /reservar, con "incluye N pórticos TAG ($X)". Si el servidor no responde, valor local con "más TAG según los pórticos de la ruta". En la app, la reserva lleva el comentario "Incluye TAG: N pórtico(s) = $X".
- Se descartó la rama `etapa-70` (TAG calculado en el navegador con Overpass): el otro chat ya había guardado los pórticos en la base.

## 22 nov 2026 · Tarifa al aeropuerto a prueba de "elegir la más barata"
- **El pasajero ya no elige el sector:** el valor lo decide siempre el punto marcado en el mapa, que es donde lo retira el conductor. Si mueve el punto para pagar menos, lo pasamos a buscar ahí.
- Datos nuevos en `osm_datos`: `comunas_compactas` (límites de las 52 comunas de la RM + Valparaíso, Viña, Rancagua y Los Andes, ~2 MB), `localidades_sur` (Champa, Huelquén, etc.) y 192 tramos de calles límite agregados a `divisiones` (Camino Otoñal, San Damián, Av. La Plaza, El Golf de Manquehue, P. L. Urquieta, B. Larraín Cotapos, Av. Chicureo, Lo Arcaya, Esmeralda, Virginia Subercaseaux). `comunas_rm` (versión completa, 8 MB) quedó guardada pero no se usa: era demasiado lenta.
- `sector.ts`: reglas fijas para San Carlos de Apoquindo (Otoñal/San Damián y La Plaza), Lo Barnechea (El Golf de Manquehue y Urquieta/Cotapos; El Arrayán al oriente; Farellones → WhatsApp), Chicureo (hasta Piedra Roja / Lo Arcaya), Colina (Esmeralda), Pirque (Virginia Subercaseaux), Paine (Champa, Huelquén), Buin (Linderos, Maipo), Lonquén; Ñuñoa sin opciones. Comunas de una sola tarifa: la de su comuna. Fuera de las comunas del tarifario (p. ej., San Felipe) o en la cordillera / interior del Cajón del Maipo: no se cobra en línea, se deriva a WhatsApp. Probado con 34 puntos.
- Función `flow` v13: **más de 4 pasajeros = van** (aunque se elija auto); si el texto de la dirección dice otra comuna que el punto del mapa, la reserva queda con la nota "REVISAR: …" para Operaciones; si no cargan los datos de mapa, avisa "intente de nuevo" en vez de "fuera de zona". (v11–v12 tuvieron unos minutos sin cotizar viajes al aeropuerto por la carga de datos muy pesada; corregido en v13).
- Página /reservar: el valor mostrado es el que calcula el servidor según el punto; envía el número de pasajeros; aviso de van; se retiró el recuadro "Precise su sector". **Publicada en `main` (22 nov 2026, aprobada por el dueño).**
- Límites aprobados por el dueño: Pirque (solo hasta Virginia Subercaseaux paga $48.000; más al sur, El Principal), Lo Barnechea (Quillayes y Valle La Dehesa = Pie Andino; Lomas de La Dehesa = hasta el Golf), Chicureo (Lo Arcaya, Brisas y al oriente de Piedra Roja = $40.000).
- Función de prueba `sector-prueba`: desactivada (responde 410). Se puede eliminar desde Supabase → Edge Functions.

## 22 nov 2026 · TAG automático y sector según la dirección (cobro en línea)
- Datos de OpenStreetMap en `osm_datos` (etapa 71a): `porticos` (157 pórticos TAG + 13 casetas, con sentido), `divisiones` (avenidas límite: Manquehue, Paul Harris, V. Pérez Rosales, Las Perdices, Tobalaba, Av. La Florida, Irarrázaval…), `localidades` (2.750 barrios/lugares) y `comunas` (límites oficiales de las 13 comunas con varias tarifas). Se importan con `pg_net` desde la base (etapa 71b) o con la Edge Function `importar-osm` (en segundo plano).
- Función `flow` v9:
  - **Punto a punto:** suma **$900 por pórtico** TAG que cruza la ruta (`empresas.valor_tag`, criterio Servimóvil; < 25 m y mismo sentido). Casetas de peaje troncal: se anotan, no se cobran. Acción `cotizar`: la página muestra km, minutos y TAG.
  - **Aeropuerto en comunas con varias tarifas:** el sector lo define el punto marcado (`sector.ts`, límites aprobados por el dueño), no lo que elige el pasajero. Las Condes (Manquehue / Paul Harris; al oriente de Paul Harris, una de San Carlos de Apoquindo), Vitacura (Manquehue), La Reina (V. P. Rosales / Las Perdices), Peñalolén (Tobalaba / Las Perdices), La Florida (Av. La Florida / Las Perdices), Ñuñoa (norte/sur de Irarrázaval), Maipú (Ciudad Satélite; oriente/poniente de la Plaza), Puente Alto (Las Vizcachas), San Bernardo (Nos), Lampa (Batuco, Valle Grande, Chicauma), Lo Barnechea (El Arrayán), Colina/Chicureo y Pirque (por localidad; si no se puede precisar, se acepta la elección dentro de la comuna o la más barata de la comuna). Probado con 16 puntos reales.
  - Acción `sector` (lat, lng) para revisar un punto.
- Página /reservar: elige sola el sector al marcar la dirección y lo explica ("Sector según su dirección: …"). Cuando la dirección no basta (al oriente de Paul Harris, Lo Barnechea, Chicureo, Colina, Pirque), muestra el recuadro dorado **"Precise su sector"** con las opciones de su comuna y su valor, y **no deja pagar hasta elegir** (la función `flow` v10 también lo exige: `precisar`). Bajo la dirección: aviso de dejar el pin en la entrada exacta. **Pendiente de publicar.**
- Pendiente: TAG prellenado en el cierre del conductor (servicios con taxímetro creados en el panel).

## 22 nov 2026 · Reserva por enlace con pago antes de reservar (Flow) (rama `reserva-por-enlace`, sin publicar)
- Página nueva **/reservar/** (sin cuenta, `noindex`) para el enlace que envía el agente de WhatsApp. El pasajero completa el viaje y sus datos (correo obligatorio: comprobante de Flow), ve el valor y toca **"Pagar y reservar"**. Admite `?tipo=regreso` o `?tipo=punto_a_punto`.
- **La reserva se crea solo cuando Flow confirma el pago**: antes es una "solicitud de pago" (tabla `solicitudes_pago`, no aparece en el panel). Pagada → reserva(s) **confirmada(s) y pagada(s)** (canal `whatsapp`, comentario "PAGADA EN LÍNEA con Flow (orden …)", aviso "📅 Reserva nueva"). Ida y vuelta = dos reservas con un solo pago. Sin pago: vence a los 40 min (cron `flotak-solicitudes-vencer`).
- **El precio lo calcula el servidor**: tablas `tarifas_aeropuerto` (tarifario 2026) y `tarifas_tramos` (Oriente ↔ costa); punto a punto con la ruta real (OSRM) y el taxímetro de la empresa; más de 120 km o sin ruta → WhatsApp. Si el valor de la página difiere, se muestra el del servidor antes de cobrar. Se verifica que el monto pagado sea exacto.
- Edge Function **`flow`** (verify_jwt = false): `pagar`, `confirmar` (aviso de Flow), `volver` (regreso del pasajero → /reservar/?pago=<id>), `estado`. Secretos: `FLOW_API_KEY`, `FLOW_SECRET_KEY`, `FLOW_API_URL`.
- **Prueba OK (22 nov, 16:08):** pago real de $1.000 por Webpay (N° Flow 189598213) creó FK-1AC585 confirmada y pagada con aviso a Operaciones; anulada después. Zona de prueba quitada de la tabla y de la página. Página publicada en `main` (oculta: sin enlaces en el sitio, `noindex`).
- Después de la prueba: la dirección de retiro/destino no puede ser el aeropuerto en "Al/Desde el aeropuerto" (página y función `flow` v5).
- **Instalado el 22 nov (aprobado por el dueño):** etapa 70 aplicada en Supabase (versión 20261122183848) y Edge Function `flow` publicada (verify_jwt = false). **Sin activar:** faltan los secretos de Flow, la prueba de pago, publicar /reservar en `main` y cambiar el agente de WhatsApp.

## 22 nov 2026 · Editar los datos de una reserva
- Panel, ficha de la reserva: botón **"✏ Editar datos de la reserva"** (todas menos las canceladas). Se puede cambiar pasajero, teléfono, correo, vuelo, tipo de servicio, vehículo que pide, origen y destino (con punto en el mapa), indicaciones del retiro, pasajeros, maletas, centro de costo (convenio) y comentarios. La fecha/hora y las paradas siguen con sus botones propios.
- Si cambia el recorrido se recalculan distancia y duración y se pide revisar el precio. Si se cambia el texto de una dirección sin mover el punto, pregunta si es el mismo lugar.
- Al conductor asignado le llega "✏️ Servicio modificado" si cambian origen, destino o vuelo (aviso que ya existía).
- Historial de cambios (etapa 69, ya aplicada): registra también pasajero, teléfono, correo, servicio, indicaciones, maletas y comentarios.
- Se quitó el texto "primero confirme la reserva" junto a Publicar en Reservas (desde la etapa 68 ya no hace falta).

## 21 nov 2026 · Publicar en Reservas servicios por confirmar
- Panel: el botón **"📢 Publicar en Reservas"** (ficha, acciones y selección en grupo) aparece también en las reservas **"Recibida"** (por confirmar). Al publicarlas quedan **confirmadas** solas; el historial dice "Confirmada y liberada a Reservas". Caso que lo motivó: vans FK-825588 y FK-139ABD que no se podían publicar.
- Base de datos (etapa 68, ya aplicada): `liberar_a_bolsa` acepta el estado `recibida`.
- Ojo: hoy ningún conductor de la plataforma tiene van; una van publicada la ven todos pero nadie puede tomarla (conviene derivarla a Servimóvil).

## 21 nov 2026 · Facturación, carga masiva, repeticiones, ventas y resumen semanal
- **Facturación mensual** (etapa 63): pestaña **Facturación** en el panel (admin y nuevo rol **"Facturación"**, que solo ve esa pestaña). Resumen por empresa del período (total, facturado, por facturar, por cobrar); detalle de viajes con centro de costo y solicitante; **Excel del detalle**; **marcar viajes como facturados** con N° de factura (no se factura dos veces); facturas con "Marcar pagada" (marca pagados sus viajes) y "Anular" (vuelven a por facturar). Portal de empresas → Facturación: **estado de cuenta** (viajes del período con su factura, facturas emitidas). Tablas/funciones: `facturas`, `reservas.factura_id`, `facturacion_resumen`, `facturacion_viajes`, `facturar_viajes`, `facturas_de`, `factura_accion`, `convenio_estado_cuenta`; `proteger_pago` acepta el rol facturación; `crear-miembro` acepta el rol.
- **Cotizador punto a punto en el portal de empresas**: valor aproximado con la ruta (como la web y la app), no se guarda como tarifa: se confirma al reservar.
- **Carga masiva por Excel** (`assets/carga.js`): plantilla con instrucciones, revisión fila por fila (fecha, hora, tipo, dirección con su punto en el mapa, tarifa fija del sector si es aeropuerto y la comuna tiene un solo sector), vista previa con errores y creación. Panel → Nueva reserva (elige si se cobran particular o a un convenio) y portal de empresas → Agendar (encargado; usa `crear_reserva_convenio`).
- **Reservas que se repiten** (etapa 64): ficha → "🔁 Repetir" (días de la semana, hasta una fecha, máx. 3 meses / 60, opcional mismo conductor); no duplica días; "Cancelar las próximas de la serie" (`repetir_reserva`, `cancelar_serie`, `reservas.serie_id`).
- **Negativo fuera de Santiago** (etapa 65): retiros en comunas de la periferia (Lampa, Padre Hurtado, Peñaflor, Talagante, Colina, etc.) → **60 % del valor del servicio** automático (`comuna_periferia`, `negativo_detalle`).
- **Ventas** (etapa 66): pestaña "Ventas" (admin) con empresas por contactar: rubro, contacto, estado (por contactar → contactado → respondió → propuesta → prueba → convenio / no por ahora), próximo contacto con aviso de atrasados y notas; meta 10 por semana (`prospectos`).
- **Resumen semanal** (etapa 67): cada lunes ≈ 9:00 aviso "📊 Resumen de la semana" a Operaciones (servicios, ingresos vs. semana anterior, de empresas, no presentados, cancelados, por cobrar, ventas) con la tarea `flotak-resumen-semanal`; tarjeta en Reportes con selector de semana y "¿Cómo nos conocieron?".

## 21 nov 2026 · Negativo según tarifario y conductores en el mapa
- Valor del negativo según el tarifario 2026 (etapa 62, ya aplicada, `negativo_calculo`): **domicilio $5.000** con 15 min de espera incluida, **regreso desde el aeropuerto $15.000** con **45 min**, **van $19.000**; más la espera después del tiempo incluido ($180/min auto, $270/min SUV o van). Fuera de Santiago (60 % del servicio): la central ajusta el valor en la ficha (el texto lo recuerda).
- App del conductor (Inicio): además del mapa de calor, se ven los **otros conductores conectados** (🚗 azul disponible, gris en servicio), en zona aproximada (~1 km) y sin nombres, con el conteo en la leyenda (`mapa_conductores`, etapa 62b ya aplicada). Se actualiza cada ~2 min.

## 20 nov 2026 · Pasajero no presentado (negativo) con autorización de la central
- App del conductor: con el servicio "en el lugar", botón **"🚫 Pasajero no presentado"** (con detalle opcional). El servicio **no se cierra**: queda "esperando autorización de la central". Si la central autoriza, aparece **"Cerrar como no presentado ($X)"**; si no, el aviso "⛔ Negativo no autorizado". Aviso con sonido al responder la central.
- Valor del negativo: **$5.000** (incluye los 15 min de gracia) **+ espera después de la gracia** hasta que lo informó ($180/min auto, $270/min SUV o van), igual que la espera de los punto a punto (`negativo_calculo`).
- Panel: alerta roja "🚫 Pasajero no presentado: autorice el negativo" (suena); en la ficha, recuadro con el cálculo, valor editable, nota, **✅ Autorizar negativo** / **⛔ No autorizar**, y luego "Cerrar ahora como no presentado". Despacho: etiqueta "🚫 Negativo por autorizar" / "🚫 No presentado". Aviso a Operaciones también con la app cerrada (tipo `negativo`).
- Al cerrar: servicio **finalizado**, tarifa fija = valor del negativo, `no_presentado = true` (reportes y billetera lo cuentan).
- Base de datos (etapa 61, ya aplicada): columnas `negativo_estado`, `negativo_solicitado_en`, `negativo_valor`, `negativo_resuelto_por/_en`, `no_presentado`; `conductor_pedir_negativo`, `staff_resolver_negativo`, `conductor_cerrar_negativo`.

## 20 nov 2026 · Corregir el valor de un servicio finalizado directamente en la ficha
- Pedido del dueño (facturación, cobros de más, etc.): en la ficha de un servicio finalizado el campo pasa a llamarse **"Valor final cobrado"**, muestra el valor real (el del taxímetro o la tarifa fija) y el administrador lo cambia y toca **"Guardar cambios"**. El guardado usa `admin_corregir_valor` (queda en el historial con el valor anterior y la nota escrita como motivo). Se quitó el botón separado "✏️ Corregir valor". Para otros roles el campo es de solo lectura.

## 20 nov 2026 · Corregir el valor de un servicio finalizado
- Ficha de un servicio finalizado: recuadro "Valor cobrado" (indica si fue con taxímetro y si fue corregido, con el valor original) y botón **"✏️ Corregir valor"** (solo administrador): valor correcto + motivo opcional. El campo "Precio final" queda de solo lectura en servicios finalizados, para que todo cambio quede registrado.
- Base de datos (etapa 60, ya aplicada): `admin_corregir_valor` cambia `taxi_total` (taxímetro) o `precio` (tarifa fija), guarda `valor_original` (la primera vez), `valor_corregido_por`/`_en` y anota en el historial "Valor corregido por …: $A → $B · motivo". Reportes, liquidaciones y billetera usan el valor nuevo (`v_cobro`).

## 20 nov 2026 · La asignación automática informa el móvil y la patente
- Etapa 59b (ya aplicada): el aviso "🤖 Asignada sola a …" y el historial dicen "Móvil 286 · Juan Kieferling · SSHY88", igual que la asignación manual (`conductor_mas_cercano` devuelve esa etiqueta). El vehículo ya quedaba guardado en la reserva, pero no se mencionaba. Se corrigió la nota de FK-888BC8.

## 20 nov 2026 · Regla comercial actualizada (Cabify / Servimóvil)
- Decisión del dueño tras la reunión con la Cámara Chileno-India: se mantiene el respeto a los clientes de **Servimóvil** (partner); con **Cabify** se compite abiertamente. CLAUDE.md y el kit de venta a empresas actualizados (objeción "Trabajamos con Cabify" con argumentos; cámaras de comercio como fuente de listados de empresas).

## 20 nov 2026 · Reservas que nadie toma: alertas y asignación automática al más cercano
- Tarea programada nueva `flotak-bolsa-vigilar` (cada 2 min, `bolsa_vigilar`, etapa 59 ya aplicada), para reservas publicadas sin conductor:
  - 90 min antes: aviso a Operaciones "⚠️ Nadie ha tomado …" (tipo `sin_tomar`, también con la app cerrada).
  - `empresas.bolsa_autoasignar_min` antes (por defecto **60**; se cambia o apaga en Equipo y roles): se asigna sola al **conductor más cercano que cumple** (`conductor_mas_cercano`: requisitos, vehículo que pide el servicio, sin otro servicio que se cruce, sin "otro servicio" a esa hora; primero los conectados y con ubicación reciente, luego por distancia GPS al retiro). Al conductor le llega "🚗 Servicio nuevo" y a Operaciones "🤖 Asignada sola a …" (tipo `auto_asignada`); el historial lo anota con la distancia. Si nadie cumple: "🚨 Nadie puede tomar …".
  - 45 min antes, si sigue sin conductor: "🚨 … sigue sin conductor".
  - Una reserva recién publicada tiene al menos 10 minutos en Reservas antes de avisar o asignar. Al volver a publicarla, todo parte de cero.

## 20 nov 2026 · Aviso de reservas nuevas aunque el conductor esté desconectado
- Pedido del dueño: el aviso "Nueva reserva disponible" llega **siempre**, conectado o no, con la app abierta (ya no exige `yo.disponible`) o cerrada (`conductor_latido`, etapa 58b ya aplicada). Los avisos de servicios asignados, quitados, cancelados o modificados ya llegaban estando desconectado.

## 20 nov 2026 · El dueño de vehículo inscribe a sus conductores y les asigna su auto
- /propietario → **"Mis conductores"**: enlace personal del dueño (`/conductor/?dueno=<código>`, `propietario_codigo`) con botones WhatsApp y copiar; lista de sus conductores (él mismo si conduce y los inscritos con su enlace) con su estado (activo, esperando aprobación de Flota-K, no aprobado) y el vehículo que manejan; **"¿Quién maneja cada vehículo?"** con un selector por vehículo (`propietario_asignar_conductor`: solo sus vehículos y sus conductores; un conductor maneja un solo vehículo del dueño a la vez). No aparece en la vista de administrador.
- App del conductor: el enlace del dueño muestra "conductor de <dueño>" y oculta "Tengo vehículo propio". **Flota-K igual aprueba** a cada conductor en Equipo y roles (decisión del dueño); el aviso a Operaciones y la ficha de la inscripción dicen "inscrito por el dueño <nombre>".
- Edge Function `registro-conductor` (v4) acepta `dueno`. Base de datos (etapa 58, ya aplicada): `perfiles.codigo_dueno`, `postulaciones_conductor.invitado_por`, `inscripcion_dueno`, `propietario_conductores`; `conductor_postular` acepta el código del dueño.

## 20 nov 2026 · Corrección: el inscrito queda como propietario de su vehículo
- Etapa 57b (ya aplicada): `aprobar_postulante` ahora deja al conductor como **propietario** (`propietario_id`) además de conductor habitual del vehículo que declaró en la inscripción. Se corrigió KKLJ80 (Bruno Oliveri), que figuraba como "Flota-K (propio)" en el selector de propietario y no aparecía en su portal /propietario.

## 20 nov 2026 · Aviso de reservas nuevas con la app cerrada
- Base de datos (etapa 57, ya aplicada): `conductor_latido` ahora también entrega avisos "Nueva reserva disponible · DD/MM HH:MM" (tipo `reserva_disponible`) de las reservas publicadas que el conductor ya puede ver según su prioridad, cumpla o no los requisitos, una sola vez por reserva (tabla `bolsa_avisos`, con RLS y sin políticas) y solo si está conectado. El servicio nativo de la app Android 2.0+ los muestra con sonido cuando la app no está a la vista: no hizo falta armar una versión nueva.

## 20 nov 2026 · Mapa de calor de próximos servicios y aviso de todas las reservas
- **Mapa de calor** (próximas 12 horas, por cuánto falta): 🔴 menos de 30 min, 🟠 30–60 min, 🟡 1–2 h, 🔵 más de 2 h. Círculos de ~900 m en la zona de retiro; donde hay varios, el color se intensifica.
  - App del conductor (Inicio): todos los próximos servicios de la empresa, solo zona aproximada (redondeada a ~1 km) y minutos que faltan, sin datos del pasajero (`mapa_demanda`, etapa 56). Se actualiza cada ~2 min. Sin servicio en curso, el mapa se abre más alejado para ver la zona.
  - Panel → Mapa en vivo: casilla "🔥 Mapa de calor" (activada), con código, hora y origen al tocar cada círculo.
  - `FKMapa.calor`, `colorCalor`, `leyendaCalor`, `tiempoTxt` en assets/mapa.js (`?v=56` en conductor y equipo).
- App del conductor → Reservas: **el aviso con sonido y el número de la pestaña cuentan todas las reservas nuevas**, cumpla o no los requisitos (pedido del dueño).

## 20 nov 2026 · Reservas para conductores: todos ven, solo toma quien cumple
- App del conductor → Reservas: cada reserva muestra **🚘 Categoría** (las que pide o "cualquiera") y los requisitos (🏢 Corporativo, ★ calificación mínima). Quien no cumple **la ve atenuada, sin botón para tomarla, con el motivo** ("🔒 No puede tomarlo: Pide Van o Particular VIP y su vehículo es Taxi ejecutivo"). El aviso con sonido y el número en la pestaña cuentan solo las que puede tomar. Usa `bolsa_servicios_v4` (con respaldo a v3).
- Base de datos (etapa 55, ya aplicada): `categoria_nombre`, `motivo_requisitos_bolsa` (y `cumple_requisitos_bolsa` la usa), `bolsa_servicios` ya no esconde a quien no cumple (la prioridad por calificación se mantiene), `bolsa_servicios_v4`; `conductor_tomar_reserva` responde con el motivo exacto.

## 20 nov 2026 · Requisitos al publicar en Reservas para conductores
- Ficha de la reserva → "📢 Publicar en Reservas" abre un formulario (en vez de las preguntas sueltas): **tipos de vehículo** que pueden tomarla (ninguno = todos), **🏢 solo corporativos** (obligatorio y ya marcado en reservas de convenio), **calificación mínima** (4,50 a 5,00★, promedio de 90 días; opción "también sin calificaciones") y **bono**. Muestra cuántos conductores cumplen por vehículo. La ficha muestra los requisitos de una reserva publicada y el historial los anota.
- Solo la ven (`bolsa_servicios`) y la pueden tomar (`conductor_tomar_reserva`) quienes cumplen (`cumple_requisitos_bolsa`). Publicar en grupo parte sin requisitos.
- Base de datos (etapa 54, ya aplicada): `reservas.bolsa_categorias`, `bolsa_corporativo`, `bolsa_calif_min`, `bolsa_sin_calif`; `liberar_a_bolsa_requisitos`.

## 20 nov 2026 · Cotizador punto a punto en la web y "¿Cómo nos conoció?"
- Página principal: nueva sección **"Viajes punto a punto · taxi ejecutivo"** (#punto, botón "Cotizar punto a punto" en la portada). Origen y destino con autocompletar (Photon), ruta con OSRM (+25 % por tráfico) y **valor estimado** con el taxímetro de la empresa (`cotizador_publico`: bajada, cada 200 m, mínimo $12.000), auto o van. Si un extremo es el aeropuerto, remite a la tarifa fija; Oriente ↔ costa usa la tarifa fija por tramo; > 120 km, cotización a medida. Botón "Reservar por WhatsApp" con origen, destino, vehículo y valor estimado ya escritos. Se aclara que el valor es aproximado y se confirma al reservar.
- **Mínimo del auto: $5.000** (etapa 53c, en `cotizador_publico` y `pasajero_inicio`).
- **Mínimo de la van: $25.000** (pedido del dueño): la van vale el mayor entre $25.000 y el cálculo por distancia, en la web y en la app del pasajero (etapa 53b, `cotizador_publico` entrega `minimo_van`; caché de la app fk-app-v11).
- Corrección: los botones Ida/Regreso/Van del tarifario solo toman sus propios botones (`.seg button[data-mode]`).
- Panel: campo **"¿Cómo nos conoció?"** en la reserva nueva (se marca "Página web" solo si el mensaje pegado viene del cotizador), editable en la ficha, y gráfico "¿Cómo nos conoció?" en Reportes. Base de datos (etapa 53, ya aplicada): `reservas.como_nos_conocio`.

## 19 nov 2026 · El admin ve el portal de cada propietario
- Equipo y roles: botón **"👁 Ver su portal"** en cada propietario. Abre /propietario/?ver=<id> con un aviso "Vista de administrador" y muestra exactamente sus vehículos, servicios y reportes (solo lectura).
- Base de datos (etapa 52, ya aplicada): `admin_puede_ver_propietario`, `admin_ver_propietario_vehiculos`, `admin_ver_propietario_servicios` (solo admin de la misma empresa).

## 19 nov 2026 · Propietario que también conduce
- Un usuario con rol **Propietario** y la casilla **"🚗 También conduce"** entra a la app del conductor y al portal /propietario. Al registrar su vehículo en la app (Perfil → Mi vehículo) queda automáticamente como **su propietario** y lo ve en /propietario con sus reportes (etapa 51, ya aplicada: `conductor_guardar_vehiculo` llena `propietario_id`).
- App del conductor: botón "📊 Reportes de mi vehículo" en Perfil para propietarios. /propietario: botón "🚗 Ir a la app del conductor" y, si aún no tiene vehículos, explica cómo registrarlo.
- Datos: Jorge Muñoz pasó de Conductor a Propietario (sigue con "También conduce"; su vehículo PKSH59 ya estaba a su nombre). Pedido del dueño.

## 19 nov 2026 · "Decreto 80" pasa a llamarse "Corporativo"
- Pedido del dueño: en pantalla la casilla se llama **"🏢 Corporativo"** (vehículo con autorización ministerial). Cambian los textos del panel (Flota, advertencia al asignar, ficha, inscripciones), del formulario de inscripción y el mensaje de `conductor_tomar_reserva` (etapa 50b, ya aplicada). Las columnas internas siguen siendo `decreto80` y `decreto80_vence`.

## 19 nov 2026 · Decreto 80: servicios de empresas con convenio solo con vehículos acreditados
- Flota (panel): casilla **"🏢 Decreto 80"** en cada vehículo, con fecha de vencimiento (opcional) y aviso "Decreto 80 vencido".
- **Toda reserva de una empresa con convenio exige un vehículo con Decreto 80 vigente** (decisión del dueño). En "Reservas para conductores" no se le muestra a quien no lo tenga y no la puede tomar (`bolsa_servicios`, `conductor_tomar_reserva`). En el panel, la lista de conductores marca "⚠ sin Decreto 80" y al asignar pide confirmación ("¿Asignar de todas formas?"). La ficha muestra "🏢 exige vehículo con Decreto 80".
- Inscripción de conductores: casilla "Mi vehículo está inscrito en el Decreto 80"; el panel lo muestra como "dice tener Decreto 80 (verifíquelo y márquelo en Flota)". No se marca solo.
- Base de datos (etapa 50, ya aplicada): `vehiculos.decreto80`, `vehiculos.decreto80_vence`, `postulaciones_conductor.dice_decreto80`, función `vehiculo_decreto80_ok`.

## 19 nov 2026 · Inscripción de conductores con enlace (aprobación con un toque)
- Panel → Equipo y roles (solo admin): **"🆕 Inscripción de conductores"** con el enlace para enviar (WhatsApp o copiar), "Cambiar enlace" (el anterior deja de servir) y "Pausar inscripciones". Lista **"Por aprobar"** con datos (teléfono, correo, RUT, comuna, licencia, experiencia, vehículo propio) y documentos para abrir; botones **✅ Activar**, Rechazar (con motivo opcional que la persona ve) y WhatsApp. Las rechazadas quedan plegadas, con "Activar de todas formas". La pestaña muestra "(🆕 N)" si hay inscripciones pendientes. Los postulantes no aparecen en la tabla de miembros hasta ser aprobados.
- App del conductor: con `/conductor/?inscripcion=<código>` aparece el formulario "Inscripción de conductores" (nombre, RUT, teléfono, comuna, licencia, experiencia, vehículo propio opcional, correo y contraseña, declaración). Al enviar, entra solo y ve **"Su inscripción está en revisión"**, donde sube licencia, cédula, antecedentes y hoja de vida (lista con ✅). No ve servicios hasta ser activado. Si se rechaza, ve el aviso con el motivo.
- **Tres categorías nuevas de vehículo** (etapa 49c, ya aplicada): **Particular sedán**, **Particular SUV** y **Particular VIP**, en Flota, en "Mi vehículo" del conductor, en la inscripción (el conductor elige la categoría de su auto), en el seguimiento y en el portal de propietarios. "Particular SUV" sirve para las reservas que piden SUV (igual que SUV y Van), en el panel, en la bolsa (`bolsa_servicios`, `conductor_tomar_reserva`) y al registrar el vehículo (`conductor_guardar_vehiculo`). Si el inscrito no elige categoría, su auto queda como Particular sedán.
- Edge Function nueva `registro-conductor`: valida el código, limita intentos (5 por IP y 3 por correo por hora), crea la cuenta ya confirmada (no gasta correos) y el perfil por activar.
- Base de datos (etapas 49 y 49b, ya aplicadas): `perfiles.postulacion` (pendiente/aprobada/rechazada), `empresas.inscripcion_codigo` e `inscripcion_activa`, tabla `postulaciones_conductor` (RLS), `inscripcion_empresa`, `registro_conductor_permitido`, `conductor_postular` (solo la función), `mi_empresa_postulante` + política de Storage para que el postulante suba documentos, `postulante_documento`, `aprobar_postulante` (activa, marca "Conduce" y crea su vehículo propio como no propio de Flota-K) e `inscripcion_config`. Aviso a Operaciones "🆕 Nuevo conductor inscrito" (tipo `postulante`), también con la app cerrada.

## 19 nov 2026 · Semáforo del conductor y aviso de aceptación
- Panel de Operaciones: etiqueta de color con el estado del conductor en cada servicio (pedido de Paola): 🟤 sin aceptar, 🟢 aceptó, 🔴 no puede, 🟡 en camino, 🔵 ubicado (celeste), 🔷 pasajero a bordo (azul), ⚪ finalizado (gris). En Despacho (bajo el conductor, con leyenda arriba), en la lista de Reservas, en la Agenda (columnas y línea de tiempo, donde el bloque toma el color) y en la ficha ("Asignación"). `SEM`, `semClave`, `semaforo` en equipo; estilos `.sem` en app.css.
- Base de datos (etapa 48, ya aplicada): aviso a Operaciones "✅ [conductor] aceptó el servicio" (tipo `acepto`), también con la app cerrada; el rechazo ya avisaba.

## 18 nov 2026 · Gastos (fijos o variables, por patente) y otros ingresos con comisión en Reportes
- Gastos: se marcan **Fijo** o **Variable** (chips al ingresar y casilla "Fijo" en la lista para cambiarlo); se asocian a la **patente** (o a la empresa), sin conductor.
- **Otros ingresos** (Cabify, Servimóvil, Uber, DiDi, particular, otra; se pueden agregar plataformas): monto bruto, % de comisión (por defecto según la plataforma; Servimóvil 23 %, editable en "⚙ Comisiones por plataforma"), viajes, patente; la comisión y el neto los calcula la base de datos. Se pueden anular.
- Resultado = servicios Flota-K finalizados + otros ingresos netos − gastos; KPIs con gastos fijos/variables y comisiones; otros ingresos por plataforma; **resultado por patente** (Flota-K + otros − gastos). Excel con hojas "Gastos" y "Otros ingresos".
- Base de datos (etapa 46, ya aplicada): `fuentes_ingreso` y `ingresos_externos` (solo administrador).
- **Cierres diarios** de los conductores en el resultado, sin contar dos veces: en **"⚙ ¿De dónde salen los números?"** (etapa 47b, `empresas.reportes_config`) se elige la fuente oficial de los gastos del día (por defecto: lo que ingresa el admin, p. ej. la boleta mensual de bencina) y de los ingresos de Cabify/otras apps (por defecto: el cierre del conductor). Lo que no es oficial se muestra como referencia y no suma. Aviso al ingresar a mano algo que ya viene de los cierres.
- Etapa 47c (ya aplicada): por concepto del cierre (combustible, peajes, otros) se elige **"se descuenta de lo que compró la empresa"** (por defecto: la compra va en Gastos y lo que anotan los conductores se descuenta; cuadro "Compras de la empresa y consumo de los conductores" con comprado/consumido/disponible; en "Resultado por patente" el consumo pasa a la patente que lo usó sin cambiar el total) o **"se suma como gasto nuevo"**.
- **🎯 Presupuestos del mes** (tabla `presupuestos`): tope mensual por concepto, para toda la empresa o una patente; barra de avance con aviso al 80 % y al pasarse; usado = lo que anotan los conductores (si el concepto se descuenta) o lo registrado + cierres (si se suma). Monto editable y "Quitar".
- **Corregir cierres**: botón "✏ Corregir" en la tabla de cierres diarios (km, Cabify, peajes, otras apps, combustible, otros gastos); el disparador `cierres_guardar_original` guarda quién, cuándo y los valores originales del conductor.
- **🏦 Saldo en cuenta** (etapa 47, ya aplicada, tabla `saldos_cuenta`): "Actualizar saldo" con cuenta, fecha, saldo y nota; muestra el último saldo de cada cuenta y el total; historial con "Anular".

## 18 nov 2026 · Gastos y resultado en Reportes
- Panel → Reportes (solo admin): sección **"Gastos y resultado"**: agregar gasto (fecha, tipo, monto, móvil o "Empresa (general)", detalle, "se repite todos los meses"); ingresos (finalizados) − gastos = resultado y margen; gastos por tipo; **resultado por móvil** (ingresos de sus servicios − sus gastos); lista con "Anular"; botón "Cargar los gastos fijos de este mes" (copia los fijos del mes anterior que falten); Excel de gastos.
- Base de datos (etapa 45, ya aplicada): tabla `gastos` (18 tipos, `fijo`, anular en vez de borrar), solo administrador.
- Seguimiento: el aviso "Su conductor está terminando otro traslado" sube al principio, con borde dorado.

## 18 nov 2026 · "Estoy en otro servicio"
- App del conductor (Inicio): botón **"🚕 Estoy en otro servicio"**: hacia dónde va (con autocompletar) y a qué hora termina (se sugiere según la ruta desde donde está). Mientras dure: "En otro servicio hasta HH:MM" con "Cambiar" y "✓ Terminé". Carga `assets/lugar.js`.
- Seguimiento: en reservas confirmadas o asignadas que empiezan dentro de 3 horas, si el conductor está en otro servicio (marcado a mano o un servicio de Flota-K en curso), muestra "🚕 Su conductor está terminando otro traslado (en <comuna>)", la hora en que termina y la llegada estimada (OSRM +25 %), y si podría llegar después de la hora reservada. Sin datos del otro pasajero: solo la zona (punto redondeado a ~1 km).
- Panel, Mapa en vivo: el conductor aparece "En otro servicio hasta HH:MM · hacia …".
- Etapa 44b: también con la reserva "en camino" (el conductor la marcó así mientras seguía en otro viaje); en ese caso se oculta la llegada calculada desde su ubicación.
- Base de datos (etapa 44, ya aplicada): columnas `otro_servicio_*` en `perfiles`, `conductor_otro_servicio`, `conductor_fin_otro_servicio` y `ver_conductor_ocupado` (con el enlace de seguimiento).

## 18 nov 2026 · El cliente cambia la hora de su reserva
- Portal (/empresa) y app del pasajero (/app): botón **"🕒 Cambiar hora"** en los viajes que aún se pueden cancelar (hasta 2 horas antes, como dicen los Términos). `FK.cambiarHoraUI` y `FK.isoALocal` en assets/app.js. Cachés `fk-app-v10` y `fk-empresa-v4`.
- Base de datos (etapas 43a y 43, ya aplicadas): `convenio_cambiar_hora` y `pasajero_cambiar_hora` (mismas reglas de acceso que cancelar) con `cambiar_hora_cliente` (nueva hora al menos 2 h desde ahora, nota en el historial). Aviso nuevo para Operaciones "🕒 Cliente cambió la hora" (tipo `cambio_hora`); el conductor asignado recibe "✏️ Servicio modificado".

## 18 nov 2026 · Cambiar la fecha u hora de una reserva
- Panel, detalle de la reserva: botón **"✏ Cambiar fecha u hora"** (no en reservas a bordo, finalizadas o canceladas). Hora de Chile (`FK.chileLocalToISO`), avisa si la hora ya pasó y si el conductor asignado queda con servicios cruzados. Al guardar, el conductor recibe "✏️ Servicio modificado" (etapa 38) y aparece el botón **"📲 Avisar al pasajero por WhatsApp"** con el mensaje del cambio (nueva y anterior hora, origen, destino y seguimiento).

## 18 nov 2026 · Más confianza para Google
- Portada: sección **"Quiénes somos"** (#nosotros) con razón social FK Servicios SpA, RUT 77.573.708-5, dirección Santa Elena 1486, of. 1406, Santiago, contacto y enlace a los Términos; el pie también muestra RUT y dirección.
- Datos estructurados (portada e /en): `legalName`, `taxID` y `address` en la ficha `TaxiService`, para que Google identifique a la empresa.
- Panel: el mensaje "Gracias + calificar" agrega el pedido de reseña en Google (`FK_CONFIG.resenaGoogle`).

## 18 nov 2026 · Términos y condiciones
- Nueva página **/terminos/** (versión 1.0, vigente desde el 18-11-2026), redactada con las reglas del dueño: espera $180/min sobre 15 min en domicilio; cancelación sin costo con 2 h o más, $5.000 con menos de 2 h y 60 % fuera de Américo Vespucio en comunas periféricas (caso a caso); no presentación $5.000 (60 % en la periferia); limpieza mín. $30.000; reembolsos según el banco o 10 días hábiles si los hace Flota-K; objetos olvidados 30 días (retiro en oficina, encargo pagado o entrega sin costo según la operación); reclamos en 10 días hábiles; pago anticipado y cargos adicionales a la tarjeta registrada. Respeta la Ley 19.496 (sin cláusulas abusivas) y la Ley 19.628. Pendiente: revisión de un abogado.
- Enlaces: pie de la portada, /empresas y /en; pantallas de ingreso de /app y /empresa ("Al ingresar acepta los Términos y condiciones"); sitemap.

## 18 nov 2026 · Solo reservan los clientes con cuenta entregada por Flota-K
- Para asegurar el pago, el dueño decidió que por ahora las cuentas de pasajeros las entrega Flota-K (pestaña "Cuentas de clientes").
- /app: "Crear cuenta" pasa a ser **"Solicitar cuenta"** (botón a WhatsApp con mensaje listo). Caché `fk-app-v8`. Las cuentas creadas por Flota-K (particulares o de empresas) entran a /app y a /empresa con el mismo usuario.
- Base de datos (etapa 42, ya aplicada): `registro_permitido` siempre responde no (la Edge Function `registro-pasajero` ya no crea cuentas) y el disparador `reservas_app_autorizada` rechaza reservas del canal `app` de personas sin acceso activo en `convenio_usuarios`.

## 18 nov 2026 · Cuentas de clientes (empresas y particulares), roles más claros y vehículo en el seguimiento
- Panel, nueva pestaña **Cuentas de clientes** (solo admin): todas las personas con acceso al portal de empresas en una lista con buscador (empresa, rol, estado, nueva clave, quitar/dar acceso, ver como) y formulario para crear una cuenta eligiendo la empresa (`crear-usuario-convenio`). `datosAcceso` acepta el recuadro donde mostrar los datos.
- Equipo y roles: columna **"🚗 También conduce"** (rol principal + casilla) con explicación; los conductores siempre conducen. Paola Quichiz (admin) quedó sin "conduce" (lo había marcado la etapa 2 a todos los administradores).
- Flota: botón **"✏️ Editar datos"** en cada vehículo (marca, modelo, año, color, patente, categoría, capacidad, conductor y foto). Antes solo se podían poner al crearlo.
- **Clientes particulares** (etapa 41, ya aplicada): en "Cuentas de clientes" se elige "👤 Cliente particular (sin empresa)". Cada empresa tiene una cuenta interna `es_particulares` ("Clientes particulares", creada por `cuenta_particulares()`) que no aparece en las listas de convenios. El particular entra al mismo portal (/empresa, encabezado "Cliente particular" con su nombre), agenda a su nombre con `crear_reserva_convenio` (la reserva queda sin convenio, canal "portal", sin presupuestos ni facturación), ve "Mis viajes" y puede cancelar con más de 2 horas. Su ficha de cliente no queda ligada a ningún convenio; etapa 41b: `asignar_cuenta_corporativa` tampoco carga a convenio las reservas del canal "portal".
- Seguimiento (etapa 40, ya aplicada): `ver_reserva_publica_v3` agrega categoría y capacidad; se muestra "Vehículo · Taxi ejecutivo", marca y modelo, **Color**, año y pasajeros. Los mensajes de WhatsApp del panel incluyen categoría y color.

## 18 nov 2026 · App del pasajero con cuenta (rama `app-pasajero`, sin publicar)
- **/app con cuenta obligatoria:** Ingresar (correo o usuario + contraseña, recuperar contraseña) o Crear cuenta (nombre, teléfono, correo, contraseña). Edge Function `registro-pasajero`: crea la cuenta sin confirmar y envía el correo de confirmación (SMTP Gmail); máx. 5 registros por IP y 40 en total por hora (`registro_intentos`). El historial con el mismo correo se vincula solo con el correo ya confirmado.
- **Reservar (reserva activa, la confirma el equipo):** al aeropuerto (con opción ida y vuelta), desde el aeropuerto y otro trayecto; direcciones guardadas con un toque; pasajeros y maletas con − / +; reservar para otra persona (queda como solicitante).
- **Cotizador punto a punto:** ruta real (OSRM) × taxímetro ejecutivo de la empresa (bajada $2.400 + $180 cada 200 m, mínimo $12.000, redondeado a $500; van × factor del tarifario). Sector Oriente ↔ costa con su tarifa fija; más de 120 km: "a cotizar". La reserva queda con nota "Valor estimado por la app, por confirmar".
- **Mis viajes** (desde la base de datos, cualquier teléfono): próximos y anteriores con valor, conductor, móvil, auto y patente; aviso "Su conductor va en camino" con enlace al mapa en vivo; cancelar hasta 2 h antes; calificar con estrellas (y reseña de Google con 5); repetir un viaje.
- **Mi cuenta:** datos, direcciones guardadas (hasta 15), contacto, cambiar contraseña, cerrar sesión.
- Las reservas de la app (canal `app`) son siempre particulares: `asignar_cuenta_corporativa` ya no las carga a un convenio.
- Portada: los enlaces del correo de pasajeros de la app (signup o `origen = app_pasajero`) vuelven a /app; el resto sigue a /equipo.
- Base de datos (etapa 40, ya aplicada): `pasajero_favoritos`, `registro_intentos`, `pasajero_cliente`, `pasajero_inicio`, `pasajero_actualizar_perfil`, `pasajero_guardar_favorito`, `pasajero_borrar_favorito`, `pasajero_reservar`, `pasajero_viajes`, `pasajero_cancelar`, `registro_permitido`.
- Caché de la app del pasajero `fk-app-v7`.

## 18 nov 2026 · App Flota-K Operaciones 2.2: suena con la app cerrada
- Base de datos (etapa 39, ya aplicada): `avisos_equipo` y disparador `reservas_zz_avisar_equipo`: reserva nueva (agendada por otra persona: equipo, empresa con convenio, web), cancelada por alguien fuera del equipo, conductor que no puede y conductor que tomó una reserva publicada. `dispositivos_equipo` con llave de dispositivo: `equipo_registrar_dispositivo`, `equipo_latido` (cada 60 s, sin los avisos que generó la misma persona) y `equipo_cerrar_dispositivo` (al salir).
- Android: `AvisosEquipoService` (servicio en primer plano de uso especial, con el procesador despierto lo justo para preguntar cada minuto) muestra los avisos con sonido y vibración cuando la app no está a la vista; se reinicia al encender el teléfono.
- /equipo: carga el puente de Capacitor; en la app Android registra el teléfono, arranca los avisos y muestra "Ajustes para recibir avisos con la app cerrada" (notificaciones, batería, apps sin usar). "Salir" detiene los avisos y anula la llave.
- Versión 2.2 para las tres apps (mismo proyecto Android). La app del conductor no cambia su funcionamiento.

## 18 nov 2026 · App del conductor 2.1: suena con la app cerrada
- Problema: con la app cerrada, la ubicación seguía llegando, pero un servicio asignado no sonaba hasta abrir la app (el aviso dependía de la pantalla).
- Base de datos (etapa 38, ya aplicada): `avisos_conductor` y disparador `reservas_zz_avisar_conductor` (servicio nuevo, quitado, cancelado o modificado; no avisa al conductor de lo que hizo él mismo). `conductor_latido` reemplaza a `conductor_ubicacion_dispositivo` en la app 2.1: guarda la ubicación y entrega los avisos pendientes (cada 15 s en servicio, 30 s conectado, 60 s desconectado; la ubicación desconectado se sigue guardando cada 5 min).
- Android: el servicio de ubicación muestra los avisos como notificación con sonido y vibración (canal "Servicios de la central") cuando la app no está a la vista. Pide el permiso de notificaciones (Android 13+) y lo agrega al recuadro de ajustes.
- Etapa 38b: el aviso no llegaba si quien asignaba era el mismo conductor con rol de equipo (el dueño es admin y conductor). Ahora solo se omite cuando lo hace un conductor sin rol de equipo.
- Sin Firebase: el aviso llega en 30-60 segundos. La app 2.0 sigue funcionando (sin estos avisos).
- Las tres apps ya se firman con la llave de Flota-K (secretos en GitHub): las actualizaciones se instalan encima.

## 17 nov 2026 · App del conductor 2.0: ubicación con la app cerrada (rama `app-siempre-conectada`, sin publicar)
- Android: servicio propio (`UbicacionService`) que envía la ubicación aunque el conductor cierre la app o reinicie el teléfono (`ArranqueReceiver`), hasta que cierre sesión. Cada 15 s en servicio, 60 s conectado, 5 min desconectado (lo indica el servidor). Notificación fija "Compartiendo su ubicación con la central".
- Puente `FlotaKNativo` (página ↔ Android): iniciar/detener, pedir "Permitir todo el tiempo", batería "Sin restricciones" y desactivar "Pausar actividad si no se usa". La pantalla del conductor muestra un recuadro "Ajustes para que la app no se corte" con un botón por ajuste pendiente.
- Base de datos (etapa 37, ya aplicada): `dispositivos_conductor` y llave de dispositivo (solo se guarda su huella; solo sirve para enviar la ubicación de ese conductor). `conductor_registrar_dispositivo`, `conductor_ubicacion_dispositivo`, `conductor_cerrar_dispositivo` (al cerrar sesión), `admin_cerrar_dispositivos` (celular perdido) y `conductor_guardar_push` (para los avisos con la app cerrada, próxima etapa).
- Las apps antiguas (1.x) siguen funcionando como antes. Versión 2.0 (`app-android/version.json`): la página avisa que hay que actualizar.
- Armado de la app: solo `main` reemplaza la app que descargan los conductores; otras ramas publican una versión de PRUEBA ("conductor-prueba").

## 17 nov 2026 · Deshacer al mover el pin
- `assets/lugar.js` (nueva reserva y edición en el panel, portal de empresas, servicios habituales): botón "↶ Deshacer" que devuelve el pin y el texto de la dirección al punto anterior, paso a paso (hasta 30). Cargar un punto desde el sistema (`set`) empieza un historial nuevo.
- Seguimiento, "Confirme su punto exacto de retiro": "↶ Deshacer" y "Volver al punto guardado".

## 17 nov 2026 · El enlace de seguimiento siempre va con su mensaje
- Panel, ficha de la reserva: "Copiar" copiaba solo el enlace. Ahora "⧉ Copiar mensaje" y "📲 Compartir por WhatsApp" (elige el contacto) usan `mensajeSeguimiento(r)`: saludo, código, fecha, origen, destino, vuelo, conductor y vehículo, y el enlace con lo que puede hacer en él.
- Seguimiento, "Compartir mi viaje": el enlace va dentro del texto (WhatsApp a veces botaba el texto cuando el enlace iba aparte).

## 17 nov 2026 · Recuperar contraseña por correo (todas las pantallas de ingreso) y más seguridad
- "¿Olvidó su contraseña?" en equipo, conductor, propietario y portal de empresas (`assets/recuperar.js`): envía un enlace de recuperación (`resetPasswordForEmail`) solo al correo dueño de la cuenta, con la misma respuesta exista o no la cuenta; las cuentas con usuario corto (@usuarios.fk-servicios.com) no tienen correo y se les indica pedir clave provisoria.
- Al volver desde el enlace aparece "Cree su contraseña nueva" (mín. 8 caracteres, letras y números); al guardar se cierran las sesiones en otros dispositivos (`signOut({ scope: "others" })`) y se marca `convenio_clave_cambiada`.
- El ingreso del equipo ya no puede crear cuentas (antes usaba `signInWithOtp` con `shouldCreateUser: true`) ni consulta `puede_ingresar_equipo` (que permitía averiguar si un correo es del equipo).
- `FK.enlaceTipo` en assets/app.js indica con qué enlace del correo se entró.

## 17 nov 2026 · Correo propio (Gmail) y enlace de acceso que funciona en cualquier navegador
- Supabase ya envía correos con SMTP de Gmail (gerencia@fk-servicios.com), configurado por el dueño. Límite: 30 por hora.
- El enlace del correo entraba en un bucle: con `flowType: "pkce"` solo funcionaba en el mismo navegador donde se pidió (al abrirlo desde la app de Gmail fallaba con "code challenge does not match"). Ahora `flowType: "implicit"` en assets/app.js.
- Si el enlace cae en la portada (Supabase vuelve a la dirección del sitio cuando la página pedida no está en su lista permitida), la portada lo reenvía a /equipo.
- /equipo: la ventana "Cree su contraseña" se abre apenas se entra con el enlace (antes esperaba que cargara todo el panel); un enlace vencido o ya usado muestra qué hacer. El error "Error sending magic link email" se traduce al español.

## 17 nov 2026 · Mejoras de la revisión general
- Imagen al compartir el enlace (WhatsApp, Facebook, LinkedIn): `assets/img/compartir.jpg`, `compartir-en.jpg` y `compartir-empresas.jpg` (1200×630) con `og:image` y `twitter:card` en la portada, inglés, /empresas y las 13 páginas por comuna.
- Ícono de Flota-K (favicon) en todas las páginas.
- App del pasajero (/app): "Mi cuenta" ya no lleva a /cuenta (enlace por correo, sin configurar): ahora "Entrar y agendar" lleva al portal /empresa, donde se entra con correo o usuario y contraseña.
- /empresas: ficha para Google (datos estructurados `Service`) y se corrigió un `</head>` repetido.
- Reseñas de Google: sección "Lo que dicen nuestros pasajeros" en la portada y botón en /empresas; `resenaGoogle` en `assets/config.js` (ficha de Google por CID), que el seguimiento ya ofrece al pasajero que califica con 5 estrellas. La ficha de Google se agregó a los datos estructurados de la portada.
## 17 nov 2026 · Portal de empresas: el valor del viaje igual que en cobranza
- Base de datos (etapa 35, ya aplicada): `valor_cobro(reserva)` calcula como `v_cobro` (taxímetro si se cobró con taxímetro; si no, precio fijo o tarifa web; más gastos). Lo usan `convenio_reservas` (valor que ve el pasajero o la empresa) y `convenio_gasto` (presupuestos). Antes los servicios con taxímetro salían "Valor por confirmar" en el portal.

## 17 nov 2026 · Nueva clave: mensaje visible y WhatsApp en las apps Android
- Portal de empresas en el panel: el recuadro con la clave provisoria y el botón "Enviar por WhatsApp" aparece arriba de la sección y la pantalla baja sola hasta él (antes quedaba al final, fuera de la vista en el teléfono). El mensaje de clave nueva incluye el usuario corto.
- `FK.abrirExterno(url)`: en las apps Android (Capacitor) abre WhatsApp navegando directo; en el navegador, en pestaña nueva. Reemplaza los `window.open` de WhatsApp del panel, el portal de empresas y el seguimiento.

## 17 nov 2026 · Ingreso con usuario corto
- Pantallas de ingreso (equipo, conductor, propietario y portal de empresas): el campo ahora es "Correo o usuario". Si no se escribe "@", la página pasa a minúsculas, quita espacios y tildes y agrega "@usuarios.fk-servicios.com" (`FK.usuarioACorreo` en assets/app.js). "R González", "rgonzalez" y "RGonzalez" entran a la misma cuenta.
- Al crear cuentas en el panel o en el portal de empresas también se puede escribir solo el usuario; el mensaje para enviar muestra el usuario corto (`FK.usuarioVisible`).
- El enlace al correo del equipo no se ofrece a cuentas con usuario (no tienen correo real).

## 16 nov 2026 · Nueva reserva más amigable (panel)
- El formulario se ordena en 5 pasos numerados: quién viaja, servicio y cuándo, dónde, pasajeros y vehículo, precio y quién paga. Canal y repetir quedan en "Más opciones".
- Servicio, vehículo y "¿quién paga?" con botones grandes en vez de listas; pasajeros y maletas con − / +.
- Atajos de fecha: Hoy / Mañana / Pasado mañana (mantiene la hora).
- Al elegir Ida o Regreso, el aeropuerto se pone solo como destino u origen si está vacío.
- Barra fija abajo con el resumen (fecha, trayecto, precio), lo que falta para guardar y aviso si la fecha ya pasó o si hay más de 4 pasajeros en auto.
- Sin cambios en la base de datos: los mismos campos y la misma validación al guardar.

## 16 nov 2026 · Servicios con paradas intermedias y vuelo solo en aeropuerto
- **Paradas (hasta 8)** entre el origen y el destino, cada una con su punto en el mapa: en la nueva reserva del despacho y en el portal de empresas ("Paradas en el camino"). La ruta y los km se recalculan con las paradas y el panel muestra cuánto agregan ("Ajuste el precio").
- Portal de empresas: con paradas no se muestra tarifa fija ("el valor se lo confirmamos"); los servicios habituales no llevan paradas.
- Al duplicar o crear el regreso se copian las paradas (en el regreso, en orden inverso).
- **Editar paradas** en una reserva ya creada: solo desde la ficha del panel (✏ Editar paradas), mientras no esté finalizada ni cancelada. Muestra el cambio de km/min y deja nota en el historial (`editar_paradas`).
- **App del conductor:** cada parada con Waze / Google Maps; con el pasajero a bordo, el botón principal abre Google Maps con todas las paradas en orden. Botones "📍 Llegué a la parada" y "➤ Seguimos".
- **Espera en paradas:** 5 min sin costo en cada parada; después $180/min (auto) o $270/min (SUV o van). No aplica a servicios por hora ni con taxímetro. Al salir de la parada (o al llegar a la siguiente, o al finalizar) queda como gasto "espera" de la reserva ("Espera en parada N: …"). Contador en la app del conductor, en el enlace del pasajero y resumen en la ficha del panel.
- **Número de vuelo:** el panel lo oculta y no lo guarda en punto a punto y por hora (el portal y la app ya lo hacían).
- Enlace del pasajero: muestra las paradas y su espera.
- Base de datos: columna `reservas.paradas` (revisada con `paradas_limpias` en todo insert/update), tabla `reserva_paradas_espera` (RLS, sin acceso directo), `conductor_parada`, `ver_paradas_espera`, `ver_paradas_espera_publica`, `ver_paradas_publica`, `crear_reserva_convenio` con `p_paradas`. Migración `20261117011807_etapa34_paradas`.
- Cachés: app del pasajero `fk-app-v6`, portal de empresas `fk-empresa-v3`.

## 16 nov 2026 · La "bolsa de servicios" se llama "Reservas"
- App del conductor: pestaña "Reservas", título "Reservas disponibles", avisos "Nueva reserva disponible".
- Panel: "Publicar en Reservas", "Quitar de Reservas", "Reservas para conductores" (para no confundir con la pestaña Reservas del panel).
- Notas del historial que escribe la base de datos (liberar, devolver, tomar) dicen "Reservas". Solo textos: tablas, columnas y funciones siguen llamándose `bolsa`.

## 16 nov 2026 · Página /empresas/ para prospección
- Nueva página de venta para empresas (`/empresas/`): problema, lo que ven en el portal, cómo empezamos. Enlazada desde la sección Empresas de la portada y en el sitemap.
- Base para los correos de prospección (sin prometer cantidad de vehículos: "vehículos coordinados con anticipación" para grupos).

## 16 nov 2026 · Vista previa del portal de empresas desde el panel
- En Clientes y cobros → Empresas → ficha → Portal de empresas: botón 👁 por cada persona con acceso. Abre `/empresa/?como=<persona>` y muestra el portal exactamente como lo ve esa persona (encargado, directivo o pasajero), sin entrar a su cuenta.
- Solo lectura: en la vista previa solo se permiten `convenio_inicio` y `convenio_reservas`; agendar, cancelar, personas, presupuesto y facturación quedan bloqueados en la página y, además, esas funciones siguen exigiendo ser la persona real.
- Base de datos: `convenio_yo_o_vista(p_como)` (solo equipo de Flota-K y de la misma empresa); `convenio_inicio(p_como)` y `convenio_reservas(p_desde, p_como)` con parámetro opcional. Migración `20261116200515_etapa32`.
- Caché del portal `fk-empresa-v2`.

## 16 nov 2026 · Particular o convenio en cada reserva, rol directivo y viajes particulares en el portal
- **Nueva reserva (despacho):** campo obligatorio "¿Particular o convenio?". Si es convenio, se elige la empresa y aparece el centro de costo. Si el cliente tiene convenio en su ficha, se sugiere, pero el despachador confirma. Al copiar una reserva se mantiene lo mismo.
- **Ficha de la reserva:** se puede cambiar entre particular y un convenio.
- La base de datos ya no pone el convenio sola cuando reserva el equipo (`asignar_cuenta_corporativa`: solo para reservas que hace el propio cliente).
- **Rol "Directivo"** en empresas con convenio (ej.: el dueño): ve todos los viajes de la empresa y el gasto del mes, sin administrar personas, presupuestos ni facturación. Lo puede dar el admin de Flota-K (Portal de empresas) o el encargado de convenio.
- **Portal /empresa:** cada persona ve además sus viajes particulares (los que paga ella, sin convenio), con filtro Todos / Empresa / Particulares. Los particulares no se pueden cancelar desde el portal.
- Al dar acceso al portal, si la persona ya era cliente particular (por correo o, si no, por teléfono), se usa la misma ficha y conserva su historial (migración `20261116195711_etapa31b`).
- Datos: cliente Roberto González (+56993591706) creado; FK-CC6D07 y FK-9FE18D quedan a su nombre como solicitante (particular), pasajera María Eugenia de González.
- Base de datos: migración `20261116195017_etapa31`; Edge Function `crear-usuario-convenio` v2 acepta el rol directivo.

## 16 nov 2026 · Espera en servicios punto a punto
- Regla: 15 min sin costo desde la hora agendada; después $180 por minuto (auto) o $270 (SUV o van, según lo que pidió el cliente). Solo tarifa fija (el taxímetro ya cobra su espera).
- El cobro corre desde lo que pase después: fin de la gracia o llegada del conductor ("llegué"), hasta que el pasajero sube. Minutos completos.
- Al subir el pasajero, la espera queda como gasto "Espera" de la reserva y se suma al total en cobros.
- Contador en vivo con lo que se va cobrando: enlace de seguimiento, app del pasajero ("Mis viajes") y app del conductor. Antes de la llegada se informa la regla.
- Base de datos: `espera_calculo`, `ver_espera_publica` (con token), `ver_espera` (conductor y equipo), trigger `reservas_zz_cobro_espera`. Migración `20261116193753_etapa30`.
- El contador de espera parte en la hora agendada aunque el conductor llegue antes (antes de esa hora se muestra "ya llegó" con la hora agendada). El cobro siempre parte a la hora agendada + 15 min o más tarde.
- Nuevo `assets/espera.js`. Caché de la app del pasajero `fk-app-v3`.

## 16 nov 2026 · Papelera de reservas: borrado definitivo a las 24 horas
- Las reservas eliminadas quedan 24 horas en la papelera (se pueden restaurar) y después se borran definitivamente junto con sus eventos, gastos, mensajes, calificaciones, ubicaciones e historial de cambios.
- Función `purgar_reservas_eliminadas()` (solo la ejecuta la tarea programada) y tarea pg_cron `flotak-purgar-eliminadas`, cada hora al minuto 17. Migración `20261116183114_etapa29`.
- La papelera del panel muestra cuándo se borra cada reserva.
- Al probarla se borraron FK-C41CC8 y FK-6600FB, que llevaban más de 24 horas en la papelera.

## 16 nov 2026 · Privacidad en "Mis viajes" de la app del pasajero
- "Mis viajes" (`/app`) muestra los viajes cuyos enlaces de seguimiento se abrieron en ese teléfono (se guardan en el teléfono, no hay cuenta). Cuando el admin o un conductor abría el enlace de un pasajero, ese viaje quedaba en su "Mis viajes" y parecía que se veían viajes de otras personas. La base de datos no estaba expuesta: un pasajero solo ve los viajes cuyo enlace tiene.
- `/seguimiento` ya no guarda el viaje en "Mis viajes" si en ese teléfono hay una sesión del equipo (cualquier persona con perfil: admin, despachador, telefonista, conductor, propietario).
- Cada viaje en "Mis viajes" tiene "Quitar de este teléfono" (no cancela la reserva).
- Caché de la app del pasajero `fk-app-v2`.

## 15 nov 2026 · Portal de empresas: vista app (pasajero y encargado) y vista computador 
- **"Acceso clientes"** de la portada (español e inglés) ahora lleva al portal de empresas `/empresa/`: solo cuentas registradas por Flota-K, sin registro abierto. `/cuenta/` queda sin enlace.
- **Celular (app):** barra de navegación abajo, como app. El pasajero autorizado ve solo "Agendar" y "Mis viajes" con su presupuesto; el encargado ve además "Personas" y "Facturación". Encabezado compacto (🔑 contraseña, ⏻ salir). Las personas con acceso se muestran como tarjetas (antes la tabla no cabía).
- **Computador:** menú lateral, agendar en dos columnas (formulario y resumen con precio y botón fijo a la derecha), viajes en dos columnas, tabla de personas completa.
- **Instalable:** `/empresa/` se puede instalar como app "FK Empresas" desde el navegador (manifest y `empresa/sw.js`).

## 15 nov 2026 · Portal de empresas con convenio (/empresa)
- Dos tipos de usuario de la empresa cliente: **encargado de convenio** y **pasajero autorizado** (tabla `convenio_usuarios`; no son parte del equipo y no ven el panel).
- El admin crea la empresa y el primer acceso desde Clientes y cobros → Empresas → ficha → "Portal de empresas" (Edge Function `crear-usuario-convenio`, contraseña provisoria que el admin envía por WhatsApp). Al entrar, cambio de contraseña obligatorio.
- Datos de facturación obligatorios antes de agendar (razón social, RUT, giro, dirección, encargado de facturación, correo de facturas, orden de compra, centros de costo).
- Presupuesto mensual de la empresa y por persona; el encargado elige si al superarlo solo se avisa (la reserva queda con aviso 💰 en el despacho) o se bloquea.
- Servicios habituales con tarifa fija que carga el admin en la ficha de la empresa (`servicios_habituales`); en el portal se agendan con un toque.
- Reservas del portal: canal `convenio`, cobradas a la empresa con centro de costo; cancelación desde el portal hasta 2 horas antes.
- Base de datos: etapa 28 (portal) y 28b (se cierra la reserva pública antigua `crear_reserva_publica`, que ya no usaba ninguna página).

## 15 nov 2026 · Estado del vuelo con Flightradar24
- Panel y app del conductor: el vuelo abre Flightradar24 (avión en vivo y hora estimada real) en vez de la búsqueda de Google, más un enlace al sitio del aeropuerto (Nuevo Pudahuel). Funciones `FK.vueloFR24` / `FK.VUELO_PUDAHUEL` en assets/app.js.
- App del conductor, servicios de regreso con vuelo: aviso para revisar el vuelo 1 hora antes y al salir (los vuelos suelen adelantarse).

## 13 nov 2026 · Reserva en línea pausada y apps Android del pasajero y de operaciones
- A pedido del dueño: se quitó "Reservar en línea" de la portada; la app del pasajero (/app) queda solo con "Mis viajes" y "Contacto" (constante `RESERVA_EN_LINEA = false`). Las reservas las crea el equipo.
- Base de datos (etapa 27b): sin permiso para usar `crear_reserva_app` hasta que se active.
- Apps Android (.apk) "Flota-K Operaciones" (abre /equipo) y "Flota-K" del pasajero (abre /app), armadas con el mismo proyecto de la app del conductor (workflow `app-android-otras.yml`, releases `operaciones-android` y `pasajero-android`).

## 13 nov 2026 · App del pasajero y app de operaciones (pendiente de publicar)
- **App del pasajero** en `fk-servicios.com/app` (se instala en el teléfono desde el navegador, Android y iPhone, gratis):
  - Reservar: ida, regreso, ida y vuelta (regreso al valor de la ida) u otro trayecto; sector con tarifa fija; dirección con punto obligatorio en el mapa; auto o van; datos del pasajero recordados en el teléfono.
  - Mis viajes: los viajes quedan guardados en el teléfono (sin cuenta ni contraseña), con estado, conductor y vehículo, y enlace al seguimiento en vivo. Al abrir un enlace de seguimiento, el viaje también se agrega.
  - Contacto e incluidos. Mínimo 2 horas de anticipación (antes, por WhatsApp).
  - Base de datos: `crear_reserva_app` (etapa 27) guarda las coordenadas, canal `app`, máximo 6 solicitudes por teléfono por hora.
- **App Flota-K Operaciones**: el panel `/equipo` se puede instalar como app (teléfono o computador), con accesos directos a Nueva reserva, Reservas y Mapa.
- Portada: enlaces "Reservar en línea" a la app.

## 12 nov 2026 · Textos con tono ejecutivo en toda la página (pendiente de publicar)
- Portada (español e inglés) y las 13 páginas por comuna reescritas con tono de servicio ejecutivo: traslado privado puerta a puerta, seguimiento de vuelo en tiempo real, datos del conductor y del vehículo con seguimiento en vivo, disponibilidad a toda hora, convenio para empresas con detalle por pasajero y centro de costo. Sin cambios de precios ni de reglas (peajes y TAG en la RM, estacionamiento solo durante la espera, mascotas en canil, sin sillas para niños).
- Viajes a la costa: "Traslados ejecutivos a la costa · Santiago Oriente ↔ Viña del Mar y Valparaíso", auto ejecutivo $170.000 y van para grupos $240.000.

## 12 nov 2026 · Tarifa Sector Oriente ↔ Viña del Mar / Valparaíso (pendiente de publicar)
- Nueva tarifa fija por tramo (ida o regreso), sin pasar por el aeropuerto: **auto $170.000**, **van $240.000**. Sector Oriente = Las Condes, Vitacura, Lo Barnechea, Providencia, La Reina y Ñuñoa (`FK_INTERURBANOS` en `assets/tarifas.js`).
- Portada: sección "Viajes a la costa" con botones de WhatsApp; aparece en el buscador de tarifas al escribir Viña, Valparaíso u Oriente; mencionada en la pregunta frecuente. Página de Viña del Mar y Valparaíso: tabla nueva. Página en inglés: mencionada en la pregunta frecuente.
- Panel → Nueva reserva: si el origen y destino son Sector Oriente y Viña/Valparaíso (en cualquier sentido), sugiere y pone la tarifa (auto o van según el vehículo).

## 11 nov 2026 · Botón de la bolsa en Asignación (pendiente de publicar)
- En la ficha, el botón **"📢 Enviar a la bolsa"** ahora aparece también en la sección **Asignación** (antes solo estaba al final de la ficha). Si la reserva está "por confirmar", se explica que primero hay que confirmarla.

## 11 nov 2026 · Nota 4,96 y ubicación también desconectado (pendiente de publicar)
- **Vista anticipada de la bolsa con 4,96 o más** (`etapa26_nota_496_y_aceptacion_ubicacion`): minutos 0–10 móviles de Flota-K con 4,96+ (o sin ninguna calificación aún: si su primera nota no es 5, pierden la prioridad); minutos 10–20 conductores con 4,96+ y al menos 3 calificaciones; luego todos. En la Bolsa, cada conductor ve su nota y cuándo ve las reservas.
- **Ubicación también desconectado:** con la sesión iniciada, la app envía la ubicación cada 5 minutos aunque el conductor esté desconectado (cada 1 min conectado, cada 15 s en servicio). Aviso al conductor y **aceptación registrada** (`ubicacion_aceptada_en`), con guía para elegir "Permitir todo el tiempo" y batería "Sin restricciones" en los ajustes. En el mapa del panel, un desconectado se marca "sin señal" solo si pasan más de 7 minutos.
- Pendiente (requiere app Android nueva, conviene hacerlo con la llave de firma guardada): pedir el permiso de ubicación "todo el tiempo" desde la propia app.

## 11 nov 2026 · Orden de la bolsa y calificación 4,8 (pendiente de publicar)
- **"Buena calificación" = 4,8 o más** (antes 4,5). Las calificaciones se muestran con **dos decimales** (5,00 · 4,98…) en el panel y en la app del conductor.
- **Orden de la bolsa** (`etapa25_orden_bolsa_y_calificacion_48`), servicios programados: minutos 0–10 solo **móviles de Flota-K con buena calificación** (o nuevos, con menos de 3 calificaciones); minutos 10–20 se suman los **conductores destacados** de toda la red (4,8+); desde el minuto 20, **toda la flota**.
- **Servicios de momento** (dentro de 2 horas): **sin prioridad** en la bolsa. En la ficha, los conductores sugeridos se ordenan por **cercanía real según su GPS en vivo** ("📍 está a ~6 min del retiro · llega con 34 min de margen"), con aviso si llegaría con menos de 15 min de margen.

## 11 nov 2026 · Ajustes a la bolsa a pedido del dueño (pendiente de publicar)
- **La bolsa la libera el despachador** (`etapa24_bolsa_manual_prioridad_moviles_flotak`): la bolsa automática queda **apagada** por defecto (nueva marca `bolsa_auto_activa`); se puede activar en Equipo y roles solo para casos especiales.
- **Prioridad en la bolsa** para los **móviles de Flota-K** (conductores con vehículo propio de Flota-K) además de los conductores destacados. Ventana de 10 minutos, o **5 minutos si el servicio es de momento** (dentro de las próximas 2 horas); antes, los servicios próximos no tenían prioridad.

## 11 nov 2026 · Bolsa automática, prioridad, punto del pasajero y mapa del día (pendiente de publicar)
- **Bolsa automática** (`etapa23_bolsa_auto_prioridad_retiro_pasajero`, tarea programada `flotak-bolsa-automatica` cada 5 min con pg_cron): las reservas confirmadas sin conductor se liberan solas a la bolsa X horas antes (por defecto 6; se cambia o desactiva en Equipo y roles). Las recién creadas esperan 15 min. Se hace una sola vez por reserva y queda en el historial.
- **Prioridad para conductores destacados:** los primeros 10 minutos en la bolsa, el servicio solo lo ven y toman conductores con promedio 4,5★ o más (mínimo 3 calificaciones en 90 días), si faltan más de 2 horas. Luego queda para todos.
- **El pasajero confirma su punto de retiro** en su enlace de seguimiento: mueve el pin y deja indicaciones (ej.: "Torre B, portón negro"), hasta 20 min antes y a menos de 2 km de la dirección reservada. El conductor recibe aviso y ve las indicaciones; queda en el historial y en la ficha. El WhatsApp de confirmación invita a hacerlo.
- **Mapa de los servicios del día:** en "Mapa en vivo" y en el mapa al lado del despacho, los puntos de retiro con su hora y color (rojo sin conductor, dorado en la bolsa, azul con conductor, verde en curso), junto a los conductores. Tocar un punto abre la ficha.

## 11 nov 2026 · Encadenar servicios, distancia real, bono y devolver a la bolsa (pendiente de publicar)
- **Distancia y tiempo reales** (OSRM con datos de OpenStreetMap, gratis; +25% por tráfico): en Nueva reserva se muestran km y minutos del viaje y se guardan en la reserva. La duración del servicio queda como viaje + 10 min (o + 30 min en regresos del aeropuerto, por la espera). Mejora los choques de horario, la agenda y la bolsa.
- **Conductor sugerido encadenando servicios:** en la ficha, hasta 3 conductores sugeridos que llegan con **al menos 15 minutos de margen**, considerando el servicio que terminan antes (y el que tienen después). Primero el que termina cerca ("🔗 termina FK-X en Las Condes a las 8:20, llega en ~5 min y le quedan 35 min de margen"). Avisa si alguien "llegaría justo". Muestra también quién está conectado y cuántos servicios devolvió a la bolsa.
- **Bono en la bolsa** (`etapa22_bono_y_devolucion_bolsa`): al liberar se puede ofrecer un bono (ej.: $5.000) para quien lo tome; el conductor lo ve destacado y queda en su servicio y en el historial.
- **Devolver a la bolsa:** el conductor que no podrá hacer un servicio lo devuelve desde su app hasta 3 horas antes; queda contado, en el historial y la central recibe un mensaje. Con menos de 3 horas debe llamar a la central.

## 11 nov 2026 · Bolsa de servicios y van con precio único (pendiente de publicar)
- **Bolsa de servicios** (`etapa21_bolsa_de_servicios`): el despachador libera una reserva confirmada y futura a la bolsa (ficha → "📢 Liberar a la bolsa", o varias a la vez en Reservas → Seleccionar varias). Si tenía conductor, se le quita. En el despacho aparece "📢 En la bolsa" y hay filtro "En la bolsa de servicios" en Reservas. "↩ Retirar de la bolsa" la saca.
- **App del conductor → pestaña "✋ Bolsa"** (con contador): ve fecha, hora, tipo, zona de origen y destino, pasajeros, maletas, vehículo que pide, vuelo, valor y lo que le corresponde. **No ve** el nombre ni el teléfono del pasajero ni la dirección exacta hasta tomarlo. Se toma **deslizando**. Aviso con sonido y notificación cuando la central libera un servicio que le sirve.
- **Solo uno puede tomarlo**: la base de datos lo asigna al primero; el segundo recibe "Otro conductor ya tomó este servicio". No puede tomarlo si su vehículo no corresponde (van solo con van; SUV con SUV o van) o si se le cruza con otro servicio suyo. Queda en el historial: "Tomado desde la bolsa por Móvil X".
- **Tarifario:** la van cobra lo mismo de ida o de regreso: el botón ahora dice "Van".
- **Alerta de bolsa:** si falta 1 hora o menos y nadie tomó el servicio, el despacho lo marca en rojo "⚠ Nadie la tomó de la bolsa: asigne a mano", con sonido y notificación. Antes de eso aparece en gris "📢 En la bolsa" (sin la alerta roja de "Sin asignar").

## 11 nov 2026 · Punto obligatorio en el mapa al agendar (pendiente de publicar)
- **Nueva reserva (panel):** origen y destino con **autocompletar** mientras se escribe (OpenStreetMap vía Photon, gratis) y **mapa con pin arrastrable**. Botón "✈ Aeropuerto SCL". **No se puede guardar sin marcar los dos puntos.** Al tocar o arrastrar el pin, muestra la dirección de ese punto y ofrece usarla. Mensaje de WhatsApp, cliente registrado ("mismo trayecto" / "de vuelta"), Duplicar y Crear regreso traen también los puntos.
- Base de datos (`etapa20_coordenadas_origen_destino`): coordenadas de origen y destino en cada reserva.
- **App del conductor:** Waze y Google Maps navegan a las **coordenadas exactas** del pin; el mapa del Inicio usa ese punto. Reservas antiguas sin punto siguen con la dirección escrita.
- Ficha de la reserva: enlace "📍 ver punto" (o aviso "sin punto en el mapa").
- **Tarifario de aeropuerto automático:** con los pines, el panel detecta si el viaje va o viene del aeropuerto (marca solo "Ida" o "Regreso"), toma la comuna del otro punto y muestra **todas las tarifas de esa comuna** (cada sector con ida, regreso y van), con la que corresponde marcada; un toque pone el precio. Si la comuna tiene un solo sector, el precio se pone solo. Buscador para elegir otra comuna del tarifario.

## 10 nov 2026 · Más capacidad y avisos en vivo, gratis (pendiente de publicar)
- **Sin tope de 1.000 filas** (`etapa18_resumenes_en_servidor`): los totales de Clientes y cobros, empresas y "por cobrar" se calculan en la base de datos; la ficha de cada cliente o empresa trae todos sus servicios; reportes, base de clientes, cierres, la app del conductor y el portal del propietario traen todo por partes. La pestaña Central siempre muestra los mensajes más nuevos (antes, pasando los 1.000 mensajes, dejaban de aparecer). Índices nuevos para que las búsquedas sigan rápidas.
- **Avisos en vivo** (`etapa19_avisos_en_vivo`, Supabase Realtime): el panel y la app del conductor se actualizan al instante cuando cambia una reserva o llega un mensaje. Con la conexión en vivo, la revisión completa pasa de cada 30 segundos a cada 1–2 minutos (las alertas por hora y GPS se recalculan cada 30 s sin volver a traer todo). Si la conexión en vivo falla, todo vuelve solo a revisar cada 30 segundos. Las ubicaciones GPS no van por esta vía (superarían el límite gratis).
- Indicador "● En vivo" en el despacho y en la app del conductor.

## 10 nov 2026 · Reportes del conductor en la Billetera (pendiente de publicar)
- **Mis reportes** con período a elección (hoy, semana, mes, mes anterior, 30 días o fechas): ganado y comparación con el período anterior, servicios y promedio, **le corresponde** (descontando la comisión de Flota-K de su vehículo, si tiene), **ganancia por hora en servicio**, ingreso por km, TAG y peajes, clientes por pagar, calificación, **puntualidad** y proyección del mes.
- **Utilidad con todas sus apps** (vehículos de Flota-K con cierre diario): Flota-K + Cabify + otras − TAG/peajes − combustible − otros gastos, por km y con el costo de referencia de $410/km.
- Gráfico de lo ganado por día, por tipo de servicio, trayectos más frecuentes y comentarios de pasajeros.
- **¿Cuándo le conviene trabajar?**: promedio por día de la semana y por horario (últimos 90 días).
- Liquidación del período (imprimir/PDF), **planilla para Excel** y envío por correo. La meta del mes muestra cuánto falta por día.
- Arreglo: el mapa del Inicio ya no aparece en la Billetera.

## 10 nov 2026 · App del conductor: avisos de cambios y actualizar a mano (pendiente de publicar)
- **Avisos con sonido, vibración y notificación** cuando: le asignan un servicio, se lo quitan (reasignado o eliminado), lo cancelan, o le cambian la hora, el retiro o el destino. Quedan en pantalla hasta tocar "Entendido". También avisa al abrir la app si algo cambió mientras estaba cerrada.
- **Botón "⟳ Actualizar"** y **deslizar hacia abajo** (desde arriba de la pantalla) para actualizar al instante. La lista se sigue actualizando sola cada 30 segundos y al volver a la app.

## 10 nov 2026 · El conductor registra su vehículo y errores en español (pendiente de publicar)
- **App del conductor → Perfil → Mi vehículo:** el conductor nuevo registra su vehículo (patente, marca, modelo, año, color, categoría, pasajeros y foto) y puede editarlo. En el inicio le aparece un aviso si aún no lo registra. Los documentos del vehículo (permiso de circulación, revisión técnica, SOAP, seguro, padrón) se suben desde "Subir documento". La central recibe un mensaje automático para revisarlo.
- Base de datos (`etapa17_conductor_registra_vehiculo`): `conductor_guardar_vehiculo` (no permite tocar vehículos de Flota-K ni repetir patentes; queda como vehículo de prestador), foto solo en su carpeta, documentos solo de su propio vehículo. Probado con reversión.
- **Errores en español** en todas las páginas (ej.: "La contraseña nueva debe ser distinta de la actual"). Cambiar contraseña ahora permite ver lo que se escribe.

## 10 nov 2026 · Cuentas del equipo sin correo (pendiente de publicar)
- Problema: el correo gratuito de Supabase solo llega a direcciones del propio equipo de Supabase (y máximo 2 por hora), así que las invitaciones a correos externos nunca llegaban (Paola estaba invitada desde el 9 nov sin poder entrar).
- **Paola Quichiz** (plquichiz@gmail.com) creada como **administradora** con contraseña provisoria.
- Función nueva `crear-miembro` (Supabase Edge Function, gratis): el administrador crea la cuenta con correo, rol y contraseña provisoria, y le envía los datos por WhatsApp. También **"🔑 Nueva contraseña"** para quien la olvide (solo personas de la misma empresa). Usa la clave de servicio solo dentro de Supabase; nunca llega al navegador.

## 10 nov 2026 · Panel del despachador: celular, avisos, resumen y más (pendiente de publicar)
- **Celular:** barra inferior (Despacho, Reservas, Nueva, Mapa, Más), botones y campos más grandes, y el tablero se ve como tarjetas.
- **Avisos con sonido y notificación del navegador** (botón "🔔 Activar avisos"): reserva nueva y toda alerta roja nueva (sin conductor, atrasado, pasajero pide ayuda, pasajero sin mapa). Siguen llegando con la pestaña en segundo plano.
- **Alertas de GPS:** "Pasajero no ve al conductor (sin GPS)", "GPS con retraso" y "Conductor sin GPS activo" antes del retiro. En la ficha: estado del mapa del pasajero y botón **"👁 Ver lo que ve el pasajero"**.
- **Resumen del día en cuadros** (servicios, sin asignar, alertas, ganado hoy, por cobrar, conductores); se pueden tocar para filtrar.
- **Duplicar** y **Crear regreso** (origen y destino invertidos) desde la ficha.
- **Mensajes de WhatsApp por momento:** confirmación, recordatorio del día anterior, conductor en camino, conductor llegó, gracias + calificar (elige solo el adecuado según el estado).
- **Agenda en línea de tiempo** por conductor (bloques por hora, choques en rojo, línea de la hora actual); se mantiene la vista en columnas.
- **Acciones en grupo** en Reservas: confirmar varias y marcar varias como pagadas (solo administrador).
- **Etiquetas de cliente** (`etapa16_etiquetas_clientes`): VIP, Frecuente, Empresa, Requiere factura, Paga tarde, Mascota en canil, Llamar al llegar, Exigente. Se ven en el despacho, la ficha y al tomar una reserva.
- **Buscador único** arriba del panel: reservas (código, nombre, teléfono, dirección, vuelo) y clientes.

## 10 nov 2026 · Eliminar reservas con papelera (pendiente de publicar)
- Base de datos (`etapa15_eliminar_reservas_papelera`): "eliminar" no borra; la reserva queda cancelada y **oculta en todas partes** (despacho, agenda, reportes, cobros, app del conductor), con motivo, fecha y quién la eliminó. Solo el administrador; no se puede eliminar un servicio en curso. `restaurar_reserva` la devuelve con el estado que tenía. Probado (con reversión): oculta, aparece en la papelera, se restaura y un no administrador queda bloqueado.
- Panel → ficha de la reserva: botón **"Cancelar reserva"** (pide motivo, queda en el historial) y, para el administrador, **"Eliminar"**. Reservas → filtro **"Eliminadas (papelera)"** con botón **Restaurar**.

## 9 nov 2026 · Cierre diario solo con km recorridos (pendiente de publicar)
- A pedido del dueño, el cierre ya no pide odómetro inicial y final: solo **los kilómetros recorridos en el día** (Flota-K + Cabify + otras). Función nueva `guardar_cierre_km` (`etapa14b_cierre_solo_km`); la anterior queda sin uso. El Excel del panel ya no trae columnas de odómetro.

## 9 nov 2026 · Cierre diario de vehículos propios de Flota-K (pendiente de publicar)
- Base de datos (`etapa14_cierre_diario_vehiculos_propios`): marca **vehículo propio** (por defecto sí; a los prestadores se les quita); tabla de cierres diarios (odómetro, Cabify: ingreso/viajes/peajes, otras apps, combustible, otros gastos, notas); `guardar_cierre` solo funciona con el vehículo fijo del conductor si es propio (hoy o últimos 7 días; corrige si ya existe). Probado: bloquea km negativos, fechas antiguas y vehículos de prestador.
- **App del conductor → Billetera → "Cierre del día"** (solo si su vehículo es propio; los prestadores no lo ven): odómetro (sugiere el último), Cabify, otras apps y gastos; Flota-K se suma solo (servicios finalizados del día y sus TAG/peajes). Muestra km, ingresos (% Flota-K y apps), gastos directos, **costo/km, ingreso/km, ganancia/km** y el resultado con el **costo de referencia $410/km**.
- **Panel → Reportes → "Cierres diarios"**: totales del período y tabla por día y vehículo, con descarga en Excel. **Flota**: casilla "Propio de Flota-K (cierre diario)" en cada vehículo.
- Los montos negativos se muestran como "-$7.500".

## 9 nov 2026 · Portal del propietario de vehículos (pendiente de publicar)
- Base de datos (`etapa13_rol_propietario`, `etapa13_portal_propietario`): rol nuevo **propietario**; cada vehículo puede tener propietario y **comisión de Flota-K (%)**. Funciones `propietario_vehiculos` y `propietario_servicios` (solo sus vehículos; trayecto por comuna; sin nombre ni teléfono de pasajeros). Probado: el dueño ve lo suyo y un usuario ajeno no ve nada.
- Página nueva **fk-servicios.com/propietario**: vehículos con foto, conductor, estado de documentos y comisión; totales del período (servicios, total generado, le corresponde, comisión, clientes por pagar, km taxímetro); gráficos por vehículo, conductor y tipo de servicio; tabla de servicios; **liquidación en Excel**.
- Panel: invitar con rol "Propietario de vehículo"; en Flota, cada vehículo tiene **Propietario** y **Comisión Flota-K %**. Un propietario que entra a /equipo es dirigido a su portal.

## 9 nov 2026 · Mejoras de uso en ruta (pendiente de publicar)
- **Conductor:** deslizar para confirmar (Voy en camino, Llegué, Pasajero a bordo, Finalizar; también con Enter); **modo en ruta** en el Inicio con el servicio en curso (lo esencial en grande; "Ver detalles"); **cuenta regresiva** "Sale en X min" / "Atrasado"; **aviso de documentos** vencidos o por vencer (30 días) al abrir; **meta del mes** en la Billetera con barra de avance; aviso **"Sin conexión"**; el recordatorio en pantalla ahora aparece arriba (no tapa la barra).
- **Pasajero:** botón **"Compartir mi viaje"** (enlace en vivo para un familiar).
- **Despacho:** **resumen del día** sobre el tablero (servicios de hoy, valor, finalizados, en curso, sin asignar y conductores conectados).
- Pendiente (requiere cuenta del dueño): estado del vuelo dentro de la app con un servicio de vuelos (AeroDataBox o AviationStack).

## 9 nov 2026 · Rediseño de la app del conductor (pendiente de publicar)
- **Inicio con mapa:** su posición (con su número de móvil) y el punto al que debe ir (retiro, o destino si el pasajero va a bordo), y la tarjeta del servicio en curso o del **próximo** (ya no el último realizado). Enlace "Ver los N de hoy".
- **Barra de navegación abajo:** Inicio · Servicios · Billetera · Perfil. Servicios con "Hoy" y "Próximos días"; primero lo pendiente y al final "Realizados" (sin botones de navegación).
- **Encabezado compacto:** foto (lleva al Perfil), "Móvil 286 · Juan · patente", lo ganado hoy y el botón Conectado/Desconectado. Se quitaron "Actualizar" y "Salir" de arriba (cerrar sesión está en Perfil).
- **Botón "Navegar" (Waze)** que lleva al retiro o, con el pasajero a bordo, al destino.
- **Llamar y WhatsApp al pasajero desaparecen al finalizar** el servicio.
- Perfil con foto grande, móvil y estado de conexión.
- **Modo oscuro por defecto** (se puede cambiar en Perfil).
- El diagnóstico en pantalla solo avisa si falla un archivo imprescindible (si el mapa no carga, la app sigue funcionando).

## 9 nov 2026 · Quien reserva y paga distinto del pasajero; confirmación por WhatsApp; copiar reserva (pendiente de publicar)
- Base de datos (`etapa12_solicitante_distinto_del_pasajero`): la reserva guarda nombre, teléfono y correo de quien reserva y paga; el cliente (cobranza) se toma de esa persona. Probado: una reserva para la suegra de Fernando queda en la ficha de Fernando.
- "Nueva reserva": casilla **"Viaja otra persona"** con nombre y teléfono del pasajero; el cliente buscado es quien reserva y paga.
- Ficha: "Reservado y pagado por …"; botones **"Enviar confirmación al pasajero"** y **"a quien reservó"** (abre WhatsApp con código, fecha, origen, destino, vuelo, móvil, vehículo y enlace de seguimiento); **"Copiar reserva"** (abre Nueva reserva con los mismos datos, falta la fecha).
- Tablero: "paga: …" bajo el pasajero. App del conductor: "Reservado por …".

## 9 nov 2026 · Chat solo con servicio activo y ayuda a la central (pendiente de publicar)
- Base de datos (`etapa11_chat_activo_y_ayuda_central`): los mensajes tienen canal ("viaje" o "central"), tema (objeto perdido, ayuda, otro) y si fueron atendidos. El chat pasajero-conductor solo funciona en camino, en el lugar o a bordo; al finalizar se cierra. El conductor no ve el canal central. Funciones nuevas: `enviar_central_publico`, `enviar_mensaje_central`, `ver_mensajes_publico_v2`.
- **Pasajero:** el chat con el conductor aparece solo con el servicio en curso. Nueva sección "¿Necesita algo? Escriba a Flota-K" con **Olvidé un objeto**, **Necesito ayuda** y **Otra consulta** (llega solo a la central; la respuesta aparece ahí mismo; hasta 60 días después del viaje).
- **Conductor:** el botón "Mensajes con el pasajero" aparece solo con el servicio en curso. La central le sigue escribiendo por Perfil → Central.
- **Panel:** alerta roja en el tablero ("Objeto perdido", "Pasajero pide ayuda", "Consulta del pasajero"); en la ficha, dos conversaciones (viaje y pasajero ↔ central); en la pestaña Central, lista "Solicitudes de pasajeros" con las pendientes arriba; el contador de la pestaña Central suma estas solicitudes.

## 9 nov 2026 · Tanda grande de mejoras para despacho, conductor y pasajero (pendiente de publicar)
- Base de datos (`etapa10_respuesta_conductor_historial`): el conductor acepta o rechaza el servicio (al rechazar queda libre para reasignar); historial de cambios de cada reserva (quién cambió qué); serie para reservas recurrentes; enlace del pasajero v2 con fotos (`ver_reserva_publica_v2`, la anterior no se tocó). Probado con datos que se deshacen.
- **Despacho:** reserva rápida pegando el mensaje de WhatsApp (lee fecha, hora, vuelo, teléfono, correo, nombre, pasajeros, maletas, van/SUV, ida o regreso y comuna); reservas recurrentes (semanal, lunes a viernes o diario, hasta 60); conductor sugerido en la ficha (libre, con vehículo adecuado y conectado); notas internas del cliente (se ven al tomar su reserva y en su ficha); historial de cambios en la ficha; alertas "Conductor rechazó" y "Conductor no ha aceptado"; mapa al lado del tablero (opción "Ver mapa al lado").
- **Conductor:** aviso de servicio nuevo con sonido, vibración y notificación, con botones **Aceptar** / **No puedo**; recordatorios 2 h y 45 min antes (en la app Android quedan programados aunque esté cerrada; también aviso en pantalla); mensajes rápidos al pasajero; cronómetro de espera al llegar (15 min domicilio; 45 min / 1 h aeropuerto) que avisa cuando se pasa; modo noche y letra grande; liquidación del mes para imprimir/guardar en PDF o enviarse por correo.
- **Pasajero:** el enlace de seguimiento muestra foto, nombre, móvil y calificación del conductor, y foto, modelo, color, año y patente del auto; tiempo estimado de llegada mientras va en camino (aproximado, con OpenStreetMap); "Agregar a mi calendario" (aviso 2 h antes); "Reservar mi regreso" por WhatsApp.
- **Cuenta del cliente:** próximos y anteriores, viajes del año, pendiente de pago, direcciones frecuentes, "Repetir este viaje" y "Reservar el regreso".
- **Página en inglés** completa en `/en/` con el cotizador (mismo tarifario); enlace desde la sección English de la principal; hreflang y sitemap.
- La librería de Supabase se sirve desde el sitio en todas las páginas (antes, desde un servidor externo).
- **Respaldo semanal** automático a Google Drive (carpeta "Flota-K Respaldos"), domingos 22:43, solo lectura (rutina trig_01AYcPA7jYwiUfSLDULeAFAi).

## 9 nov 2026 · Categorías de vehículo y número de móvil (pendiente de publicar)
- Base de datos (`etapa9_categorias_y_movil`): categoría del vehículo (Taxi básico, Taxi turismo, Taxi ejecutivo, SUV, Van) y número de móvil por conductor (único). La nota del historial al asignar incluye el móvil.
- El servicio indica qué vehículo pide (campo existente): **Auto** (lo hace cualquiera), **SUV** (SUV o van) o **Van** (solo van).
- Al asignar (tablero o ficha), los conductores aparecen como **"286 · Juan Kieferling · SSHY88 Virtus"**, ordenados por móvil; los que no calzan llevan ⚠ y, si se eligen, se pide confirmación ("Este servicio es de Van y va a asignar un Taxi ejecutivo… ¿Está seguro?"). El despachador decide.
- Flota: número de móvil en cada conductor; categoría editable en cada vehículo; al agregar un vehículo el **conductor fijo es obligatorio**; aviso "Sin conductor fijo" en los vehículos que no lo tienen.
- App del conductor: muestra "Móvil 286 · Juan Kieferling".
- Pendiente del dueño: en Flota, poner la categoría **Taxi ejecutivo** al Virtus SSHY88 y su móvil **286**.

## Pendientes acordados con el dueño
- Correos automáticos al cliente (confirmación, conductor asignado, en camino, calificación): queda para más adelante. Requiere cuenta gratis en Resend, registros DNS del dominio en Squarespace (con visto bueno del dueño) y la clave guardada por el dueño en Supabase.
- Llave de firma de la app Android en GitHub (secretos FK_KEYSTORE_PASS y FK_KEYSTORE_B64).
- Enlace de reseñas de la ficha de Google (`resenaGoogle` en `assets/config.js`).

## 9 nov 2026 · Flota, documentos y app del conductor con perfil (pendiente de publicar)
- Base de datos (`etapa8_vehiculos_documentos_conductor`): vehículo con marca, modelo, año, color y foto; foto y teléfono del conductor; tabla de documentos con vencimiento y estado (pendiente, aprobado, rechazado); archivos en Supabase Storage (`fotos` público, `documentos` privado); conductor conectado/desconectado; chat del conductor con la central. Probado con datos que se deshacen.
- Panel, pestaña **Flota** (administrador): tarjetas de conductores (foto, conectado, teléfono, vehículo, estado de documentos) y vehículos (foto, conductor fijo, documentos, dar de baja). Agregar vehículo con **marca autocompletada, modelos de esa marca, año y color de lista** y foto. Tabla de documentos con filtros (vencidos o por vencer, por revisar), ver archivo, aprobar o rechazar. Aviso arriba si hay documentos vencidos o por revisar. Las fotos se achican antes de subir.
- Panel, pestaña **Central**: mensajes de los conductores con contador de no leídos; el despacho responde desde ahí.
- Mapa en vivo: los conductores desconectados aparecen en gris como "Desconectado".
- App del conductor: botón **Conectado / Desconectado** (desconectado no comparte ubicación, salvo con un servicio en curso; al cerrar sesión se desconecta). Pestaña **Billetera** (antes Ganancias). Pestaña **Perfil**: foto, teléfono, calificación, su vehículo con documentos, **sus documentos y "Subir documento"** (queda en revisión), **chat con la central** (con aviso de mensajes nuevos), llamar a la central, cambiar contraseña y cerrar sesión.
- El enlace del pasajero no cambió por ahora (decisión del dueño).

## 9 nov 2026 · Cuentas de empresa (pendiente de publicar)
- Base de datos (`etapa7_cuentas_empresa`): cada reserva guarda la empresa a la que se cobra (se toma del pasajero al crearla) y un **centro de costo**; la empresa tiene días de pago y si el convenio está activo. Probado con datos que se deshacen.
- "Clientes y cobros" ahora tiene **Personas / Empresas**. En Empresas: crear empresa (razón social, RUT, contacto, correo de facturación, días de pago), **pasajeros autorizados** (buscar y agregar o quitar), servicios del período con su centro de costo, resumen por centro de costo, marcar pagados, **planilla Excel para facturar** (con RUT y resumen por centro de costo) y "Cobrar por correo" al correo de facturación.
- "Nueva reserva": campo **Centro de costo** y aviso "Se cobra a la empresa: …" al elegir un pasajero de empresa. La ficha de la reserva muestra la empresa y el centro de costo.
- Corregido: los botones Personas/Empresas se confundían con los filtros del tablero.

## 9 nov 2026 · Tarifario compartido y precio sugerido (pendiente de publicar)
- El tarifario 2026 pasó a `assets/tarifas.js`; la página principal (cotizador por comuna con reserva por WhatsApp) lo usa igual que antes.
- En "Nueva reserva" del panel aparece la **tarifa sugerida** según la comuna de la dirección (ida, regreso o van); un toque la pone como precio.

## 9 nov 2026 · Reportes y cobranza (pendiente de publicar)
- Pestaña **"Reportes"** (solo administrador): ingresos de servicios finalizados, ticket promedio, por cobrar y cobrado, servicios agendados y cancelados, margen de lo derivado a la red, km de taxímetro con costo operativo estimado ($410/km). Gráfico de ingresos por día y desgloses por canal, tipo de servicio, conductor y mejores clientes. Períodos: este mes, mes anterior, últimos 30 días, este año. Descarga en Excel.
- **Cobranza** en la ficha del cliente: "Cobrar por WhatsApp" y "Cobrar por correo" arman el mensaje con el detalle de servicios pendientes y el total; el envío lo hace el dueño desde su WhatsApp o su correo.

## 9 nov 2026 · Tablero de despacho compacto (pendiente de publicar)
- Pestaña nueva **"Despacho"** (la primera al entrar): una línea por servicio con hora, código y estado, pasajero (pax y maletas), trayecto, vuelo, conductor y patente, valor y estado de pago, y alertas.
- **Alertas:** Por confirmar (reserva web nueva, con sonido y título parpadeante), Sin asignar (rojo si faltan menos de 2 h), Debía salir (faltan 45 min o menos y no va en camino), Atrasado, Llegada tarde, Esperando (15 min o más en el lugar), Mensaje sin responder, Observación y Calificación baja.
- Lo urgente arriba (borde rojo o dorado), luego en curso, próximos y finalizados. Filtros: Todo, Requiere atención, Sin asignar, En curso, Hoy.
- **Asignar conductor directo en la fila** (pone el vehículo habitual y avisa si se cruza con otro servicio).
- **Número de vuelo como enlace**: abre en Google el estado del vuelo (también en la ficha de la reserva).
- Se actualiza solo cada 30 segundos.

## 9 nov 2026 · Nueva reserva con clientes registrados
- En "Nueva reserva" hay un buscador de clientes (nombre, teléfono o correo). Al elegir uno se completan nombre, teléfono y correo, y las preferencias de su último servicio (forma de pago, tipo de cobro, vehículo, pasajeros, maletas). Botones "Mismo trayecto" y "Trayecto de vuelta" (invierte origen/destino y el tipo ida/regreso, con el precio anterior).
- Si se escribe a mano un teléfono o correo que ya es de un cliente, avisa "Este contacto ya es cliente" con "Usar sus datos".
- La reserva queda unida a ese cliente.

## 9 nov 2026 · Cobros: todo servicio queda pendiente hasta que administración lo marque pagado
- Corregido: "Clientes y cobros" mostraba $0 pendiente porque al agregar las calificaciones se cruzó el orden de dos consultas (leía calificaciones en vez de cobros).
- Regla nueva del dueño: todo servicio no cancelado (realizado o por realizar) queda **pendiente de pago** hasta que un administrador lo marque como pagado. Aplica a la lista de clientes, la ficha del cliente, el filtro "Por cobrar (no pagados)" y la planilla Excel (que ahora incluye la columna "Estado del servicio").
- La ficha del cliente muestra por defecto todos los servicios (sin fecha "hasta"); un taxímetro aún no finalizado aparece como "se calcula al finalizar".

## 9 nov 2026 · Arreglo de la pantalla en blanco en la app Android (pendiente de publicar)
- Causa (vista gracias al nuevo diagnóstico en pantalla): dentro de la app faltaba la librería de Capacitor que conecta la página con Android (`registerPlugin`). Ahora se carga desde `assets/vendor/capacitor-core-6.2.3.js` (en el navegador no hace nada).
- La librería de Supabase también se sirve desde el sitio (`assets/vendor/supabase-2.45.4.js`); dentro de la app se omite el "candado" de sesión que puede quedarse pegado.
- Si algo impide cargar la app del conductor, aparece un recuadro rojo con el motivo y "Reintentar".
- La app Android ya no reenvía todas las conexiones por Android (causaba problemas); solo el envío de ubicación usa la conexión nativa.

## 9 nov 2026 · Calificaciones y mensajes (pendiente de publicar)
- **Calificaciones:**
  - El pasajero califica al conductor (1 a 5 estrellas + comentario) desde su enlace de seguimiento cuando el servicio finaliza (una vez, hasta 30 días). Si da 5 estrellas y está configurado `resenaGoogle` en `assets/config.js`, se le invita a dejar reseña en Google (pendiente: enlace de reseñas de la ficha de Google).
  - El conductor califica al pasajero en su app (interno: el pasajero no lo ve) y ve cómo lo calificaron.
  - Panel: calificaciones en la ficha de la reserva (con "Marcar revisada"), filtro "Calificación baja por revisar", promedio por cliente en "Clientes y cobros" y promedio por conductor en el mapa. En "Ganancias", el conductor ve su promedio de 90 días.
- **Mensajes por servicio** entre pasajero, conductor y despacho (sin compartir números): abiertos desde que hay conductor asignado hasta 3 horas después de finalizar. El conductor ve un contador de no leídos, vibración y notificación en la app Android. El despacho los ve y puede escribir como "Flota-K" desde la ficha; filtro "Con mensajes (últimas 24 horas)".
- **App Android de prueba** (mientras falta la llave): https://github.com/FLOTAK286/flota-k-web/releases/download/conductor-android-prueba/flota-k-conductor.apk
- Probado en base de datos (bloqueos: doble calificación, enlace falso, personas ajenas, chat cerrado o vacío) y en las tres pantallas con datos de prueba.

## 9 nov 2026 · Pestaña "Ganancias" en la app del conductor (pendiente de publicar)
- Muestra lo generado hoy, esta semana (desde el lunes) y este mes, con cantidad de servicios, gastos incluidos y lo que falta por cobrar. Debajo, la lista de servicios finalizados del mes (pagado / por cobrar).
- Cada conductor ve solo sus servicios (probado en base de datos).
- Seguridad de la app Android: GitHub ya no arma la app si falta la llave de firma; `app-android/version.json` queda en 1 hasta que la llave esté guardada (luego se sube a 2 y aparece el aviso "Actualizar app").

### Pendiente del dueño
- Guardar los secretos `FK_KEYSTORE_PASS` y `FK_KEYSTORE_B64` en GitHub (archivo llave-flota-k.txt enviado el 9 nov). Recordatorio programado.

## 9 nov 2026 · Actualización automática de la app Android (pendiente: llave de firma)
- La app abre la página, así que **todas las mejoras de pantallas y funciones llegan solas**, sin descargar nada.
- Si cambia la parte instalada (pocas veces), la app muestra "Hay una versión nueva" con un botón "Actualizar app" que se instala encima. La versión se lleva en `app-android/version.json`.
- Para instalar encima, todas las versiones deben ir firmadas con la misma llave. La llave se guarda solo como secreto de GitHub (`FK_KEYSTORE_B64`, `FK_KEYSTORE_PASS`), nunca en el código. **Pendiente: falta crear y guardar esa llave (requiere permiso del dueño).**

## 9 nov 2026 · Mapa del despacho con disponibilidad y retiro de la app de Chrome (pendiente de publicar)
- **Mapa en vivo (despacho):** cada conductor aparece con su estado: verde disponible, dorado disponible con servicio en menos de 1 hora, rojo ocupado (en camino / en el lugar / a bordo), gris sin señal. La lista muestra el servicio actual, el próximo servicio agendado (36 horas) y el resumen "X disponibles · Y ocupados · Z sin señal". También aparecen los conductores que nunca han abierto la app.
- **App del conductor:** se retiró la versión instalable desde Chrome (obsoleta). En Android la página ahora ofrece "Descargar app" (la app Android) y explica cómo desinstalar la versión anterior.

## 9 nov 2026 · App Android del conductor (pendiente de publicar)
- App Android instalable (`app-android/`, hecha con Capacitor, gratis). Abre fk-servicios.com/conductor, así que todo cambio a la página llega solo a la app sin reinstalar.
- **Sigue enviando la ubicación con Waze, Cabify u otra app abierta**, con una notificación fija "Flota-K Conductor · Compartiendo su ubicación…". Si el permiso está bloqueado, el botón "Activar" abre los ajustes de la app.
- GitHub arma el archivo automáticamente (`.github/workflows/app-android.yml`) cada vez que cambia `app-android/`. Descarga: https://github.com/FLOTAK286/flota-k-web/releases/download/conductor-android/flota-k-conductor.apk
- Nota: el aviso de permisos de Android no aparece si otra app muestra una burbuja encima (por ejemplo, Cabify). Se da el permiso desde Ajustes → Apps → Flota-K Conductor → Permisos → Ubicación.
- Pendiente: cada armado usa una firma distinta; si algún día hay que reinstalar, se desinstala la anterior primero (casi nunca hará falta, porque las mejoras llegan por la página).

## 9 nov 2026 · Etapa 5: ubicación en vivo del conductor (pendiente de publicar)
- **App del conductor:** al abrirla, comparte su ubicación (cada 15 s con un servicio en curso, cada minuto sin servicio). Muestra un aviso verde "Compartiendo ubicación…" o, si está bloqueada, cómo activarla. Durante el servicio mantiene la pantalla encendida.
- **Pasajero (/seguimiento):** cuando el servicio está "En camino", "Llegó al lugar" o "A bordo", ve un mapa con el auto, actualizado cada 15 s. Fuera de esos estados no ve nada (privacidad del conductor).
- **Despacho (/equipo → "Mapa en vivo"):** todos los conductores en el mapa, con su servicio, pasajero, destino, velocidad y hace cuánto se actualizó (gris si lleva más de 3 min sin señal).
- **Límite actual:** el navegador deja de enviar la ubicación cuando la app queda en segundo plano (por ejemplo, con Waze en pantalla completa). Soluciones: pantalla dividida en Android, o "Compartir viaje" de Waze. La solución definitiva es una app Android instalable (siguiente paso).
- Mapa gratuito: Leaflet + OpenStreetMap. Probado en base de datos (el pasajero solo ve durante el servicio; ubicaciones inválidas o de personas que no conducen se rechazan) y en las tres pantallas con datos de prueba.

## 9 nov 2026 · Etapa 4: cobro, taxímetro, fichas de clientes y planilla (pendiente de publicar)
- **Tipo de cobro por servicio:** "Tarifa fija" o "Taxímetro" (se elige al crear la reserva o en su ficha).
  - Tarifa fija: el conductor no puede cambiar el valor; solo deja una observación, que queda marcada "por revisar" en el panel.
  - Taxímetro: al finalizar, el conductor ingresa metros y minutos de espera; la app calcula sola (bajada $2.400 + $180 cada 200 m + $180 cada 60 s). Agrega gastos: TAG ($900 c/u), peajes, estacionamiento y otros.
  - Las tarifas se pueden cambiar en Equipo y roles → Tarifas (solo administrador).
- **Botón "+ Observación"** en la app del conductor, en cualquier momento del servicio.
- **Pagos:** solo el administrador marca un servicio como pagado (la base de datos lo impide a cualquier otra persona). El **efectivo está bloqueado** por ahora.
- **Fichas de clientes automáticas:** cada reserva nueva queda unida a un cliente (por correo o teléfono); si no existe, se crea. Las reservas antiguas ya quedaron unidas (por ejemplo, Fernando Chacana).
- **Pestaña "Clientes y cobros"** en /equipo: lista de clientes con lo cobrado, pagado y pendiente; ficha por cliente con período, marcar varios como pagados y **"Descargar planilla Excel"** lista para enviar a cobro (detalle de cada servicio, taxímetro, gastos, total, pendiente y enlace de respaldo).
- Filtros nuevos en Reservas: "Observación por revisar" y "Por cobrar".
- Probado: cálculos en la base de datos (12,5 km + 5 min = $14.460; 2 TAG + peaje = $3.300; total $17.760), bloqueos de pago y efectivo, y las pantallas con datos de prueba (incluida la descarga del Excel).

## 9-10 nov 2026 · Vehículo en seguimiento, vehículo fijo por conductor y app del conductor (pendiente de publicar)
- **Seguimiento:** el cliente ve modelo y patente del vehículo (probado con la reserva real FK-684D1C: Virtus azul SSHY88).
- **Vehículo fijo por conductor:** en Equipo → Vehículos se elige el conductor de cada auto. Al asignar ese conductor, el vehículo se completa solo (en la ficha y en la base de datos). SSHY88 quedó asociado a Juan.
- **App del conductor** (`/conductor/`), instalable en el teléfono:
  - Pestañas Hoy (incluye las próximas 12 horas) y Próximos.
  - Por servicio: hora, pasajero, pasajeros y maletas, vuelo, retiro y destino con Waze / Google Maps, nota, valor y forma de pago, Llamar y WhatsApp.
  - Botón grande para avanzar: Voy en camino → Llegué al lugar → Pasajero a bordo → Finalizar (con confirmación y nota). Cada toque actualiza el seguimiento del cliente.
  - Probado en base de datos: avanza, permite saltar pasos hacia adelante, bloquea retroceder y bloquea a otros usuarios.
- Un conductor (rol conductor) que entra a /equipo ve el enlace a su app y puede crear su contraseña.

## 9 nov 2026 · Contraseña para el equipo (pendiente de publicar)
- /equipo ahora pide **correo y contraseña**. La primera vez (o si se olvida) se usa "Enviarme un enlace al correo"; al entrar por el enlace, el panel ofrece crear la contraseña.
- Botón **"Contraseña"** en la barra superior para cambiarla cuando se quiera.
- La sesión queda guardada en el dispositivo: si no se toca "Salir", no hace falta volver a ingresar.
- Clientes (/cuenta) siguen con enlace al correo.

## 9 nov 2026 · Etapa 2: despacho (rama `etapa-1`, pendiente de publicar)

### Qué se hizo
- **Base de datos:** tabla de vehículos; cada persona del equipo puede marcarse como "conduce"; la reserva guarda conductor, vehículo, duración estimada, partner al que se derivó y su costo. Función `asignar_reserva` que asigna y deja nota en el historial (pasa la reserva a "Conductor asignado"). Probado con una reserva de prueba (borrada).
- **Panel /equipo:**
  - Pestaña **Agenda**: un día a la vez, una columna por conductor, más "Derivados a la red" y "Sin asignar". Los servicios que se cruzan para un mismo conductor aparecen en rojo.
  - En la ficha de cada reserva: **asignar conductor y vehículo**, duración estimada, o **derivar a un partner** con su costo; muestra el margen. Si el conductor ya tiene otro servicio en ese horario, avisa y pide "Asignar igual".
  - Las tarjetas de reservas muestran a quién está asignada.
  - Pestaña Equipo: columna **"Conduce"** y sección **Vehículos** (agregar, dar de baja).

### Qué debe probar el dueño (cuando se publique)
1. Equipo y roles → Vehículos: agregar su auto (patente, modelo, capacidad).
2. Abrir una reserva → Asignación: elegirse como conductor y el vehículo → Guardar.
3. Agenda: revisar el día de la reserva.

## 9 nov 2026 · Corrección (pendiente de publicar)
- /cuenta mostraba todas las reservas cuando entraba una cuenta del equipo (por sus permisos de administrador). Ahora muestra solo las reservas propias del cliente. Ningún cliente real veía reservas ajenas.

## 9 nov 2026 · Publicación de la etapa 1 (aprobada por el dueño)
- Publicadas /equipo, /cuenta y /seguimiento.
- Página principal: franja superior y pie de página con "Acceso clientes" y "Acceso equipo".
- **Registro de clientes desactivado por ahora** (pedido del dueño): en /cuenta solo pueden entrar cuentas ya existentes y se muestra un aviso de "muy pronto".
- /equipo solo envía el enlace de ingreso a correos invitados por el administrador (función `puede_ingresar_equipo`).
- Nota técnica: el bloqueo de registro se hace en la página. Para bloquearlo también en el servidor, más adelante se desactiva "Allow new users to sign up" en Supabase, una vez que el equipo tenga sus cuentas creadas.

## 9 nov 2026 · Etapa 1 (rama `etapa-1`, sin publicar)

### Qué se hizo
- **Base de datos en Supabase** (proyecto "FLOTAK Project"): empresas, equipo con roles, invitaciones, clientes, reservas, historial de estados y reportes. Seguridad por filas activada en todas las tablas.
  - Se agregó a la reserva: tipo de servicio, vehículo, comuna, maletas y tarifa web.
  - Probado: crear una reserva pública y verla con el enlace de seguimiento (la reserva de prueba se borró).
- **Mi cuenta** (`/cuenta/`): el cliente entra con un enlace a su correo y ve sus reservas y su estado. Si reservó antes como invitado con el mismo correo, sus reservas aparecen solas.
- **Seguimiento** (`/seguimiento/?t=...`): estado de la reserva sin iniciar sesión, con los pasos del servicio.
- **Panel del equipo** (`/equipo/`):
  - Reservas: hoy, próximas, historial y pendientes de confirmar; búsqueda; ficha con precio final, forma de pago, cambio de estado con nota e historial.
  - Nueva reserva: para reservas que llegan por teléfono, WhatsApp o correo.
  - Equipo y roles (solo administrador): invitar por correo, cambiar rol, activar o desactivar.
  - Reportar o sugerir.
- **gerencia@fk-servicios.com quedó invitado como administrador.**

### Qué falta
- Configurar en Supabase las direcciones permitidas para el ingreso (ver abajo).
- Correos propios (aviso de reserva nueva y confirmación al cliente) con un remitente @fk-servicios.com: Resend gratis, requiere agregar registros en Squarespace.
- Conectar el formulario de reserva de la página principal a la base de datos.
- Protección contra spam (Cloudflare Turnstile).
- Ingreso con Google (opcional).

### Qué debe hacer / probar el dueño
1. En Supabase: Authentication → URL Configuration
   - Site URL: `https://fk-servicios.com`
   - Redirect URLs: `https://fk-servicios.com/**` y `http://fk-servicios.com/**`
2. Aprobar la publicación de la rama en `main`.
3. Entrar a `fk-servicios.com/equipo/` con gerencia@fk-servicios.com, tocar el enlace del correo y comprobar que entra como Administrador.
4. Crear una reserva de prueba en "Nueva reserva", cambiarle el estado y ver el historial.

### Limitación importante
Mientras no se configure un correo propio (Resend), Supabase solo envía los enlaces de ingreso a correos del equipo dueño del proyecto en Supabase y con un máximo de pocos correos por hora. Sirve para probar el panel, pero no para clientes reales.
