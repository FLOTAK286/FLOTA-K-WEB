// Crea la cuenta de un miembro del equipo con una contraseña provisoria, sin enviar correos
// (el correo gratuito de Supabase solo llega a direcciones del propio equipo de Supabase).
// Solo un administrador activo puede usarla; el rol lo asigna invitar_miembro (que también exige admin).
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { ...CORS, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Método no permitido" }, 405);
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const usuario = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
      auth: { persistSession: false },
    });
    const { data: u } = await usuario.auth.getUser();
    if (!u?.user) return json({ error: "Debe iniciar sesión" }, 401);
    const { data: yo } = await usuario.from("perfiles").select("rol, activo").eq("id", u.user.id).maybeSingle();
    if (!yo || !yo.activo || yo.rol !== "admin") return json({ error: "Solo el administrador puede crear cuentas" }, 403);

    const b = await req.json().catch(() => ({}));
    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
    // Dar una contraseña nueva a un miembro del equipo (solo de la misma empresa y nunca a sí mismo por aquí)
    if (b.accion === "clave") {
      const id = String(b.id ?? ""), clave = String(b.clave ?? "");
      if (clave.length < 8) return json({ error: "La contraseña provisoria debe tener al menos 8 caracteres" }, 400);
      if (id === u.user.id) return json({ error: "Cambie su propia contraseña con el botón Contraseña" }, 400);
      const { data: mia } = await admin.from("perfiles").select("empresa_id").eq("id", u.user.id).maybeSingle();
      const { data: otra } = await admin.from("perfiles").select("empresa_id, nombre").eq("id", id).maybeSingle();
      if (!mia || !otra || otra.empresa_id !== mia.empresa_id) return json({ error: "Esa persona no es de su equipo" }, 403);
      const { error } = await admin.auth.admin.updateUserById(id, { password: clave });
      if (error) return json({ error: error.message }, 400);
      return json({ ok: true, nombre: otra.nombre });
    }
    const correo = String(b.correo ?? "").trim().toLowerCase(), nombre = String(b.nombre ?? "").trim(), rol = String(b.rol ?? ""), clave = String(b.clave ?? "");
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(correo)) return json({ error: "Correo no válido" }, 400);
    if (nombre.length < 2) return json({ error: "Ingrese el nombre" }, 400);
    if (!["admin", "despachador", "telefonista", "conductor", "propietario"].includes(rol)) return json({ error: "Rol no válido" }, 400);
    if (clave.length < 8) return json({ error: "La contraseña provisoria debe tener al menos 8 caracteres" }, 400);

    let existia = false;
    const { error: eC } = await admin.auth.admin.createUser({ email: correo, password: clave, email_confirm: true, user_metadata: { nombre } });
    if (eC) {
      if (!/already|registered|exists/i.test(eC.message)) return json({ error: eC.message }, 400);
      existia = true; // ya tenía cuenta: no se cambia su contraseña, solo se le da el rol
    }
    const { data: r, error: eR } = await usuario.rpc("invitar_miembro", { p_correo: correo, p_nombre: nombre, p_rol: rol });
    if (eR) return json({ error: eR.message }, 400);
    return json({ ok: true, existia, resultado: r });
  } catch (e) {
    return json({ error: (e as Error).message || "Error inesperado" }, 500);
  }
});
