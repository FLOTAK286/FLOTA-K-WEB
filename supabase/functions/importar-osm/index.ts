// Desactivada (22 nov 2026): estaba abierta al público y podía reemplazar los datos de mapa (osm_datos).
// Los datos de OpenStreetMap se reimportan desde la base con pg_net (ver CAMBIOS.md, etapa 71).
Deno.serve(() => new Response("desactivada", { status: 410 }));
