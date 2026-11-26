# Traspaso 26 nov 2026 (chat "Sistemas y página web" que el dueño va a borrar)

Lo técnico de la plataforma está en `CLAUDE.md` y `CAMBIOS.md` (siempre al día). Aquí va lo de negocio, el equipo de agentes, lo pendiente y lo que hay que hacer ahora.

## 1. Decisiones del dueño (Juan Kieferling) que siguen vigentes
- Español de Chile simple, de usted. No es programador. Decisiones con fundamento.
- Publicar en `main` solo con "Autorizo". Migraciones con apply_migration (él aprueba la ventana; si se cierra sola, no reintentar en el mismo turno).
- Costo $0. **Sin publicidad pagada** hasta tener resultados orgánicos medibles (decisión 25-nov). Google Ads (~$45.000) quedó rechazado por ahora.
- Meta de diciembre aprobada: **25 viajes directos finalizados** (~6 por semana).
- Competencia: Cabify (se compite abiertamente), Uber, DiDi, Transvip, radiotaxis (Centro Oriente, Apoquindo, Solución). Servimóvil es partner: no nombrarlo ni captar sus clientes.
- La operación diaria la ve Juan con el cierre diario de la app desde el 1-dic: no crear agentes de operación.
- No enviar correos ni mensajes a terceros sin su confirmación (excepción: correos de PRIMER contacto de prospección del agente comercial).
- Marca: "Comprometidos con su traslado" (nunca "cumplimiento garantizado"); no dar a entender que sabemos de problemas de un prospecto; no usar logos de terceros sin permiso; nada de testimonios ni clientes inventados (tampoco con IA).

## 2. Equipo de agentes (tareas programadas, todas empiezan con "Flota-K:")
| Tarea | ID | Horario (Chile) | Ligada a |
|---|---|---|---|
| gerente general (metas y equipo) | trig_01SCLknEezypDxfxqSrZ6h94 | 9:46, 13:46, 17:46, 21:46 | sesión nueva en cada ejecución (tiene conectores) |
| gerencia comercial y marketing diaria | trig_01R68ZiyFgVZUhQ1MVSGRRdF | L-V 8:33 | sesión nueva (tiene conectores) |
| ejecutivo de cuentas y respuestas de clientes | trig_01GxsQzsjagtUGxpPXxtC8T3 | L-S 9:17, 12:17, 15:17, 18:17 | sesión nueva (tiene conectores) |
| mejora de la plataforma (viernes) | trig_01WQqYyAAtWyL4aZMYj13QQ3 | viernes 17:36 | **ESTE CHAT** → recrear (texto en el punto 6) |
| respaldo semanal a Google Drive | trig_01AYcPA7jYwiUfSLDULeAFAi | domingo 22:43 | **ESTE CHAT** → recrear (texto en el punto 6) |
| gerente general (cada hora) | trig_0167Z7qvydH6UcF8woFJEkdB | — | pausado (reemplazado por "metas y equipo") |
Pausadas a propósito: operaciones y calidad, calidad, finanzas y cobranza, ejecutivo de cuentas de empresas, ciclo semanal de marketing y copias sin conectores.
Nota técnica: las tareas "sesión nueva" creadas desde una sesión de Claude Code no reciben conectores; las de arriba sí los tienen porque se crearon bien. Si se recrea una tarea, ligarla a la conversación nueva (persist_session) o verificar que tenga conectores.

## 3. Documentos clave (Google Drive de gerencia@)
- Plan comercial y metas (dic 2026): Google Doc `12hBK8SUoZD4DdJoEAleRmIarPLm92gJxiFf77V3VqvQ`
- Bitácora del gerente (planilla): `1TfbgNudH4z0ehrF7naE8Ze3KBs1jbb8k1m__9CRaFB0`
- Tablero semanal de gerencia: `1bKEO_bsVyGW0OqrC7IdKyUJDpCbz_kPgc4jBU8kB3xY`
- Bitácora de mejora continua de marketing: `1K6rfTIb6qJQr9wxpsr9oyUVHK3o08ZH0qrmknHV6RGQ`
- **Competencia y estrategia de contenido (26-nov):** Google Doc `1Q547-bVrgnnytakWrZ31v0eKWjogIrn5B-TXNW2_faw`
- Fotos del auto real (VW Virtus azul): carpeta `164MRjHOJYIKCgr8Sd7yc5cou_YMZTnLH`; Marketing fotos y videos: `1-V5jGPgRig9p_sD97yPsZsg0rf02fJVO`; FLOTA-K IA: `1kQVG7Il-fsBBCEvMsg_BEB2IJqDJzzs4`
- Metricool brand 7177765 (plan gratis: 20 publicaciones por mes calendario).

## 4. Hecho en este chat (24–26 nov)
- Etapa 74: servicios derivados a partner con seguimiento propio. Etapa 75: derivados se finalizan sin "atrasado" (botón ✅ Finalizar) y reasignar un servicio en curso lo reinicia (espera desde la nueva llegada).
- Etapa 76: crédito de clientes con límite (bloquea agendar sobre el límite) y pago en línea de servicios pendientes (💳 Pagos en portal y app; Edge Function `flow-deuda`).
- Etapa 77: tablas del panel como tarjetas en el celular. Estilos con `?v=` para que el celular cargue lo nuevo.
- Etapa 78: saldos anteriores (cargos manuales), clientes que pagan en efectivo ("💵 Al conductor") y "Efectivo" como medio de pago (solo admin).
- Investigación de competencia y de contenido viral (doc del punto 3). Hallazgo: Cabify se anuncia como "Transporte Oficial del Aeropuerto"; Transvip/Cabify venden desde $9.000 compartido; radiotaxis sin publicidad digital. En Chile se viralizan situaciones reales del transporte y sketches conductor-pasajero; las cuentas de IA usan gancho en 3 s + pantalla dividida + "Comenta PALABRA".

## 5. Pendientes
- Juan: probar un pago real de deuda con tarjeta (monto chico) y confirmar que queda pagado.
- Juan: cargar el saldo anterior de **Enrique Mancini $40.000** (Panel → Cuentas de clientes → Crédito → "➕ Agregar saldo o cargo"; usar el registro con correo).
- Juan: crear cuenta a **Carmen Vizcarra** y marcarle "💵 Al conductor".
- Juan: aprobar la conexión de Instagram y Facebook a vidIQ (los enlaces de este chat pueden vencer: generar nuevos con vidiq_social_account_connect, plataforma INSTAGRAM y FACEBOOK_PAGES). vidIQ: 105 créditos, se renuevan el 5-dic.
- Extremo Norte (Francisco Leyton): se les preguntó su disponibilidad para reunión el 25-nov; esperar respuesta.
- Revisar a mano los anunciantes chicos dudosos del doc de competencia.
- TinyFish: quedan ~US$3,60; Juan pidió gastarlos en investigación útil (no se recarga).

## 6. Instrucciones de las 2 tareas que hay que recrear
### "Flota-K: mejora de la plataforma (viernes)" — viernes 17:36 Chile (cron `CRON_TZ=America/Santiago 36 17 * * 5`)
Tarea programada del equipo de agentes de Flota-K (pedido del dueño, 25 nov 2026): actúa como responsable de MEJORA DE LA PLATAFORMA (fk-servicios.com, apps de pasajero, conductor y empresas, panel; repositorio de este directorio; Supabase proyecto iejhmplstveockkjjbks). Tu área es que la plataforma funcione sin errores y venda más. Español de Chile simple, de usted.
REGLAS: sigue el CLAUDE.md del repositorio. NUNCA publiques en main ni apliques cambios a la base de datos ni a las Edge Functions: trabajas en una rama nueva (mejora-AAAA-MM-DD) y Juan autoriza publicar. Supabase solo SELECT y lectura de logs. Costo $0. Tu único correo es a gerencia@fk-servicios.com.
1. Revisa la semana: logs de Supabase (errores de API, Postgres y de las Edge Functions "flow" y "flow-deuda"), solicitudes_pago con estado 'error' o 'rechazada' y su motivo, consejos de seguridad y rendimiento (get_advisors) y el estado de los despliegues de GitHub Pages.
2. Embudo de venta en línea: solicitudes de pago creadas frente a pagadas, dónde se pierde la gente y qué canales traen ventas (reservas.como_nos_conocio; assets/origen.js).
3. Haz como máximo 2 mejoras chicas de alto impacto por semana, hechas y probadas en la rama, con una línea en CAMBIOS.md. Primero arregla cualquier error real que haya afectado a un cliente. Si no hay errores, avanza en esta lista, en orden, sin repetir lo hecho: a) páginas por comuna para Google (/aeropuerto/<comuna>/) de mayor demanda (Ñuñoa, Macul, San Miguel, La Cisterna, Huechuraba, Quilicura, Colina, San Bernardo), con la tarifa real de assets/tarifas.js, botón "Reservar y pagar en línea" y sitemap.xml, 3 o 4 por semana; b) página en inglés (/en/) con reserva y pago en línea; c) testimonios reales en la portada (solo 5 estrellas con comentario y permiso del pasajero). No toques cobros, tarifas ni seguridad sin explicarlo primero.
CORREO a gerencia@fk-servicios.com, asunto "Flota-K plataforma: semana AAAA-MM-DD": errores encontrados (en simple), cómo va el embudo, qué mejoras dejaste listas (rama) y que responda "Autorizo" para publicarlas. Si todo está en orden, 3 líneas.

### "Flota-K: respaldo semanal a Google Drive" — domingo 22:43 Chile (cron `CRON_TZ=America/Santiago 43 22 * * 0`)
Respaldo semanal de Flota-K (pedido por el dueño). Solo LECTURA de la base de datos: nunca modificar, borrar ni insertar en Supabase.
1. Con Supabase (proyecto iejhmplstveockkjjbks), lee con SELECT: reservas, clientes, cuentas_corporativas, v_cobro, reserva_gastos, vehiculos, documentos (solo metadatos), calificaciones, perfiles (solo id, nombre, rol, activo, conduce, movil, telefono, disponible; sin correos ni datos de autenticación), reserva_eventos, mensajes (últimos 90 días), cargos_cliente y solicitudes_pago (sin datos de tarjeta: no hay).
2. En Google Drive, usa (o crea) la carpeta "Flota-K Respaldos" en Mi unidad.
3. Crea ahí una planilla nueva "Respaldo Flota-K AAAA-MM-DD" (fecha de Chile) con una pestaña por tabla, encabezados y todas las filas. No toques respaldos anteriores ni compartas la planilla.
4. Verifica que las filas coincidan.
5. Solo si algo falla, avisa por correo a gerencia@fk-servicios.com (asunto "Flota-K: el respaldo semanal falló") en español simple. Si todo sale bien, no envíes correo; deja una línea de resumen en esta conversación.

## 7. Lo que hay que hacer ahora (aprobado por Juan el 26-nov: "Ok crea el prompt para hacer todo esto")
1. **Ahorro de tokens** (Juan lo pidió explícitamente): ejecutivo de cuentas a 2 revisiones (12:17 y 18:17, L-S); gerente "metas y equipo" a 2 (9:46 y 21:46, conservando el informe del lunes y el resumen de las 21:46); modelo más barato (Sonnet) para el ejecutivo de cuentas y el respaldo; el gerente y el comercial pueden quedar en el modelo actual. Al cambiar instrucciones, conservar todo el texto vigente (update_trigger reemplaza el texto entero). Pasar a tareas de Supabase (pg_cron, sin IA) lo mecánico cuando convenga.
2. **Recrear** las 2 tareas del punto 6 ligadas a la conversación nueva, y pausar (no borrar) las viejas si siguen existiendo.
3. **Microsoft Clarity** (gratis) en fk-servicios.com y /reservar para ver dónde abandonan el pago: Juan crea la cuenta y entrega el ID del proyecto (es público); enmascarar campos personales; rama + Autorizo.
4. **Brevo** (gratis, 300 correos/día) como SMTP de Supabase (quita el límite de 2 correos por hora) y para correos del sistema. Juan crea la cuenta y pega las credenciales en el panel de Supabase (Authentication → SMTP), nunca en el chat.
5. **Instagram automático propio (gratis):** app propia en Meta para Desarrolladores (modo desarrollo, solo la cuenta de Flota-K, sin revisión de Meta); Edge Function `ig-webhook` que recibe comentarios de cualquier publicación y, si traen "aeropuerto/precio/tarifa", responde en público y manda mensaje privado con fk-servicios.com/reservar/?utm_source=instagram; sección "Instagram" en el panel (comentarios, palabras clave y textos editables); botón "Conectar Instagram" con OAuth que guarda el token en una tabla solo de servicio; renovación automática del token (vence a los 60 días). Juan solo crea la app y pega el App ID y la clave secreta en Supabase → Edge Functions → Secrets. Reemplaza a ManyChat (gratis solo cubre la última publicación).
6. **Contenido viral** según el doc de competencia: 5 guiones (gancho en 3 s, pantalla dividida o sketch conductor-pasajero, cierre "Comente AEROPUERTO y le envío su tarifa") y lista de tomas para Juan; escenas de apoyo con Gemini/Veo sin personas falsas como clientes.
7. Revisar 1 vez a la semana el saldo de vidIQ y TinyFish.
