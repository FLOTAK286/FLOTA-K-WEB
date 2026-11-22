// Sector de tarifa según la ubicación real del punto (comunas con más de una tarifa).
// Datos: osm_datos "divisiones" (avenidas límite) y "localidades" (barrios con nombre), de OpenStreetMap.
// Devuelve { zona } si el punto define un sector, { opciones } si solo se sabe la comuna, o null si no aplica.
// Límites aprobados por el dueño (22 nov 2026).

type P = { lat: number; lon: number };
type Via = { nombre: string; g: P[] };
type Lugar = { nombre: string; lat: number; lon: number };
type Comuna = { nombre: string; segs: [P, P][]; caja: [number, number, number, number] };
export type Datos = { vias: Via[]; lugares: Lugar[]; comunas: Comuna[] };

const norm = (s: string) => String(s || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").trim();
const km = (a: { lat: number; lon: number }, b: { lat: number; lon: number }) => {
  const R = 6371, r = (x: number) => x * Math.PI / 180, dLa = r(b.lat - a.lat), dLo = r(b.lon - a.lon);
  return 2 * R * Math.asin(Math.sqrt(Math.sin(dLa / 2) ** 2 + Math.cos(r(a.lat)) * Math.cos(r(b.lat)) * Math.sin(dLo / 2) ** 2));
};

export function prepararDatos(divisiones: any, localidades: any, comunasOsm?: any): Datos {
  // Límites de comunas (OpenStreetMap, admin_level 8): todos los tramos de sus bordes, para saber si un punto está dentro
  const comunas: Comuna[] = (comunasOsm?.elements ?? []).filter((e: any) => e.type === "relation").map((e: any) => {
    const segs: [P, P][] = []; let s0 = 90, n0 = -90, w0 = 180, e0 = -180;
    for (const m of e.members || []) if (m.type === "way" && m.geometry && (m.role === "outer" || m.role === "inner" || !m.role))
      for (let i = 1; i < m.geometry.length; i++) {
        const a = m.geometry[i - 1], b = m.geometry[i]; segs.push([a, b]);
        s0 = Math.min(s0, a.lat); n0 = Math.max(n0, a.lat); w0 = Math.min(w0, a.lon); e0 = Math.max(e0, a.lon);
      }
    return { nombre: e.tags?.name ?? "", segs, caja: [s0, n0, w0, e0] as [number, number, number, number] };
  });
  const vias = (divisiones?.elements ?? []).filter((e: any) => e.type === "way" && e.geometry)
    .map((e: any) => ({ nombre: norm(e.tags?.name), g: e.geometry as P[] }));
  const lugares = (localidades?.elements ?? []).filter((e: any) => e.type === "node" && e.tags?.name)
    .map((e: any) => ({ nombre: norm(e.tags.name), lat: e.lat, lon: e.lon }));
  return { vias, lugares, comunas };
}

// Comuna que contiene el punto (regla par-impar sobre los bordes)
export function comunaDe(d: Datos, p: P): string | null {
  for (const c of d.comunas) {
    const [s0, n0, w0, e0] = c.caja; if (p.lat < s0 || p.lat > n0 || p.lon < w0 || p.lon > e0) continue;
    let dentro = false;
    for (const [a, b] of c.segs) if ((a.lat > p.lat) !== (b.lat > p.lat) && p.lon < (b.lon - a.lon) * (p.lat - a.lat) / (b.lat - a.lat) + a.lon) dentro = !dentro;
    if (dentro) return c.nombre;
  }
  return null;
}

// Longitud de una avenida (norte-sur) a la latitud del punto. Si el punto queda fuera del tramo, se usa el extremo más cercano.
function lngAvenida(d: Datos, re: RegExp, p: P): number | null {
  const segs: [P, P][] = [];
  for (const v of d.vias) if (re.test(v.nombre)) for (let i = 1; i < v.g.length; i++) segs.push([v.g[i - 1], v.g[i]]);
  if (!segs.length) return null;
  let mejor: number | null = null;
  for (const [a, b] of segs) {
    const lo = Math.min(a.lat, b.lat), hi = Math.max(a.lat, b.lat);
    if (p.lat < lo || p.lat > hi || hi === lo) continue;
    const lng = a.lon + (b.lon - a.lon) * (p.lat - a.lat) / (b.lat - a.lat);
    if (mejor == null || Math.abs(lng - p.lon) < Math.abs(mejor - p.lon)) mejor = lng;
  }
  if (mejor != null) return mejor;
  let cerca: P | null = null, dmin = Infinity; // fuera del tramo: extremo más cercano
  for (const [a, b] of segs) for (const x of [a, b]) { const dd = Math.abs(x.lat - p.lat); if (dd < dmin) { dmin = dd; cerca = x; } }
  return cerca ? cerca.lon : null;
}
// Latitud de una avenida (oriente-poniente) a la longitud del punto
function latAvenida(d: Datos, re: RegExp, p: P): number | null {
  const segs: [P, P][] = [];
  for (const v of d.vias) if (re.test(v.nombre)) for (let i = 1; i < v.g.length; i++) segs.push([v.g[i - 1], v.g[i]]);
  let mejor: number | null = null;
  for (const [a, b] of segs) {
    const lo = Math.min(a.lon, b.lon), hi = Math.max(a.lon, b.lon);
    if (p.lon < lo || p.lon > hi || hi === lo) continue;
    const lat = a.lat + (b.lat - a.lat) * (p.lon - a.lon) / (b.lon - a.lon);
    if (mejor == null || Math.abs(lat - p.lat) < Math.abs(mejor - p.lat)) mejor = lat;
  }
  return mejor;
}
const alOriente = (d: Datos, re: RegExp, p: P) => { const l = lngAvenida(d, re, p); return l == null ? null : p.lon > l; };
// Localidad con nombre más cercana (dentro de maxKm) entre las que calzan con el patrón
function cerca(d: Datos, re: RegExp, p: P, maxKm: number) {
  let m: Lugar | null = null, dm = Infinity;
  for (const l of d.lugares) if (re.test(l.nombre)) { const x = km(l, p); if (x < dm) { dm = x; m = l; } }
  return m && dm <= maxKm ? m : null;
}

const MANQUEHUE = /manquehue/, PAUL_HARRIS = /paul harris/, VPR = /vicente perez rosales/, PERDICES = /^avenida las perdices$/;
const TOBALABA = /^(avenida )?tobalaba$/, AV_FLORIDA = /^avenida la florida$/, IRARRAZAVAL = /irarrazaval/;
const PLAZA_MAIPU = { lat: -33.5104, lon: -70.7573 };

// comunas = nombres de comuna que entrega el geocodificador (city, district, etc.)
export function sectorPorUbicacion(d: Datos, p: P, comunas: string[]): { zona?: string; opciones?: string[]; motivo: string } | null {
  const c = comunas.map(norm), es = (n: string) => c.includes(n);
  if (es("las condes")) {
    if (alOriente(d, MANQUEHUE, p) === false) return { zona: "Las Condes hasta Manquehue", motivo: "al poniente de Av. Manquehue" };
    if (alOriente(d, PAUL_HARRIS, p) === false) return { zona: "Las Condes desde Manquehue hasta Paul Harris", motivo: "entre Manquehue y Paul Harris" };
    return { opciones: ["San Carlos de Apoquindo hasta C. Otoñal, San Damián", "San Carlos de Apoquindo hasta Av. La Plaza", "San Carlos de Apoquindo, Av. La Plaza a cordillera"],
      motivo: "al oriente de Paul Harris" };
  }
  if (es("vitacura")) {
    const o = alOriente(d, MANQUEHUE, p);
    if (o === false) return { zona: "Vitacura hasta Manquehue", motivo: "al poniente de Av. Manquehue" };
    if (o === true) return { zona: "Vitacura hasta Tabancura", motivo: "al oriente de Av. Manquehue" };
  }
  if (es("la reina")) {
    if (alOriente(d, VPR, p) === false) return { zona: "La Reina (Vicente Pérez Rosales)", motivo: "al poniente de Vicente Pérez Rosales" };
    if (alOriente(d, PERDICES, p) === false) return { zona: "La Reina (Padre Hurtado - Las Perdices)", motivo: "entre V. Pérez Rosales y Las Perdices" };
    return { zona: "La Reina Alta (Álvaro Casanova)", motivo: "al oriente de Las Perdices" };
  }
  if (es("penalolen")) {
    if (alOriente(d, TOBALABA, p) === false) return { zona: "Peñalolén hasta Tobalaba", motivo: "al poniente de Tobalaba" };
    if (alOriente(d, PERDICES, p) === false) return { zona: "Peñalolén Alto hasta Las Perdices", motivo: "entre Tobalaba y Las Perdices" };
    return { zona: "Peñalolén Diagonal Las Torres", motivo: "al oriente de Las Perdices" };
  }
  if (es("la florida")) {
    if (alOriente(d, AV_FLORIDA, p) === false) return { zona: "La Florida hasta Av. La Florida", motivo: "al poniente de Av. La Florida" };
    if (alOriente(d, PERDICES, p) === false) return { zona: "La Florida desde Av. La Florida", motivo: "entre Av. La Florida y Las Perdices" };
    return { zona: "La Florida Alto Macul, Las Perdices al oriente", motivo: "al oriente de Las Perdices" };
  }
  if (es("nunoa")) {
    const l = latAvenida(d, IRARRAZAVAL, p);
    if (l != null) return p.lat > l ? { zona: "Ñuñoa por Costanera", motivo: "al norte de Irarrázaval" } : { zona: "Ñuñoa por Vespucio Sur", motivo: "al sur de Irarrázaval" };
    return { opciones: ["Ñuñoa por Costanera", "Ñuñoa por Vespucio Sur"], motivo: "Ñuñoa" };
  }
  if (es("maipu")) {
    if (cerca(d, /ciudad satelite/, p, 1.8)) return { zona: "Maipú Ciudad Satélite", motivo: "Ciudad Satélite" };
    return p.lon > PLAZA_MAIPU.lon ? { zona: "Maipú hasta Plaza de Maipú", motivo: "al oriente de la Plaza de Maipú" }
      : { zona: "Maipú desde Plaza de Maipú", motivo: "al poniente de la Plaza de Maipú" };
  }
  if (es("puente alto")) return cerca(d, /vizcachas/, p, 2) ? { zona: "Puente Alto Las Vizcachas", motivo: "Las Vizcachas" } : { zona: "Puente Alto", motivo: "Puente Alto" };
  if (es("san bernardo")) return cerca(d, /^nos$/, p, 2) ? { zona: "San Bernardo - Nos", motivo: "Nos" } : { zona: "San Bernardo", motivo: "San Bernardo" };
  if (es("lampa")) {
    if (cerca(d, /batuco/, p, 3)) return { zona: "Lampa Batuco", motivo: "Batuco" };
    if (cerca(d, /valle grande/, p, 2)) return { zona: "Lampa Valle Grande", motivo: "Valle Grande" };
    if (cerca(d, /chicauma/, p, 3)) return { zona: "Lampa Chicauma", motivo: "Chicauma" };
    return { zona: "Lampa Pueblo (centro)", motivo: "Lampa" };
  }
  if (es("lo barnechea")) {
    if (cerca(d, /arrayan/, p, 2)) return { zona: "El Arrayán", motivo: "El Arrayán" };
    return { opciones: ["Lo Barnechea hasta el Golf de Manquehue", "Lo Barnechea hasta P.L. Urqueta y B.L. Cotapos", "Lo Barnechea Pie Andino (Paseo Los Bravos)", "El Arrayán"], motivo: "Lo Barnechea" };
  }
  if (es("colina")) {
    if (p.lat < -33.255) return { opciones: ["Chicureo hasta Piedra Roja (vía normal)", "Chicureo desde Los Pioneros - Lo Arcaya"], motivo: "Chicureo" };
    if (cerca(d, /peldehue|chacabuco/, p, 4)) return { zona: "Colina sector Peldehue - Chacabuco", motivo: "Peldehue - Chacabuco" };
    return { opciones: ["Colina centro hasta Esmeralda", "Colina sector Peldehue - Chacabuco"], motivo: "Colina" };
  }
  if (es("pirque")) {
    if (cerca(d, /el principal/, p, 2.5)) return { zona: "Pirque El Principal - Club de Golf", motivo: "El Principal" };
    return { opciones: ["Pirque hasta Virginia Subercaseaux", "Pirque El Principal - Club de Golf"], motivo: "Pirque" };
  }
  return null;
}
