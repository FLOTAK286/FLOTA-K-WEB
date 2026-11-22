// TAG de las autopistas urbanas para el cotizador punto a punto (gratis):
// la ruta de OSRM trae los puntos (nodos de OpenStreetMap) por donde pasa, y se cuentan los que son pórticos TAG
// (highway=toll_gantry en OpenStreetMap). Cada pórtico se cobra a FKTag.VALOR.
// La lista de pórticos de la zona central se pide una vez a Overpass (OpenStreetMap) y se guarda 7 días en el navegador.
(() => {
  const VALOR = 900, CLAVE = "fk-porticos-v1", DIAS = 7;
  const SERVIDORES = ["https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter"];
  const CONSULTA = '[out:json][timeout:25];node["highway"="toll_gantry"](-34.3,-71.8,-32.8,-69.8);out ids;';
  let pendiente = null;
  function guardado() {
    try {
      const x = JSON.parse(localStorage.getItem(CLAVE) || "null");
      if (x && x.t > Date.now() - DIAS * 864e5 && Array.isArray(x.ids) && x.ids.length) return new Set(x.ids);
    } catch (_) {}
    return null;
  }
  // Conjunto de ids de los pórticos (null si no se pudo obtener)
  function porticos() {
    const g = guardado(); if (g) return Promise.resolve(g);
    if (pendiente) return pendiente;
    pendiente = (async () => {
      for (const url of SERVIDORES) {
        try {
          const ctrl = new AbortController(), to = setTimeout(() => ctrl.abort(), 12000);
          const r = await fetch(url, { method: "POST", body: "data=" + encodeURIComponent(CONSULTA),
            headers: { "Content-Type": "application/x-www-form-urlencoded" }, signal: ctrl.signal });
          clearTimeout(to);
          if (!r.ok) continue;
          const ids = ((await r.json()).elements || []).map(e => e.id);
          if (!ids.length) continue;
          try { localStorage.setItem(CLAVE, JSON.stringify({ t: Date.now(), ids })); } catch (_) {}
          return new Set(ids);
        } catch (_) {}
      }
      pendiente = null; // se vuelve a intentar en la próxima cotización
      return null;
    })();
    return pendiente;
  }
  // nodos: ids de OpenStreetMap de la ruta (OSRM annotations=nodes). Devuelve la cantidad de pórticos o null si no se sabe.
  async function contar(nodos) {
    if (!nodos || !nodos.length) return null;
    const set = await porticos(); if (!set) return null;
    let n = 0, antes = null;
    for (const id of nodos) { if (id !== antes && set.has(id)) n++; antes = id; }
    return n;
  }
  // Nodos de una respuesta de OSRM (todas las etapas)
  const nodosDe = ruta => ((ruta && ruta.legs) || []).flatMap(l => (l.annotation && l.annotation.nodes) || []);
  const texto = n => n == null ? "más TAG de autopistas según los pórticos (se confirma al reservar)"
    : n ? `incluye ${n} pórtico${n > 1 ? "s" : ""} TAG ($${VALOR.toLocaleString("es-CL")} c/u)` : "sin pórticos TAG";
  window.FKTag = { VALOR, porticos, contar, nodosDe, texto };
})();
