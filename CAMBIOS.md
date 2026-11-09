# Cambios

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
