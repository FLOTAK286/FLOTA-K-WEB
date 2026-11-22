// Cotización punto a punto calculada en el servidor (Edge Function "flow", acción "cotizar"):
// el mismo valor que se cobra en /reservar, con la ruta real y $900 por cada pórtico TAG (pórticos de OpenStreetMap
// guardados en la base, contados por la calzada y el sentido que recorre la ruta).
// Uso: const r = await FKCotizar.puntoAPunto({ texto, lat, lng }, { texto, lat, lng }, "auto" | "van", pasajeros)
//   → { ida, km, min, porticos, tag, nota, error } ; { red: true } si no hubo respuesta (sin conexión).
(() => {
  const cache = new Map();
  async function puntoAPunto(o, d, vehiculo = "auto", pasajeros = 1) {
    if (!o || !d || o.lat == null || d.lat == null) return null;
    const k = [o.lat, o.lng, d.lat, d.lng, vehiculo, pasajeros].map(x => typeof x === "number" ? x.toFixed(5) : x).join(",");
    if (cache.has(k)) return cache.get(k);
    const C = window.FK_CONFIG;
    try {
      const ctrl = new AbortController(), to = setTimeout(() => ctrl.abort(), 20000);
      const r = await fetch(C.url + "/functions/v1/flow?accion=cotizar", {
        method: "POST", signal: ctrl.signal,
        headers: { "Content-Type": "application/json", apikey: C.anonKey, Authorization: "Bearer " + C.anonKey },
        body: JSON.stringify({ tipo: "punto_a_punto", vehiculo, pasajeros,
          origen: { texto: o.texto || "", lat: o.lat, lng: o.lng }, destino: { texto: d.texto || "", lat: d.lat, lng: d.lng } }) });
      clearTimeout(to);
      const j = await r.json().catch(() => ({}));
      if (!r.ok && !j.error) return { red: true };
      if (!j.error) cache.set(k, j);
      return j;
    } catch (_) { return { red: true }; }
  }
  // Texto del TAG para mostrar junto al valor
  const textoTag = j => !j || j.porticos == null ? "" : j.porticos ? `incluye ${j.porticos} pórtico${j.porticos > 1 ? "s" : ""} TAG ($${Number(j.tag).toLocaleString("es-CL")})` : "sin pórticos TAG";
  window.FKCotizar = { puntoAPunto, textoTag };
})();
