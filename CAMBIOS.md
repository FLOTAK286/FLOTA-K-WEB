# Cambios

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
