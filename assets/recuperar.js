// Recuperar contraseña por correo (equipo, conductor, propietario y portal de empresas).
// Seguridad:
//  - El enlace llega SOLO al correo dueño de la cuenta: quien lo pide sin acceso a ese correo no puede cambiar nada.
//  - La respuesta es siempre la misma, exista o no la cuenta (no se revela quién tiene cuenta).
//  - Las cuentas con usuario corto (@usuarios.fk-servicios.com) no tienen correo real: su clave la da el administrador o el encargado.
//  - Nunca crea cuentas nuevas (resetPasswordForEmail no registra a nadie).
//  - Al guardar la contraseña nueva se cierran las sesiones abiertas en otros dispositivos.
(function () {
  const sb = FK.sb;
  const esc = FK.esc;

  // Pedir el enlace. campo: el input "Correo o usuario". avisar(texto, tipo) muestra el mensaje en la pantalla.
  async function enviar(valor, avisar, volverA) {
    const correo = FK.usuarioACorreo(valor);
    if (!/.+@.+\..+/.test(correo)) return avisar("Escriba arriba su correo y vuelva a tocar \"¿Olvidó su contraseña?\".", "err");
    if (correo.endsWith("@" + FK.DOMINIO_USUARIOS))
      return avisar("Su cuenta es con usuario y no tiene correo para recibir el enlace. Pídale una contraseña provisoria al administrador de Flota-K o al encargado de convenio de su empresa.", "err");
    avisar("Enviando…");
    const { error } = await sb.auth.resetPasswordForEmail(correo, { redirectTo: volverA || (location.origin + location.pathname) });
    if (error && /rate limit|only request this after|too many/i.test(error.message || ""))
      return avisar("Ya pedimos un enlace hace muy poco. Espere un minuto, revise su correo (también spam) y vuelva a intentar si no llegó.", "err");
    // Misma respuesta exista o no la cuenta
    avisar("Si ese correo tiene una cuenta en Flota-K, le enviamos un enlace para crear una contraseña nueva. Revise su bandeja de entrada y la carpeta de spam, y ábralo una sola vez. El enlace vence en poco tiempo.", "ok");
  }

  // Ventana para crear la contraseña nueva (aparece sola al volver desde el enlace del correo)
  let abierta = false;
  function pedirClaveNueva(alListo) {
    if (abierta) return; abierta = true;
    const d = document.createElement("dialog");
    d.className = "panel";
    d.style.cssText = "max-width:420px;width:calc(100% - 32px);border:1px solid var(--gold);color:var(--fg);background:var(--panel);padding:20px";
    d.innerHTML = `<h2 style="margin:0 0 6px">Cree su contraseña nueva</h2>
      <p class="small muted" style="margin:0 0 10px">Entró con el enlace de su correo. Escriba una contraseña nueva: al guardarla se cerrará la sesión en sus otros teléfonos o computadores.</p>
      <form class="f" novalidate>
        <label for="rc-1">Nueva contraseña (mínimo 8 caracteres)</label><input id="rc-1" type="password" autocomplete="new-password" minlength="8">
        <label for="rc-2" style="margin-top:6px">Repítala</label><input id="rc-2" type="password" autocomplete="new-password" minlength="8">
        <label class="chk small" style="margin-top:6px"><input type="checkbox" id="rc-ver"> Mostrar lo que escribo</label>
        <div class="actions" style="margin-top:10px"><button class="btn" type="submit">Guardar contraseña</button></div>
        <div class="msg" id="rc-msg" hidden></div>
      </form>`;
    document.body.appendChild(d);
    d.addEventListener("cancel", e => e.preventDefault()); // no se cierra con "atrás" hasta guardar
    const m = (t, k) => { const x = d.querySelector("#rc-msg"); x.hidden = !t; x.className = "msg " + (k || ""); x.textContent = t || ""; };
    d.querySelector("#rc-ver").onchange = e => d.querySelectorAll("input[type=password],input[data-pw]").forEach(i => { i.dataset.pw = 1; i.type = e.target.checked ? "text" : "password"; });
    d.querySelector("form").addEventListener("submit", async e => {
      e.preventDefault();
      const a = d.querySelector("#rc-1").value, b = d.querySelector("#rc-2").value;
      if (a.length < 8) return m("La contraseña debe tener al menos 8 caracteres.", "err");
      if (!/[A-Za-z]/.test(a) || !/\d/.test(a)) return m("Use letras y números para que sea más segura.", "err");
      if (a !== b) return m("Las dos contraseñas no coinciden.", "err");
      m("Guardando…");
      const { error } = await sb.auth.updateUser({ password: a });
      if (error) return m(FK.errText(error), "err");
      try { await sb.auth.signOut({ scope: "others" }); } catch (_) {}
      try { await sb.rpc("convenio_clave_cambiada"); } catch (_) {}
      try { history.replaceState(null, "", location.pathname); } catch (_) {}
      m("✅ Contraseña guardada. Desde ahora entre con su correo y esta contraseña.", "ok");
      setTimeout(() => { d.close(); abierta = false; if (alListo) alListo(); else location.reload(); }, 1200);
    });
    d.showModal();
  }

  // ¿Se entró con un enlace del correo? (lo detecta app.js antes de que Supabase limpie la dirección)
  function auto(alListo) {
    const tipo = FK.enlaceTipo;
    let hecho = false;
    const lanzar = () => { if (!hecho) { hecho = true; pedirClaveNueva(alListo); } };
    sb.auth.onAuthStateChange((ev, s) => { if (ev === "PASSWORD_RECOVERY" || (s && tipo)) lanzar(); });
    if (tipo) sb.auth.getSession().then(({ data }) => { if (data.session) lanzar(); });
  }

  window.FKRecuperar = { enviar, pedirClaveNueva, auto };
})();
