// App del pasajero: permite instalarla y abrirla aunque falle la conexión (muestra la última versión guardada).
// Siempre intenta primero la red, para que los datos y precios estén al día.
const CACHE = "fk-app-v1";
const BASE = ["/app/", "/assets/site.css", "/assets/app.css", "/assets/app.js", "/assets/config.js", "/assets/tarifas.js",
  "/assets/lugar.js", "/assets/mapa.js", "/assets/pasajero.js", "/assets/vendor/supabase-2.45.4.js", "/assets/img/icono-192.png"];
self.addEventListener("install", e => { e.waitUntil(caches.open(CACHE).then(c => c.addAll(BASE)).catch(() => {})); self.skipWaiting(); });
self.addEventListener("activate", e => e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim())));
self.addEventListener("fetch", e => {
  const u = new URL(e.request.url);
  if (e.request.method !== "GET" || u.origin !== location.origin) return; // Supabase, mapas, etc.: siempre a la red
  e.respondWith(fetch(e.request).then(r => {
    if (r.ok && (u.pathname.startsWith("/assets/") || u.pathname === "/app/")) { const copia = r.clone(); caches.open(CACHE).then(c => c.put(e.request, copia)); }
    return r;
  }).catch(() => caches.match(e.request, { ignoreSearch: true })));
});
