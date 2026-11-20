// Mapa simple y gratuito: Leaflet + OpenStreetMap. Lo usan /seguimiento y /equipo.
window.FKMapa = {
  crear(el, centro, zoom) {
    const m = L.map(el, { scrollWheelZoom: false }).setView(centro || [-33.45, -70.66], zoom || 11);
    L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 19, attribution: '&copy; <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener">OpenStreetMap</a>'
    }).addTo(m);
    return m;
  },
  // estilo: true = sin señal (gris), o "libre" / "ocupado" / "viejo"
  icono(txt, estilo) {
    const c = estilo === true ? "viejo" : (estilo || "");
    return L.divIcon({ className: "fk-pin" + (c ? " " + c : ""), html: "<span>" + (txt || "K") + "</span>", iconSize: [34, 34], iconAnchor: [17, 17], popupAnchor: [0, -16] });
  },
  // Mapa de calor de próximos servicios: rojo < 30 min, naranjo < 1 h, amarillo < 2 h, azul 2 h o más
  CALOR: [[30, "#e5533d", "Menos de 30 min"], [60, "#f2994a", "30 a 60 min"], [120, "#f2c94c", "1 a 2 horas"], [Infinity, "#2f80ed", "Más de 2 horas"]],
  colorCalor(min) { return this.CALOR.find(c => min < c[0])[1]; },
  tiempoTxt(min) { return min < 60 ? `${min} min` : `${Math.floor(min / 60)} h${min % 60 ? " " + (min % 60) + " min" : ""}`; },
  // puntos: [{ lat, lng, min, txt? }]
  calor(mapa, capa, puntos) {
    if (!mapa || !window.L) return capa;
    if (!capa) capa = L.layerGroup().addTo(mapa); else capa.clearLayers();
    [...puntos].sort((a, b) => b.min - a.min).forEach(p => {
      const c = this.colorCalor(p.min);
      L.circle([p.lat, p.lng], { radius: 900, stroke: false, fillColor: c, fillOpacity: 0.38, interactive: true })
        .bindPopup(p.txt || `Servicio en ${this.tiempoTxt(p.min)} (zona aproximada)`).addTo(capa);
    });
    return capa;
  },
  leyendaCalor() {
    return this.CALOR.map(c => `<span style="display:inline-flex;align-items:center;gap:4px;margin-right:10px"><i style="width:12px;height:12px;border-radius:50%;background:${c[1]};display:inline-block"></i>${c[2]}</span>`).join("");
  },
  hace(iso) {
    const s = Math.max(0, Math.round((Date.now() - new Date(iso)) / 1000));
    return s < 60 ? `hace ${s} s` : s < 3600 ? `hace ${Math.round(s / 60)} min` : s < 86400 ? `hace ${Math.round(s / 3600)} h` : `hace ${Math.round(s / 86400)} días`;
  }
};
