// De dónde llegó la visita (para medir qué canal trae ventas). Sin cookies de terceros ni servicios externos:
// se guarda solo en este navegador por 30 días y se usa para prellenar "¿Cómo nos conoció?" en /reservar.
// Detecta: ?utm_source= o ?ref= (enlaces de anuncios y redes), ttclid (TikTok Ads), fbclid (Facebook/Instagram),
// gclid (Google Ads) y la página de la que viene (Google, Instagram, Facebook, TikTok, LinkedIn).
(() => {
  const CLAVE = "fk_origen", DIAS = 30, VALIDOS = ["google", "instagram", "facebook", "tiktok", "linkedin"];
  const leer = () => { try { const o = JSON.parse(localStorage.getItem(CLAVE)); return o && Date.now() - o.t < DIAS * 864e5 ? o.v : null; } catch (_) { return null; } };
  const guardar = v => { try { localStorage.setItem(CLAVE, JSON.stringify({ v, t: Date.now() })); } catch (_) {} };
  const normal = s => { s = String(s || "").toLowerCase(); return VALIDOS.find(x => s.includes(x)) || (s.includes("ig") ? "instagram" : s.includes("fb") || s.includes("meta") ? "facebook" : null); };
  try {
    const q = new URLSearchParams(location.search);
    let v = normal(q.get("utm_source") || q.get("ref"));
    if (!v && q.get("ttclid")) v = "tiktok";
    if (!v && q.get("gclid")) v = "google";
    if (!v && q.get("fbclid")) v = /instagram/i.test(document.referrer) ? "instagram" : "facebook";
    if (!v && document.referrer && !document.referrer.includes(location.hostname)) v = normal(new URL(document.referrer).hostname);
    if (v) guardar(v); // la visita más reciente manda
  } catch (_) {}
  window.FKOrigen = { get: leer };
})();
