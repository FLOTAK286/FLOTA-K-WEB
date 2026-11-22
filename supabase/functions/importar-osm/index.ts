// Importa datos públicos de OpenStreetMap a la tabla osm_datos (pórticos TAG, avenidas que dividen sectores, localidades).
// Uso: abrir https://<proyecto>.supabase.co/functions/v1/importar-osm?que=porticos|divisiones|localidades en el navegador.
// Responde al tiro y descarga en segundo plano; si falla, deja el motivo en osm_datos con clave "error_<que>".
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
  // Avenidas que separan sectores de tarifa (oriente: Las Condes, Vitacura, La Reina, Peñalolén, La Florida, Ñuñoa)
  divisiones: `[out:json][timeout:80];
    way["highway"~"^(primary|secondary|tertiary|trunk)$"]["name"~"Manquehue|Paul Harris|Vicente P.rez Rosales|Las Perdices|Tobalaba|^Avenida La Florida|Diagonal Las Torres|Irarr.zaval|lvaro Casanova|Padre Hurtado|Tabancura"](-33.58,-70.64,-33.36,-70.50);
    out geom tags;`,
  // Avenidas límite en la periferia (Colina: Esmeralda; Chicureo: Los Pioneros, Lo Arcaya; Pirque: Virginia Subercaseaux)
  divisiones2: `[out:json][timeout:80];
    (way["highway"]["name"~"Esmeralda"](-33.25,-70.72,-33.18,-70.63);
     way["highway"]["name"~"Los Pioneros|Lo Arcaya|Piedra Roja"](-33.32,-70.70,-33.24,-70.60);
     way["highway"]["name"~"Virginia Subercaseaux"](-33.70,-70.62,-33.62,-70.53););
    out geom tags;`,
  // Localidades y barrios con nombre (Batuco, Nos, Las Vizcachas, El Arrayán, Ciudad Satélite...)
  localidades: `[out:json][timeout:80];
    node["place"~"^(suburb|neighbourhood|village|hamlet|locality|town)$"](${BBOX});
    out body;`,
};

Deno.serve(async (req) => {
  const que = new URL(req.url).searchParams.get("que") ?? "";
  const q = CONSULTAS[que];
  if (!q) return new Response("Indique ?que=" + Object.keys(CONSULTAS).join("|"), { status: 400 });
  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  const { data: prev } = await sb.from("osm_datos").select("importado_en").eq("clave", que).maybeSingle();
  if (prev && Date.now() - new Date(prev.importado_en).getTime() < 5 * 60e3) return new Response("Ya se importó hace menos de 5 minutos. Listo.", { status: 200 });

  const tarea = (async () => {
    const fallas: string[] = [];
    for (const url of SERVIDORES) {
      try {
        const r = await fetch(url, { method: "POST", body: new URLSearchParams({ data: q }), signal: AbortSignal.timeout(90000),
          headers: { "User-Agent": "Flota-K/1.0 (https://fk-servicios.com)", "Accept": "application/json" } });
        const t = await r.text();
        if (!r.ok) { fallas.push(`${new URL(url).host}: ${r.status} ${t.slice(0, 120)}`); continue; }
        const j = JSON.parse(t);
        await sb.from("osm_datos").upsert({ clave: que, datos: j, importado_en: new Date().toISOString() });
        await sb.from("osm_datos").delete().eq("clave", "error_" + que);
        return;
      } catch (e) { fallas.push(`${new URL(url).host}: ${(e as Error).message.slice(0, 120)}`); }
    }
    await sb.from("osm_datos").upsert({ clave: "error_" + que, datos: { fallas }, importado_en: new Date().toISOString() });
  })();
  // @ts-ignore EdgeRuntime existe en Supabase: deja terminar la tarea después de responder
  if (typeof EdgeRuntime !== "undefined") EdgeRuntime.waitUntil(tarea); else await tarea;
  return new Response(`Recibido: descargando "${que}" en segundo plano. Puede cerrar esta página; en 2 minutos avísele a Claude.`,
    { headers: { "Content-Type": "text/plain; charset=utf-8" } });
});
