// Mapa simple y gratuito: Leaflet + OpenStreetMap. Lo usan /seguimiento y /equipo.
window.FKMapa = {
  crear(el, centro, zoom) {
    const m = L.map(el, { scrollWheelZoom: false }).setView(centro || [-33.45, -70.66], zoom || 11);
    L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 19, attribution: '&copy; <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener">OpenStreetMap</a>'
    }).addTo(m);
    return m;
  },
  icono(txt, viejo) {
    return L.divIcon({ className: "fk-pin" + (viejo ? " viejo" : ""), html: "<span>" + (txt || "K") + "</span>", iconSize: [34, 34], iconAnchor: [17, 17], popupAnchor: [0, -16] });
  },
  hace(iso) {
    const s = Math.max(0, Math.round((Date.now() - new Date(iso)) / 1000));
    return s < 60 ? `hace ${s} s` : s < 3600 ? `hace ${Math.round(s / 60)} min` : s < 86400 ? `hace ${Math.round(s / 3600)} h` : `hace ${Math.round(s / 86400)} días`;
  }
};
