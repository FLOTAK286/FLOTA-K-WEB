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
- **Páginas:** `/` (marketing + tarifario), `/aeropuerto/<comuna>/` (SEO), `/cuenta/` (cliente), `/equipo/` (panel interno), `/conductor/` (app del conductor; también app Android en `app-android/`), `/propietario/` (portal de dueños de vehículos), `/en/` (inglés), `/seguimiento/?t=<token>`.
- **Frontend:** HTML + JavaScript simple. supabase-js 2.45.4 desde jsDelivr. Código común en `assets/app.js`, estilos en `assets/site.css` y `assets/app.css`, configuración pública en `assets/config.js` (solo URL y clave `anon`).
- **Base de datos:** Supabase, proyecto "FLOTAK Project" (`iejhmplstveockkjjbks`, región us-east-2). Migraciones en `supabase/migrations/` con el mismo número de versión que aparece en Supabase. Nunca editar una migración ya aplicada: crear una nueva.
- **Ingreso:** equipo y conductores con correo + contraseña. El admin crea la cuenta con contraseña provisoria desde Equipo y roles (Edge Function `crear-miembro`), porque el correo gratuito de Supabase solo llega a miembros del equipo de Supabase. Clientes con enlace al correo, registro desactivado por ahora. Google desactivado (`google: false`).
- **Despacho:** `asignar_reserva` (usa el vehículo habitual del conductor si no se elige otro), `conductor_avanzar` (solo sus servicios, solo hacia adelante). Límite de correos de Supabase sin SMTP propio: 2 por hora.
- **Tareas programadas (pg_cron, Supabase):** `flotak-bolsa-automatica` cada 5 min ejecuta `bolsa_automatica()`, que solo actúa si la empresa la activó (`bolsa_auto_activa`, apagada por defecto: la bolsa la libera el despachador).
- **Bolsa de servicios:** la libera el despachador. Programados: 0–10 min solo móviles de Flota-K con 4,96★+ (o sin ninguna calificación; si la primera no es 5 pierden la prioridad), 10–20 min + destacados (4,96★+, mín. 3 calificaciones en 90 días), luego todos. De momento (< 2 h): sin prioridad; se sugiere el conductor más cercano por GPS. Calificaciones con 2 decimales.
- **Rutas y direcciones (gratis):** autocompletar con Photon (photon.komoot.io) y rutas con OSRM (router.project-osrm.org), +25% por tráfico; margen mínimo para encadenar servicios: 15 min.
- **Roles:** `admin`, `despachador`, `telefonista`, `conductor`, `propietario` (solo ve sus vehículos en /propietario). El admin invita por correo (`invitar_miembro`); al entrar a `/equipo` la persona acepta su invitación (`aceptar_invitacion`).

## Reglas de seguridad
- Nunca subir claves secretas (`service_role`, contraseña de la base). En el frontend solo URL + `anon`.
- Toda tabla con Row Level Security. La seguridad la aplica la base de datos.
- Reservas públicas solo con `crear_reserva_publica`. Cambios de estado con `cambiar_estado_reserva` (deja nota en `reserva_eventos`).
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
- No captar clientes de Servimóvil ni de Cabify. No pagar comisiones a intermediarios.

## Datos de referencia
- Costo operativo: $410 por km.
- Estados de reserva: `recibida`, `confirmada`, `asignada`, `en_camino`, `en_lugar`, `a_bordo`, `finalizada`, `cancelada`.
