// App "Flota-K Operaciones": permite instalar el panel. No guarda datos: todo se pide siempre a la red,
// y si no hay conexión muestra un aviso simple.
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", e => e.waitUntil(self.clients.claim()));
self.addEventListener("fetch", e => {
  if (e.request.mode !== "navigate") return;
  e.respondWith(fetch(e.request).catch(() => new Response(
    '<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><body style="background:#0d0f12;color:#eee;font-family:sans-serif;padding:24px"><h2>Sin conexión</h2><p>Revise su internet y vuelva a abrir la app.</p><button onclick="location.reload()" style="padding:10px 16px">Reintentar</button></body>',
    { headers: { "Content-Type": "text/html; charset=utf-8" } })));
});
