// Instagram automático de Flota-K (etapa 79). Reemplaza a ManyChat, sin costo.
// Si alguien comenta en CUALQUIER publicación una palabra clave (por defecto: aeropuerto, precio, tarifa),
// se responde en el comentario y se le manda un mensaje privado con el enlace de reserva.
//
// Rutas (todas en https://<proyecto>.supabase.co/functions/v1/ig-webhook/...):
//   GET  /                 verificación del webhook de Meta (hub.challenge con IG_VERIFY_TOKEN).
//   POST /                 aviso de Meta (comentarios). Se valida la firma X-Hub-Signature-256.
//   POST /conectar         (admin con sesión) devuelve el enlace para autorizar la cuenta de Instagram.
//   GET  /callback         regreso desde Instagram: guarda el permiso (60 días) y suscribe la cuenta a los avisos.
//   POST /revisar          (admin con sesión) revisa ahora los comentarios recientes.
//   POST /tarea            tarea programada (pg_cron cada 10 min): renueva el permiso y revisa comentarios.
//
// Secretos (Supabase → Edge Functions → Secrets): IG_APP_ID, IG_APP_SECRET (los de "Instagram" en la app de Meta),
// IG_VERIFY_TOKEN (una frase cualquiera, la misma que se escribe en Meta), y opcional META_APP_SECRET
// (Configuración de la app → Básica), por si Meta firma los avisos con esa clave.
// Se publica con verify_jwt = false (Meta e Instagram no envían la sesión de Supabase).
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { ...CORS, "Content-Type": "application/json" } });
const env = (k: string) => (Deno.env.get(k) ?? "").trim();
const db = () => createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), { auth: { persistSession: false } });
const GRAPH = "https://graph.instagram.com/v22.0";
const PANEL = "https://fk-servicios.com/equipo/";
const redirectUri = () => `${env("SUPABASE_URL")}/functions/v1/ig-webhook/callback`;
const SCOPES = "instagram_business_basic,instagram_business_manage_comments,instagram_business_manage_messages";

// ---------- utilidades
const norm = (s: string) => (s || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
function palabraClave(texto: string, palabras: string[]): string | null {
  const tokens = norm(texto).split(/[^a-z0-9ñ]+/).filter(Boolean);
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
async function ig(metodo: "GET" | "POST", url: string, token?: string, cuerpo?: unknown) {
  const h: Record<string, string> = {};
  if (token) h["Authorization"] = "Bearer " + token;
  if (cuerpo !== undefined) h["Content-Type"] = "application/json";
  const r = await fetch(url, { method: metodo, headers: h, body: cuerpo === undefined ? undefined : JSON.stringify(cuerpo) });
  const j = await r.json().catch(() => ({})) as any;
  if (!r.ok || j.error) throw new Error(j.error?.message || j.error_message || `Instagram respondió ${r.status}`);
  return j;
}
async function empresaFlotaK(sb: ReturnType<typeof db>) {
  const { data } = await sb.from("empresas").select("id").eq("slug", "flota-k").single();
  return data?.id as string;
}
// Revisa que quien llama tenga sesión de administrador (para /conectar y /revisar)
async function adminDe(req: Request) {
  const auth = req.headers.get("Authorization") ?? "";
  if (!/^Bearer\s+\S+/.test(auth)) return null;
  const cli = createClient(env("SUPABASE_URL"), env("SUPABASE_ANON_KEY"), { auth: { persistSession: false }, global: { headers: { Authorization: auth } } });
  const { data: u } = await cli.auth.getUser();
  if (!u?.user) return null;
  const { data: p } = await db().from("perfiles").select("id, rol, activo, empresa_id").eq("id", u.user.id).single();
  return p && p.activo && p.rol === "admin" ? p : null;
}

// ---------- responder un comentario
type Comentario = { id: string; texto: string; autorId?: string; autor?: string; mediaId?: string; padre?: string };
async function procesar(sb: ReturnType<typeof db>, c: Comentario, origen: "webhook" | "revision") {
  const { data: cta } = await sb.from("ig_cuentas").select("*").limit(1).maybeSingle();
  if (!cta) return "sin conexión";
  if (c.autorId && c.autorId === cta.ig_user_id) return "comentario propio";
  if (c.padre) return "respuesta dentro de un hilo";
  const { data: cfg } = await sb.from("ig_config").select("*").eq("empresa_id", cta.empresa_id).single();
  const palabra = cfg ? palabraClave(c.texto, cfg.palabras || []) : null;
  // Se registra cada comentario una sola vez (si ya estaba, no se responde de nuevo)
  const { data: fila, error } = await sb.from("ig_comentarios").insert({
    empresa_id: cta.empresa_id, comentario_id: c.id, publicacion_id: c.mediaId || null, autor_id: c.autorId || null,
    autor: c.autor || null, texto: (c.texto || "").slice(0, 2200), palabra, origen,
    resultado: !palabra ? "sin palabra clave" : !cfg?.activo ? "automático apagado" : null,
  }).select("id").single();
  if (error) return error.code === "23505" ? "ya procesado" : "error al registrar: " + error.message;
  if (!palabra || !cfg?.activo) return "registrado";

  // A la misma persona se le manda el mensaje privado como máximo una vez cada 24 horas
  let repetido = false;
  if (c.autorId) {
    const { count } = await sb.from("ig_comentarios").select("id", { count: "exact", head: true })
      .eq("empresa_id", cta.empresa_id).eq("autor_id", c.autorId).eq("mensaje_enviado", true)
      .gte("creado_en", new Date(Date.now() - 864e5).toISOString());
    repetido = (count ?? 0) > 0;
  }
  const notas: string[] = []; let respondido = false, enviado = false;
  try {
    await ig("POST", `${GRAPH}/${encodeURIComponent(c.id)}/replies`, cta.token, { message: cfg.respuesta_publica });
    respondido = true;
  } catch (e) { notas.push("respuesta: " + (e as Error).message); }
  if (repetido) notas.push("mensaje privado ya enviado en las últimas 24 h");
  else {
    try {
      await ig("POST", `${GRAPH}/${encodeURIComponent(cta.ig_user_id)}/messages`, cta.token, { recipient: { comment_id: c.id }, message: { text: cfg.mensaje_privado } });
      enviado = true;
    } catch (e) { notas.push("mensaje: " + (e as Error).message); }
  }
  await sb.from("ig_comentarios").update({ respondido, mensaje_enviado: enviado, resultado: notas.length ? notas.join(" · ").slice(0, 1000) : "respondido y mensaje enviado" }).eq("id", fila.id);
  return notas.length ? notas.join(" · ") : "ok";
}

// ---------- revisión de comentarios recientes (respaldo por si un aviso no llegó)
async function revisar(sb: ReturnType<typeof db>, forzar = false) {
  const { data: cta } = await sb.from("ig_cuentas").select("*").limit(1).maybeSingle();
  if (!cta) return { revisados: 0, nota: "Instagram no está conectado." };
  const { data: cfg } = await sb.from("ig_config").select("activo").eq("empresa_id", cta.empresa_id).single();
  if (!cfg?.activo && !forzar) return { revisados: 0, nota: "automático apagado" };
  if (!forzar && cta.ultima_revision && Date.now() - new Date(cta.ultima_revision).getTime() < 4 * 60e3) return { revisados: 0, nota: "revisado hace poco" };
  await sb.from("ig_cuentas").update({ ultima_revision: new Date().toISOString() }).eq("empresa_id", cta.empresa_id);
  // Solo comentarios posteriores a la conexión y de los últimos 7 días (Instagram no permite mensaje privado después)
  const desde = Math.max(new Date(cta.conectado_en).getTime(), Date.now() - 7 * 864e5);
  const medios = await ig("GET", `${GRAPH}/me/media?fields=id,timestamp&limit=12`, cta.token);
  let n = 0;
  for (const m of medios.data || []) {
    const cs = await ig("GET", `${GRAPH}/${m.id}/comments?fields=id,text,timestamp,username,from&limit=50`, cta.token).catch(() => ({ data: [] }));
    for (const x of cs.data || []) {
      if (new Date(x.timestamp).getTime() < desde) continue;
      const { count } = await sb.from("ig_comentarios").select("id", { count: "exact", head: true }).eq("comentario_id", x.id);
      if (count) continue;
      await procesar(sb, { id: x.id, texto: x.text || "", autorId: x.from?.id, autor: x.from?.username || x.username, mediaId: m.id }, "revision");
      n++;
    }
  }
  return { revisados: n };
}

// ---------- permiso: renovar antes de que venza (dura 60 días; se renueva si faltan menos de 15)
async function renovar(sb: ReturnType<typeof db>) {
  const { data: cta } = await sb.from("ig_cuentas").select("*").limit(1).maybeSingle();
  if (!cta) return "sin conexión";
  const vence = cta.token_vence ? new Date(cta.token_vence).getTime() : 0;
  if (vence - Date.now() > 15 * 864e5) return "vigente";
  if (Date.now() - new Date(cta.token_renovado_en).getTime() < 864e5) return "renovado hace menos de 24 h";
  try {
    const j = await ig("GET", `https://graph.instagram.com/refresh_access_token?grant_type=ig_refresh_token&access_token=${encodeURIComponent(cta.token)}`);
    await sb.from("ig_cuentas").update({ token: j.access_token, token_vence: new Date(Date.now() + (j.expires_in || 5184000) * 1000).toISOString(), token_renovado_en: new Date().toISOString(), ultimo_error: null }).eq("empresa_id", cta.empresa_id);
    return "renovado";
  } catch (e) {
    await sb.from("ig_cuentas").update({ ultimo_error: ("No se pudo renovar el permiso: " + (e as Error).message).slice(0, 1000) }).eq("empresa_id", cta.empresa_id);
    return "error";
  }
}

// ---------- rutas
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  const url = new URL(req.url);
  const ruta = url.pathname.replace(/\/+$/, "").split("/").pop() || "";
  const sb = db();
  try {
    // Verificación del webhook (Meta la hace una vez al configurarlo)
    if (req.method === "GET" && url.searchParams.get("hub.mode") === "subscribe") {
      const ok = env("IG_VERIFY_TOKEN") && url.searchParams.get("hub.verify_token") === env("IG_VERIFY_TOKEN");
      return ok ? new Response(url.searchParams.get("hub.challenge") ?? "", { status: 200 }) : new Response("token incorrecto", { status: 403 });
    }

    if (ruta === "conectar" && req.method === "POST") {
      const yo = await adminDe(req);
      if (!yo) return json({ error: "Solo el administrador puede conectar Instagram." }, 403);
      if (!env("IG_APP_ID") || !env("IG_APP_SECRET")) return json({ error: "Faltan los secretos IG_APP_ID e IG_APP_SECRET en Supabase." }, 400);
      const estado = crypto.randomUUID();
      await sb.from("ig_oauth_estado").delete().lt("creado_en", new Date(Date.now() - 3600e3).toISOString());
      await sb.from("ig_oauth_estado").insert({ estado, empresa_id: yo.empresa_id, creado_por: yo.id });
      const q = new URLSearchParams({ client_id: env("IG_APP_ID"), redirect_uri: redirectUri(), response_type: "code", scope: SCOPES, state: estado });
      return json({ url: "https://www.instagram.com/oauth/authorize?" + q });
    }

    if (ruta === "callback" && req.method === "GET") {
      const volver = (r: string) => Response.redirect(PANEL + "?ig=" + encodeURIComponent(r), 302);
      if (url.searchParams.get("error")) return volver("cancelado");
      const code = (url.searchParams.get("code") || "").replace(/#_$/, "");
      const estado = url.searchParams.get("state") || "";
      const { data: st } = await sb.from("ig_oauth_estado").select("*").eq("estado", estado).maybeSingle();
      if (!code || !st || Date.now() - new Date(st.creado_en).getTime() > 3600e3) return volver("vencido");
      await sb.from("ig_oauth_estado").delete().eq("estado", estado);
      // 1) código → permiso corto
      const f = new FormData();
      f.append("client_id", env("IG_APP_ID")); f.append("client_secret", env("IG_APP_SECRET"));
      f.append("grant_type", "authorization_code"); f.append("redirect_uri", redirectUri()); f.append("code", code);
      const r1 = await fetch("https://api.instagram.com/oauth/access_token", { method: "POST", body: f });
      const j1 = await r1.json().catch(() => ({})) as any;
      if (!r1.ok || !j1.access_token) return volver("error");
      // 2) permiso corto → permiso de 60 días
      const j2 = await ig("GET", `https://graph.instagram.com/access_token?grant_type=ig_exchange_token&client_secret=${encodeURIComponent(env("IG_APP_SECRET"))}&access_token=${encodeURIComponent(j1.access_token)}`);
      const token = j2.access_token as string;
      // 3) datos de la cuenta y suscripción a los avisos de comentarios
      const me = await ig("GET", `${GRAPH}/me?fields=user_id,username`, token);
      let nota: string | null = null;
      try { await ig("POST", `${GRAPH}/me/subscribed_apps?subscribed_fields=comments,messages`, token); }
      catch (e) { nota = "No se pudo activar el aviso de comentarios: " + (e as Error).message + ". La revisión cada 10 minutos sigue funcionando."; }
      await sb.from("ig_cuentas").upsert({
        empresa_id: st.empresa_id, ig_user_id: String(me.user_id || me.id || j1.user_id), usuario: me.username || null, token,
        token_vence: new Date(Date.now() + (j2.expires_in || 5184000) * 1000).toISOString(), token_renovado_en: new Date().toISOString(),
        conectado_en: new Date().toISOString(), conectado_por: st.creado_por, ultimo_error: nota,
      });
      return volver("ok");
    }

    if (ruta === "revisar" && req.method === "POST") {
      if (!(await adminDe(req))) return json({ error: "Solo el administrador." }, 403);
      await renovar(sb);
      return json(await revisar(sb, true));
    }

    if (ruta === "tarea" && req.method === "POST") {
      const r = await renovar(sb);
      const v = await revisar(sb).catch((e) => ({ revisados: 0, nota: (e as Error).message }));
      return json({ permiso: r, ...v });
    }

    // Aviso de Meta: comentarios nuevos
    if (req.method === "POST") {
      const cuerpo = await req.text();
      const firma = (req.headers.get("X-Hub-Signature-256") || "").replace(/^sha256=/, "");
      const claves = [env("IG_APP_SECRET"), env("META_APP_SECRET")].filter(Boolean);
      let valida = false;
      for (const k of claves) if (firma && igual(firma, await hmacHex(k, cuerpo))) valida = true;
      if (!valida) return new Response("firma inválida", { status: 401 });
      const b = JSON.parse(cuerpo || "{}");
      for (const e of b.entry || []) for (const ch of e.changes || []) {
        if (ch.field !== "comments" || !ch.value?.id) continue;
        const v = ch.value;
        await procesar(sb, { id: String(v.id), texto: v.text || "", autorId: v.from?.id, autor: v.from?.username, mediaId: v.media?.id, padre: v.parent_id }, "webhook");
      }
      return new Response("ok", { status: 200 }); // Meta solo necesita un 200 rápido
    }
    return json({ error: "Ruta no encontrada" }, 404);
  } catch (e) {
    console.error("ig-webhook:", (e as Error).message);
    if (ruta === "callback") return Response.redirect(PANEL + "?ig=error", 302);
    return json({ error: (e as Error).message }, 500);
  }
});
