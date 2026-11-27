// Instagram automático de Flota-K (etapa 79). Reemplaza a ManyChat, sin costo.
// Si alguien comenta en CUALQUIER publicación una palabra clave (por defecto: aeropuerto, precio, tarifa),
// se responde en el comentario y se le manda un mensaje privado con el enlace de reserva.
//
// Usa la API de Instagram con "inicio de sesión unificado" (Facebook) y un token de USUARIO DEL SISTEMA
// del portfolio comercial de Flota-K, que no vence (no hay que renovarlo).
//
// Rutas (https://<proyecto>.supabase.co/functions/v1/ig-webhook/...):
//   GET  /            verificación del webhook de Meta (hub.challenge con IG_VERIFY_TOKEN).
//   POST /            aviso de Meta (comentarios). Se valida la firma X-Hub-Signature-256 con META_APP_SECRET.
//   POST /conectar    (admin con sesión) busca la cuenta de Instagram del token, la guarda y la suscribe a los avisos.
//   POST /revisar     (admin con sesión) revisa ahora los comentarios recientes.
//   POST /tarea       tarea programada (pg_cron cada 10 min): revisa comentarios por si un aviso no llegó.
//
// Secretos (Supabase → Edge Functions → Secrets): IG_TOKEN (token del usuario del sistema), META_APP_SECRET
// (Configuración de la app → Básica → Clave secreta) e IG_VERIFY_TOKEN (una palabra cualquiera, la misma que en Meta).
// Se publica con verify_jwt = false (Meta no envía la sesión de Supabase).
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { ...CORS, "Content-Type": "application/json" } });
const env = (k: string) => (Deno.env.get(k) ?? "").trim();
const db = () => createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), { auth: { persistSession: false } });
const GRAPH = "https://graph.facebook.com/v22.0";
type SB = ReturnType<typeof db>;

// ---------- utilidades
const norm = (s: string) => (s || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
function palabraClave(texto: string, palabras: string[]): string | null {
  const tokens = norm(texto).split(/[^a-z0-9]+/).filter(Boolean);
  for (const p of palabras.map(norm)) {
    if (p.includes(" ")) { if (norm(texto).includes(p)) return p; continue; }
    if (tokens.some((t) => t === p || t === p + "s" || t === p + "es")) return p;
  }
  return null;
}
async function hmacHex(secreto: string, cuerpo: string) {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secreto), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(cuerpo));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
function igual(a: string, b: string) {
  if (a.length !== b.length) return false;
  let r = 0; for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}
async function api(metodo: "GET" | "POST", ruta: string, token = env("IG_TOKEN"), cuerpo?: unknown) {
  if (!token) throw new Error("Falta el secreto IG_TOKEN en Supabase.");
  const h: Record<string, string> = { Authorization: "Bearer " + token };
  if (cuerpo !== undefined) h["Content-Type"] = "application/json";
  const r = await fetch(GRAPH + ruta, { method: metodo, headers: h, body: cuerpo === undefined ? undefined : JSON.stringify(cuerpo) });
  const j = await r.json().catch(() => ({})) as any;
  if (!r.ok || j.error) throw new Error(j.error?.message || `Meta respondió ${r.status}`);
  return j;
}
// Token de la página de Facebook unida al Instagram (para el mensaje privado). Derivado de un token que no vence, tampoco vence.
async function tokenPagina(pageId: string) {
  const j = await api("GET", `/${pageId}?fields=access_token`);
  return j.access_token as string;
}
async function adminDe(req: Request) {
  const auth = req.headers.get("Authorization") ?? "";
  if (!/^Bearer\s+\S+/.test(auth)) return null;
  const cli = createClient(env("SUPABASE_URL"), env("SUPABASE_ANON_KEY"), { auth: { persistSession: false }, global: { headers: { Authorization: auth } } });
  const { data: u } = await cli.auth.getUser();
  if (!u?.user) return null;
  const { data: p } = await db().from("perfiles").select("id, rol, activo, empresa_id").eq("id", u.user.id).single();
  return p && p.activo && p.rol === "admin" ? p : null;
}

// ---------- conectar: busca la cuenta de Instagram a la que tiene acceso el token
async function conectar(sb: SB, yo: { id: string; empresa_id: string }) {
  const j = await api("GET", "/me/accounts?fields=id,name,instagram_business_account{id,username}&limit=50");
  const paginas = (j.data || []).filter((p: any) => p.instagram_business_account?.id);
  if (!paginas.length) throw new Error("El token no tiene acceso a ninguna página de Facebook con Instagram. Revise que al usuario del sistema le asignó la página y la cuenta de Instagram fkservi.");
  const p = paginas.find((x: any) => x.instagram_business_account.username === "fkservi") || paginas[0];
  let nota: string | null = null;
  try {
    const pt = await tokenPagina(p.id);
    await api("POST", `/${p.id}/subscribed_apps?subscribed_fields=feed`, pt);
  } catch (e) { nota = "No se pudo activar el aviso instantáneo (" + (e as Error).message + "). La revisión cada 10 minutos funciona igual."; }
  await sb.from("ig_cuentas").upsert({
    empresa_id: yo.empresa_id, ig_user_id: p.instagram_business_account.id, page_id: p.id,
    usuario: p.instagram_business_account.username || null, conectado_en: new Date().toISOString(), conectado_por: yo.id, ultimo_error: nota,
  });
  return { usuario: p.instagram_business_account.username, nota };
}

// ---------- responder un comentario
type Comentario = { id: string; texto: string; autorId?: string; autor?: string; mediaId?: string; padre?: string };
async function procesar(sb: SB, c: Comentario, origen: "webhook" | "revision") {
  const { data: cta } = await sb.from("ig_cuentas").select("*").limit(1).maybeSingle();
  if (!cta) return "sin conexión";
  if (c.autorId && c.autorId === cta.ig_user_id) return "comentario propio";
  if (c.autor && cta.usuario && c.autor === cta.usuario) return "comentario propio";
  if (c.padre) return "respuesta dentro de un hilo";
  const { data: cfg } = await sb.from("ig_config").select("*").eq("empresa_id", cta.empresa_id).single();
  const palabra = cfg ? palabraClave(c.texto, cfg.palabras || []) : null;
  // Cada comentario se registra una sola vez (si ya estaba, no se responde de nuevo)
  const { data: fila, error } = await sb.from("ig_comentarios").insert({
    empresa_id: cta.empresa_id, comentario_id: c.id, publicacion_id: c.mediaId || null, autor_id: c.autorId || null,
    autor: c.autor || null, texto: (c.texto || "").slice(0, 2200), palabra, origen,
    resultado: !palabra ? "sin palabra clave" : !cfg?.activo ? "automático apagado" : null,
  }).select("id").single();
  if (error) return error.code === "23505" ? "ya procesado" : "error al registrar: " + error.message;
  if (!palabra || !cfg?.activo) return "registrado";

  // A la misma persona se le manda el mensaje privado como máximo una vez cada 24 horas
  let repetido = false;
  const quien = c.autorId ? ["autor_id", c.autorId] : c.autor ? ["autor", c.autor] : null;
  if (quien) {
    const { count } = await sb.from("ig_comentarios").select("id", { count: "exact", head: true })
      .eq("empresa_id", cta.empresa_id).eq(quien[0], quien[1]).eq("mensaje_enviado", true)
      .gte("creado_en", new Date(Date.now() - 864e5).toISOString());
    repetido = (count ?? 0) > 0;
  }
  const notas: string[] = []; let respondido = false, enviado = false;
  try {
    await api("POST", `/${encodeURIComponent(c.id)}/replies`, undefined, { message: cfg.respuesta_publica });
    respondido = true;
  } catch (e) { notas.push("respuesta: " + (e as Error).message); }
  if (repetido) notas.push("mensaje privado ya enviado en las últimas 24 h");
  else {
    const cuerpo = { recipient: { comment_id: c.id }, message: { text: cfg.mensaje_privado } };
    try {
      if (!cta.page_id) throw new Error("sin página");
      await api("POST", `/${cta.page_id}/messages`, await tokenPagina(cta.page_id), cuerpo);
      enviado = true;
    } catch (e1) {
      try { await api("POST", `/${cta.ig_user_id}/messages`, undefined, cuerpo); enviado = true; }
      catch (e2) { notas.push("mensaje: " + (e1 as Error).message + " / " + (e2 as Error).message); }
    }
  }
  await sb.from("ig_comentarios").update({ respondido, mensaje_enviado: enviado, resultado: notas.length ? notas.join(" · ").slice(0, 1000) : "respondido y mensaje enviado" }).eq("id", fila.id);
  return notas.length ? notas.join(" · ") : "ok";
}

// ---------- revisión de comentarios recientes (respaldo por si un aviso no llegó)
async function revisar(sb: SB, forzar = false) {
  const { data: cta } = await sb.from("ig_cuentas").select("*").limit(1).maybeSingle();
  if (!cta) return { revisados: 0, nota: "Instagram no está conectado." };
  const { data: cfg } = await sb.from("ig_config").select("activo").eq("empresa_id", cta.empresa_id).single();
  if (!cfg?.activo && !forzar) return { revisados: 0, nota: "automático apagado" };
  if (!forzar && cta.ultima_revision && Date.now() - new Date(cta.ultima_revision).getTime() < 4 * 60e3) return { revisados: 0, nota: "revisado hace poco" };
  await sb.from("ig_cuentas").update({ ultima_revision: new Date().toISOString() }).eq("empresa_id", cta.empresa_id);
  // Solo comentarios posteriores a la conexión y de los últimos 7 días (Instagram no permite mensaje privado después)
  const desde = Math.max(new Date(cta.conectado_en).getTime(), Date.now() - 7 * 864e5);
  const medios = await api("GET", `/${cta.ig_user_id}/media?fields=id,timestamp&limit=12`);
  let n = 0;
  for (const m of medios.data || []) {
    const cs = await api("GET", `/${m.id}/comments?fields=id,text,timestamp,username,from&limit=50`).catch(() => ({ data: [] }));
    for (const x of cs.data || []) {
      if (new Date(x.timestamp).getTime() < desde) continue;
      const { count } = await sb.from("ig_comentarios").select("id", { count: "exact", head: true }).eq("comentario_id", x.id);
      if (count) continue;
      await procesar(sb, { id: x.id, texto: x.text || "", autorId: x.from?.id, autor: x.from?.username || x.username, mediaId: m.id }, "revision");
      n++;
    }
  }
  if (cta.ultimo_error && /token|IG_TOKEN|permis/i.test(cta.ultimo_error)) await sb.from("ig_cuentas").update({ ultimo_error: null }).eq("empresa_id", cta.empresa_id);
  return { revisados: n };
}

// ---------- rutas
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  const url = new URL(req.url);
  const ruta = url.pathname.replace(/\/+$/, "").split("/").pop() || "";
  const sb = db();
  try {
    if (req.method === "GET" && url.searchParams.get("hub.mode") === "subscribe") {
      const ok = env("IG_VERIFY_TOKEN") && url.searchParams.get("hub.verify_token") === env("IG_VERIFY_TOKEN");
      return ok ? new Response(url.searchParams.get("hub.challenge") ?? "", { status: 200 }) : new Response("token incorrecto", { status: 403 });
    }
    if (ruta === "conectar" && req.method === "POST") {
      const yo = await adminDe(req);
      if (!yo) return json({ error: "Solo el administrador puede conectar Instagram." }, 403);
      return json(await conectar(sb, yo));
    }
    if (ruta === "revisar" && req.method === "POST") {
      if (!(await adminDe(req))) return json({ error: "Solo el administrador." }, 403);
      return json(await revisar(sb, true));
    }
    if (ruta === "tarea" && req.method === "POST") {
      const v = await revisar(sb).catch(async (e) => {
        await sb.from("ig_cuentas").update({ ultimo_error: ("La revisión falló: " + (e as Error).message).slice(0, 1000) }).neq("ig_user_id", "");
        return { revisados: 0, nota: (e as Error).message };
      });
      return json(v);
    }
    // Aviso de Meta: comentarios nuevos
    if (req.method === "POST") {
      const cuerpo = await req.text();
      const firma = (req.headers.get("X-Hub-Signature-256") || "").replace(/^sha256=/, "");
      let valida = false;
      for (const k of [env("META_APP_SECRET"), env("IG_APP_SECRET")].filter(Boolean)) if (firma && igual(firma, await hmacHex(k, cuerpo))) valida = true;
      if (!valida) return new Response("firma inválida", { status: 401 });
      const b = JSON.parse(cuerpo || "{}");
      for (const e of b.entry || []) for (const ch of e.changes || []) {
        if (ch.field !== "comments" || !ch.value?.id) continue;
        const v = ch.value;
        await procesar(sb, { id: String(v.id), texto: v.text || "", autorId: v.from?.id, autor: v.from?.username, mediaId: v.media?.id, padre: v.parent_id }, "webhook");
      }
      return new Response("ok", { status: 200 });
    }
    return json({ error: "Ruta no encontrada" }, 404);
  } catch (e) {
    console.error("ig-webhook:", (e as Error).message);
    return json({ error: (e as Error).message }, 500);
  }
});
