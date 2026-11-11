-- Etapa 26: nota mínima 4,96 para la vista anticipada de la bolsa y aceptación de compartir ubicación.
--  Nivel 1 (minutos 0-10): móvil de Flota-K con promedio 4,96 o más; o sin ninguna calificación aún
--          (si su primera nota no es 5, el promedio baja de 4,96 y pierde la prioridad).
--  Nivel 2 (minutos 10-20): conductor con al menos 3 calificaciones en 90 días y promedio 4,96 o más.
--  Nivel 3: resto (desde el minuto 20).

create or replace function conductor_destacado(p_conductor uuid) returns boolean language sql stable security definer set search_path = public as $$
  select count(*) >= 3 and coalesce(avg(estrellas), 0) >= 4.96 from calificaciones
  where conductor_id = p_conductor and autor = 'pasajero' and creado_en > now() - interval '90 days'
$$;

create or replace function nivel_bolsa(p_conductor uuid) returns int language sql stable security definer set search_path = public as $$
  with c as (select count(*) filter (where creado_en > now() - interval '90 days') n90,
                    coalesce(avg(estrellas) filter (where creado_en > now() - interval '90 days'), 0) prom90,
                    count(*) total
             from calificaciones where conductor_id = p_conductor and autor = 'pasajero'),
       f as (select exists (select 1 from vehiculos where conductor_habitual = p_conductor and activo and propio) flotak)
  select case when f.flotak and (c.total = 0 or (c.n90 >= 1 and c.prom90 >= 4.96)) then 1
              when c.n90 >= 3 and c.prom90 >= 4.96 then 2 else 3 end
  from c, f
$$;

-- Para la app: su nivel, su nota y si es móvil de Flota-K (para explicarle cuándo ve las reservas).
create or replace function mi_nivel_bolsa()
returns table (o_nivel int, o_prom numeric, o_n int, o_flotak boolean)
language sql stable security definer set search_path = public as $$
  select nivel_bolsa(auth.uid()),
         (select round(avg(estrellas)::numeric, 2) from calificaciones where conductor_id = auth.uid() and autor = 'pasajero' and creado_en > now() - interval '90 days'),
         (select count(*)::int from calificaciones where conductor_id = auth.uid() and autor = 'pasajero' and creado_en > now() - interval '90 days'),
         exists (select 1 from vehiculos where conductor_habitual = auth.uid() and activo and propio)
$$;
revoke execute on function mi_nivel_bolsa() from public, anon;
grant execute on function mi_nivel_bolsa() to authenticated;

-- Aceptación del conductor: compartir su ubicación con Flota-K mientras tenga la sesión iniciada (también desconectado).
alter table perfiles add column if not exists ubicacion_aceptada_en timestamptz;
create or replace function conductor_aceptar_ubicacion() returns void language plpgsql security definer set search_path = public as $$
begin
  update perfiles set ubicacion_aceptada_en = coalesce(ubicacion_aceptada_en, now()) where id = auth.uid() and activo;
end $$;
revoke execute on function conductor_aceptar_ubicacion() from public, anon;
grant execute on function conductor_aceptar_ubicacion() to authenticated;
