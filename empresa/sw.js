// Portal de empresas: permite instalarlo como app. Siempre intenta primero la red (datos al día);
// sin conexión muestra la última versión guardada de la página.
const CACHE = "fk-empresa-v3";
const BASE = ["/empresa/", "/assets/site.css", "/assets/app.css", "/assets/app.js", "/assets/config.js", "/assets/tarifas.js",
  "/assets/lugar.js", "/assets/mapa.js", "/assets/vendor/supabase-2.45.4.js", "/assets/img/icono-192.png"];
self.addEventListener("install", e => { e.waitUntil(caches.open(CACHE).then(c => c.addAll(BASE)).catch(() => {})); self.skipWaiting(); });
self.addEventListener("activate", e => e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k.startsWith("fk-empresa") && k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim())));
self.addEventListener("fetch", e => {
  const u = new URL(e.request.url);
  if (e.request.method !== "GET" || u.origin !== location.origin) return;
  e.respondWith(fetch(e.request).then(r => {
    if (r.ok && (u.pathname.startsWith("/assets/") || u.pathname === "/empresa/")) { const copia = r.clone(); caches.open(CACHE).then(c => c.put(e.request, copia)); }
    return r;
  }).catch(() => caches.match(e.request, { ignoreSearch: true })));
});
