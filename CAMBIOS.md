# Cambios

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
