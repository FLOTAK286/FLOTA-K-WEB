// Mensajes por servicio y estrellas de calificación. Lo usan /seguimiento, /conductor y /equipo.
window.FKChat = {
  NOMBRES: { pasajero: "Pasajero", conductor: "Conductor", despacho: "Flota-K" },
  // msgs: [{ autor, texto, creado_en }]; yo: autor propio ("pasajero" | "conductor" | "despacho")
  burbujas(msgs, yo) {
    const e = FK.esc, h = iso => new Date(iso).toLocaleTimeString("es-CL", { timeZone: "America/Santiago", hour: "2-digit", minute: "2-digit" });
    if (!msgs.length) return '<p class="muted small" style="margin:0">Aún no hay mensajes.</p>';
    return msgs.map(m => `<div class="burbuja ${m.autor === yo ? "yo" : "otro"} ${m.autor === "despacho" ? "desp" : ""}"><small>${e(m.autor === yo ? "Usted" : FKChat.NOMBRES[m.autor])} · ${h(m.creado_en)}</small>${e(m.texto)}</div>`).join("");
  },
  // Dibuja el chat en el elemento y devuelve funciones para actualizarlo.
  montar(el, { yo, enviar, abierto = true, placeholder = "Escriba un mensaje…", rapidos = [] }) {
    el.innerHTML = `<div class="chat"><div class="chat-msgs" aria-live="polite"></div>
      ${abierto && rapidos.length ? `<div class="rapidos">${rapidos.map(t => `<button type="button" class="chip">${FK.esc(t)}</button>`).join("")}</div>` : ""}
      ${abierto ? `<form class="chat-form"><input maxlength="500" placeholder="${FK.esc(placeholder)}" aria-label="Mensaje"><button class="btn sm" type="submit">Enviar</button></form>` : '<p class="muted small" style="margin:0">El chat de este servicio está cerrado.</p>'}
      <p class="msg err" hidden></p></div>`;
    const lista = el.querySelector(".chat-msgs"), form = el.querySelector("form"), err = el.querySelector(".msg");
    let ultimo = "";
    const pintar = msgs => {
      const firma = msgs.map(m => m.id).join(",");
      if (firma === ultimo) return; ultimo = firma;
      const abajo = lista.scrollTop + lista.clientHeight >= lista.scrollHeight - 30;
      lista.innerHTML = FKChat.burbujas(msgs, yo);
      if (abajo || msgs.length && msgs[msgs.length - 1].autor === yo) lista.scrollTop = lista.scrollHeight;
    };
    form?.addEventListener("submit", async ev => {
      ev.preventDefault();
      const inp = form.querySelector("input"), t = inp.value.trim(); if (!t) return;
      form.querySelector("button").disabled = true; err.hidden = true;
      const r = await enviar(t);
      form.querySelector("button").disabled = false;
      if (r && r.error) { err.hidden = false; err.textContent = FK.errText(r.error); return; }
      inp.value = ""; inp.focus();
    });
    el.querySelectorAll(".rapidos .chip").forEach(b => b.addEventListener("click", async () => {
      b.disabled = true; const r = await enviar(b.textContent); b.disabled = false;
      if (r && r.error) { err.hidden = false; err.textContent = FK.errText(r.error); }
    }));
    return { pintar };
  },
  // Estrellas 1 a 5. onElegir(n) se llama al tocar una.
  estrellas(el, onElegir, valor = 0) {
    const dibujar = v => {
      el.innerHTML = '<span class="estrellas" role="radiogroup" aria-label="Calificación">' + [1, 2, 3, 4, 5].map(n =>
        `<button type="button" role="radio" aria-checked="${n === v}" aria-label="${n} estrella${n > 1 ? "s" : ""}" class="${n <= v ? "on" : ""}" data-n="${n}">★</button>`).join("") + "</span>";
      el.querySelectorAll("button").forEach(b => b.addEventListener("click", () => { dibujar(+b.dataset.n); onElegir(+b.dataset.n); }));
    };
    dibujar(valor);
  },
  fijas(n) { return '<span class="estrellas fijas" aria-label="' + n + ' de 5 estrellas">' + "★★★★★".slice(0, n) + '<span class="off">' + "★★★★★".slice(n) + "</span></span>"; }
};
