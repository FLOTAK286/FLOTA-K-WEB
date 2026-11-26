// Pagos pendientes del cliente (etapa 76): lista de servicios realizados sin pagar, el cliente elige cuáles y paga con
// tarjeta en Flow (Edge Function "flow-deuda"). Lo usan el portal de empresas (/empresa) y la app (/app).
// La base valida todo (mis_pendientes, deuda_crear_solicitud): aquí solo se muestra y se envía la selección.
(() => {
  const clp = n => "$" + Math.round(Number(n) || 0).toLocaleString("es-CL");
  const esc = s => String(s ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const fecha = iso => new Date(iso).toLocaleString("es-CL", { timeZone: "America/Santiago", weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });
  const FN = () => window.FK_CONFIG.url + "/functions/v1/flow-deuda";

  function montar(el, op) {
    const sb = op.sb, volver = op.volver === "app" ? "app" : "empresa";
    let info = null, elegidos = new Set();

    // Al volver de Flow (?pago=<id>): se muestra el resultado y se limpia la dirección
    const pagoId = new URLSearchParams(location.search).get("pago");
    let aviso = "";
    async function revisarRegreso() {
      if (!pagoId || !/^[0-9a-f-]{36}$/.test(pagoId)) return;
      try { const u = new URL(location.href); u.searchParams.delete("pago"); history.replaceState(null, "", u); } catch (_) {}
      aviso = '<p class="msg">⏳ Revisando su pago…</p>'; pintar();
      for (let i = 0; i < 6; i++) {
        let s = null; try { s = await (await fetch(FN() + "?accion=estado&id=" + pagoId)).json(); } catch (_) {}
        if (s && s.estado === "pagada") { aviso = `<p class="msg ok">✅ <b>Pago recibido.</b> ${s.codigos && s.codigos.length ? "Quedaron pagados: " + esc(s.codigos.join(", ")) + "." : ""} Le llega el comprobante de Flow a su correo.</p>`; break; }
        if (s && ["rechazada", "error", "vencida"].includes(s.estado)) { aviso = '<p class="msg err">✖ El pago no se completó. No se le cobró. Puede intentarlo de nuevo.</p>'; break; }
        aviso = '<p class="msg">⏳ Su pago se está procesando. Si ya pagó, en unos minutos aparecerá como pagado.</p>';
        await new Promise(r => setTimeout(r, 2500));
      }
      await cargar();
    }

    async function cargar() {
      const { data, error } = await sb.rpc("mis_pendientes", {});
      if (error) { el.hidden = false; el.innerHTML = `<p class="msg err">${esc(error.message)}</p>`; return null; }
      info = data;
      elegidos = new Set([...elegidos].filter(id => (info?.viajes || []).some(v => v.id === id && !v.en_pago)));
      pintar();
      if (op.alCargar) op.alCargar(info);
      return info;
    }

    function pintar() {
      if (!info) { el.hidden = !aviso; el.innerHTML = aviso; return; }
      const vs = info.viajes || [], deuda = info.deuda || 0;
      el.hidden = false;
      const credito = info.credito && info.limite != null
        ? `<div class="small">💳 Su cuenta tiene crédito hasta <b>${clp(info.limite)}</b> · pendiente de pago: <b>${clp(deuda)}</b>${info.limite > 0 ? ` (${Math.min(999, Math.round(deuda / info.limite * 100))} % del límite)` : ""}</div>` : "";
      const bloqueo = info.bloqueado ? `<p class="msg err" style="margin:6px 0">⛔ <b>Su cuenta superó el límite de crédito.</b> Para volver a agendar, pague sus servicios pendientes aquí abajo (o escríbanos al WhatsApp +56 9 2227 5399).</p>` : "";
      if (!info.puede_pagar && info.alcance === "empresa" && !op.soloLectura) {
        el.innerHTML = aviso + `<h2 style="margin:0">💳 Pagos</h2>${credito}${bloqueo}<p class="muted small">Los servicios de su empresa los paga el encargado de convenio.</p>`;
        return;
      }
      if (!vs.length) {
        el.innerHTML = aviso + `<h2 style="margin:0">💳 Pagos</h2>${credito}<p class="muted">✅ No tiene servicios pendientes de pago.</p>`;
        return;
      }
      const sel = vs.filter(v => elegidos.has(v.id)), total = sel.reduce((s, v) => s + (v.total || 0), 0);
      const libres = vs.filter(v => !v.en_pago);
      el.innerHTML = aviso + `
        <h2 style="margin:0">💳 Pagos pendientes <span class="muted small">${vs.length} servicio${vs.length === 1 ? "" : "s"} · ${clp(deuda)}</span></h2>
        ${credito}${bloqueo}
        <p class="small muted" style="margin:4px 0">Elija los servicios que quiere pagar y pague con tarjeta de débito o crédito. Puede pagar uno, varios o todos.</p>
        ${libres.length > 1 && !op.soloLectura ? `<div class="actions" style="margin:0"><button class="linkbtn" type="button" data-todos>${sel.length === libres.length ? "Quitar todos" : "Elegir todos"}</button></div>` : ""}
        <div style="display:grid;gap:6px">${vs.map(v => `
          <label class="pay" style="display:flex;gap:10px;align-items:flex-start;cursor:${v.en_pago || op.soloLectura ? "default" : "pointer"};margin:0">
            <input type="checkbox" data-id="${esc(v.id)}" ${elegidos.has(v.id) ? "checked" : ""} ${v.en_pago || op.soloLectura ? "disabled" : ""} style="margin-top:4px;width:20px;height:20px">
            <span style="flex:1;min-width:0"><b>${clp(v.total)}</b> · <span class="small">${esc(fecha(v.fecha))}</span> · <span class="small muted">${esc(v.codigo)}</span><br>
              <span class="small">${esc(v.origen)} → ${esc(v.destino)}</span>${info.alcance === "empresa" && v.pasajero ? `<br><span class="small muted">Pasajero: ${esc(v.pasajero)}</span>` : ""}
              ${v.en_pago ? '<br><span class="small" style="color:var(--gold)">⏳ Pago en curso (si no lo terminó, vuelve a estar disponible en 35 minutos)</span>' : ""}</span>
          </label>`).join("")}</div>
        ${op.soloLectura ? '<p class="small muted">Vista previa: solo lectura.</p>' : `<div class="actions" style="align-items:center">
          <button class="btn" type="button" data-pagar ${sel.length ? "" : "disabled"}>💳 Pagar ${sel.length ? clp(total) : ""} con tarjeta</button>
          <span class="small muted">${sel.length ? `${sel.length} servicio${sel.length === 1 ? "" : "s"} elegido${sel.length === 1 ? "" : "s"}` : "Elija al menos un servicio"}</span></div>
        <p class="small muted" style="margin:0">El pago se hace en Flow, la plataforma de pagos segura. Al terminar vuelve aquí y el servicio queda pagado.</p>`}
        <div class="msg" data-msg hidden></div>`;
      el.querySelectorAll("input[data-id]").forEach(c => c.addEventListener("change", () => { c.checked ? elegidos.add(c.dataset.id) : elegidos.delete(c.dataset.id); pintar(); }));
      const t = el.querySelector("[data-todos]");
      if (t) t.onclick = () => { if (sel.length === libres.length) elegidos.clear(); else libres.forEach(v => elegidos.add(v.id)); pintar(); };
      const b = el.querySelector("[data-pagar]");
      if (b) b.onclick = () => pagar(b);
    }

    async function pagar(b) {
      const m = el.querySelector("[data-msg]"), ids = [...elegidos];
      if (!ids.length) return;
      b.disabled = true; b.textContent = "Abriendo el pago…";
      const ver = (t, k) => { m.hidden = false; m.className = "msg " + (k || ""); m.textContent = t; };
      try {
        const { data: { session } } = await sb.auth.getSession();
        if (!session) { ver("Su sesión expiró. Vuelva a entrar.", "err"); b.disabled = false; return; }
        const r = await fetch(FN() + "?accion=pagar", { method: "POST",
          headers: { "Content-Type": "application/json", Authorization: "Bearer " + session.access_token, apikey: window.FK_CONFIG.anonKey },
          body: JSON.stringify({ reservas: ids, volver }) });
        const j = await r.json().catch(() => ({}));
        if (j.url) { location.href = j.url; return; }
        ver(j.error || "No pudimos abrir el pago. Intente de nuevo.", "err");
      } catch (_) { ver("No hay conexión. Revise su internet e intente de nuevo.", "err"); }
      b.disabled = false; b.textContent = "💳 Pagar con tarjeta";
    }

    revisarRegreso();
    return { cargar };
  }
  window.FKPagos = { montar };
})();
