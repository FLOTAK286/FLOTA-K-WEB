// Carga masiva de reservas desde Excel (panel /equipo y portal /empresa).
// 1) Plantilla para descargar. 2) El usuario sube el archivo. 3) Se revisa cada fila (fecha, hora, dirección con su punto en
// el mapa, tipo de servicio) y se muestra la vista previa con los errores. 4) Se crean las reservas válidas.
// Necesita: XLSX (SheetJS), window.FK_TARIFAS (assets/tarifas.js) y FK (assets/app.js).
(function () {
  const COLS = ["Fecha", "Hora", "Tipo", "Pasajero", "Teléfono", "Dirección", "Destino (solo punto a punto)", "Vuelo", "Pasajeros", "Maletas", "Vehículo", "Centro de costo", "Comentarios"];
  const EJ = [["25-11-2026", "06:30", "Ida", "María Pérez", "+56 9 1234 5678", "Av. Apoquindo 3000, Las Condes", "", "LA 330", 1, 2, "Auto", "Gerencia", ""],
              ["25-11-2026", "21:15", "Regreso", "Juan Soto", "+56 9 8765 4321", "Av. Providencia 1208, Providencia", "", "LA 800", 2, 3, "Auto", "Operaciones", "Llamar al aterrizar"],
              ["26-11-2026", "09:00", "Punto a punto", "Ana Rojas", "+56 9 5555 1111", "Av. Vitacura 2939, Las Condes", "Clínica Alemana, Vitacura", "", 1, 0, "Auto", "", ""]];
  const AERO = { texto: "Aeropuerto Internacional de Santiago (SCL), Pudahuel", lat: -33.39297, lng: -70.78579 };
  const norm = s => String(s ?? "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").trim();
  const esc = s => String(s ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const clp = n => n == null ? "por confirmar" : "$" + Math.round(n).toLocaleString("es-CL");
  const pad = n => String(n).padStart(2, "0");

  function plantilla(nombre) {
    if (!window.XLSX) return alert("No se pudo cargar el generador de planillas. Revise su conexión.");
    const ws = XLSX.utils.aoa_to_sheet([COLS, ...EJ]);
    ws["!cols"] = COLS.map((c, i) => ({ wch: [12, 7, 14, 20, 16, 38, 30, 9, 9, 8, 9, 16, 26][i] }));
    const ay = XLSX.utils.aoa_to_sheet([["Cómo llenar la plantilla"], [],
      ["Fecha", "Día-mes-año, por ejemplo 25-11-2026."], ["Hora", "Hora de Chile, 24 horas, por ejemplo 06:30 o 21:15. En Regreso, la hora de aterrizaje del vuelo."],
      ["Tipo", "Ida (al aeropuerto), Regreso (desde el aeropuerto) o Punto a punto."],
      ["Dirección", "Ida: dónde lo retiramos. Regreso: dónde lo dejamos. Punto a punto: el origen. Calle, número y comuna."],
      ["Destino", "Solo en punto a punto."], ["Vehículo", "Auto, SUV o Van (si lo deja vacío: Auto)."],
      ["Las filas de ejemplo", "Bórrelas antes de subir el archivo."]]);
    const wb = XLSX.utils.book_new(); XLSX.utils.book_append_sheet(wb, ws, "Reservas"); XLSX.utils.book_append_sheet(wb, ay, "Instrucciones");
    XLSX.writeFile(wb, nombre || "Flota-K_plantilla_reservas.xlsx");
  }

  // Fecha y hora (de texto o de celdas de Excel) → "AAAA-MM-DDTHH:MM" en hora de Chile
  function fechaHora(f, h) {
    let d = null, t = null;
    if (f instanceof Date) d = `${f.getFullYear()}-${pad(f.getMonth() + 1)}-${pad(f.getDate())}`;
    else if (typeof f === "number") { const x = new Date(Math.round((f - 25569) * 864e5)); d = `${x.getUTCFullYear()}-${pad(x.getUTCMonth() + 1)}-${pad(x.getUTCDate())}`; }
    else { const m = String(f || "").trim().match(/^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})$/) || null, m2 = String(f || "").trim().match(/^(\d{4})-(\d{1,2})-(\d{1,2})$/);
      if (m) d = `${m[3].length === 2 ? "20" + m[3] : m[3]}-${pad(m[2])}-${pad(m[1])}`; else if (m2) d = `${m2[1]}-${pad(m2[2])}-${pad(m2[3])}`; }
    if (h instanceof Date) t = `${pad(h.getHours())}:${pad(h.getMinutes())}`;
    else if (typeof h === "number") { const mins = Math.round((h % 1) * 1440); t = `${pad(Math.floor(mins / 60))}:${pad(mins % 60)}`; }
    else { const m = String(h || "").trim().match(/^(\d{1,2})[:.h](\d{2})/); if (m && +m[1] < 24 && +m[2] < 60) t = `${pad(m[1])}:${m[2]}`; }
    return d && t ? `${d}T${t}` : null;
  }
  const tipoDe = s => { const x = norm(s); return !x ? null : x.includes("reg") || x.includes("llega") ? "regreso" : x.includes("punto") || x.includes("p2p") || x.includes("traslado") ? "punto_a_punto" : x.includes("ida") || x.includes("aerop") ? "ida" : null; };
  const vehDe = s => { const x = norm(s); return x.includes("van") ? "van" : x.includes("suv") ? "suv" : "auto"; };

  const cacheGeo = new Map();
  async function geocodificar(dir) {
    const k = norm(dir); if (cacheGeo.has(k)) return cacheGeo.get(k);
    if (/aeropuerto|\bscl\b|arturo merino/.test(k)) return { lat: AERO.lat, lng: AERO.lng, comunas: ["pudahuel"], texto: AERO.texto };
    let res = null;
    try {
      const r = await fetch(`https://photon.komoot.io/api/?q=${encodeURIComponent(dir + ", Chile")}&limit=1&lat=-33.45&lon=-70.66&bbox=-71.8,-34.3,-69.8,-32.8`);
      const f = ((await r.json()).features || [])[0];
      if (f) { const p = f.properties; res = { lat: f.geometry.coordinates[1], lng: f.geometry.coordinates[0], comunas: [p.city, p.district, p.locality, p.county].filter(Boolean).map(norm) }; }
    } catch (_) {}
    cacheGeo.set(k, res); return res;
  }
  // Tarifa fija al aeropuerto según la comuna (solo si hay un único sector para esa comuna en el tarifario)
  function tarifaAero(comunas, tipo, veh) {
    const T = window.FK_TARIFAS || [];
    for (const c of comunas || []) {
      const filas = T.filter(r => norm(r[0]) === c || norm(r[0]).startsWith(c + " "));
      if (filas.length === 1) { const r = filas[0]; return { valor: veh === "van" ? r[3] : tipo === "regreso" ? r[2] : r[1], sector: r[0] }; }
      if (filas.length > 1) return { valor: null, sector: null, varios: true };
    }
    return { valor: null, sector: null };
  }

  async function leerArchivo(file) {
    const buf = await file.arrayBuffer();
    const wb = XLSX.read(buf, { type: "array", cellDates: true });
    const ws = wb.Sheets[wb.SheetNames[0]];
    const filas = XLSX.utils.sheet_to_json(ws, { header: 1, raw: true, defval: "" });
    const enc = (filas[0] || []).map(norm), col = nom => enc.findIndex(x => x.startsWith(norm(nom)));
    const ix = { f: col("fecha"), h: col("hora"), t: col("tipo"), p: col("pasajero"), tel: col("tel"), dir: col("direc"), dest: col("destino"), v: col("vuelo"), pax: col("pasajeros"), mal: col("maletas"), veh: col("veh"), cc: col("centro"), com: col("coment") };
    return filas.slice(1).map((r, i) => ({ n: i + 2, r, ix })).filter(x => x.r.some(c => String(c).trim() !== ""));
  }

  async function revisar(lista, avance) {
    const out = [];
    for (const { n, r, ix } of lista) {
      const g = k => ix[k] >= 0 ? r[ix[k]] : "";
      const e = [], fh = fechaHora(g("f"), g("h")), tipo = tipoDe(g("t")), veh = vehDe(g("veh"));
      const pas = String(g("p")).trim(), tel = String(g("tel")).trim(), dir = String(g("dir")).trim(), dest = String(g("dest")).trim();
      if (!fh) e.push("revise la fecha y la hora"); else if (new Date(FK.chileLocalToISO(fh)) < new Date(Date.now() + 30 * 60000)) e.push("la fecha ya pasó o es muy próxima");
      if (!tipo) e.push("el tipo debe ser Ida, Regreso o Punto a punto");
      if (!pas) e.push("falta el pasajero");
      if (!dir) e.push("falta la dirección");
      if (tipo === "punto_a_punto" && !dest) e.push("falta el destino del punto a punto");
      let o = null, d = null, tar = { valor: null };
      if (dir) { avance && avance(`Buscando la dirección de la fila ${n}…`); o = await geocodificar(dir); if (!o) e.push(`no encontramos "${dir}"`); }
      if (tipo === "punto_a_punto" && dest) { d = await geocodificar(dest); if (!d) e.push(`no encontramos "${dest}"`); }
      if (tipo === "ida" || tipo === "regreso") { d = { lat: AERO.lat, lng: AERO.lng }; if (o) tar = tarifaAero(o.comunas, tipo, veh); }
      const ida = tipo !== "regreso";
      out.push({ n, ok: !e.length, errores: e, fh, tipo, veh, pasajero: pas, telefono: tel,
        origen: tipo === "regreso" ? AERO.texto : dir, destino: tipo === "regreso" ? dir : tipo === "ida" ? AERO.texto : dest,
        o_lat: ida ? o && o.lat : AERO.lat, o_lng: ida ? o && o.lng : AERO.lng, d_lat: ida ? d && d.lat : o && o.lat, d_lng: ida ? d && d.lng : o && o.lng,
        vuelo: String(g("v")).trim() || null, pax: Number(g("pax")) || 1, maletas: g("mal") === "" ? null : Number(g("mal")) || 0,
        cc: String(g("cc")).trim() || null, com: String(g("com")).trim() || null, tarifa: tar.valor, sector: tar.sector, comuna: o && o.comunas && o.comunas[0] });
    }
    return out;
  }

  // opts: { titulo, nota, crear: async fila => { error }, extraHtml, alListo }
  function montar(box, opts) {
    box.innerHTML = `<details class="carga-xl"><summary><b>📥 ${esc(opts.titulo || "Cargar varias reservas desde Excel")}</b></summary>
      <div style="display:grid;gap:8px;margin-top:8px">
        <p class="small muted" style="margin:0">${opts.nota || "Descargue la plantilla, llénela (una reserva por fila) y súbala. Revisamos cada fila antes de crear las reservas."}</p>
        <div class="actions"><button class="btn ghost sm" type="button" data-c="plantilla">⬇ Descargar plantilla</button>
          <label class="btn ghost sm" style="cursor:pointer">📤 Subir Excel<input type="file" accept=".xlsx,.xls,.csv" data-c="archivo" hidden></label></div>
        ${opts.extraHtml || ""}
        <div data-c="estado" class="small muted"></div>
        <div data-c="vista"></div>
      </div></details>`;
    const q = s => box.querySelector(`[data-c="${s}"]`);
    let filas = [];
    q("plantilla").onclick = () => plantilla();
    q("archivo").onchange = async ev => {
      const f = ev.target.files[0]; ev.target.value = ""; if (!f) return;
      if (!window.XLSX) return (q("estado").textContent = "No se pudo cargar el lector de planillas. Revise su conexión.");
      q("vista").innerHTML = ""; q("estado").textContent = "Leyendo el archivo…";
      try {
        const lista = await leerArchivo(f);
        if (!lista.length) return (q("estado").textContent = "El archivo no tiene filas con datos.");
        if (lista.length > 200) return (q("estado").textContent = "Máximo 200 reservas por archivo. Divídalo en varios.");
        filas = await revisar(lista, t => q("estado").textContent = t);
      } catch (e) { return (q("estado").textContent = "No pudimos leer el archivo: " + (e.message || e)); }
      pintar();
    };
    function pintar() {
      const okN = filas.filter(x => x.ok).length;
      const dia = fh => fh ? fh.replace("T", " ").replace(/^(\d{4})-(\d\d)-(\d\d)/, "$3-$2-$1") : "—";
      const TIPO = { ida: "Ida", regreso: "Regreso", punto_a_punto: "Punto a punto" };
      q("estado").innerHTML = `<b>${okN} de ${filas.length} fila(s) listas.</b> ${filas.length - okN ? "Corrija las filas con error en el Excel y súbalo de nuevo, o cree solo las que están bien." : ""}`;
      q("vista").innerHTML = `<div class="tblwrap"><table class="tbl"><thead><tr><th>Fila</th><th>Fecha</th><th>Tipo</th><th>Pasajero</th><th>Trayecto</th><th>Valor</th><th>Estado</th></tr></thead><tbody>
        ${filas.map(x => `<tr${x.ok ? "" : ' style="background:rgba(229,83,61,.12)"'}><td>${x.n}</td><td class="nowrap">${esc(dia(x.fh))}</td><td>${esc(TIPO[x.tipo] || "—")}${x.veh !== "auto" ? " · " + esc(x.veh.toUpperCase()) : ""}</td>
          <td>${esc(x.pasajero)}${x.telefono ? `<br><span class="small muted">${esc(x.telefono)}</span>` : ""}</td><td class="small">${esc(x.origen)} → ${esc(x.destino)}</td>
          <td>${x.tarifa != null ? esc(clp(x.tarifa)) : '<span class="small muted">por confirmar</span>'}</td>
          <td>${x.ok ? (x.creada ? "✅ Creada" : x.fallo ? `<span style="color:#e5533d">${esc(x.fallo)}</span>` : "Lista") : `<span style="color:#e5533d">${esc(x.errores.join("; "))}</span>`}</td></tr>`).join("")}</tbody></table></div>
        ${okN ? `<div class="actions" style="margin-top:6px"><button class="btn sm" type="button" data-c="crear">Crear ${okN} reserva(s)</button></div>` : ""}`;
      if (q("crear")) q("crear").onclick = crear;
    }
    async function crear() {
      const b = q("crear"); b.disabled = true;
      let hechas = 0;
      for (const x of filas.filter(x => x.ok && !x.creada)) {
        q("estado").textContent = `Creando la reserva de la fila ${x.n}…`;
        const { error } = await opts.crear(x);
        if (error) x.fallo = FK.errText ? FK.errText(error) : String(error.message || error); else { x.creada = true; x.fallo = null; hechas++; }
      }
      pintar(); q("estado").innerHTML = `<b>${hechas} reserva(s) creadas.</b> ${filas.some(x => x.fallo) ? "Revise las que muestran error." : ""}`;
      if (opts.alListo) opts.alListo(hechas);
    }
  }
  window.FKCarga = { montar, plantilla };
})();
