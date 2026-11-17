-- Etapa 36: puede_ingresar_equipo permitía, sin iniciar sesión, averiguar si un correo pertenece al equipo de Flota-K.
-- Ya ninguna pantalla la usa (el ingreso del equipo ahora recupera la contraseña con un enlace al correo, sin revelar si la cuenta existe).
-- Se quita el permiso de usarla desde la página; la función se mantiene.
revoke execute on function puede_ingresar_equipo(text) from public, anon, authenticated;
