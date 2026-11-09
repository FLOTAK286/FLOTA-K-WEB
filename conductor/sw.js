// La app instalada desde Chrome quedó reemplazada por la app Android. Este archivo se elimina a sí mismo.
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", e => e.waitUntil(self.registration.unregister()));
