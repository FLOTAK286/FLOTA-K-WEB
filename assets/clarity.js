// Microsoft Clarity (gratis): grabaciones anónimas y mapas de calor para ver dónde se pierde la gente en /reservar.
// Solo se activa si en assets/config.js está el ID del proyecto (FK_CONFIG.clarity; el ID es público).
// Los campos con datos personales van ocultos (data-clarity-mask en el formulario de /reservar),
// y en el panel de Clarity se debe dejar "Masking" en modo "Strict".
(() => {
  const id = (window.FK_CONFIG && window.FK_CONFIG.clarity) || "";
  if (!/^[a-z0-9]{6,20}$/i.test(id) || /^(localhost|127\.)/.test(location.hostname)) return;
  (function (c, l, a, r, i, t, y) {
    c[a] = c[a] || function () { (c[a].q = c[a].q || []).push(arguments); };
    t = l.createElement(r); t.async = 1; t.src = "https://www.clarity.ms/tag/" + i;
    y = l.getElementsByTagName(r)[0]; y.parentNode.insertBefore(t, y);
  })(window, document, "clarity", "script", id);
})();
