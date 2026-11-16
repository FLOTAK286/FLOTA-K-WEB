// Espera en servicios punto a punto (enlace del pasajero, app del pasajero y app del conductor).
// Regla: 15 min sin costo desde la hora agendada. Después, $180 por minuto en auto y $270 en SUV o van.
// Solo corre mientras el conductor está en el lugar (desde que marca "llegué" hasta que el pasajero sube).
// El cálculo oficial lo hace la base de datos (espera_calculo); aquí solo se muestra el contador.
(function () {
  const clp = n => "$" + Math.round(n || 0).toLocaleString("es-CL");
  const hhmm = d => new Date(d).toLocaleTimeString("es-CL", { hour: "2-digit", minute: "2-digit", timeZone: "America/Santiago" });
  const reloj = s => {
    s = Math.max(0, Math.floor(s));
    const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), x = s % 60;
    return (h ? h + ":" + String(m).padStart(2, "0") : String(m).padStart(2, "0")) + ":" + String(x).padStart(2, "0");
  };
  // Diferencia entre el reloj del servidor y el del teléfono, para que el contador no dependa de la hora del celular
  const desfase = e => (e && e.ahora ? new Date(e.ahora).getTime() - Date.now() : 0);

  function calcular(e, dif) {
    const ahora = Date.now() + (dif || 0);
    const fin = e.a_bordo_en ? new Date(e.a_bordo_en).getTime() : ahora;
    const llegada = new Date(e.llegada_en).getTime(), desde = new Date(e.cobro_desde).getTime();
    const minutos = Math.max(0, Math.floor((fin - desde) / 60000));
    return {
      esperando: (fin - llegada) / 1000,
      enGracia: fin < desde,
      faltaGracia: (desde - fin) / 1000,
      minutos, monto: minutos * e.tarifa_min,
      siguiente: 60 - Math.floor(((fin - desde) / 1000) % 60),
      terminado: !!e.a_bordo_en
    };
  }

  // para: "pasajero" o "conductor". estado: estado de la reserva.
  function html(e, dif, para, estado) {
    if (!e || !e.aplica || estado === "cancelada") return "";
    const pas = para === "pasajero";
    // Antes de que llegue el conductor: se informa la regla
    if (!e.llegada_en) {
      if (["finalizada", "a_bordo"].includes(estado)) return "";
      return `<div class="espera-info small">⏱ ${pas ? "Su servicio incluye" : "Incluye"} <b>15 min de espera sin costo</b> desde la hora agendada (hasta las ${esc(hhmm(e.gracia_hasta))}). Después: <b>${clp(e.tarifa_min)} por minuto</b>.</div>`;
    }
    const s = calcular(e, dif);
    if (s.terminado) {
      return s.monto > 0
        ? `<div class="espera-box cobra"><b>Espera cobrada: ${clp(s.monto)}</b><span class="small">${s.minutos} min × ${clp(e.tarifa_min)} (desde las ${esc(hhmm(e.cobro_desde))})</span></div>`
        : `<div class="espera-box"><b>Espera sin costo</b><span class="small">${pas ? "Subió" : "El pasajero subió"} dentro del tiempo incluido.</span></div>`;
    }
    const t = `<span class="espera-reloj">${reloj(s.esperando)}</span>`;
    if (s.enGracia) {
      return `<div class="espera-box">
        <b>⏱ ${pas ? "Su conductor lo espera hace" : "Esperando hace"} ${t}</b>
        <span class="small">${pas ? "Llegó" : "Llegó"} a las ${esc(hhmm(e.llegada_en))}. Sin costo hasta las ${esc(hhmm(e.cobro_desde))} (quedan ${reloj(s.faltaGracia)}). Después: ${clp(e.tarifa_min)} por minuto.</span></div>`;
    }
    return `<div class="espera-box cobra">
      <b>⏱ ${pas ? "Lo esperamos hace" : "Esperando hace"} ${t}</b>
      <span class="espera-monto">${pas ? "Cobro de espera" : "Cobrando espera"}: <b>${clp(s.monto)}</b></span>
      <span class="small">${s.minutos} min × ${clp(e.tarifa_min)} desde las ${esc(hhmm(e.cobro_desde))} · suma ${clp(e.tarifa_min)} más en ${reloj(s.siguiente)}</span></div>`;
  }
  const esc = s => String(s ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

  window.FKEspera = { html, calcular, desfase, clp, hhmm, reloj };
})();
