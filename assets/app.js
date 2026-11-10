// Utilidades compartidas: cliente Supabase, inicio de sesión, formatos.
(function () {
  const C = window.FK_CONFIG;
  const sb = window.supabase.createClient(C.url, C.anonKey, {
    auth: Object.assign({ persistSession: true, autoRefreshToken: true, detectSessionInUrl: true, flowType: "pkce" },
      // Dentro de la app Android, el "candado" del navegador puede quedarse pegado y dejar la pantalla en blanco: se omite.
      (window.Capacitor && window.Capacitor.isNativePlatform && window.Capacitor.isNativePlatform()) ? { lock: (_n, _t, fn) => fn() } : {})
  });

  const ESTADOS = {
    recibida:   { t: "Recibida",       c: "s-new" },
    confirmada: { t: "Confirmada",     c: "s-ok" },
    asignada:   { t: "Conductor asignado", c: "s-ok" },
    en_camino:  { t: "En camino",      c: "s-go" },
    en_lugar:   { t: "Conductor en el lugar", c: "s-go" },
    a_bordo:    { t: "A bordo",        c: "s-go" },
    finalizada: { t: "Finalizada",     c: "s-done" },
    cancelada:  { t: "Cancelada",      c: "s-cancel" }
  };
  const ROLES = { admin: "Administrador", despachador: "Despachador", telefonista: "Telefonista", conductor: "Conductor", propietario: "Propietario de vehículo" };
  const SERVICIOS = { ida: "Ida al aeropuerto", regreso: "Regreso desde el aeropuerto", ida_vuelta: "Ida y vuelta", punto_a_punto: "Punto a punto", por_hora: "Por hora" };

  const esc = s => String(s ?? "").replace(/[&<>"']/g, ch => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[ch]));
  const clp = n => (n == null || n === "") ? "—" : (Number(n) < 0 ? "-$" : "$") + Math.abs(Number(n)).toLocaleString("es-CL");
  const fecha = iso => iso ? new Date(iso).toLocaleString("es-CL", { timeZone: "America/Santiago", weekday: "short", day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit" }) : "—";
  const pill = e => { const x = ESTADOS[e] || { t: e, c: "" }; return `<span class="pill ${x.c}">${esc(x.t)}</span>`; };
  // Errores de Supabase traducidos a español simple
  const ERRORES = [
    [/should be different from the old password/i, "La contraseña nueva debe ser distinta de la actual (por ejemplo, de la provisoria que le dieron). Escriba otra."],
    [/password should be at least|weak password|password is too weak/i, "La contraseña es muy débil: use al menos 8 caracteres, con letras y números."],
    [/invalid login credentials/i, "Correo o contraseña incorrectos."],
    [/email not confirmed/i, "Su correo aún no está confirmado. Pida ayuda al administrador."],
    [/rate limit|only request this after|too many requests/i, "Demasiados intentos seguidos. Espere unos minutos e intente de nuevo."],
    [/signups not allowed|user not found/i, "Este correo no tiene cuenta. Pida acceso al administrador."],
    [/jwt expired|invalid jwt|session.*(missing|expired)|refresh token/i, "Su sesión venció. Cierre sesión y vuelva a ingresar."],
    [/failed to fetch|networkerror|network request failed|load failed/i, "Sin conexión a internet. Revise su señal e intente de nuevo."],
    [/payload too large|entity too large|exceeded the maximum allowed size/i, "El archivo es muy grande. Pruebe con una foto más liviana."],
    [/duplicate key|already exists/i, "Ese dato ya está registrado."]
  ];
  const errText = e => {
    const m = (e && (e.message || e.error_description)) || "";
    if (!m) return "Ocurrió un error. Intente de nuevo.";
    const t = ERRORES.find(([re]) => re.test(m));
    return t ? t[1] : m;
  };

  // "2026-12-15T06:40" escrito en hora de Chile -> ISO con la zona correcta (considera horario de verano).
  function chileLocalToISO(local) {
    if (!local) return null;
    const [d, t] = local.split("T");
    const [y, m, day] = d.split("-").map(Number);
    const [hh, mm] = t.split(":").map(Number);
    const guess = Date.UTC(y, m - 1, day, hh, mm);
    const parts = new Intl.DateTimeFormat("en-US", { timeZone: "America/Santiago", hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit" }).formatToParts(new Date(guess));
    const g = k => Number(parts.find(p => p.type === k).value);
    const asChile = Date.UTC(g("year"), g("month") - 1, g("day"), g("hour"), g("minute"));
    return new Date(guess - (asChile - guess)).toISOString();
  }

  // crear=false: solo pueden entrar cuentas que ya existen (no se registran usuarios nuevos).
  async function enviarEnlace(correo, volverA, crear = false) {
    return sb.auth.signInWithOtp({ email: correo.trim().toLowerCase(), options: { emailRedirectTo: volverA, shouldCreateUser: crear } });
  }
  async function entrarConGoogle(volverA) {
    return sb.auth.signInWithOAuth({ provider: "google", options: { redirectTo: volverA } });
  }

  window.FK = { sb, ESTADOS, ROLES, SERVICIOS, esc, clp, fecha, pill, errText, chileLocalToISO, enviarEnlace, entrarConGoogle, empresa: C.empresa };
})();
