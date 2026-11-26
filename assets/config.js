// Configuración pública de Supabase (la clave "anon" está hecha para ir en la página: la seguridad la aplica la base de datos).
window.FK_CONFIG = {
  url: "https://iejhmplstveockkjjbks.supabase.co",
  anonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImllamhtcGxzdHZlb2Nra2pqYmtzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQxNzU5NzEsImV4cCI6MjEwOTc1MTk3MX0.M0dV27_xF8KVUKjNqPHaBCElLIF4EQoWk-xAmrRwafI",
  empresa: "flota-k",
  clarity: "", // ID del proyecto de Microsoft Clarity (lo entrega el dueño; es público). Vacío = apagado.
  google: false, // activar cuando se configure el ingreso con Google en Supabase
  resenaGoogle: "https://www.google.com/maps?cid=4726366054387270227" // ficha de Flota-K en Google (cambiar por el enlace "Pedir reseñas" de Google Business cuando lo tengamos); enlace para dejar reseña en la ficha de Google (se ofrece al pasajero que califica con 5 estrellas)
};
