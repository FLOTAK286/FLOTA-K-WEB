// Sector de tarifa según la ubicación real del punto marcado en el mapa.
// Datos (tabla osm_datos, de OpenStreetMap): "comunas_compactas" (límites de comunas), "divisiones" (avenidas límite)
// y "localidades" + "localidades_sur" (pueblos y barrios con nombre).
// Devuelve { zona } con el sector que corresponde al punto, { fuera } si no se cobra en línea, o null si la comuna no está en el tarifario.
// El pasajero no elige: el sector lo decide siempre el punto marcado en el mapa (donde lo retira el conductor).
// Límites aprobados por el dueño (22 nov 2026).

type P = { lat: number; lon: number };
type Via = { nombre: string; g: P[] };
type Lugar = { nombre: string; lat: number; lon: number };
type Comuna = { nombre: string; segs: [P, P][]; caja: [number, number, number, number] };
export type Datos = { vias: Via[]; lugares: Lugar[]; comunas: Comuna[] };

const norm = (s: string) => String(s || "").toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "").trim();
const km = (a: { lat: number; lon: number }, b: { lat: number; lon: number }) => {
  const R = 6371, r = (x: number) => x * Math.PI / 180, dLa = r(b.lat - a.lat), dLo = r(b.lon - a.lon);
  return 2 * R * Math.asin(Math.sqrt(Math.sin(dLa / 2) ** 2 + Math.cos(r(a.lat)) * Math.cos(r(b.lat)) * Math.sin(dLo / 2) ** 2));
};

export function prepararDatos(divisiones: any, localidades: any, comunasOsm?: any): Datos {
  // Límites de comunas (OpenStreetMap, admin_level 8): todos los tramos de sus bordes, para saber si un punto está dentro
  // Formato compacto (osm_datos "comunas_compactas"): { comunas: [{ n: nombre, w: [[[lat, lon], ...], ...] }] }
  if (comunasOsm?.comunas) comunasOsm = { elements: comunasOsm.comunas.map((c: any) => ({ type: "relation", tags: { name: c.n },
    members: c.w.map((w: number[][]) => ({ type: "way", role: "outer", geometry: w.map(([lat, lon]) => ({ lat, lon })) })) })) };
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
// Igual, pero fuera del tramo se prolonga la avenida desde su extremo más cercano
function latAvenidaExt(d: Datos, re: RegExp, p: P): number | null {
  const l = latAvenida(d, re, p); if (l != null) return l;
  let cerca: P | null = null, dmin = Infinity;
  for (const v of d.vias) if (re.test(v.nombre)) for (const x of v.g) { const dd = Math.abs(x.lon - p.lon); if (dd < dmin) { dmin = dd; cerca = x; } }
  return cerca ? cerca.lat : null;
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
const OTONAL_DAMIAN = /^(camino otonal|san damian)$/, LA_PLAZA = /^avenida la plaza$/, GOLF_MANQUEHUE = /golf de manquehue/;
const URQUIETA_COTAPOS = /pedro lira urquieta|larrain cotapos/, ESMERALDA = /^esmeralda$/, VIRGINIA = /^virginia subercaseaux$/;
const PLAZA_MAIPU = { lat: -33.5104, lon: -70.7573 };

// comunas = nombre(s) de la comuna que contiene el punto
export function sectorPorUbicacion(d: Datos, p: P, comunas: string[]): { zona?: string; opciones?: string[]; fuera?: string; motivo: string } | null {
  const c = comunas.map(norm), es = (n: string) => c.includes(n);
  if (es("las condes")) {
    if (alOriente(d, MANQUEHUE, p) === false) return { zona: "Las Condes hasta Manquehue", motivo: "al poniente de Av. Manquehue" };
    if (alOriente(d, PAUL_HARRIS, p) === false) return { zona: "Las Condes desde Manquehue hasta Paul Harris", motivo: "entre Manquehue y Paul Harris" };
    if (p.lon > -70.45) return { fuera: "Para la cordillera se lo cotizamos por WhatsApp al +56 9 2227 5399.", motivo: "cordillera" };
    if (alOriente(d, OTONAL_DAMIAN, p) === false) return { zona: "San Carlos de Apoquindo hasta C. Otoñal, San Damián", motivo: "entre Paul Harris y Camino Otoñal / San Damián" };
    if (alOriente(d, LA_PLAZA, p) === false) return { zona: "San Carlos de Apoquindo hasta Av. La Plaza", motivo: "entre Camino Otoñal / San Damián y Av. La Plaza" };
    return { zona: "San Carlos de Apoquindo, Av. La Plaza a cordillera", motivo: "al oriente de Av. La Plaza" };
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
    return { zona: "Ñuñoa por Vespucio Sur", motivo: "Ñuñoa" };
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
    // Farellones y la cordillera: el valor depende de la temporada, se cotiza por WhatsApp
    if (p.lon > -70.44 || p.lat > -33.29) return { fuera: "Para Farellones y la cordillera el valor depende de la temporada: se lo cotizamos por WhatsApp al +56 9 2227 5399.", motivo: "cordillera" };
    // Oriente (valle del Mapocho y Huinganal alto): El Arrayán y Pie Andino tienen el mismo valor
    if (p.lon > -70.51) return p.lat < -33.335 ? { zona: "El Arrayán", motivo: "sector El Arrayán" } : { zona: "Lo Barnechea Pie Andino (Paseo Los Bravos)", motivo: "Pie Andino" };
    const g = latAvenidaExt(d, GOLF_MANQUEHUE, p);
    if (g != null && p.lat < g) return { zona: "Lo Barnechea hasta el Golf de Manquehue", motivo: "al sur de El Golf de Manquehue" };
    const u = latAvenidaExt(d, URQUIETA_COTAPOS, p);
    if (u != null && p.lat < u) return { zona: "Lo Barnechea hasta P.L. Urqueta y B.L. Cotapos", motivo: "entre El Golf de Manquehue y P. L. Urquieta / B. Larraín Cotapos" };
    return { zona: "Lo Barnechea Pie Andino (Paseo Los Bravos)", motivo: "al norte de P. L. Urquieta / B. Larraín Cotapos" };
  }
  if (es("colina")) {
    if (p.lon > -70.715 && p.lat < -33.215) {
      // Chicureo: hasta Piedra Roja por la vía normal; más al norte (Lo Arcaya, Brisas) o al oriente de Piedra Roja, el sector siguiente
      if (p.lat < -33.258 && p.lon < -70.625) return { zona: "Chicureo hasta Piedra Roja (vía normal)", motivo: "Chicureo, hasta Piedra Roja" };
      return { zona: "Chicureo desde Los Pioneros - Lo Arcaya", motivo: p.lat < -33.258 ? "Chicureo, al oriente de Piedra Roja" : "Chicureo, sector Lo Arcaya" };
    }
    const e = latAvenidaExt(d, ESMERALDA, p) ?? -33.181;
    return p.lat > e ? { zona: "Colina sector Peldehue - Chacabuco", motivo: "al norte de Esmeralda" } : { zona: "Colina centro hasta Esmeralda", motivo: "Colina, hasta Esmeralda" };
  }
  if (es("pirque")) {
    // Hasta Virginia Subercaseaux (entrada desde Puente Alto); más al sur, sector El Principal
    const v = latAvenidaExt(d, VIRGINIA, p);
    if (v != null && p.lat > v - 0.003) return { zona: "Pirque hasta Virginia Subercaseaux", motivo: "hasta Av. Virginia Subercaseaux" };
    return { zona: "Pirque El Principal - Club de Golf", motivo: "al sur de Av. Virginia Subercaseaux" };
  }
  if (es("paine")) {
    if (cerca(d, /^champa$/, p, 3)) return { zona: "Champa", motivo: "Champa" };
    if (cerca(d, /^huelquen$/, p, 3)) return { zona: "Huelquén", motivo: "Huelquén" };
    return { zona: "Paine", motivo: "Paine" };
  }
  if (es("buin")) {
    if (cerca(d, /^linderos( norte| sur)?$/, p, 2)) return { zona: "Linderos", motivo: "Linderos" };
    if (cerca(d, /^maipo( viluco)?$/, p, 2)) return { zona: "Maipo", motivo: "Maipo" };
    return { zona: "Buin", motivo: "Buin" };
  }
  if (es("talagante") || es("isla de maipo") || es("calera de tango")) {
    if (cerca(d, /^lonquen( sur)?$/, p, 2.5)) return { zona: "Lonquén (Pueblo)", motivo: "Lonquén" };
  }
  if (es("san jose de maipo") && p.lat < -33.72) return { fuera: "Para el interior del Cajón del Maipo se lo cotizamos por WhatsApp al +56 9 2227 5399.", motivo: "Cajón del Maipo" };
  // Comunas con una sola tarifa: la de su comuna
  const unica: Record<string, string> = { "santiago": "Santiago Centro", "tiltil": "Til Til", "valparaiso": "Valparaíso - Viña del Mar", "vina del mar": "Valparaíso - Viña del Mar" };
  for (const n of c) {
    if (unica[n]) return { zona: unica[n], motivo: comunas[c.indexOf(n)] };
    if (UNA_TARIFA.has(n)) return { zona: UNA_TARIFA.get(n)!, motivo: comunas[c.indexOf(n)] };
  }
  return null;
}
// Comunas cuyo nombre es igual al de su zona en el tarifario
const UNA_TARIFA = new Map(["Cerrillos", "Cerro Navia", "Conchalí", "Curacaví", "El Bosque", "El Monte", "Estación Central", "Huechuraba", "Independencia",
  "Isla de Maipo", "La Cisterna", "La Granja", "La Pintana", "Lo Espejo", "Lo Prado", "Los Andes", "Macul", "María Pinto", "Melipilla", "Padre Hurtado",
  "Pedro Aguirre Cerda", "Peñaflor", "Providencia", "Pudahuel", "Quilicura", "Quinta Normal", "Rancagua", "Recoleta", "Renca", "San Joaquín",
  "San José de Maipo", "San Miguel", "San Ramón", "Talagante", "Calera de Tango"].map((z) => [norm(z), z]));
