// Inscripción de conductores con el enlace que envía Flota-K (/conductor/?inscripcion=<código>).
// Crea la cuenta (correo y contraseña, sin correo de confirmación para no gastar el cupo) y el perfil
// "por activar": la persona no ve servicios hasta que el administrador la apruebe en Equipo y roles.
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { ...CORS, "Content-Type": "application/json" } });
const txt = (v: unknown, n: number) => String(v ?? "").trim().slice(0, n);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Método no permitido" }, 405);
  try {
    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
    const b = await req.json().catch(() => ({}));
    const codigo = txt(b.codigo, 40).toLowerCase();
    const correo = txt(b.correo, 200).toLowerCase();
    const clave = String(b.clave ?? "");
    const d = {
      nombre: txt(b.nombre, 120), telefono: txt(b.telefono, 30), rut: txt(b.rut, 20), comuna: txt(b.comuna, 80),
      licencia: txt(b.licencia, 20), experiencia: txt(b.experiencia, 500), tiene_vehiculo: b.tiene_vehiculo === true,
      patente: txt(b.patente, 10), marca: txt(b.marca, 60), modelo: txt(b.modelo, 60), anio: txt(b.anio, 4), color: txt(b.color, 40),
    };

    const { data: emp } = await admin.rpc("inscripcion_empresa", { p_codigo: codigo });
    if (!emp) return json({ error: "Este enlace de inscripción no es válido o ya no está activo. Pida uno nuevo a Flota-K." }, 400);
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(correo) || /@usuarios\.fk-servicios\.com$/.test(correo)) return json({ error: "Escriba un correo válido" }, 400);
    if (d.nombre.length < 5 || !d.nombre.includes(" ")) return json({ error: "Escriba su nombre y apellido" }, 400);
    if (d.telefono.replace(/\D/g, "").length < 8) return json({ error: "Escriba un teléfono válido" }, 400);
    if (d.rut.replace(/[^0-9kK]/g, "").length < 7) return json({ error: "Escriba su RUT" }, 400);
    if (!d.licencia) return json({ error: "Indique la clase de su licencia" }, 400);
    if (d.tiene_vehiculo) {
      const pat = d.patente.toUpperCase().replace(/[^A-Z0-9]/g, "");
      if (!/^[A-Z]{2,4}[0-9]{2,4}$/.test(pat) || pat.length < 5 || pat.length > 6) return json({ error: "Revise la patente (ej.: ABCD12)" }, 400);
      if (!d.marca || !d.modelo) return json({ error: "Escriba la marca y el modelo del vehículo" }, 400);
      if (!/^(19|20)\d\d$/.test(d.anio)) return json({ error: "Escriba el año del vehículo" }, 400);
    }
    if (clave.length < 8 || !/[a-zA-Z]/.test(clave) || !/\d/.test(clave)) return json({ error: "La contraseña debe tener al menos 8 caracteres, con letras y números" }, 400);

    const ip = (req.headers.get("x-forwarded-for") || "").split(",")[0].trim() || "?";
    const { data: ok } = await admin.rpc("registro_conductor_permitido", { p_ip: ip, p_correo: correo });
    if (!ok) return json({ error: "Demasiados intentos seguidos. Espere un rato e intente de nuevo." }, 429);

    const { data: nuevo, error } = await admin.auth.admin.createUser({
      email: correo, password: clave, email_confirm: true, user_metadata: { nombre: d.nombre, telefono: d.telefono, origen: "inscripcion_conductor" },
    });
    if (error) {
      if (/already|registered|exists/i.test(error.message)) {
        return json({ error: "Ese correo ya tiene una cuenta en Flota-K. Ingrese con su contraseña (o use \"¿Olvidó su contraseña?\"). Si es una cuenta de pasajero, escríbanos por WhatsApp para habilitarla como conductor.", existe: true }, 409);
      }
      return json({ error: error.message }, 400);
    }
    const { error: e2 } = await admin.rpc("conductor_postular", { p_uid: nuevo.user!.id, p_codigo: codigo, p_correo: correo, p_datos: d });
    if (e2) {
      await admin.auth.admin.deleteUser(nuevo.user!.id); // no dejar una cuenta a medias
      return json({ error: e2.message }, 400);
    }
    return json({ ok: true, empresa: emp });
  } catch (e) {
    return json({ error: (e as Error).message || "Error inesperado" }, 500);
  }
});
