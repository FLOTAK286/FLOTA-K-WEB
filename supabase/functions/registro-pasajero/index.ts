// Registro de pasajeros de la app (/app). Crea la cuenta SIN confirmar y envía el correo de confirmación
// (SMTP de Gmail configurado en Supabase). Hasta confirmar el correo no se puede ingresar, y el historial
// de viajes con ese correo solo se vincula después de confirmarlo (pasajero_cliente).
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { ...CORS, "Content-Type": "application/json" } });
const VOLVER = "https://fk-servicios.com/app/";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Método no permitido" }, 405);
  try {
    const url = Deno.env.get("SUPABASE_URL")!, anon = Deno.env.get("SUPABASE_ANON_KEY")!;
    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
    const b = await req.json().catch(() => ({}));
    const nombre = String(b.nombre ?? "").trim().slice(0, 120);
    const telefono = String(b.telefono ?? "").trim().slice(0, 30);
    const correo = String(b.correo ?? "").trim().toLowerCase();
    const clave = String(b.clave ?? "");
    const reenviar = b.reenviar === true;

    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(correo) || /@usuarios\.fk-servicios\.com$/.test(correo)) return json({ error: "Escriba un correo válido" }, 400);
    const ip = (req.headers.get("x-forwarded-for") || "").split(",")[0].trim() || "?";
    const { data: ok } = await admin.rpc("registro_permitido", { p_ip: ip, p_correo: correo });
    if (!ok) return json({ error: "Demasiados intentos seguidos. Espere unos minutos e intente de nuevo." }, 429);

    const enviar = async () => {
      const r = await fetch(`${url}/auth/v1/resend`, {
        method: "POST",
        headers: { apikey: anon, Authorization: `Bearer ${anon}`, "Content-Type": "application/json" },
        body: JSON.stringify({ type: "signup", email: correo, options: { emailRedirectTo: VOLVER } }),
      });
      if (!r.ok) { const t = await r.text(); throw new Error(t || `Error ${r.status}`); }
    };

    if (reenviar) {
      await enviar().catch(() => {}); // misma respuesta exista o no la cuenta
      return json({ ok: true });
    }

    if (nombre.length < 2) return json({ error: "Escriba su nombre" }, 400);
    if (telefono.replace(/\D/g, "").length < 8) return json({ error: "Escriba un teléfono válido" }, 400);
    if (clave.length < 8 || !/[a-zA-Z]/.test(clave) || !/\d/.test(clave)) return json({ error: "La contraseña debe tener al menos 8 caracteres, con letras y números" }, 400);

    const { data: nuevo, error } = await admin.auth.admin.createUser({
      email: correo, password: clave, email_confirm: false, user_metadata: { nombre, telefono, origen: "app_pasajero" },
    });
    if (error) {
      if (/already|registered|exists/i.test(error.message)) {
        await enviar().catch(() => {});
        return json({ error: "Ese correo ya tiene una cuenta. Ingrese con su contraseña o use \"¿Olvidó su contraseña?\". Si aún no confirma su correo, le reenviamos el enlace.", existe: true }, 409);
      }
      return json({ error: error.message }, 400);
    }
    try { await enviar(); }
    catch (e) {
      await admin.auth.admin.deleteUser(nuevo.user!.id); // no dejar una cuenta sin correo de confirmación
      return json({ error: "No pudimos enviar el correo de confirmación. Intente de nuevo en unos minutos.", detalle: (e as Error).message }, 502);
    }
    return json({ ok: true });
  } catch (e) {
    return json({ error: (e as Error).message || "Error inesperado" }, 500);
  }
});
