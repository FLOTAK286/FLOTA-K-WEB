// Tarifario 2026 (pesos chilenos): [zona, ida al aeropuerto, regreso desde el aeropuerto, van ida].
// Lo usan la página principal (cotizador) y el panel del equipo (precio sugerido).
window.FK_TARIFAS = [
["Buin",46000,49000,63000],["Maipo",49000,51000,63000],["Linderos",49000,51000,63000],["Paine",54000,57000,69000],
["Huelquén",62000,64000,79000],["Champa",63000,65000,84000],["Calera de Tango",38000,40000,53000],
["Camino Lonquén (Veterquímica)",24000,26000,32000],["Cerrillos",21000,23000,34000],["Cerro Navia",19000,20000,30000],
["Colina centro hasta Esmeralda",44000,46000,58000],["Colina sector Peldehue - Chacabuco",60000,62000,69000],
["Conchalí",23000,25000,34000],["Curacaví",49000,51000,69000],["María Pinto",52000,54000,69000],
["Chicureo hasta Piedra Roja (vía normal)",38000,40000,53000],["Chicureo desde Los Pioneros - Lo Arcaya",40000,43000,58000],
["El Bosque",31000,33000,42000],["El Monte",53000,57000,69000],["Estación Central",19000,21000,28000],
["Farellones (temporada baja)",108000,108000,158000],["Huechuraba",29000,31000,37000],["Independencia",22000,24000,32000],
["Isla de Maipo",57000,59000,74000],["La Cisterna",29000,31000,37000],["La Florida hasta Av. La Florida",37000,39000,53000],
["La Florida desde Av. La Florida",39000,42000,55000],["La Florida Alto Macul, Las Perdices al oriente",43000,45000,58000],
["La Granja",32000,34000,42000],["La Pintana",36000,38000,48000],["La Reina (Vicente Pérez Rosales)",37000,39000,53000],
["La Reina (Padre Hurtado - Las Perdices)",39000,42000,55000],["La Reina Alta (Álvaro Casanova)",43000,45000,63000],
["Lampa Pueblo (centro)",30000,32000,42000],["Lampa Chicauma",33000,35000,48000],["Lampa Valle Grande",32000,34000,48000],
["Lampa Batuco",40000,43000,53000],["Las Condes hasta Manquehue",34000,36000,48000],
["Las Condes desde Manquehue hasta Paul Harris",37000,39000,50000],["Lo Barnechea hasta el Golf de Manquehue",43000,45000,58000],
["Lo Barnechea hasta P.L. Urqueta y B.L. Cotapos",44000,46000,60000],["Lo Barnechea Pie Andino (Paseo Los Bravos)",49000,51000,63000],
["El Arrayán",49000,51000,69000],["Lo Espejo",29000,31000,38000],["Lo Prado",18000,20000,29000],
["Lonquén (Pueblo)",46000,48000,63000],["Los Andes",98000,98000,137000],["Macul",36000,38000,48000],
["Maipú hasta Plaza de Maipú",22000,24000,32000],["Maipú desde Plaza de Maipú",27000,30000,37000],
["Maipú Ciudad Satélite",31000,33000,42000],["Melipilla",76000,78000,100000],["Ñuñoa por Costanera",33000,35000,48000],
["Ñuñoa por Vespucio Sur",35000,37000,48000],["Padre Hurtado",32000,34000,42000],["Pedro Aguirre Cerda",27000,30000,37000],
["Peñaflor",39000,42000,51000],["Peñalolén hasta Tobalaba",39000,42000,51000],["Peñalolén Alto hasta Las Perdices",42000,44000,53000],
["Peñalolén Diagonal Las Torres",44000,46000,58000],["Pirque hasta Virginia Subercaseaux",48000,50000,61000],
["Pirque El Principal - Club de Golf",54000,57000,74000],["Providencia",30000,32000,42000],["Pudahuel",18000,19000,25000],
["Puente Alto",43000,45000,58000],["Puente Alto Las Vizcachas",45000,47000,60000],["Quilicura",22000,24000,34000],
["Quinta Normal",19000,22000,30000],["Rancagua",103000,103000,137000],["Recoleta",29000,31000,40000],
["Renca",19000,22000,26000],["San Bernardo",35000,38000,46000],["San Bernardo - Nos",37000,39000,48000],
["San Carlos de Apoquindo hasta C. Otoñal, San Damián",37000,39000,48000],["San Carlos de Apoquindo hasta Av. La Plaza",39000,42000,51000],
["San Carlos de Apoquindo, Av. La Plaza a cordillera",42000,44000,55000],["San Felipe",108000,108000,153000],
["San Joaquín",31000,33000,42000],["San José de Maipo",71000,73000,100000],["San Miguel",30000,32000,40000],
["San Ramón",32000,33000,42000],["Santiago Centro",26000,28000,37000],["Talagante",47000,49000,61000],
["Til Til",65000,67000,84000],["Valparaíso - Viña del Mar",130000,130000,168000],["Vitacura hasta Manquehue",34000,36000,46000],
["Vitacura hasta Tabancura",37000,39000,48000]
];

// Traslados directos fuera del aeropuerto (tarifa fija por tramo, de ida o de regreso). [nombre, auto, van]
// "oriente" y "costa": comunas de cada extremo (para el precio sugerido del panel). "claves": búsquedas en la portada.
window.FK_INTERURBANOS = [
  { nombre: "Sector Oriente de Santiago ↔ Viña del Mar / Valparaíso", auto: 170000, van: 240000,
    oriente: ["las condes", "vitacura", "lo barnechea", "providencia", "la reina", "nunoa"],
    costa: ["vina del mar", "valparaiso"],
    claves: ["vina", "valpara", "oriente", "costa", "playa"] }
];
