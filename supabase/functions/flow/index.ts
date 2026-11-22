// Pago con Flow ANTES de crear la reserva (página /reservar).
// Acciones (?accion=...):
//   pagar     POST JSON desde /reservar: valida, calcula el precio en el servidor, guarda la solicitud y crea el pago en Flow.
//   confirmar POST de Flow (urlConfirmation, servidor a servidor) con "token": consulta payment/getStatus y, si está
//             pagado por el monto exacto, crea la(s) reserva(s) con crear_reservas_pagadas.
//   volver    POST del navegador del pasajero al volver de Flow (urlReturn): mismo chequeo y redirige a /reservar/?pago=<id>.
//   estado    GET ?id=<solicitud>: estado para mostrar en la página.
// Secretos (Supabase → Edge Functions → Secrets): FLOW_API_KEY, FLOW_SECRET_KEY, FLOW_API_URL
//   (https://sandbox.flow.cl/api para pruebas, https://www.flow.cl/api para cobrar de verdad).
// Se publica con verify_jwt = false (Flow no envía la sesión de Supabase).
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { ...CORS, "Content-Type": "application/json" } });
const SITIO = "https://fk-servicios.com/reservar/";
const AERO = { lat: -33.39297, lng: -70.78579, texto: "Aeropuerto Internacional de Santiago (SCL), Pudahuel" };
const MIN_ANTICIPACION_H = 2;

const env = (k: string) => (Deno.env.get(k) ?? "").trim();
// Si FLOW_API_URL no está, se usa la de producción (cobro real)
const FLOW_URL = () => (env("FLOW_API_URL") || "https://www.flow.cl/api").replace(/\/+$/, "");
const db = () => createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), { auth: { persistSession: false } });
const norm = (s: string) => String(s || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
const distKm = (a: { lat: number; lng: number }, b: { lat: number; lng: number }) => {
  const R = 6371, r = (x: number) => x * Math.PI / 180, dLa = r(b.lat - a.lat), dLo = r(b.lng - a.lng);
  return 2 * R * Math.asin(Math.sqrt(Math.sin(dLa / 2) ** 2 + Math.cos(r(a.lat)) * Math.cos(r(b.lat)) * Math.sin(dLo / 2) ** 2));
};
const enChile = (lat: number, lng: number) => Number.isFinite(lat) && Number.isFinite(lng) && lat >= -56 && lat <= -17 && lng >= -76 && lng <= -66;
const redondear = (n: number) => Math.ceil(n / 500) * 500;
const txt = (v: unknown, max: number) => String(v ?? "").trim().slice(0, max);

// ---------- Flow ----------
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

// ---------- Pórticos TAG (OpenStreetMap, tabla osm_datos clave "porticos") ----------
type Portico = { id: number; nombre: string; lat: number; lng: number; rumbo: number | null; caseta: boolean };
let PORTICOS: Portico[] | null = null, porticosCargados = 0;
const rumbo = (a: number[], b: number[]) => { // grados, a y b = [lat, lng]
  const r = (x: number) => x * Math.PI / 180, y = Math.sin(r(b[1] - a[1])) * Math.cos(r(b[0]));
  const x = Math.cos(r(a[0])) * Math.sin(r(b[0])) - Math.sin(r(a[0])) * Math.cos(r(b[0])) * Math.cos(r(b[1] - a[1]));
  return (Math.atan2(y, x) * 180 / Math.PI + 360) % 360;
};
async function porticos(sb: ReturnType<typeof db>) {
  if (PORTICOS && Date.now() - porticosCargados < 3600e3) return PORTICOS;
  const { data } = await sb.from("osm_datos").select("datos").eq("clave", "porticos").maybeSingle();
  const els: any[] = data?.datos?.elements ?? [];
  const vias = els.filter((e) => e.type === "way");
  PORTICOS = els.filter((e) => e.type === "node").map((n) => {
    let rb: number | null = null;
    for (const w of vias) {
      const i = (w.nodes || []).indexOf(n.id); if (i < 0 || !w.geometry) continue;
      const ow = w.tags?.oneway, uni = ow === "yes" || ow === "-1" || w.tags?.highway === "motorway" || w.tags?.junction === "roundabout";
      if (!uni) break; // vía de doble sentido: cuenta en ambos sentidos
      const g = w.geometry, a = g[Math.max(0, i - 1)], b = g[Math.min(g.length - 1, i + 1)];
      rb = rumbo([a.lat, a.lon], [b.lat, b.lon]); if (ow === "-1") rb = (rb + 180) % 360;
      break;
    }
    return { id: n.id, nombre: n.tags?.name || n.tags?.ref || "Pórtico", lat: n.lat, lng: n.lon, rumbo: rb, caseta: n.tags?.barrier === "toll_booth" };
  });
  porticosCargados = Date.now();
  return PORTICOS;
}
// Pórticos por los que pasa la ruta (a menos de 25 m de la calzada y en el mismo sentido de circulación)
function porticosEnRuta(ruta: number[][], lista: Portico[]) { // ruta = [[lng, lat], ...]
  const res: Portico[] = [];
  const cosLat = Math.cos(-33.45 * Math.PI / 180), M = 111320;
  for (const p of lista) {
    let mejor = Infinity, rbRuta = 0;
    for (let i = 1; i < ruta.length; i++) {
      const [x1, y1] = [(ruta[i - 1][0] - p.lng) * M * cosLat, (ruta[i - 1][1] - p.lat) * M];
      const [x2, y2] = [(ruta[i][0] - p.lng) * M * cosLat, (ruta[i][1] - p.lat) * M];
      const dx = x2 - x1, dy = y2 - y1, L = dx * dx + dy * dy;
      const t = L ? Math.max(0, Math.min(1, -(x1 * dx + y1 * dy) / L)) : 0;
      const d = Math.hypot(x1 + t * dx, y1 + t * dy);
      if (d < mejor) { mejor = d; rbRuta = rumbo([ruta[i - 1][1], ruta[i - 1][0]], [ruta[i][1], ruta[i][0]]); }
    }
    if (mejor > 25) continue;
    if (p.rumbo != null) { const dif = Math.abs(((rbRuta - p.rumbo) + 540) % 360 - 180); if (dif > 60) continue; }
    res.push(p);
  }
  return res;
}

// ---------- Precio (servidor) ----------
type Tramo = Record<string, unknown>;
async function cotizar(sb: ReturnType<typeof db>, empresaId: string, b: Record<string, unknown>) {
  const tipo = String(b.tipo), veh = b.vehiculo === "van" ? "van" : "auto";
  if (tipo === "ida" || tipo === "regreso") {
    const { data: z } = await sb.from("tarifas_aeropuerto").select("zona, ida, regreso, van").eq("empresa_id", empresaId).eq("zona", String(b.zona ?? "")).maybeSingle();
    if (!z) throw new Error("Elija su sector de la lista para calcular la tarifa fija.");
    const iv = tipo === "ida" && b.ida_vuelta === true;
    const ida = veh === "van" ? z.van : tipo === "regreso" ? z.regreso : z.ida;
    return { zona: z.zona, ida, regreso: iv ? (veh === "van" ? z.van : z.ida) : null, estimado: false, km: null };
  }
  if (tipo !== "punto_a_punto") throw new Error("Tipo de servicio no válido.");
  const o = b.origen as any, d = b.destino as any;
  if (!o || !d || !enChile(+o.lat, +o.lng) || !enChile(+d.lat, +d.lng)) throw new Error("Marque en el mapa el origen y el destino.");
  if (distKm(o, AERO) < 3 || distKm(d, AERO) < 3) throw new Error("Para viajes desde o hacia el aeropuerto elija «Al aeropuerto» o «Desde el aeropuerto»: tienen tarifa fija.");
  // Tramos con tarifa fija (por comuna en el texto de la dirección)
  const { data: tramos } = await sb.from("tarifas_tramos").select("*").eq("empresa_id", empresaId);
  const to = norm(o.texto), td = norm(d.texto), tiene = (t: string, l: string[]) => l.some((c) => t.includes(c));
  const tf = (tramos || []).find((x: any) => (tiene(to, x.lado_a) && tiene(td, x.lado_b)) || (tiene(to, x.lado_b) && tiene(td, x.lado_a)));
  if (tf) return { zona: null, ida: veh === "van" ? tf.van : tf.auto, regreso: null, estimado: false, km: null, nota: tf.nombre };
  // Ruta real (OSRM). Si no responde, no se cobra en línea: mejor confirmar el valor por WhatsApp.
  let km: number | null = null, min = 0, geo: number[][] = [];
  try {
    const r = await fetch(`https://router.project-osrm.org/route/v1/driving/${o.lng},${o.lat};${d.lng},${d.lat}?overview=full&geometries=geojson`, { signal: AbortSignal.timeout(8000) });
    const x = ((await r.json()).routes || [])[0];
    if (x) { km = Math.round(x.distance / 100) / 10; min = Math.max(1, Math.ceil(x.duration * 1.25 / 60)); geo = x.geometry?.coordinates ?? []; }
  } catch (_) { /* sin ruta */ }
  if (km == null) throw new Error("No pudimos calcular la ruta en este momento. Intente de nuevo en unos minutos o escríbanos por WhatsApp.");
  if (km > 120) throw new Error(`Viaje largo (${km} km): se lo cotizamos por WhatsApp al +56 9 2227 5399.`);
  const { data: e } = await sb.from("empresas").select("taxi_bajada, taxi_cada_200m, valor_tag").eq("id", empresaId).single();
  const { data: T } = await sb.from("tarifas_aeropuerto").select("ida, van").eq("empresa_id", empresaId);
  const fs = (T || []).map((r: any) => r.van / r.ida).filter((x: number) => x > 1 && x < 3).sort((a: number, b: number) => a - b);
  const factorVan = fs.length ? fs[Math.floor(fs.length / 2)] : 1.35;
  const auto = Math.max(5000, (e?.taxi_bajada ?? 2400) + Math.ceil(km * 5) * (e?.taxi_cada_200m ?? 180));
  // TAG: pórticos de la ruta x valor por pórtico (hoy $900, criterio Servimóvil). Las casetas de peaje troncal se informan aparte.
  const enRuta = geo.length > 1 ? porticosEnRuta(geo, await porticos(sb)) : [];
  const nPort = enRuta.filter((p) => !p.caseta).length, casetas = enRuta.filter((p) => p.caseta).map((p) => p.nombre);
  const tag = nPort * (e?.valor_tag ?? 900);
  const base = redondear(veh === "van" ? Math.max(25000, auto * factorVan) : auto);
  return { zona: null, ida: base + tag, regreso: null, estimado: true, km, min, base, porticos: nPort, tag, casetas, nombres_porticos: enRuta.filter((p) => !p.caseta).map((p) => p.nombre) };
}

// ---------- Acciones ----------
async function pagar(req: Request) {
  const sb = db();
  const b = await req.json().catch(() => ({})) as Record<string, any>;
  const { data: emp } = await sb.from("empresas").select("id").eq("slug", "flota-k").single();
  const c = {
    nombre: txt(b.nombre, 120), telefono: txt(b.telefono, 30), correo: txt(b.correo, 200).toLowerCase(),
    pasajero_nombre: txt(b.pasajero_nombre, 120) || null, pasajero_telefono: txt(b.pasajero_telefono, 30) || null, como: txt(b.como, 30) || null,
  };
  const tel = c.telefono.replace(/\D/g, "");
  if (c.nombre.length < 2) return json({ error: "Escriba su nombre." }, 400);
  if (tel.length < 8) return json({ error: "Escriba su teléfono de WhatsApp." }, 400);
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(c.correo)) return json({ error: "Escriba su correo: ahí le llega el comprobante de pago." }, 400);
  if (c.pasajero_nombre && (c.pasajero_telefono ?? "").replace(/\D/g, "").length < 8) return json({ error: "Escriba el teléfono de la persona que viaja." }, 400);

  const fh = new Date(String(b.fecha_hora));
  if (isNaN(+fh)) return json({ error: "Indique la fecha y la hora." }, 400);
  if (+fh < Date.now() + MIN_ANTICIPACION_H * 3600e3) return json({ error: "Para viajes en menos de 2 horas, escríbanos por WhatsApp al +56 9 2227 5399." }, 400);
  if (+fh > Date.now() + 365 * 864e5) return json({ error: "La fecha es demasiado lejana." }, 400);
  const o = b.origen ?? {};
  if (!enChile(+o.lat, +o.lng) || txt(o.texto, 300).length < 3) return json({ error: "Marque en el mapa el punto exacto de retiro." }, 400);
  if (String(b.tipo) !== "punto_a_punto" && distKm({ lat: +o.lat, lng: +o.lng }, AERO) < 3)
    return json({ error: "La dirección de retiro (o de destino, si viene desde el aeropuerto) debe ser su domicilio u otro lugar, no el aeropuerto." }, 400);
  const pax = Math.min(15, Math.max(1, parseInt(b.pasajeros) || 1)), mal = Math.min(30, Math.max(0, parseInt(b.maletas) || 0));

  // Control de abuso
  const hace1h = new Date(Date.now() - 3600e3).toISOString();
  const { count: nTel } = await sb.from("solicitudes_pago").select("id", { count: "exact", head: true }).eq("telefono", tel).gte("creada_en", hace1h);
  const { count: nTot } = await sb.from("solicitudes_pago").select("id", { count: "exact", head: true }).gte("creada_en", hace1h);
  if ((nTel ?? 0) >= 8) return json({ error: "Recibimos varios intentos seguidos desde este teléfono. Escríbanos por WhatsApp." }, 429);
  if ((nTot ?? 0) >= 60) return json({ error: "En este momento no podemos recibir más pagos en línea. Escríbanos por WhatsApp al +56 9 2227 5399." }, 429);

  let p;
  try { p = await cotizar(sb, emp!.id, b); } catch (e) { return json({ error: (e as Error).message }, 400); }
  const total = p.ida + (p.regreso ?? 0);
  // Si el valor que vio el pasajero no coincide con el del servidor, se le muestra el correcto antes de cobrar
  if (Number(b.monto_visto) !== total) return json({ monto: total, cambio: true, error: `El valor de su viaje es $${total.toLocaleString("es-CL")}. Revíselo y toque de nuevo «Pagar y reservar».` }, 409);

  const tipo = String(b.tipo), veh = b.vehiculo === "van" ? "van" : "auto";
  const d = b.destino ?? {}, base = { pasajeros: pax, maletas: mal, vehiculo: veh, comuna: p.zona, comentarios: txt(b.comentarios, 500) };
  const tramos: Tramo[] = [];
  const ivTxt = p.regreso ? "Ida y vuelta (regreso al valor de la ida)." : "";
  if (tipo === "ida") tramos.push({ ...base, tipo_servicio: "ida", fecha_hora: fh.toISOString(), origen: txt(o.texto, 300), origen_lat: +o.lat, origen_lng: +o.lng,
    destino: AERO.texto, destino_lat: AERO.lat, destino_lng: AERO.lng, vuelo: txt(b.vuelo, 12) || null, retiro_detalle: txt(b.retiro_detalle, 200), monto: p.ida,
    comentarios: [ivTxt, base.comentarios].filter(Boolean).join(" ") });
  if (tipo === "regreso" || p.regreso) {
    const fh2 = p.regreso ? new Date(String(b.fecha_hora_regreso)) : fh;
    if (isNaN(+fh2) || +fh2 <= +fh && p.regreso) return json({ error: "El regreso debe ser después de la ida." }, 400);
    tramos.push({ ...base, tipo_servicio: "regreso", fecha_hora: fh2.toISOString(), origen: AERO.texto, origen_lat: AERO.lat, origen_lng: AERO.lng,
      destino: txt(o.texto, 300), destino_lat: +o.lat, destino_lng: +o.lng, vuelo: txt(p.regreso ? b.vuelo_regreso : b.vuelo, 12) || null,
      monto: p.regreso ?? p.ida, comentarios: [ivTxt, "Hora indicada = aterrizaje.", base.comentarios].filter(Boolean).join(" ") });
  }
  if (tipo === "punto_a_punto") tramos.push({ ...base, tipo_servicio: "punto_a_punto", fecha_hora: fh.toISOString(), origen: txt(o.texto, 300), origen_lat: +o.lat, origen_lng: +o.lng,
    destino: txt(d.texto, 300), destino_lat: +d.lat, destino_lng: +d.lng, retiro_detalle: txt(b.retiro_detalle, 200), monto: p.ida, estimado: p.estimado, km: p.km,
    porticos: (p as any).porticos ?? 0, tag: (p as any).tag ?? 0,
    comentarios: [base.comentarios, (p as any).porticos ? `Incluye TAG: ${(p as any).porticos} pórtico(s) = $${(p as any).tag}.` : "",
      (p as any).casetas?.length ? `Ruta con peaje troncal: ${(p as any).casetas.join(", ")} (no incluido).` : ""].filter(Boolean).join(" ") });

  const orden = "FKW-" + Date.now().toString(36).toUpperCase() + "-" + crypto.randomUUID().slice(0, 4).toUpperCase();
  const { data: sol, error } = await sb.from("solicitudes_pago").insert({ empresa_id: emp!.id, orden, datos: { contacto: c, tramos }, monto: total, telefono: tel, correo: c.correo }).select("id").single();
  if (error) return json({ error: "No pudimos guardar su solicitud. Intente de nuevo." }, 500);

  const fn = `${env("SUPABASE_URL")}/functions/v1/flow`;
  try {
    const r = await flow("POST", "/payment/create", {
      commerceOrder: orden, subject: tramos.length > 1 ? "Traslados Flota-K (ida y vuelta)" : "Traslado Flota-K", currency: "CLP",
      amount: String(total), email: c.correo, paymentMethod: "9", timeout: "1800",
      urlConfirmation: `${fn}?accion=confirmar`, urlReturn: `${fn}?accion=volver&id=${sol.id}`,
      optional: JSON.stringify({ solicitud: sol.id }),
    });
    await sb.from("solicitudes_pago").update({ flow_token: r.token, flow_order: r.flowOrder }).eq("id", sol.id);
    return json({ url: `${r.url}?token=${r.token}`, id: sol.id });
  } catch (e) {
    await sb.from("solicitudes_pago").update({ estado: "error", error: (e as Error).message.slice(0, 300) }).eq("id", sol.id);
    return json({ error: "El sistema de pago no respondió. Intente de nuevo en unos minutos o escríbanos por WhatsApp." }, 502);
  }
}

// Consulta a Flow y, si está pagado por el monto correcto, crea la reserva. Devuelve el id de la solicitud.
async function revisarPago(token: string) {
  const sb = db();
  const st = await flow("GET", "/payment/getStatus", { token });
  const { data: sol } = await sb.from("solicitudes_pago").select("id, monto, estado").eq("orden", String(st.commerceOrder)).maybeSingle();
  if (!sol) throw new Error("Pago sin solicitud: " + st.commerceOrder);
  if (sol.estado === "pagada") return sol.id;
  const medio = st.paymentData?.media ? String(st.paymentData.media).slice(0, 40) : null;
  if (st.status === 2) { // 2 = pagada
    if (Number(st.amount) !== sol.monto) {
      await sb.from("solicitudes_pago").update({ estado: "error", error: `Monto pagado ${st.amount} distinto de ${sol.monto}` }).eq("id", sol.id);
      throw new Error("Monto no coincide");
    }
    const { error } = await sb.rpc("crear_reservas_pagadas", { p_id: sol.id, p_flow_order: st.flowOrder ?? null, p_medio: medio });
    if (error) { await sb.from("solicitudes_pago").update({ error: "Pagada, pero falló crear la reserva: " + error.message }).eq("id", sol.id); throw error; }
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
    if (accion === "cotizar" && req.method === "POST") {
      const sb = db(), b = await req.json().catch(() => ({}));
      const { data: emp } = await sb.from("empresas").select("id").eq("slug", "flota-k").single();
      try { return json(await cotizar(sb, emp!.id, b)); } catch (e) { return json({ error: (e as Error).message }, 400); }
    }
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
      return new Response(null, { status: 303, headers: { Location: `${SITIO}?pago=${encodeURIComponent(id)}` } });
    }
    if (accion === "estado") {
      const id = u.searchParams.get("id") ?? "";
      if (!/^[0-9a-f-]{36}$/.test(id)) return json({ error: "Solicitud no válida" }, 400);
      const { data: s } = await db().from("solicitudes_pago").select("estado, monto, codigos, token_seguimiento, flow_token").eq("id", id).maybeSingle();
      if (!s) return json({ error: "Solicitud no encontrada" }, 404);
      // Si sigue pendiente y Flow ya tiene el resultado (por ejemplo, el aviso de Flow aún no llegó), se revisa ahora
      if (s.estado === "pendiente" && s.flow_token) {
        try { await revisarPago(s.flow_token); } catch (_) { /* sigue pendiente */ }
        const { data: s2 } = await db().from("solicitudes_pago").select("estado, monto, codigos, token_seguimiento").eq("id", id).single();
        return json(s2);
      }
      const { flow_token: _, ...rest } = s;
      return json(rest);
    }
    return json({ error: "Acción no válida" }, 400);
  } catch (e) {
    console.error(e);
    return json({ error: "Error del servidor" }, 500);
  }
});
