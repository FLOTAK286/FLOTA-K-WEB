// Dirección con punto obligatorio en el mapa (pin), gratis:
// autocompletar con Photon (datos de OpenStreetMap) y mapa Leaflet para fijar el punto exacto arrastrando el pin.
(function () {
  const AERO = { texto: "Aeropuerto Internacional de Santiago (SCL), Pudahuel", lat: -33.39297, lng: -70.78579 };
  const BBOX = "-75.8,-56.0,-66.3,-17.4"; // Chile
  const esc = s => String(s ?? "").replace(/[&<>"']/g, ch => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[ch]));
  const esAero = t => /aeropuerto|\bscl\b|arturo merino|terminal (nacional|internacional)/i.test(t || "");

  function etiqueta(p) {
    const calle = [p.street, p.housenumber].filter(Boolean).join(" ");
    const nombre = p.name && p.name !== p.street ? p.name : "";
    const l1 = nombre || calle || p.name || "";
    const resto = [...new Set([nombre ? calle : "", p.district || p.locality, p.city || p.county].filter(Boolean))].filter(x => x !== l1);
    return { l1, l2: resto.join(", "), completo: [l1, ...resto].filter(Boolean).join(", "), comunas: [p.city, p.district, p.locality, p.county].filter(Boolean) };
  }
  async function buscar(q, signal) {
    const r = await fetch(`https://photon.komoot.io/api/?q=${encodeURIComponent(q)}&limit=7&lat=-33.45&lon=-70.66&bbox=${BBOX}`, { signal });
    const j = await r.json();
    return (j.features || []).filter(f => !f.properties.countrycode || f.properties.countrycode === "CL")
      .map(f => ({ ...etiqueta(f.properties), lat: f.geometry.coordinates[1], lng: f.geometry.coordinates[0] }))
      .filter((x, i, a) => x.l1 && a.findIndex(y => y.completo === x.completo) === i);
  }
  async function inversa(lat, lng) {
    try {
      const r = await fetch(`https://photon.komoot.io/reverse?lat=${lat}&lon=${lng}&limit=1`);
      const f = ((await r.json()).features || [])[0];
      return f ? etiqueta(f.properties) : null;
    } catch (_) { return null; }
  }

  // input: el campo de texto. opts.alCambiar(): se llama cuando cambia el punto o el texto elegido.
  function montar(input, opts = {}) {
    const wrap = document.createElement("div");
    wrap.className = "lugar";
    input.insertAdjacentElement("afterend", wrap);
    input.setAttribute("autocomplete", "off");
    input.setAttribute("role", "combobox");
    wrap.innerHTML = `<div class="lugar-sug" role="listbox" hidden></div>
      <div class="lugar-barra"><span class="lugar-estado"></span>
        <span><button type="button" class="linkbtn l-deshacer" hidden title="Volver el pin a donde estaba antes">↶ Deshacer</button><span class="l-sep" hidden> · </span><button type="button" class="linkbtn l-aero">✈ Aeropuerto SCL</button> · <button type="button" class="linkbtn l-mapa">📍 Marcar en el mapa</button></span></div>
      <div class="lugar-mapa" hidden></div>
      <div class="lugar-inv small" hidden></div>`;
    const sug = wrap.querySelector(".lugar-sug"), est = wrap.querySelector(".lugar-estado"), mapaEl = wrap.querySelector(".lugar-mapa"), inv = wrap.querySelector(".lugar-inv");
    let punto = null, mapa = null, pin = null, ctrl = null, timer = null, items = [], idx = -1;
    // Historial para "Deshacer": cada vez que el punto cambia se guarda el anterior (y el texto de la dirección)
    let historial = [], deshaciendo = false;
    const btnDeshacer = wrap.querySelector(".l-deshacer"), sepDeshacer = wrap.querySelector(".l-sep");
    const avisar = () => { if (opts.alCambiar) opts.alCambiar(); };

    function estado() {
      est.className = "lugar-estado " + (punto ? "ok" : "falta");
      est.textContent = punto ? "✅ Punto marcado (puede arrastrar el pin)" : "⚠ Falta marcar el punto: elija una sugerencia o toque el mapa";
      btnDeshacer.hidden = sepDeshacer.hidden = !historial.length;
    }
    function verMapa() {
      mapaEl.hidden = false;
      if (!mapa) {
        if (!window.L || !window.FKMapa) { mapaEl.innerHTML = '<p class="small muted">No se pudo cargar el mapa. Revise su conexión.</p>'; return; }
        mapa = FKMapa.crear(mapaEl, punto ? [punto.lat, punto.lng] : [-33.45, -70.66], punto ? 17 : 11);
        mapa.on("click", e => fijar(e.latlng.lat, e.latlng.lng, true));
      }
      setTimeout(() => { mapa.invalidateSize(); if (punto) mapa.setView([punto.lat, punto.lng], Math.max(mapa.getZoom(), 16)); }, 60);
    }
    function fijar(lat, lng, desdeMapa, comunas) {
      const nuevoLat = Math.round(lat * 1e6) / 1e6, nuevoLng = Math.round(lng * 1e6) / 1e6;
      if (punto && !deshaciendo && (punto.lat !== nuevoLat || punto.lng !== nuevoLng)) {
        historial.push({ lat: punto.lat, lng: punto.lng, comunas: [...(punto.comunas || [])], texto: input.value });
        if (historial.length > 30) historial.shift();
      }
      punto = { lat: Math.round(lat * 1e6) / 1e6, lng: Math.round(lng * 1e6) / 1e6, comunas: comunas || [] };
      verMapa();
      if (mapa) {
        if (!pin) {
          pin = L.marker([punto.lat, punto.lng], { draggable: true, autoPan: true, icon: L.divIcon({ className: "lugar-pin", html: "<span>📍</span>", iconSize: [34, 34], iconAnchor: [17, 32] }) }).addTo(mapa);
          pin.on("dragend", () => { const p = pin.getLatLng(); fijar(p.lat, p.lng, true); });
        } else pin.setLatLng([punto.lat, punto.lng]);
        if (!desdeMapa) mapa.setView([punto.lat, punto.lng], 17);
      }
      estado();
      if (desdeMapa) {
        inv.hidden = false; inv.textContent = "Buscando la dirección de ese punto…";
        const quien = punto;
        inversa(punto.lat, punto.lng).then(e => {
          if (quien !== punto) return;
          if (!e) { inv.textContent = "Punto marcado en el mapa."; return; }
          punto.comunas = e.comunas; const t = e.completo;
          if (!input.value.trim()) { input.value = t; inv.hidden = true; avisar(); return; }
          avisar();
          inv.innerHTML = `📍 El pin está en: <b>${esc(t)}</b> <button type="button" class="linkbtn l-usar">Usar esta dirección</button>`;
          inv.querySelector(".l-usar").onclick = () => { input.value = t; inv.hidden = true; avisar(); };
        });
      } else inv.hidden = true;
      avisar();
    }
    function pintarSug() {
      idx = -1;
      sug.innerHTML = items.length
        ? items.map((x, i) => `<button type="button" role="option" data-i="${i}"><b>${esc(x.l1)}</b><span>${esc(x.l2)}</span></button>`).join("")
        : '<p class="small muted" style="margin:6px 10px">Sin resultados. Pruebe escribirlo de otra forma (calle y número, o nombre del lugar) o marque el punto en el mapa.</p>';
      sug.hidden = false; input.setAttribute("aria-expanded", "true");
      sug.querySelectorAll("[data-i]").forEach(b => b.addEventListener("mousedown", e => { e.preventDefault(); elegir(items[+b.dataset.i]); }));
    }
    function cerrar() { sug.hidden = true; input.setAttribute("aria-expanded", "false"); }
    function elegir(x) { input.value = x.completo; cerrar(); fijar(x.lat, x.lng, false, x.comunas); }
    function buscarAhora() {
      clearTimeout(timer);
      const q = input.value.trim();
      if (q.length < 3) { cerrar(); return; }
      timer = setTimeout(async () => {
        if (ctrl) ctrl.abort(); ctrl = new AbortController();
        try { items = await buscar(q, ctrl.signal); } catch (e) { if (e.name === "AbortError") return; items = []; }
        if (document.activeElement === input || opts.mostrarSiempre) pintarSug();
      }, 350);
    }
    input.addEventListener("input", buscarAhora);
    input.addEventListener("keydown", e => {
      if (sug.hidden || !items.length) return;
      const bs = [...sug.querySelectorAll("[data-i]")];
      if (e.key === "ArrowDown" || e.key === "ArrowUp") { e.preventDefault(); idx = (idx + (e.key === "ArrowDown" ? 1 : -1) + bs.length) % bs.length; bs.forEach((b, i) => b.classList.toggle("act", i === idx)); }
      else if (e.key === "Enter" && idx >= 0) { e.preventDefault(); elegir(items[idx]); }
      else if (e.key === "Escape") cerrar();
    });
    input.addEventListener("blur", () => setTimeout(cerrar, 150));
    btnDeshacer.addEventListener("click", () => {
      const prev = historial.pop(); if (!prev) return;
      deshaciendo = true;
      input.value = prev.texto;
      fijar(prev.lat, prev.lng, false, prev.comunas);
      deshaciendo = false;
      estado(); avisar();
    });
    wrap.querySelector(".l-aero").addEventListener("click", () => { input.value = AERO.texto; cerrar(); fijar(AERO.lat, AERO.lng, false); });
    wrap.querySelector(".l-mapa").addEventListener("click", () => { verMapa(); if (!punto) est.textContent = "👆 Toque el mapa en el punto exacto (puede acercar con + y −)"; });
    estado();

    const api = {
      get: () => punto ? { ...punto, comunas: [...punto.comunas] } : null,
      // Pone texto y punto; si no hay punto pero el texto es el aeropuerto, usa el punto del aeropuerto.
      // (cargar un punto desde el sistema empieza un historial nuevo: "Deshacer" no vuelve a datos de otra reserva)
      set(texto, lat, lng) {
        historial = []; deshaciendo = true;
        if (texto != null) input.value = texto;
        if (lat != null && lng != null) fijar(lat, lng, false);
        else { api.limpiar(); if (esAero(input.value)) fijar(AERO.lat, AERO.lng, false); }
        deshaciendo = false; estado();
      },
      limpiar() { punto = null; historial = []; if (pin) { pin.remove(); pin = null; } mapaEl.hidden = true; inv.hidden = true; cerrar(); estado(); },
      buscarAhora() { opts.mostrarSiempre = true; buscarAhora(); setTimeout(() => { opts.mostrarSiempre = false; }, 3000); },
      exigir() { if (punto) return true; verMapa(); wrap.scrollIntoView({ behavior: "smooth", block: "center" }); est.classList.add("parpadeo"); setTimeout(() => est.classList.remove("parpadeo"), 1500); return false; }
    };
    return api;
  }
  // Ruta real en auto (OSRM, datos de OpenStreetMap, gratis). Se suma un 25% por tráfico.
  // Si el servicio de rutas no responde, se estima con la distancia en línea recta (x1,35 y 25 km/h promedio).
  const TRAFICO = 1.25, cacheRuta = new Map();
  // vias: paradas intermedias opcionales [{lat, lng}], en orden
  // opts.tag: además cuenta los pórticos TAG de la ruta (res.tags: número, o null si no se pudo saber; necesita assets/tag.js)
  async function ruta(a, b, vias = [], opts = {}) {
    if (!a || !b || a.lat == null || b.lat == null) return null;
    const pts = [a, ...(vias || []).filter(v => v && v.lat != null), b];
    const k = pts.flatMap(p => [p.lat, p.lng]).map(x => Number(x).toFixed(4)).join(",");
    let res = cacheRuta.get(k) || null;
    if (res) return conTag(res, opts);
    try {
      const ctrl = new AbortController(), to = setTimeout(() => ctrl.abort(), 6000);
      const r = await fetch(`https://router.project-osrm.org/route/v1/driving/${pts.map(p => p.lng + "," + p.lat).join(";")}?overview=false&annotations=nodes`, { signal: ctrl.signal });
      clearTimeout(to);
      const x = ((await r.json()).routes || [])[0];
      if (x) res = { km: Math.round(x.distance / 100) / 10, min: Math.max(1, Math.ceil(x.duration * TRAFICO / 60)), aprox: false,
                     nodos: (x.legs || []).flatMap(l => (l.annotation && l.annotation.nodes) || []) };
    } catch (_) {}
    if (!res) { let lineal = 0; for (let i = 1; i < pts.length; i++) lineal += distKm(pts[i - 1], pts[i]);
      const km = Math.round(lineal * 1.35 * 10) / 10; res = { km, min: Math.max(1, Math.ceil(km / 25 * 60)), aprox: true }; }
    cacheRuta.set(k, res);
    return conTag(res, opts);
  }
  async function conTag(res, opts) {
    if (!opts || !opts.tag || !window.FKTag) return res;
    if (res.tags === undefined || res.tags === null) res.tags = await FKTag.contar(res.nodos);
    return res;
  }
  const distKm = (a, b) => { const R = 6371, r = x => x * Math.PI / 180, dLa = r(b.lat - a.lat), dLo = r(b.lng - a.lng);
    return 2 * R * Math.asin(Math.sqrt(Math.sin(dLa / 2) ** 2 + Math.cos(r(a.lat)) * Math.cos(r(b.lat)) * Math.sin(dLo / 2) ** 2)); };
  // ¿Este punto (o este texto) es el aeropuerto de Santiago? (a menos de 3 km del terminal)
  const enAeropuerto = (p, texto) => (p ? distKm(p, AERO) < 3 : false) || esAero(texto);
  window.FKLugar = { montar, AERO, esAero, distKm, enAeropuerto, ruta, TRAFICO };
})();
