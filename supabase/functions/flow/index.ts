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
import { prepararDatos, sectorPorUbicacion, comunaDe, type Datos } from "./sector.ts";

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
const norm = (s: string) => String(s || "").toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
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
// Vespucio Oriente (AVO): cobra por km entre entrada y salida. Regla del dueño (23 nov 2026): si la ruta pasa por AVO
// se cobran 2 pórticos fijos (entrada y salida). osm_datos "avo" = nodos de sus calzadas.
let AVO: Set<number> = new Set();
// Peajes de carretera (plazas con caseta, osm_datos "casetas"): se cobran a precio costo y de ida y vuelta (el móvil vuelve).
// Regla del dueño (23 nov 2026). Las plazas troncales se detectan por cercanía a la ruta (< 60 m; una plaza tiene varias pistas);
// las laterales (salidas) solo si la ruta pasa por ese nodo exacto (para no cobrar la salida que no se usa).
type Caseta = { id: number; plaza: string; lat: number; lng: number; valor: number; punta: number | null; troncal: boolean };
let CASETAS: Caseta[] = [];
const rumbo = (a: number[], b: number[]) => { // grados, a y b = [lat, lng]
  const r = (x: number) => x * Math.PI / 180, y = Math.sin(r(b[1] - a[1])) * Math.cos(r(b[0]));
  const x = Math.cos(r(a[0])) * Math.sin(r(b[0])) - Math.sin(r(a[0])) * Math.cos(r(b[0])) * Math.cos(r(b[1] - a[1]));
  return (Math.atan2(y, x) * 180 / Math.PI + 360) % 360;
};
async function porticos(sb: ReturnType<typeof db>) {
  if (PORTICOS && Date.now() - porticosCargados < 3600e3) return PORTICOS;
  const { data } = await sb.from("osm_datos").select("datos").eq("clave", "porticos").maybeSingle();
  const { data: avo } = await sb.from("osm_datos").select("datos").eq("clave", "avo").maybeSingle();
  AVO = new Set<number>((avo?.datos?.nodos ?? []).map((x: any) => Number(x)));
  const { data: cas } = await sb.from("osm_datos").select("datos").eq("clave", "casetas").maybeSingle();
  CASETAS = (cas?.datos?.casetas ?? []).filter((c: any) => c.valor != null).map((c: any) => ({ id: Number(c.id), plaza: c.plaza, lat: +c.lat, lng: +c.lng,
    valor: +c.valor, punta: c.punta == null ? null : +c.punta, troncal: !c.verificar && !/^lateral/i.test(c.plaza) }));
  const els: any[] = data?.datos?.elements ?? [];
  const vias = els.filter((e) => e.type === "way");
  PORTICOS = els.filter((e) => e.type === "node").map((n) => {
    // Sentido del pórtico: el del tramo de calzada (vía de un sentido) que pasa por el pórtico (a menos de 3 m)
    let rb: number | null = null, dMin = 3;
    const cosLat = Math.cos(n.lat * Math.PI / 180), M = 111320;
    for (const w of vias) {
      const g = w.geometry; if (!g || g.length < 2) continue;
      const ow = w.tags?.oneway, uni = ow === "yes" || ow === "-1" || w.tags?.highway === "motorway" || w.tags?.junction === "roundabout";
      if (!uni) continue; // vía de doble sentido: no define sentido
      for (let i = 1; i < g.length; i++) {
        const x1 = (g[i - 1].lon - n.lon) * M * cosLat, y1 = (g[i - 1].lat - n.lat) * M, x2 = (g[i].lon - n.lon) * M * cosLat, y2 = (g[i].lat - n.lat) * M;
        const dx = x2 - x1, dy = y2 - y1, L = dx * dx + dy * dy, t = L ? Math.max(0, Math.min(1, -(x1 * dx + y1 * dy) / L)) : 0;
        const dd = Math.hypot(x1 + t * dx, y1 + t * dy);
        if (dd < dMin) { dMin = dd; rb = rumbo([g[i - 1].lat, g[i - 1].lon], [g[i].lat, g[i].lon]); if (ow === "-1") rb = (rb + 180) % 360; }
      }
    }
    return { id: n.id, nombre: n.tags?.name || n.tags?.ref || "Pórtico", lat: n.lat, lng: n.lon, rumbo: rb, caseta: n.tags?.barrier === "toll_booth" };
  });
  porticosCargados = Date.now();
  return PORTICOS;
}
// Pórticos por los que pasa la ruta.
// Método exacto (preferido): OSRM entrega los nodos de OpenStreetMap por los que pasa la ruta (annotations=nodes) y el pórtico
// es un nodo de la calzada; así solo se cuenta el pórtico de la calzada y el sentido que se recorren (las dos calzadas de una
// autopista quedan a 15-20 m y antes se cobraban ambas). Si no hay nodos, se usa la cercanía (< 8 m) como respaldo.
function porticosEnRuta(ruta: number[][], lista: Portico[], nodos: number[] = []) { // ruta = [[lng, lat], ...]
  if (nodos.length) {
    const set = new Set(nodos);
    let res = lista.filter((p) => set.has(p.id));
    // Vespucio Oriente: si la ruta la usa, 2 pórticos fijos (entrada y salida) en vez de los del mapa
    const idx: number[] = [];
    if (AVO.size) for (let i = 0; i < nodos.length; i++) if (AVO.has(nodos[i])) idx.push(i);
    if (idx.length >= 3) {
      res = res.filter((p) => !AVO.has(p.id) && !/vespucio oriente/i.test(p.nombre));
      const pt = (i: number) => ruta.length === nodos.length && ruta[i] ? { lat: ruta[i][1], lng: ruta[i][0] } : { lat: -33.42, lng: -70.575 };
      const a = pt(idx[0]), b = pt(idx[idx.length - 1]);
      res.push({ id: -1, nombre: "Vespucio Oriente · entrada", lat: a.lat, lng: a.lng, rumbo: null, caseta: false },
               { id: -2, nombre: "Vespucio Oriente · salida", lat: b.lat, lng: b.lng, rumbo: null, caseta: false });
    }
    return res;
  }
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
    if (mejor > 8) continue;
    if (p.rumbo != null) { const dif = Math.abs(((rbRuta - p.rumbo) + 540) % 360 - 180); if (dif > 60) continue; }
    res.push(p);
  }
  return res;
}

// Peajes de carretera de una ruta (cada plaza una vez). geo = [[lng, lat], ...]
function peajesEnRuta(ruta: number[][], nodos: number[] = []) {
  const set = new Set(nodos), vistos = new Map<string, Caseta>();
  const cosLat = Math.cos(-33.45 * Math.PI / 180), M = 111320;
  for (const c of CASETAS) {
    let pasa = set.has(c.id);
    if (!pasa && c.troncal && ruta.length > 1) {
      let mejor = Infinity;
      for (let i = 1; i < ruta.length && mejor > 60; i++) {
        const x1 = (ruta[i - 1][0] - c.lng) * M * cosLat, y1 = (ruta[i - 1][1] - c.lat) * M, x2 = (ruta[i][0] - c.lng) * M * cosLat, y2 = (ruta[i][1] - c.lat) * M;
        if (Math.min(Math.abs(x1), Math.abs(x2)) > 2000 && Math.sign(x1) === Math.sign(x2)) continue;
        if (Math.min(Math.abs(y1), Math.abs(y2)) > 2000 && Math.sign(y1) === Math.sign(y2)) continue;
        const dx = x2 - x1, dy = y2 - y1, L = dx * dx + dy * dy, t = L ? Math.max(0, Math.min(1, -(x1 * dx + y1 * dy) / L)) : 0;
        mejor = Math.min(mejor, Math.hypot(x1 + t * dx, y1 + t * dy));
      }
      pasa = mejor <= 60;
    }
    if (!pasa) continue;
    const k = c.troncal ? c.plaza : "id" + c.id;
    if (!vistos.has(k)) vistos.set(k, c);
  }
  return [...vistos.values()];
}

// ---------- Rutas ----------
// Polyline de Valhalla (precisión 6) → [[lng, lat], ...]
function decodificar6(str: string) {
  let i = 0, lat = 0, lng = 0; const out: number[][] = [];
  while (i < str.length) {
    let b = 0, sh = 0, r = 0;
    do { b = str.charCodeAt(i++) - 63; r |= (b & 0x1f) << sh; sh += 5; } while (b >= 0x20);
    lat += (r & 1) ? ~(r >> 1) : (r >> 1);
    sh = 0; r = 0;
    do { b = str.charCodeAt(i++) - 63; r |= (b & 0x1f) << sh; sh += 5; } while (b >= 0x20);
    lng += (r & 1) ? ~(r >> 1) : (r >> 1);
    out.push([lng / 1e6, lat / 1e6]);
  }
  return out;
}
// Ruta para dibujar en el mapa: como máximo ~300 puntos, [[lat, lng], ...] con 5 decimales
function rutaParaMapa(geo: number[][]) {
  const paso = Math.max(1, Math.ceil(geo.length / 300)), out: number[][] = [];
  for (let i = 0; i < geo.length; i += paso) out.push([+geo[i][1].toFixed(5), +geo[i][0].toFixed(5)]);
  const u = geo[geo.length - 1]; if (u) out.push([+u[1].toFixed(5), +u[0].toFixed(5)]);
  return out;
}
type Ruta = { km: number; min: number; geo: number[][]; nodos: number[] };
// Ruta más rápida (OSRM, usa autopistas). puntos = [{lat, lng}, ...] (origen, paradas, destino)
async function rutaOsrm(puntos: { lat: number; lng: number }[]): Promise<Ruta | null> {
  try {
    const r = await fetch(`https://router.project-osrm.org/route/v1/driving/${puntos.map((x) => `${x.lng},${x.lat}`).join(";")}?overview=full&geometries=geojson&annotations=nodes`, { signal: AbortSignal.timeout(8000) });
    const x = ((await r.json()).routes || [])[0];
    if (!x) return null;
    return { km: Math.round(x.distance / 100) / 10, min: Math.max(1, Math.ceil(x.duration * 1.25 / 60)), geo: x.geometry?.coordinates ?? [],
      nodos: (x.legs || []).flatMap((l: any) => l.annotation?.nodes ?? []) };
  } catch (_) { return null; }
}
// Ruta evitando autopistas con peaje (Valhalla de OpenStreetMap, gratis)
async function rutaSinAutopista(puntos: { lat: number; lng: number }[]): Promise<Ruta | null> {
  try {
    const r = await fetch("https://valhalla1.openstreetmap.de/route", { method: "POST", signal: AbortSignal.timeout(10000), headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ locations: puntos.map((x) => ({ lat: x.lat, lon: x.lng })), costing: "auto", costing_options: { auto: { use_tolls: 0, use_highways: 0 } }, units: "kilometers", directions_type: "none" }) });
    const t = (await r.json()).trip;
    if (!t?.summary) return null;
    const geo = (t.legs || []).flatMap((l: any) => decodificar6(l.shape || ""));
    return { km: Math.round(t.summary.length * 10) / 10, min: Math.max(1, Math.ceil(t.summary.time * 1.15 / 60)), geo, nodos: [] };
  } catch (_) { return null; }
}

// ---------- Sector de tarifa según el punto del mapa (todas las comunas; el pasajero no elige) ----------
let DATOS_SECTOR: Datos | null = null, sectorCargado = 0;
async function datosSector(sb: ReturnType<typeof db>) {
  if (DATOS_SECTOR && Date.now() - sectorCargado < 3600e3) return DATOS_SECTOR;
  // Se cargan por separado: los límites de comunas son lo más pesado (~2 MB, formato compacto)
  const { data, error } = await sb.from("osm_datos").select("clave, datos").in("clave", ["divisiones", "localidades", "localidades_sur"]);
  const { data: cr, error: e2 } = await sb.from("osm_datos").select("datos").eq("clave", "comunas_compactas").maybeSingle();
  if (error || e2) console.error("osm_datos", error?.message, e2?.message);
  const m = Object.fromEntries((data || []).map((x: any) => [x.clave, x.datos]));
  const lugares = { elements: [...(m.localidades?.elements ?? []), ...(m.localidades_sur?.elements ?? [])] };
  const d = prepararDatos(m.divisiones, lugares, cr?.datos);
  if (!d.comunas.length || !d.vias.length) throw new Error("No pudimos calcular la tarifa en este momento. Intente de nuevo en unos minutos o escríbanos por WhatsApp al +56 9 2227 5399.");
  DATOS_SECTOR = d; sectorCargado = Date.now();
  return DATOS_SECTOR;
}
// Aviso para Operaciones si el texto de la dirección nombra otra comuna que la del punto del mapa
// (el precio y el retiro se rigen por el punto; esto solo alerta al conductor de revisar con el pasajero).
const COMUNAS_TEXTO = ["providencia", "las condes", "vitacura", "lo barnechea", "la reina", "nunoa", "penalolen", "la florida", "puente alto", "maipu",
  "pudahuel", "quilicura", "huechuraba", "colina", "chicureo", "lampa", "san bernardo", "pirque", "macul", "san miguel", "recoleta", "independencia",
  "estacion central", "cerrillos", "renca", "conchali", "quinta normal", "lo prado", "cerro navia", "la cisterna", "el bosque", "la granja", "la pintana",
  "san ramon", "san joaquin", "lo espejo", "pedro aguirre cerda", "buin", "paine", "talagante", "penaflor", "padre hurtado", "calera de tango"];
function avisoDireccion(texto: string, comuna: string) {
  // Solo la parte después de la primera coma (la comuna), para no confundir con calles como «Av. Vitacura» o «Av. Las Condes»
  const t = norm(texto).split(",").slice(1).join(","), cn = norm(comuna);
  if (!t || !cn) return "";
  const dichas = COMUNAS_TEXTO.filter((x) => new RegExp(`(^|[^a-z])${x}([^a-z]|$)`).test(t));
  if (!dichas.length || dichas.some((x) => x === cn || (x === "chicureo" && cn === "colina"))) return "";
  return `REVISAR: la dirección dice «${dichas[0]}», pero el punto del mapa está en ${comuna}. Se cobró según el punto del mapa.`;
}
async function detectarSector(sb: ReturnType<typeof db>, lat: number, lng: number) {
  // Comuna según los límites guardados (OpenStreetMap, sin servicios externos) y sector según las calles límite.
  const d = await datosSector(sb);
  const comuna = comunaDe(d, { lat, lon: lng });
  if (!comuna) return null;
  return { comunas: [comuna], ...(sectorPorUbicacion(d, { lat, lon: lng }, [comuna]) || {}) };
}

// Viajes fuera de Santiago (fuera de la Región Metropolitana): siempre se cotizan por WhatsApp (decisión del dueño, 23 nov 2026).
// Los límites guardados incluyen las 52 comunas de la RM y, aparte, Valparaíso, Viña del Mar, Rancagua y Los Andes.
const FUERA_RM = new Set(["valparaiso", "vina del mar", "rancagua", "los andes"]);
const MSG_FUERA = "Los viajes fuera de Santiago se los cotizamos por WhatsApp al +56 9 2227 5399.";
async function exigirRM(sb: ReturnType<typeof db>, ...puntos: any[]) {
  const d = await datosSector(sb);
  for (const p of puntos) {
    if (!p) continue;
    const c = comunaDe(d, { lat: +p.lat, lon: +p.lng });
    if (!c || FUERA_RM.has(norm(c))) throw new Error(MSG_FUERA);
  }
}

// ---------- Precio (servidor) ----------
type Tramo = Record<string, unknown>;
async function cotizar(sb: ReturnType<typeof db>, empresaId: string, b: Record<string, unknown>) {
  const tipo = String(b.tipo), pax = Math.max(1, parseInt(String(b.pasajeros ?? 1)) || 1);
  // Más de 4 pasajeros no caben en un auto: se cobra van aunque se haya elegido auto
  const veh = b.vehiculo === "van" || pax > 4 ? "van" : "auto", vanForzada = veh === "van" && b.vehiculo !== "van";
  if (tipo === "ida" || tipo === "regreso") {
    // El sector lo decide SIEMPRE el punto marcado en el mapa (no lo que eligió el pasajero)
    const o0 = b.origen as any;
    if (!o0 || !enChile(+o0.lat, +o0.lng)) throw new Error("Marque en el mapa el punto exacto de su dirección.");
    const pa = b.parada as any, hayParada = !!(pa && pa.lat != null && pa.lng != null);
    if (hayParada && !enChile(+pa.lat, +pa.lng)) throw new Error("Marque en el mapa el punto exacto de la segunda dirección.");
    await exigirRM(sb, o0, hayParada ? pa : null);
    const ds = await detectarSector(sb, +o0.lat, +o0.lng);
    if ((ds as any)?.fuera) throw new Error((ds as any).fuera);
    if (!ds?.zona) throw new Error("Su dirección queda fuera de nuestras zonas con tarifa fija: se la cotizamos por WhatsApp al +56 9 2227 5399.");
    const { data: z } = await sb.from("tarifas_aeropuerto").select("zona, ida, regreso, van").eq("empresa_id", empresaId).eq("zona", ds.zona).maybeSingle();
    if (!z) throw new Error("Su dirección queda fuera de nuestras zonas con tarifa fija: se la cotizamos por WhatsApp al +56 9 2227 5399.");
    const comuna = ds.comunas?.[0] ?? "";
    const sectorAuto = z.zona !== String(b.zona ?? "") ? z.zona : null;
    const iv = tipo === "ida" && b.ida_vuelta === true;
    const ida = veh === "van" ? z.van : tipo === "regreso" ? z.regreso : z.ida;
    // Dos direcciones (regla del dueño, 23 nov 2026): la dirección principal se cobra con la tarifa fija de su sector
    // y el tramo entre las dos direcciones, con taxímetro (ruta real + TAG).
    // Al aeropuerto: se retira primero en la segunda dirección y luego en la principal. Desde el aeropuerto: se deja primero en la principal.
    if (hayParada) {
      if (iv) throw new Error("Para ida y vuelta con dos direcciones, reserve cada viaje por separado.");
      if (distKm({ lat: +pa.lat, lng: +pa.lng }, AERO) < 3) throw new Error("La segunda dirección no puede ser el aeropuerto.");
      if (distKm({ lat: +pa.lat, lng: +pa.lng }, { lat: +o0.lat, lng: +o0.lng }) < 0.05) throw new Error("La segunda dirección es la misma que la principal.");
      const tramo = await cotizar(sb, empresaId, { tipo: "punto_a_punto", vehiculo: veh, pasajeros: pax,
        origen: tipo === "ida" ? pa : o0, destino: tipo === "ida" ? o0 : pa }) as any;
      const t = { ida: tramo.ida, km: tramo.km, min: tramo.min, porticos: tramo.porticos ?? 0, tag: tramo.tag ?? 0, nombres_porticos: tramo.nombres_porticos ?? [] };
      return { zona: z.zona, ida: ida + t.ida, tarifa_zona: ida, tramo_parada: t, regreso: null, estimado: false, km: null, sector_auto: sectorAuto, motivo: ds.motivo ?? "",
        comuna, opciones: null, precisar: false, vehiculo: veh, van_forzada: vanForzada, aviso_direccion: avisoDireccion(String(o0.texto ?? ""), comuna) };
    }
    return { zona: z.zona, ida, regreso: iv ? (veh === "van" ? z.van : z.ida) : null, estimado: false, km: null, sector_auto: sectorAuto, motivo: ds.motivo ?? "",
      comuna, opciones: null, precisar: false, vehiculo: veh, van_forzada: vanForzada, aviso_direccion: avisoDireccion(String(o0.texto ?? ""), comuna) };
  }
  if (tipo !== "punto_a_punto") throw new Error("Tipo de servicio no válido.");
  const o = b.origen as any, d = b.destino as any;
  if (!o || !d || !enChile(+o.lat, +o.lng) || !enChile(+d.lat, +d.lng)) throw new Error("Marque en el mapa el origen y el destino.");
  if (distKm(o, AERO) < 3 || distKm(d, AERO) < 3) throw new Error("Para viajes desde o hacia el aeropuerto elija «Al aeropuerto» o «Desde el aeropuerto»: tienen tarifa fija.");
  await exigirRM(sb, o, d);
  // Tramos con tarifa fija (por comuna en el texto de la dirección)
  const { data: tramos } = await sb.from("tarifas_tramos").select("*").eq("empresa_id", empresaId);
  const to = norm(o.texto), td = norm(d.texto), tiene = (t: string, l: string[]) => l.some((c) => t.includes(c));
  const tf = (tramos || []).find((x: any) => (tiene(to, x.lado_a) && tiene(td, x.lado_b)) || (tiene(to, x.lado_b) && tiene(td, x.lado_a)));
  // Tarifa fija por tramo: ya incluye los peajes (decisión del dueño, 23 nov 2026); los peajes de carretera se suman solo a los viajes por km
  if (tf) return { zona: null, ida: veh === "van" ? tf.van : tf.auto, regreso: null, estimado: false, km: null, nota: tf.nombre, vehiculo: veh, van_forzada: vanForzada };
  // Dos opciones: con autopista (la más rápida, OSRM) y sin autopista (evita peajes, Valhalla).
  // Si no hay ruta, no se cobra en línea: mejor confirmar el valor por WhatsApp.
  const pts = [{ lat: +o.lat, lng: +o.lng }, { lat: +d.lat, lng: +d.lng }];
  const con = await rutaOsrm(pts);
  if (!con) throw new Error("No pudimos calcular la ruta en este momento. Intente de nuevo en unos minutos o escríbanos por WhatsApp.");
  if (con.km > 120) throw new Error(`Viaje largo (${con.km} km): se lo cotizamos por WhatsApp al +56 9 2227 5399.`);
  const { data: e } = await sb.from("empresas").select("taxi_bajada, taxi_cada_200m, valor_tag").eq("id", empresaId).single();
  const { data: T } = await sb.from("tarifas_aeropuerto").select("ida, van").eq("empresa_id", empresaId);
  const fs = (T || []).map((r: any) => r.van / r.ida).filter((x: number) => x > 1 && x < 3).sort((a: number, b: number) => a - b);
  const factorVan = fs.length ? fs[Math.floor(fs.length / 2)] : 1.35;
  const lista = await porticos(sb), valorTag = e?.valor_tag ?? 900;
  // Valor de una ruta: taxímetro por km + TAG ($900 por pórtico; las casetas de peaje troncal se informan aparte)
  const valorar = (ru: Ruta) => {
    const auto = Math.max(5000, (e?.taxi_bajada ?? 2400) + Math.ceil(ru.km * 5) * (e?.taxi_cada_200m ?? 180));
    const enRuta = ru.geo.length > 1 || ru.nodos.length ? porticosEnRuta(ru.geo, lista, ru.nodos) : [];
    const pp = enRuta.filter((p) => !p.caseta), nPort = pp.length, tag = nPort * valorTag;
    const base = redondear(veh === "van" ? Math.max(25000, auto * factorVan) : auto);
    // Peajes de carretera: precio costo, ida y vuelta
    const pj = peajesEnRuta(ru.geo, ru.nodos), pjIda = pj.reduce((a, c) => a + c.valor, 0);
    return { ida: base + tag + 2 * pjIda, km: ru.km, min: ru.min, base, porticos: nPort, tag, casetas: enRuta.filter((p) => p.caseta).map((p) => p.nombre),
      peajes: pj.map((c) => ({ plaza: c.plaza, valor: c.valor, lat: c.lat, lng: c.lng })), peajes_ida: pjIda, peajes_cobro: 2 * pjIda,
      nombres_porticos: pp.map((p) => p.nombre), porticos_mapa: pp.map((p) => ({ n: p.nombre, lat: +p.lat.toFixed(6), lng: +p.lng.toFixed(6) })), ruta: rutaParaMapa(ru.geo) };
  };
  const vCon = valorar(con);
  // La opción sin autopista solo se calcula si la ruta rápida tiene pórticos
  let vSin: ReturnType<typeof valorar> | null = null;
  if (vCon.porticos > 0) {
    const sin = await rutaSinAutopista(pts);
    if (sin && sin.km <= 120) {
      const vs: any = valorar(sin);
      // Tiempo extra respecto de la ruta con autopista: se cobra como la espera ($180/min auto, $270/min van)
      const minExtra = Math.max(0, sin.min - con.min), cargo = minExtra * (veh === "van" ? 270 : 180);
      vs.min_extra = minExtra; vs.cargo_tiempo = cargo; vs.ida = redondear(vs.base + cargo) + vs.tag + vs.peajes_cobro;
      // Solo se ofrece si tiene menos pórticos y sale más barata que la ruta con autopista
      if (vs.porticos < vCon.porticos && vs.ida < vCon.ida) vSin = vs;
    }
  }
  const eligeSin = b.sin_autopista === true && vSin != null;
  const v = eligeSin ? vSin! : vCon;
  return { zona: null, ...v, regreso: null, estimado: true, sin_autopista: eligeSin,
    alternativas: { con: vCon, sin: vSin }, vehiculo: veh, van_forzada: vanForzada };
}

// ---------- Códigos de descuento ----------
// Guardados en osm_datos, clave "codigos_descuento" (tabla sin acceso público: solo este servidor los lee).
// { codigos: [{ codigo, monto, usos_max, vence: "AAAA-MM-DD", activo, nota }] }. Un uso = una solicitud de pago pagada con ese código.
// Los crea el dueño (con Claude). Provisional hasta tener una tabla propia con su pestaña en el panel.
async function validarCodigo(sb: ReturnType<typeof db>, codigo: unknown) {
  const c = txt(codigo, 40).toUpperCase().replace(/\s+/g, "");
  if (!c) return null;
  const { data } = await sb.from("osm_datos").select("datos").eq("clave", "codigos_descuento").maybeSingle();
  const x = ((data?.datos?.codigos ?? []) as any[]).find((y) => String(y.codigo).toUpperCase() === c);
  if (!x || x.activo === false) throw new Error("El código de descuento no existe o ya no está activo.");
  if (x.vence && Date.now() > new Date(x.vence + "T23:59:59-03:00").getTime()) throw new Error("El código de descuento ya venció.");
  const { count } = await sb.from("solicitudes_pago").select("id", { count: "exact", head: true }).eq("estado", "pagada").eq("datos->>codigo", c);
  if ((count ?? 0) >= (x.usos_max ?? 1)) throw new Error("Este código de descuento ya fue usado.");
  return { codigo: c, monto: Math.max(0, Math.round(Number(x.monto) || 0)) };
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
  if (b.parada && txt(b.parada.texto, 300).length < 3) return json({ error: "Escriba la segunda dirección." }, 400);
  const pax = Math.min(15, Math.max(1, parseInt(b.pasajeros) || 1)), mal = Math.min(30, Math.max(0, parseInt(b.maletas) || 0));

  // Control de abuso
  const hace1h = new Date(Date.now() - 3600e3).toISOString();
  const { count: nTel } = await sb.from("solicitudes_pago").select("id", { count: "exact", head: true }).eq("telefono", tel).gte("creada_en", hace1h);
  const { count: nTot } = await sb.from("solicitudes_pago").select("id", { count: "exact", head: true }).gte("creada_en", hace1h);
  if ((nTel ?? 0) >= 8) return json({ error: "Recibimos varios intentos seguidos desde este teléfono. Escríbanos por WhatsApp." }, 429);
  if ((nTot ?? 0) >= 60) return json({ error: "En este momento no podemos recibir más pagos en línea. Escríbanos por WhatsApp al +56 9 2227 5399." }, 429);

  let p;
  try { p = await cotizar(sb, emp!.id, b); } catch (e) { return json({ error: (e as Error).message }, 400); }
  if ((p as any).precisar) return json({ error: `Su dirección está en ${(p as any).comuna || "una comuna"} con varias tarifas: elija su sector exacto antes de pagar.`, precisar: true, opciones: (p as any).opciones }, 400);
  const bruto = p.ida + (p.regreso ?? 0);
  // Código de descuento (opcional): se descuenta del total; siempre se cobra al menos $1.000
  let cod: { codigo: string; monto: number } | null = null;
  try { cod = await validarCodigo(sb, b.codigo); } catch (e) { return json({ error: (e as Error).message, codigo_error: true }, 400); }
  const descuento = cod ? Math.min(cod.monto, Math.max(0, bruto - 1000)) : 0;
  const total = bruto - descuento;
  // Si el valor que vio el pasajero no coincide con el del servidor, se le muestra el correcto antes de cobrar
  if (Number(b.monto_visto) !== total) return json({ monto: total, cambio: true, error: `El valor de su viaje es $${total.toLocaleString("es-CL")}. Revíselo y toque de nuevo «Pagar y reservar».` }, 409);

  const tipo = String(b.tipo), veh = (p as any).vehiculo === "van" ? "van" : "auto";
  const aviso = [(p as any).aviso_direccion, (p as any).van_forzada ? `Van por ${pax} pasajeros.` : ""].filter(Boolean).join(" ");
  const d = b.destino ?? {}, base = { pasajeros: pax, maletas: mal, vehiculo: veh, comuna: p.zona, comentarios: [aviso, txt(b.comentarios, 500)].filter(Boolean).join(" ") };
  const tramos: Tramo[] = [];
  const ivTxt = p.regreso ? "Ida y vuelta (regreso al valor de la ida)." : "";
  const tp = (p as any).tramo_parada, pa = b.parada ?? {};
  if (tp) {
    // Dos direcciones: la principal queda como parada; la otra es el primer retiro (al aeropuerto) o el destino final (desde el aeropuerto)
    const prin = { lat: +o.lat, lng: +o.lng, direccion: txt(o.texto, 300) };
    const nota = `DOS DIRECCIONES: tarifa fija ${p.zona} $${(p as any).tarifa_zona} + tramo con taxímetro entre las direcciones $${tp.ida} (${tp.km} km${tp.porticos ? `, incluye TAG ${tp.porticos} pórtico(s) = $${tp.tag}` : ""}).`;
    const com = [nota, base.comentarios].filter(Boolean).join(" ");
    if (tipo === "ida") tramos.push({ ...base, tipo_servicio: "ida", fecha_hora: fh.toISOString(), origen: txt(pa.texto, 300), origen_lat: +pa.lat, origen_lng: +pa.lng,
      paradas: [prin], destino: AERO.texto, destino_lat: AERO.lat, destino_lng: AERO.lng, vuelo: txt(b.vuelo, 12) || null, retiro_detalle: txt(b.retiro_detalle, 200), monto: p.ida,
      comentarios: `Primer retiro: ${txt(pa.texto, 300)}. Segundo retiro: ${prin.direccion}. ${com}` });
    else tramos.push({ ...base, tipo_servicio: "regreso", fecha_hora: fh.toISOString(), origen: AERO.texto, origen_lat: AERO.lat, origen_lng: AERO.lng,
      paradas: [prin], destino: txt(pa.texto, 300), destino_lat: +pa.lat, destino_lng: +pa.lng, vuelo: txt(b.vuelo, 12) || null, monto: p.ida,
      comentarios: `Primera parada: ${prin.direccion}. Destino final: ${txt(pa.texto, 300)}. Hora indicada = aterrizaje. ${com}` });
  }
  if (tipo === "ida" && !tp) tramos.push({ ...base, tipo_servicio: "ida", fecha_hora: fh.toISOString(), origen: txt(o.texto, 300), origen_lat: +o.lat, origen_lng: +o.lng,
    destino: AERO.texto, destino_lat: AERO.lat, destino_lng: AERO.lng, vuelo: txt(b.vuelo, 12) || null, retiro_detalle: txt(b.retiro_detalle, 200), monto: p.ida,
    comentarios: [ivTxt, base.comentarios].filter(Boolean).join(" ") });
  if ((tipo === "regreso" && !tp) || p.regreso) {
    const fh2 = p.regreso ? new Date(String(b.fecha_hora_regreso)) : fh;
    if (isNaN(+fh2) || +fh2 <= +fh && p.regreso) return json({ error: "El regreso debe ser después de la ida." }, 400);
    tramos.push({ ...base, tipo_servicio: "regreso", fecha_hora: fh2.toISOString(), origen: AERO.texto, origen_lat: AERO.lat, origen_lng: AERO.lng,
      destino: txt(o.texto, 300), destino_lat: +o.lat, destino_lng: +o.lng, vuelo: txt(p.regreso ? b.vuelo_regreso : b.vuelo, 12) || null,
      monto: p.regreso ?? p.ida, comentarios: [ivTxt, "Hora indicada = aterrizaje.", base.comentarios].filter(Boolean).join(" ") });
  }
  if (tipo === "punto_a_punto") tramos.push({ ...base, tipo_servicio: "punto_a_punto", fecha_hora: fh.toISOString(), origen: txt(o.texto, 300), origen_lat: +o.lat, origen_lng: +o.lng,
    destino: txt(d.texto, 300), destino_lat: +d.lat, destino_lng: +d.lng, retiro_detalle: txt(b.retiro_detalle, 200), monto: p.ida, estimado: p.estimado, km: p.km,
    porticos: (p as any).porticos ?? 0, tag: (p as any).tag ?? 0,
    comentarios: [(p as any).sin_autopista ? `RUTA SIN AUTOPISTAS: el pasajero eligió y pagó el viaje sin autopistas (no usar autopistas con TAG; incluye ${(p as any).min_extra ?? 0} min extra = $${(p as any).cargo_tiempo ?? 0}).` : "",
      base.comentarios, (p as any).porticos ? `Incluye TAG: ${(p as any).porticos} pórtico(s) = $${(p as any).tag} (${((p as any).nombres_porticos || []).join(", ")}).` : "",
      (p as any).peajes_cobro ? `Incluye peajes de carretera ida y vuelta: ${((p as any).peajes || []).map((c: any) => c.plaza).join(", ")} = $${(p as any).peajes_cobro}.` : ""].filter(Boolean).join(" ") });

  // El descuento se aplica al primer tramo (lo que queda como precio de la reserva es lo que se pagó)
  if (descuento && tramos[0]) {
    tramos[0].monto = Math.max(0, Number(tramos[0].monto) - descuento);
    tramos[0].comentarios = [`CÓDIGO DE DESCUENTO ${cod!.codigo}: -$${descuento.toLocaleString("es-CL")} (valor de lista $${bruto.toLocaleString("es-CL")}).`, tramos[0].comentarios].filter(Boolean).join(" ");
  }
  const orden = "FKW-" + Date.now().toString(36).toUpperCase() + "-" + crypto.randomUUID().slice(0, 4).toUpperCase();
  const { data: sol, error } = await sb.from("solicitudes_pago").insert({ empresa_id: emp!.id, orden, datos: { contacto: c, tramos, codigo: cod?.codigo ?? null, descuento }, monto: total, telefono: tel, correo: c.correo }).select("id").single();
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
    if (accion === "porticos" && req.method === "POST") {
      // { puntos: [{lat, lng}, ...] } (origen, paradas, destino) → pórticos de la ruta más rápida
      const b = await req.json().catch(() => ({})) as any;
      const puntos = (Array.isArray(b.puntos) ? b.puntos : []).map((x: any) => ({ lat: +x.lat, lng: +x.lng })).filter((x: any) => enChile(x.lat, x.lng)).slice(0, 12);
      if (puntos.length < 2) return json({ error: "Faltan el origen y el destino" }, 400);
      const ru = await rutaOsrm(puntos);
      if (!ru) return json({ error: "No pudimos calcular la ruta" }, 502);
      const sb = db(), pp = porticosEnRuta(ru.geo, await porticos(sb), ru.nodos).filter((p) => !p.caseta);
      const { data: e } = await sb.from("empresas").select("valor_tag").eq("slug", "flota-k").single();
      const pj = peajesEnRuta(ru.geo, ru.nodos), pjIda = pj.reduce((a, c) => a + c.valor, 0);
      return json({ porticos: pp.length, valor_tag: e?.valor_tag ?? 900, tag: pp.length * (e?.valor_tag ?? 900), km: ru.km, nombres: pp.map((p) => p.nombre),
        peajes: pj.map((c) => ({ plaza: c.plaza, valor: c.valor })), peajes_ida: pjIda, peajes_cobro: 2 * pjIda });
    }
    if (accion === "codigo") {
      // Revisa un código de descuento antes de pagar: { codigo, monto } o { error }
      try {
        const r = await validarCodigo(db(), u.searchParams.get("c"));
        return r ? json(r) : json({ error: "Escriba el código." }, 400);
      } catch (e) { return json({ error: (e as Error).message }, 400); }
    }
    if (accion === "sector") {
      const lat = Number(u.searchParams.get("lat")), lng = Number(u.searchParams.get("lng"));
      if (!enChile(lat, lng)) return json({ error: "Punto no válido" }, 400);
      return json(await detectarSector(db(), lat, lng) ?? { error: "Sin comuna" });
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
