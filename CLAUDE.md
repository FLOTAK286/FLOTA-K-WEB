# Flota-K Plataforma: instrucciones para Claude

## Quién es el dueño y cómo trabajar con él
- Flota-K (FK Servicios SpA) es una empresa chilena de transporte ejecutivo: traslados al aeropuerto, taxis ejecutivos y servicios corporativos. Hoy el dueño es el único conductor.
- El dueño **no es programador**. Explícale cada paso en español simple, sin jerga.
- Quiere decisiones fundamentadas: si algo no conviene, dilo con razones.
- **Nunca envíes correos ni mensajes a terceros sin su confirmación explícita.**
- Pide confirmación antes de: publicar en `main`, borrar archivos o datos, cambiar el dominio o GitHub Pages, y cualquier cosa que cueste dinero.
- Costo objetivo: **$0**. Solo planes gratuitos.

## Visión (por etapas)
1. Cuenta de cliente y reservas (**etapa actual**).
2. Roles y despacho (panel `/equipo`).
3. App del conductor.
4. Cotizador automático.
5. GPS y seguimiento en vivo.
6. Pago en línea.
Diseño **multiempresa** desde el inicio (cada dato pertenece a una empresa). Empresa inicial: Flota-K, slug `flota-k`.

## Arquitectura actual
- **Hosting:** GitHub Pages (`main` = sitio publicado en fk-servicios.com). Sitio estático, sin paso de compilación.
- **Páginas:** `/` (marketing + tarifario), `/aeropuerto/<comuna>/` (SEO), `/cuenta/` (cliente), `/equipo/` (panel interno), `/conductor/` (app del conductor; también app Android en `app-android/`), `/propietario/` (portal de dueños de vehículos), `/en/` (inglés), `/seguimiento/?t=<token>`, `/app/` (app del pasajero, instalable, con cuenta obligatoria entregada por Flota-K: el registro libre está pausado (etapa 42, "Solicitar cuenta" por WhatsApp) y solo reservan personas con acceso activo en `convenio_usuarios`; reservas con `pasajero_reservar`, viajes con `pasajero_viajes`, direcciones guardadas y cotizador punto a punto). `/equipo/` también se instala como app "Flota-K Operaciones". `/empresa/` (portal de empresas con convenio: encargado de convenio y pasajero autorizado, tabla `convenio_usuarios`; reservas con `crear_reserva_convenio`, presupuesto con aviso o bloqueo, servicios habituales que carga el admin). Clientes particulares en el mismo portal: cuenta interna `es_particulares` por empresa; sus reservas quedan sin convenio (canal `portal`). Todas las cuentas se gestionan en la pestaña "Cuentas de clientes" del panel.
- **Frontend:** HTML + JavaScript simple. supabase-js 2.45.4 desde jsDelivr. Código común en `assets/app.js`, estilos en `assets/site.css` y `assets/app.css`, configuración pública en `assets/config.js` (solo URL y clave `anon`).
- **Base de datos:** Supabase, proyecto "FLOTAK Project" (`iejhmplstveockkjjbks`, región us-east-2). Migraciones en `supabase/migrations/` con el mismo número de versión que aparece en Supabase. Nunca editar una migración ya aplicada: crear una nueva.
- **Ingreso:** equipo y conductores con correo + contraseña. El admin crea la cuenta con contraseña provisoria desde Equipo y roles (Edge Function `crear-miembro`), porque el correo gratuito de Supabase solo llega a miembros del equipo de Supabase. Clientes con enlace al correo, registro desactivado por ahora. Google desactivado (`google: false`).
- **Despacho:** `asignar_reserva` (usa el vehículo habitual del conductor si no se elige otro), `conductor_avanzar` (solo sus servicios, solo hacia adelante). Límite de correos de Supabase sin SMTP propio: 2 por hora.
- **Ubicación con la app cerrada (app Android 2.0):** servicio nativo `UbicacionService` + puente `FlotaKNativo`. Al iniciar sesión la app registra el teléfono (`conductor_registrar_dispositivo`) y guarda una llave que solo sirve para enviar la ubicación (`conductor_ubicacion_dispositivo`); cerrar sesión la anula (`conductor_cerrar_dispositivo`). Solo `main` publica la app "conductor-android"; otras ramas publican "conductor-prueba".
- **Avisos con la app cerrada (sin Firebase):** conductor: `avisos_conductor` + `conductor_latido` (servicio nuevo, quitado, cancelado o modificado; cada 15-60 s). Operaciones: `avisos_equipo` + `equipo_latido` (`AvisosEquipoService`, cada 60 s; reserva nueva de otra persona, cancelación del cliente, conductor que no puede o que tomó una reserva). La app de Operaciones se vuelve a armar a mano (workflow "Apps Android del pasajero y de operaciones").
- **Reservas para conductores (etapas 54–57):** requisitos al publicar (`liberar_a_bolsa_requisitos`: categorías, corporativo, calificación mínima); todos ven la reserva (`bolsa_servicios_v4` con `o_motivo`), solo toma quien cumple (`motivo_requisitos_bolsa`). Aviso de reservas nuevas a todos, conectados o no, también con la app cerrada (`conductor_latido` + `bolsa_avisos`). Mapa de calor de próximos servicios: `mapa_demanda` + `FKMapa.calor`. Otros conductores conectados en el mapa del conductor: `mapa_conductores` (zona aproximada, sin nombres).
- **Tareas programadas (pg_cron, Supabase):** `flotak-bolsa-automatica` cada 5 min ejecuta `bolsa_automatica()`, que solo actúa si la empresa la activó (`bolsa_auto_activa`, apagada por defecto: la bolsa la libera el despachador). `flotak-resumen-semanal` los lunes 12:07 UTC envía el resumen de la semana. `flotak-bolsa-vigilar` cada 2 min ejecuta `bolsa_vigilar()`: avisos a Operaciones 90 y 45 min antes si una reserva publicada sigue sin conductor, y asignación automática al más cercano que cumple (`conductor_mas_cercano`) `empresas.bolsa_autoasignar_min` antes (60 por defecto; null = apagado).
- **Bolsa de servicios** (en pantalla se llama **"Reservas"**: en la app del conductor "Reservas"; en el panel "Reservas para conductores"; los nombres internos siguen siendo `bolsa`): la libera el despachador. Programados: 0–10 min solo móviles de Flota-K con 4,96★+ (o sin ninguna calificación; si la primera no es 5 pierden la prioridad), 10–20 min + destacados (4,96★+, mín. 3 calificaciones en 90 días), luego todos. De momento (< 2 h): sin prioridad; se sugiere el conductor más cercano por GPS. Calificaciones con 2 decimales.
- **Rutas y direcciones (gratis):** autocompletar con Photon (photon.komoot.io) y rutas con OSRM (router.project-osrm.org), +25% por tráfico; margen mínimo para encadenar servicios: 15 min.
- **Inscripción de conductores (etapa 49):** el admin envía `/conductor/?inscripcion=<código>` (Equipo y roles → "Inscripción de conductores"); la persona crea su cuenta con la Edge Function `registro-conductor`, queda con `perfiles.postulacion = 'pendiente'` y `activo = false`, sube documentos (`postulante_documento`) y el admin la activa con `aprobar_postulante`. Aviso a Operaciones tipo `postulante`.
- **Dueños que inscriben conductores (etapa 58):** enlace `/conductor/?dueno=<perfiles.codigo_dueno>`; el conductor queda ligado (`postulaciones_conductor.invitado_por`), Flota-K lo aprueba igual, y el dueño asigna sus vehículos en /propietario (`propietario_asignar_conductor`). Al aprobar una inscripción con vehículo propio, el conductor queda también como propietario (etapa 57b).
- **Vehículo "Corporativo" (etapa 50; en pantalla "🏢 Corporativo" = autorización ministerial, columna interna `decreto80`):** `vehiculos.decreto80` + `decreto80_vence`. Toda reserva con `cuenta_corporativa_id` exige vehículo con Decreto 80 vigente (`vehiculo_decreto80_ok`): la bolsa la oculta y `conductor_tomar_reserva` la bloquea; en el panel, advertencia al asignar.
- **Pasajero no presentado (etapa 61):** el conductor lo informa en el lugar (`conductor_pedir_negativo`), la central autoriza o rechaza (`staff_resolver_negativo`) y recién ahí se cierra (`conductor_cerrar_negativo`: finalizada, tarifa fija, `no_presentado`). Valor según tarifario: domicilio $5.000 (15 min incluidos), regreso aeropuerto $15.000 (45 min), van $19.000, + espera posterior ($180/min auto, $270 SUV/van); fuera de Santiago 60 % (ajuste manual).
- **Facturación (etapa 63):** pestaña Facturación (admin o rol `facturacion`): `facturacion_resumen`, `facturacion_viajes`, `facturar_viajes` (tabla `facturas`, `reservas.factura_id`), `factura_accion` (pagada/anular). Portal: `convenio_estado_cuenta`.
- **Carga masiva** (`assets/carga.js`, panel y portal), **reservas repetidas** (`repetir_reserva`, `serie_id`), **ventas** (`prospectos`, pestaña Ventas), **resumen semanal** (`enviar_resumen_semanal`, cron lunes 12:07 UTC; `mi_resumen_semana` en Reportes). Negativo fuera de Santiago: `comuna_periferia` → 60 %.
- **Roles:** `admin`, `despachador`, `telefonista`, `conductor`, `propietario` (solo ve sus vehículos en /propietario), `facturacion` (solo la pestaña Facturación). El admin invita por correo (`invitar_miembro`); al entrar a `/equipo` la persona acepta su invitación (`aceptar_invitacion`).

## Reglas de seguridad
- Nunca subir claves secretas (`service_role`, contraseña de la base). En el frontend solo URL + `anon`.
- Toda tabla con Row Level Security. La seguridad la aplica la base de datos.
- Reserva al público pausada (`crear_reserva_publica` y `crear_reserva_app` sin permiso). Empresas con convenio: `crear_reserva_convenio`. Cambios de estado con `cambiar_estado_reserva` (deja nota en `reserva_eventos`).
- Nada se borra: las reservas se cancelan.
- Fechas: el usuario escribe hora de Chile; convertir con `FK.chileLocalToISO` (considera horario de verano).

## Forma de trabajo
- Trabajar en ramas (`etapa-1`, etc.). Publicar en `main` solo con aprobación del dueño.
- Al terminar cada sesión, actualizar `CAMBIOS.md`.
- Texto para clientes: español de Chile, trato de usted.

## Reglas de mensaje (marketing, aprobadas por el dueño)
- No usar "cumplimiento garantizado"; usar "Comprometidos con su traslado".
- Peajes y TAG incluidos en la RM; estacionamiento del aeropuerto incluido solo durante la espera (15 min domicilio, 45 min nacionales, 1 h internacionales).
- No hay sillas para niños. Mascotas sí, en canil.
- No captar clientes de Servimóvil (partner y aliado estratégico de Flota-K). Con Cabify se compite abiertamente (decisión del dueño, 20 nov 2026). No pagar comisiones a intermediarios.
- Cámaras de comercio: venden membresías (Chileno-India: 19,5 UF/año), no contratan traslados; no pagar membresías mientras no se justifiquen con ventas. Usar sus listados de socios para contactar empresas directo.

## Datos de referencia
- Capacidad operativa: 70 vehículos contando la flota de Servimóvil (partner); flota propia/asociada en la plataforma: 3. Se puede ofrecer "capacidad de 70 vehículos" a empresas y delegaciones.
- Costo operativo: $410 por km.
- Estados de reserva: `recibida`, `confirmada`, `asignada`, `en_camino`, `en_lugar`, `a_bordo`, `finalizada`, `cancelada`.
