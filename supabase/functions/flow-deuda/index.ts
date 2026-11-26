// Pago con Flow de servicios YA REALIZADOS y pendientes de pago (etapa 76): portal de empresas (/empresa) y app (/app).
// Es una función aparte de "flow" (pago antes de reservar) para no tocar ese cobro.
// Acciones (?accion=...):
//   pagar     POST JSON { reservas: [ids], volver: "empresa" | "app" } con la sesión del cliente (Authorization: Bearer).
//             La base valida que los servicios sean suyos y estén pendientes (deuda_crear_solicitud) y aquí se crea el cobro.
//   confirmar POST de Flow (servidor a servidor) con "token": si está pagado por el monto exacto, deuda_marcar_pagada.
//   volver    POST del navegador al volver de Flow: mismo chequeo y redirige al portal o a la app con ?pago=<id>.
//   estado    GET ?id=<solicitud>: estado del pago para mostrarlo.
// Secretos (los mismos de "flow"): FLOW_API_KEY, FLOW_SECRET_KEY, FLOW_API_URL. Se publica con verify_jwt = false.
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { ...CORS, "Content-Type": "application/json" } });
const env = (k: string) => (Deno.env.get(k) ?? "").trim();
const FLOW_URL = () => (env("FLOW_API_URL") || "https://www.flow.cl/api").replace(/\/+$/, "");
const db = () => createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), { auth: { persistSession: false } });
const UUID = /^[0-9a-f-]{36}$/;
const SITIOS = { empresa: "https://fk-servicios.com/empresa/", app: "https://fk-servicios.com/app/" };

async function firmar(params: Record<string, string>) {
  const cadena = Object.keys(params).sort().map((k) => k + params[k]).join("");
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(env("FLOW_SECRET_KEY")), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(cadena));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
async function flow(metodo: "GET" | "POST", ruta: string, p: Record<string, string>) {
  const faltan = ["FLOW_API_KEY", "FLOW_SECRET_KEY"].filter((k) => !env(k));
  if (faltan.length) throw new Error("Faltan secretos en Supabase: " + faltan.join(", "));
  const params = { ...p, apiKey: env("FLOW_API_KEY") };
  const s = await firmar(params);
  const cuerpo = new URLSearchParams({ ...params, s });
  const url = FLOW_URL() + ruta;
  const r = metodo === "GET" ? await fetch(url + "?" + cuerpo) : await fetch(url, { method: "POST", body: cuerpo, headers: { "Content-Type": "application/x-www-form-urlencoded" } });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(`Flow ${ruta}: ${j.message || r.status}`);
  return j;
}

async function pagar(req: Request) {
  const auth = req.headers.get("Authorization") ?? "";
  if (!/^Bearer\s+\S+/.test(auth)) return json({ error: "Inicie sesión para pagar." }, 401);
  const b = await req.json().catch(() => ({})) as any;
  const ids = (Array.isArray(b.reservas) ? b.reservas : []).map(String).filter((x: string) => UUID.test(x)).slice(0, 60);
  if (!ids.length) return json({ error: "Elija al menos un servicio para pagar." }, 400);
  const volver = b.volver === "app" ? "app" : "empresa";
  // La solicitud se crea con la sesión del cliente: la base revisa que los servicios sean suyos
  const cli = createClient(env("SUPABASE_URL"), env("SUPABASE_ANON_KEY"), { auth: { persistSession: false }, global: { headers: { Authorization: auth } } });
  const { data, error } = await cli.rpc("deuda_crear_solicitud", { p_ids: ids, p_volver: volver });
  if (error) return json({ error: error.message }, 400);
  const sol = Array.isArray(data) ? data[0] : data;
  if (!sol?.o_id) return json({ error: "No pudimos preparar el pago. Intente de nuevo." }, 500);
  const sb = db(), fn = `${env("SUPABASE_URL")}/functions/v1/flow-deuda`;
  try {
    const r = await flow("POST", "/payment/create", {
      commerceOrder: sol.o_orden, subject: sol.o_n > 1 ? `Pago de ${sol.o_n} servicios Flota-K` : "Pago de servicio Flota-K", currency: "CLP",
      amount: String(sol.o_monto), email: sol.o_correo, paymentMethod: "9", timeout: "1800",
      urlConfirmation: `${fn}?accion=confirmar`, urlReturn: `${fn}?accion=volver&id=${sol.o_id}`,
      optional: JSON.stringify({ solicitud: sol.o_id, tipo: "deuda" }),
    });
    await sb.from("solicitudes_pago").update({ flow_token: r.token, flow_order: r.flowOrder }).eq("id", sol.o_id);
    return json({ url: `${r.url}?token=${r.token}`, id: sol.o_id });
  } catch (e) {
    await sb.from("solicitudes_pago").update({ estado: "error", error: (e as Error).message.slice(0, 300) }).eq("id", sol.o_id);
    return json({ error: "El sistema de pago no respondió. Intente de nuevo en unos minutos o escríbanos por WhatsApp." }, 502);
  }
}

// Consulta a Flow y, si está pagado por el monto correcto, marca pagados los servicios. Devuelve el id de la solicitud.
async function revisarPago(token: string) {
  const sb = db();
  const st = await flow("GET", "/payment/getStatus", { token });
  const { data: sol } = await sb.from("solicitudes_pago").select("id, monto, estado, datos").eq("orden", String(st.commerceOrder)).maybeSingle();
  if (!sol || (sol.datos as any)?.tipo !== "deuda") throw new Error("Pago sin solicitud: " + st.commerceOrder);
  if (sol.estado === "pagada") return sol.id;
  const medio = st.paymentData?.media ? String(st.paymentData.media).slice(0, 40) : null;
  if (st.status === 2) { // 2 = pagada
    if (Number(st.amount) !== sol.monto) {
      await sb.from("solicitudes_pago").update({ estado: "error", error: `Monto pagado ${st.amount} distinto de ${sol.monto}` }).eq("id", sol.id);
      throw new Error("Monto no coincide");
    }
    const { error } = await sb.rpc("deuda_marcar_pagada", { p_id: sol.id, p_flow_order: st.flowOrder ?? null, p_medio: medio });
    if (error) { await sb.from("solicitudes_pago").update({ error: "Pagada, pero falló marcar los servicios: " + error.message }).eq("id", sol.id); throw error; }
  } else if (st.status === 3 || st.status === 4) { // 3 = rechazada, 4 = anulada
    await sb.from("solicitudes_pago").update({ estado: "rechazada" }).eq("id", sol.id).eq("estado", "pendiente");
  }
  return sol.id;
}

async function tokenDe(req: Request) {
  const f = await req.formData().catch(() => null);
  return String(f?.get("token") ?? new URL(req.url).searchParams.get("token") ?? "");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  const u = new URL(req.url), accion = u.searchParams.get("accion");
  try {
    if (accion === "pagar" && req.method === "POST") return await pagar(req);
    if (accion === "confirmar") {
      const token = await tokenDe(req);
      if (!token) return new Response("sin token", { status: 400 });
      await revisarPago(token);
      return new Response("ok");
    }
    if (accion === "volver") {
      const token = await tokenDe(req);
      let id = u.searchParams.get("id") ?? "";
      if (token) { try { id = await revisarPago(token); } catch (_) { /* la página muestra el estado */ } }
      let destino = SITIOS.empresa;
      if (UUID.test(id)) {
        const { data: s } = await db().from("solicitudes_pago").select("datos").eq("id", id).maybeSingle();
        if ((s?.datos as any)?.volver === "app") destino = SITIOS.app;
      }
      return new Response(null, { status: 303, headers: { Location: `${destino}?pago=${encodeURIComponent(id)}` } });
    }
    if (accion === "estado") {
      const id = u.searchParams.get("id") ?? "";
      if (!UUID.test(id)) return json({ error: "Solicitud no válida" }, 400);
      const sb = db();
      const { data: s } = await sb.from("solicitudes_pago").select("estado, monto, codigos, flow_token, datos").eq("id", id).maybeSingle();
      if (!s || (s.datos as any)?.tipo !== "deuda") return json({ error: "Solicitud no encontrada" }, 404);
      // Si sigue pendiente y Flow ya tiene el resultado (el aviso de Flow aún no llega), se revisa ahora
      if (s.estado === "pendiente" && s.flow_token) {
        try { await revisarPago(s.flow_token); } catch (_) { /* sigue pendiente */ }
        const { data: s2 } = await sb.from("solicitudes_pago").select("estado, monto, codigos").eq("id", id).single();
        return json(s2);
      }
      return json({ estado: s.estado, monto: s.monto, codigos: s.codigos });
    }
    return json({ error: "Acción no válida" }, 400);
  } catch (e) {
    console.error(e);
    return json({ error: "Error del servidor" }, 500);
  }
});
