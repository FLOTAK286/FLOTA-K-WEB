// Crea el acceso al portal de empresas (/empresa) con una contraseña provisoria, sin enviar correos.
// Pueden usarla: el administrador de Flota-K (para cualquier empresa con convenio de su empresa)
// o el encargado de convenio de esa empresa (solo para su propia empresa).
// También permite dar una contraseña provisoria nueva a una persona de la empresa (accion = "clave").
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
    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
    const b = await req.json().catch(() => ({}));
    const cuenta = String(b.cuenta ?? "");

    // ¿Quién llama? Admin de Flota-K de la misma empresa, o encargado de convenio de esa cuenta
    const { data: cta } = await admin.from("cuentas_corporativas").select("id, empresa_id, activa").eq("id", cuenta).maybeSingle();
    if (!cta) return json({ error: "Empresa no encontrada" }, 404);
    const { data: perfil } = await admin.from("perfiles").select("rol, activo, empresa_id").eq("id", u.user.id).maybeSingle();
    const esAdmin = !!perfil && perfil.activo && perfil.rol === "admin" && perfil.empresa_id === cta.empresa_id;
    const { data: yo } = await admin.from("convenio_usuarios").select("id, rol, activo, cuenta_id").eq("user_id", u.user.id).maybeSingle();
    const esEncargado = !!yo && yo.activo && yo.rol === "encargado" && yo.cuenta_id === cta.id && cta.activa;
    if (!esAdmin && !esEncargado) return json({ error: "Sin permiso para dar acceso a esta empresa" }, 403);

    const clave = String(b.clave ?? "");
    if (clave.length < 8) return json({ error: "La contraseña provisoria debe tener al menos 8 caracteres" }, 400);

    if (b.accion === "clave") {
      const { data: otra } = await admin.from("convenio_usuarios").select("user_id, nombre, cuenta_id").eq("id", String(b.id ?? "")).maybeSingle();
      if (!otra || otra.cuenta_id !== cta.id || !otra.user_id) return json({ error: "Persona no encontrada" }, 404);
      if (otra.user_id === u.user.id) return json({ error: "Cambie su propia contraseña con el botón Contraseña" }, 400);
      const { error } = await admin.auth.admin.updateUserById(otra.user_id, { password: clave });
      if (error) return json({ error: error.message }, 400);
      await admin.from("convenio_usuarios").update({ clave_cambiada: false }).eq("user_id", otra.user_id);
      return json({ ok: true, nombre: otra.nombre });
    }

    const correo = String(b.correo ?? "").trim().toLowerCase(), nombre = String(b.nombre ?? "").trim();
    const telefono = String(b.telefono ?? "").trim(), rol = String(b.rol ?? "");
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(correo)) return json({ error: "Correo no válido" }, 400);
    if (nombre.length < 2) return json({ error: "Ingrese el nombre" }, 400);
    if (!["encargado", "pasajero", "directivo"].includes(rol)) return json({ error: "Rol no válido" }, 400);

    let userId: string | null = null, existia = false;
    const { data: nuevo, error: eC } = await admin.auth.admin.createUser({ email: correo, password: clave, email_confirm: true, user_metadata: { nombre } });
    if (eC) {
      if (!/already|registered|exists/i.test(eC.message)) return json({ error: eC.message }, 400);
      existia = true;
      // Ya tenía cuenta: se busca su id (no se cambia su contraseña)
      for (let page = 1; page <= 20 && !userId; page++) {
        const { data: l } = await admin.auth.admin.listUsers({ page, perPage: 200 });
        const f = l?.users?.find((x) => (x.email || "").toLowerCase() === correo);
        if (f) userId = f.id;
        if (!l || l.users.length < 200) break;
      }
      if (!userId) return json({ error: "No se encontró la cuenta existente de ese correo" }, 400);
    } else userId = nuevo.user!.id;

    const { data: id, error: eR } = await admin.rpc("convenio_registrar_usuario", {
      p_cuenta: cta.id, p_user: userId, p_rol: rol, p_nombre: nombre, p_correo: correo, p_telefono: telefono || null, p_por: u.user.id,
    });
    if (eR) {
      if (!existia) await admin.auth.admin.deleteUser(userId!); // no dejar una cuenta suelta si el alta falló
      return json({ error: eR.message }, 400);
    }
    return json({ ok: true, existia, id });
  } catch (e) {
    return json({ error: (e as Error).message || "Error inesperado" }, 500);
  }
});
