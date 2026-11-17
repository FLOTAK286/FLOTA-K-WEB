// Utilidades compartidas: cliente Supabase, inicio de sesión, formatos.
(function () {
  const C = window.FK_CONFIG;
  // Enlace del correo que cayó en la portada (Supabase vuelve a la dirección del sitio cuando la página pedida no está
  // en su lista permitida): se reenvía al panel del equipo con los datos del enlace, sin usarlos aquí.
  const traeEnlace = /access_token=|error_code=|[#&]type=(magiclink|recovery|signup|invite)/.test(location.hash) || /[?&](code|token_hash)=/.test(location.search);
  // Tipo de enlace del correo con que se entró (recovery, magiclink, invite, signup), para pedir la contraseña nueva
  const enlaceTipo = /access_token=/.test(location.hash) ? ((location.hash.match(/[#&]type=([a-z_]+)/) || [])[1] || "magiclink") : null;
  if (traeEnlace && (location.pathname === "/" || location.pathname === "/index.html")) {
    location.replace("/equipo/" + location.search + location.hash);
  }
  const sb = window.supabase.createClient(C.url, C.anonKey, {
    // flowType "implicit": el enlace del correo funciona aunque se abra en otro navegador o en la app de Gmail
    // (con "pkce" solo funcionaba en el mismo navegador donde se pidió, y si no, volvía a pedir iniciar sesión).
    auth: Object.assign({ persistSession: true, autoRefreshToken: true, detectSessionInUrl: !(traeEnlace && location.pathname === "/"), flowType: "implicit" },
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
    [/error sending .*email|sending (magic link|recovery|confirmation)/i, "No se pudo enviar el correo en este momento. Intente de nuevo en unos minutos o pida una contraseña provisoria al administrador."],
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

  // Trae todas las filas de una consulta, de a 1.000 (armar = función que devuelve la consulta, ya ordenada).
  async function todo(armar, max = 100000) {
    const out = []; let desde = 0;
    for (;;) {
      const { data, error } = await armar().range(desde, desde + 999);
      if (error) return { data: out.length ? out : null, error };
      out.push(...(data || []));
      if (!data || data.length < 1000 || out.length >= max) return { data: out, error: null };
      desde += 1000;
    }
  }

  // Estado real del vuelo: Flightradar24 (posición del avión y hora estimada en vivo) y Nuevo Pudahuel (aeropuerto).
  // Google muestra la hora programada/estimada de la aerolínea y puede quedar atrasada si el vuelo se adelanta.
  const vueloCodigo = v => String(v || "").toUpperCase().replace(/[^A-Z0-9]/g, "");
  const vueloFR24 = v => "https://www.flightradar24.com/data/flights/" + vueloCodigo(v).toLowerCase();
  const VUELO_PUDAHUEL = "https://www.nuevopudahuel.cl/";

  // Ingreso con usuario corto: "R González", "rgonzalez" o "RGonzalez" -> "rgonzalez@usuarios.fk-servicios.com".
  // Si trae "@" se usa como correo (en minúsculas y sin espacios).
  const DOMINIO_USUARIOS = "usuarios.fk-servicios.com";
  function usuarioACorreo(t) {
    const v = String(t || "").trim();
    if (!v) return "";
    if (v.includes("@")) return v.toLowerCase().replace(/\s+/g, "");
    const u = v.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().replace(/[^a-z0-9._-]/g, "");
    return u ? u + "@" + DOMINIO_USUARIOS : "";
  }

  // Para mostrar: "rgonzalez@usuarios.fk-servicios.com" -> "rgonzalez"; un correo normal queda igual.
  const usuarioVisible = c => String(c || "").endsWith("@" + DOMINIO_USUARIOS) ? String(c).split("@")[0] : String(c || "");

  // Abre WhatsApp u otro sitio externo. Dentro de las apps Android (Capacitor) se navega directo, porque
  // ahí window.open no siempre abre la otra app; en el navegador se abre en una pestaña nueva.
  function abrirExterno(url) {
    const nativo = !!(window.Capacitor && window.Capacitor.isNativePlatform && window.Capacitor.isNativePlatform());
    if (nativo) { location.href = url; return; }
    const w = window.open(url, "_blank", "noopener");
    if (!w) location.href = url;
  }

  window.FK = { enlaceTipo, abrirExterno, usuarioACorreo, usuarioVisible, DOMINIO_USUARIOS, vueloCodigo, vueloFR24, VUELO_PUDAHUEL, sb, todo, ESTADOS, ROLES, SERVICIOS, esc, clp, fecha, pill, errText, chileLocalToISO, enviarEnlace, entrarConGoogle, empresa: C.empresa };
})();
