// Importa datos públicos de OpenStreetMap a la tabla osm_datos (pórticos TAG de la RM y las vías donde están).
// Uso: abrir https://<proyecto>.supabase.co/functions/v1/importar-osm?que=porticos en el navegador.
// Solo trae datos públicos y espera 5 minutos entre importaciones del mismo tipo.
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const SERVIDORES = [
  "https://overpass-api.de/api/interpreter",
  "https://overpass.kumi.systems/api/interpreter",
  "https://overpass.private.coffee/api/interpreter",
  "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
];
const BBOX = "-33.80,-71.00,-33.20,-70.40"; // Región Metropolitana (sur, oeste, norte, este)
const CONSULTAS: Record<string, string> = {
  porticos: `[out:json][timeout:90];
    (node["highway"="toll_gantry"](${BBOX});node["barrier"="toll_booth"](${BBOX}););
    out body;
    way(bn)["highway"];
    out geom tags;`,
  // Avenidas que separan sectores de tarifa dentro de una misma comuna, y localidades (Batuco, Nos, Las Vizcachas, etc.)
  divisiones: `[out:json][timeout:120];
    (way["highway"~"^(primary|secondary|tertiary|trunk|unclassified|residential)$"]["name"~"Manquehue|Paul Harris|Vicente P[eé]rez Rosales|Las Perdices|Tobalaba|^Avenida La Florida|Diagonal Las Torres|Irarr[aá]zaval|[ÁA]lvaro Casanova|Padre Hurtado|Camino Ot[oñ]al|San Dami[aá]n|^Avenida La Plaza|Tabancura|Esmeralda|Virginia Subercaseaux|Los Pioneros|Lo Arcaya|Pedro Lira Urquieta|Bernardo Leighton|Paseo Los Bravos"](${BBOX}););
    out geom tags;
    (node["place"~"^(suburb|neighbourhood|quarter|village|hamlet|town|locality)$"](${BBOX}););
    out body;`,
};

Deno.serve(async (req) => {
  const que = new URL(req.url).searchParams.get("que") ?? "";
  const q = CONSULTAS[que];
  if (!q) return new Response("Indique ?que=" + Object.keys(CONSULTAS).join("|"), { status: 400 });
  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  const { data: prev } = await sb.from("osm_datos").select("importado_en").eq("clave", que).maybeSingle();
  if (prev && Date.now() - new Date(prev.importado_en).getTime() < 5 * 60e3) return new Response("Ya se importó hace menos de 5 minutos. Listo.", { status: 200 });
  // Prueba varios servidores públicos de OpenStreetMap (a veces uno está saturado)
  let j: any = null; const fallas: string[] = [];
  for (const url of SERVIDORES) {
    try {
      const r = await fetch(url, { method: "POST", body: new URLSearchParams({ data: q }), signal: AbortSignal.timeout(100000),
        headers: { "User-Agent": "Flota-K/1.0 (https://fk-servicios.com)", "Accept": "application/json" } });
      const t = await r.text();
      if (!r.ok) { fallas.push(`${new URL(url).host}: ${r.status} ${t.slice(0, 80)}`); continue; }
      j = JSON.parse(t); break;
    } catch (e) { fallas.push(`${new URL(url).host}: ${(e as Error).message.slice(0, 80)}`); }
  }
  if (!j) return new Response("OpenStreetMap no respondió. Detalle para Claude:\n" + fallas.join("\n"), { status: 502, headers: { "Content-Type": "text/plain; charset=utf-8" } });
  const { error } = await sb.from("osm_datos").upsert({ clave: que, datos: j, importado_en: new Date().toISOString() });
  if (error) return new Response("No se pudo guardar: " + error.message, { status: 500 });
  const nodos = (j.elements || []).length;
  return new Response(`Listo: ${nodos} elementos importados (${que}). Ya puede cerrar esta página y avisarle a Claude.`, { headers: { "Content-Type": "text/plain; charset=utf-8" } });
});
