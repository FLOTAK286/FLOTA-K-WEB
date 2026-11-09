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
  const ROLES = { admin: "Administrador", despachador: "Despachador", telefonista: "Telefonista", conductor: "Conductor" };
  const SERVICIOS = { ida: "Ida al aeropuerto", regreso: "Regreso desde el aeropuerto", ida_vuelta: "Ida y vuelta", punto_a_punto: "Punto a punto", por_hora: "Por hora" };

  const esc = s => String(s ?? "").replace(/[&<>"']/g, ch => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[ch]));
  const clp = n => (n == null || n === "") ? "—" : "$" + Number(n).toLocaleString("es-CL");
  const fecha = iso => iso ? new Date(iso).toLocaleString("es-CL", { timeZone: "America/Santiago", weekday: "short", day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit" }) : "—";
  const pill = e => { const x = ESTADOS[e] || { t: e, c: "" }; return `<span class="pill ${x.c}">${esc(x.t)}</span>`; };
  const errText = e => (e && (e.message || e.error_description)) || "Ocurrió un error. Intente de nuevo.";

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
