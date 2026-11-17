// Paradas intermedias de un servicio (entre el origen y el destino), con punto exacto en el mapa.
// Uso: const par = FKParadas.montar(contenedor, { alCambiar }); par.get() → [{direccion, lat, lng}] | null si falta marcar alguna.
// Requiere assets/lugar.js (FKLugar).
(function () {
  const MAX = 8;
  const esc = s => String(s ?? "").replace(/[&<>"']/g, ch => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[ch]));

  function montar(box, opts = {}) {
    box.classList.add("paradas");
    box.innerHTML = `<div class="paradas-lista"></div>
      <button type="button" class="linkbtn paradas-mas">+ Agregar parada</button>`;
    const lista = box.querySelector(".paradas-lista"), mas = box.querySelector(".paradas-mas");
    let filas = []; // { el, lug }
    const avisar = () => { if (opts.alCambiar) opts.alCambiar(); };

    function numerar() {
      filas.forEach((f, i) => { f.el.querySelector(".parada-n").textContent = `Parada ${i + 1}`; });
      mas.hidden = filas.length >= MAX;
    }
    function agregar(texto, lat, lng) {
      if (filas.length >= MAX) return;
      const el = document.createElement("div");
      el.className = "f lugar-f parada";
      const id = "parada-" + Math.random().toString(36).slice(2, 9);
      el.innerHTML = `<label for="${id}"><span class="parada-n"></span> <button type="button" class="linkbtn parada-x" title="Quitar esta parada">✕ quitar</button></label>
        <input id="${id}" placeholder="Escriba calle y número, o el nombre del lugar">`;
      lista.appendChild(el);
      const lug = FKLugar.montar(el.querySelector("input"), { alCambiar: avisar });
      const fila = { el, lug };
      filas.push(fila);
      el.querySelector(".parada-x").onclick = () => { filas = filas.filter(x => x !== fila); el.remove(); numerar(); avisar(); };
      if (texto != null) lug.set(texto, lat, lng);
      numerar();
      return fila;
    }
    mas.onclick = () => { const f = agregar(); f.el.querySelector("input").focus(); avisar(); };

    const api = {
      // Todas las paradas con punto marcado; null si alguna está a medias (con texto pero sin punto)
      get() {
        const out = [];
        for (const f of filas) {
          const t = f.el.querySelector("input").value.trim(), p = f.lug.get();
          if (!t && !p) continue; // fila vacía: se ignora
          if (!p) return null;
          out.push({ direccion: t, lat: p.lat, lng: p.lng });
        }
        return out;
      },
      // Puntos para calcular la ruta (solo las que ya tienen punto)
      puntos() { return filas.map(f => f.lug.get()).filter(Boolean); },
      exigir() {
        for (const f of filas) { const t = f.el.querySelector("input").value.trim(); if (t && !f.lug.get()) { f.lug.exigir(); return false; } }
        return true;
      },
      set(lista_) { api.limpiar(); (lista_ || []).forEach(p => agregar(p.direccion, p.lat, p.lng)); avisar(); },
      limpiar() { filas.forEach(f => f.el.remove()); filas = []; numerar(); },
      cantidad() { return filas.length; }
    };
    numerar();
    return api;
  }

  // Lista para mostrar (detalle, app del conductor, seguimiento). conLinks: agrega Waze / Google Maps.
  function html(paradas, conLinks) {
    if (!paradas || !paradas.length) return "";
    return `<ol class="paradas-ver">${paradas.map(p => `<li>${esc(p.direccion)}${conLinks && p.lat != null ? ` <span class="small">· <a href="https://waze.com/ul?ll=${p.lat},${p.lng}&navigate=yes" target="_blank" rel="noopener">Waze</a> · <a href="https://www.google.com/maps/dir/?api=1&destination=${p.lat},${p.lng}" target="_blank" rel="noopener">Maps</a></span>` : ""}</li>`).join("")}</ol>`;
  }

  window.FKParadas = { montar, html, MAX };
})();
