// Cotización punto a punto calculada en el servidor (Edge Function "flow", acción "cotizar"):
// el mismo valor que se cobra en /reservar, con la ruta real y $900 por cada pórtico TAG (pórticos de OpenStreetMap
// guardados en la base, contados por la calzada y el sentido que recorre la ruta).
// El servidor entrega dos opciones cuando la ruta rápida usa autopistas: "con" (más rápida, con TAG) y "sin" (evita autopistas).
// Uso:
//   const r = await FKCotizar.puntoAPunto({ texto, lat, lng }, { texto, lat, lng }, "auto" | "van", pasajeros)
//     → { ida, km, min, porticos, tag, nombres_porticos, porticos_mapa, ruta, alternativas: { con, sin }, error } ; { red: true } sin conexión
//   FKCotizar.vista(caja, r, { sin: false, alElegir(sin) {} })  → mapa con la ruta, pórticos y botones Con / Sin autopista
(() => {
  const cache = new Map();
  const clp = n => "$" + Number(n || 0).toLocaleString("es-CL");
  const esc = s => String(s ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  async function puntoAPunto(o, d, vehiculo = "auto", pasajeros = 1) {
    if (!o || !d || o.lat == null || d.lat == null) return null;
    const k = [o.lat, o.lng, d.lat, d.lng, vehiculo, pasajeros].map(x => typeof x === "number" ? x.toFixed(5) : x).join(",");
    if (cache.has(k)) return cache.get(k);
    const C = window.FK_CONFIG;
    try {
      const ctrl = new AbortController(), to = setTimeout(() => ctrl.abort(), 25000);
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
  // Opción elegida (con o sin autopista) de una cotización del servidor
  const opcion = (j, sin) => (j && j.alternativas && (sin ? j.alternativas.sin : j.alternativas.con)) || j;
  // Texto del TAG para mostrar junto al valor
  const textoTag = j => !j || j.porticos == null ? "" : j.porticos ? `incluye ${j.porticos} pórtico${j.porticos > 1 ? "s" : ""} TAG (${clp(j.tag)})` : "sin pórticos TAG";
  const tiempo = m => m < 60 ? `${m} min` : `${Math.floor(m / 60)} h ${m % 60 ? (m % 60) + " min" : ""}`.trim();

  // Leaflet bajo demanda (la portada no lo trae)
  let cargando = null;
  function leaflet() {
    if (window.L) return Promise.resolve(true);
    if (cargando) return cargando;
    cargando = new Promise(res => {
      const css = document.createElement("link"); css.rel = "stylesheet"; css.href = "https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.css"; document.head.appendChild(css);
      const s = document.createElement("script"); s.src = "https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.js";
      s.onload = () => res(true); s.onerror = () => res(false); document.head.appendChild(s);
    });
    return cargando;
  }
  const ESTILO = `.fkc{margin-top:8px;display:grid;gap:8px;text-align:left}
.fkc-ops{display:grid;grid-template-columns:1fr 1fr;gap:6px}
.fkc-op{border:1.5px solid #d9d2c3;background:#fff;color:#1b1f24;border-radius:12px;padding:8px 10px;text-align:left;cursor:pointer;font:inherit;line-height:1.3}
.fkc-op b{display:block;font-size:1.05rem}.fkc-op small{display:block;color:#5f6670;font-size:.78rem}
.fkc-op[aria-pressed="true"]{border-color:#c9a35a;background:#fbf4e3;box-shadow:0 0 0 2px rgba(201,163,90,.35)}
.fkc-mapa{height:230px;border-radius:12px;overflow:hidden;border:1px solid #d9d2c3;background:#eee}
.fkc-lista{font-size:.8rem;color:#5f6670}.fkc-lista summary{cursor:pointer;color:#7a5a17;font-weight:600}
.fkc-tag{width:12px;height:12px;border-radius:50%;background:#e8590c;border:2px solid #fff;box-shadow:0 0 0 1px #e8590c}
@media (prefers-color-scheme:dark){.fkc-op{background:#1f242b;color:#eee;border-color:#3a4049}.fkc-op small{color:#a9adb5}.fkc-op[aria-pressed="true"]{background:#2b2618}}`;
  function estilo() { if (document.getElementById("fkc-estilo")) return; const s = document.createElement("style"); s.id = "fkc-estilo"; s.textContent = ESTILO; document.head.appendChild(s); }

  // caja: elemento donde se dibuja. j: respuesta del servidor. op.sin: opción elegida. op.alElegir(sin): al tocar un botón.
  function vista(caja, j, op = {}) {
    if (!caja) return;
    if (!j || !j.ruta || !j.alternativas) { caja.innerHTML = ""; caja.hidden = true; return; }
    estilo(); caja.hidden = false;
    const con = j.alternativas.con, sin = j.alternativas.sin, elegSin = !!(op.sin && sin), sel = elegSin ? sin : con;
    const boton = (o, esSin) => `<button type="button" class="fkc-op" data-sin="${esSin ? 1 : 0}" aria-pressed="${esSin === elegSin}">
        <small>${esSin ? "🏙 Sin autopista" : "🛣 Con autopista"}</small><b>${clp(o.ida)}</b>
        <small>${String(o.km).replace(".", ",")} km · ~${tiempo(o.min)}</small><small>${o.porticos ? `${o.porticos} pórtico${o.porticos > 1 ? "s" : ""} TAG (${clp(o.tag)})` : "Sin TAG"}</small></button>`;
    caja.innerHTML = `<div class="fkc">
      ${sin ? `<div class="fkc-ops" role="group" aria-label="Ruta">${boton(con, false)}${boton(sin, true)}</div>` : ""}
      <div class="fkc-mapa" aria-label="Mapa de la ruta"></div>
      ${sel.porticos ? `<details class="fkc-lista"><summary>Ver los ${sel.porticos} pórtico${sel.porticos > 1 ? "s" : ""} TAG de esta ruta</summary><ol>${(sel.nombres_porticos || []).map(n => `<li>${esc(n)}</li>`).join("")}</ol></details>`
        : `<div class="fkc-lista">Esta ruta no pasa por pórticos TAG.</div>`}
      ${sin && elegSin ? `<div class="fkc-lista">El conductor irá sin usar autopistas: el viaje es más lento, pero sin TAG.</div>` : ""}
    </div>`;
    caja.querySelectorAll(".fkc-op").forEach(b => b.addEventListener("click", () => { if (op.alElegir) op.alElegir(b.dataset.sin === "1"); }));
    const el = caja.querySelector(".fkc-mapa");
    leaflet().then(ok => {
      if (!ok || !el.isConnected) { el.remove(); return; }
      const m = L.map(el, { scrollWheelZoom: false, attributionControl: true });
      L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", { maxZoom: 19, attribution: '&copy; <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener">OpenStreetMap</a>' }).addTo(m);
      const otra = elegSin ? con : sin;
      if (otra && otra.ruta) L.polyline(otra.ruta, { color: "#8a8f98", weight: 4, opacity: 0.6, dashArray: "6 8" }).addTo(m);
      const linea = L.polyline(sel.ruta, { color: elegSin ? "#2e7d4f" : "#b8892c", weight: 6, opacity: 0.9 }).addTo(m);
      const ini = sel.ruta[0], fin = sel.ruta[sel.ruta.length - 1];
      L.circleMarker(ini, { radius: 8, color: "#fff", weight: 2, fillColor: "#1b1f24", fillOpacity: 1 }).bindTooltip("Origen").addTo(m);
      L.circleMarker(fin, { radius: 8, color: "#fff", weight: 2, fillColor: "#c9a35a", fillOpacity: 1 }).bindTooltip("Destino").addTo(m);
      (sel.porticos_mapa || []).forEach(p => L.marker([p.lat, p.lng], { icon: L.divIcon({ className: "", html: '<div class="fkc-tag"></div>', iconSize: [12, 12], iconAnchor: [6, 6] }) })
        .bindTooltip("TAG · " + p.n).addTo(m));
      m.fitBounds(linea.getBounds(), { padding: [18, 18] });
    });
  }
  // Pórticos TAG de la ruta más rápida entre varios puntos (origen, paradas, destino), para el cierre con taxímetro.
  // → { porticos, tag, valor_tag, km, nombres } o null si no se pudo calcular
  const cachePort = new Map();
  async function porticosRuta(puntos) {
    const pts = (puntos || []).filter(p => p && p.lat != null && p.lng != null).map(p => ({ lat: +p.lat, lng: +p.lng }));
    if (pts.length < 2) return null;
    const k = pts.map(p => p.lat.toFixed(5) + "," + p.lng.toFixed(5)).join(";");
    if (cachePort.has(k)) return cachePort.get(k);
    const C = window.FK_CONFIG;
    try {
      const r = await fetch(C.url + "/functions/v1/flow?accion=porticos", { method: "POST",
        headers: { "Content-Type": "application/json", apikey: C.anonKey, Authorization: "Bearer " + C.anonKey }, body: JSON.stringify({ puntos: pts }) });
      const j = await r.json().catch(() => null);
      if (!r.ok || !j || j.porticos == null) return null;
      cachePort.set(k, j);
      return j;
    } catch (_) { return null; }
  }
  // Puntos de una reserva: origen, paradas (con punto) y destino
  const puntosReserva = r => [{ lat: r.origen_lat, lng: r.origen_lng }, ...((r.paradas || []).filter(p => p && p.lat != null)), { lat: r.destino_lat, lng: r.destino_lng }];
  window.FKCotizar = { puntoAPunto, textoTag, opcion, vista, porticosRuta, puntosReserva };
})();
