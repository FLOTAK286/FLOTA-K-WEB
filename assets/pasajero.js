// Viajes del pasajero guardados en este teléfono (sin cuenta ni contraseña).
// Cada viaje se guarda con su enlace de seguimiento; lo usan la app del pasajero (/app) y /seguimiento.
(function () {
  const K = "fk_viajes";
  const lista = () => { try { const v = JSON.parse(localStorage.getItem(K)); return Array.isArray(v) ? v : []; } catch (_) { return []; } };
  const escribir = v => { try { localStorage.setItem(K, JSON.stringify(v.slice(0, 60))); } catch (_) {} };
  const okToken = t => /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(t || "");
  function agregar(t, c) {
    if (!okToken(t)) return;
    const v = lista().filter(x => x.t !== t);
    v.unshift({ t, c: c || "", en: Date.now() });
    escribir(v);
  }
  // Deja solo los enlaces que siguen existiendo
  function dejar(tokens) { if (!tokens) return; const s = new Set(tokens); escribir(lista().filter(x => s.has(x.t))); }
  window.FKPasajero = { lista, agregar, dejar };
})();
