// Service worker mínimo: permite instalar la app. No guarda copias de datos (siempre información al día).
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", e => e.waitUntil(self.clients.claim()));
self.addEventListener("fetch", () => {});
