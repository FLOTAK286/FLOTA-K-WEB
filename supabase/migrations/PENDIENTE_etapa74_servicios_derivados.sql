-- Etapa 74: servicios derivados a un partner (proveedor externo) con su propio seguimiento.
-- El despachador pega el enlace de "compartir viaje" de la app del partner y los datos de su conductor;
-- la página de seguimiento de Flota-K los muestra (sin nombrar al partner) y ofrece el botón "Ver su traslado en vivo".
alter table reservas add column if not exists derivado_enlace text;
alter table reservas add column if not exists derivado_conductor text;
alter table reservas add column if not exists derivado_vehiculo text;
alter table reservas add column if not exists derivado_patente text;

-- Si la reserva deja de estar derivada (se asigna a un conductor propio), se borran los datos del partner
create or replace function public.limpiar_datos_derivado() returns trigger
 language plpgsql set search_path to 'public' as $$
begin
  if new.derivado_a is null then
    new.derivado_enlace := null; new.derivado_conductor := null; new.derivado_vehiculo := null; new.derivado_patente := null;
  end if;
  return new;
end $$;
drop trigger if exists trg_limpiar_datos_derivado on reservas;
create trigger trg_limpiar_datos_derivado before update of derivado_a on reservas
  for each row execute function public.limpiar_datos_derivado();

-- Guardar los datos del partner (solo equipo de la misma empresa; la reserva debe estar derivada)
create or replace function public.staff_datos_derivado(p_reserva uuid, p_enlace text, p_conductor text, p_vehiculo text, p_patente text)
 returns void language plpgsql security definer set search_path to 'public' as $$
declare
  v_der text;
  v_enlace text := nullif(trim(coalesce(p_enlace, '')), '');
begin
  if not es_staff() then raise exception 'Sin permiso'; end if;
  select derivado_a into v_der from reservas where id = p_reserva and empresa_id = mi_empresa() for update;
  if not found then raise exception 'Reserva no encontrada'; end if;
  if v_der is null then raise exception 'Primero derive la reserva a un partner'; end if;
  if v_enlace is not null and (v_enlace !~* '^https://[^\s<>"]+$' or length(v_enlace) > 500) then
    raise exception 'El enlace de seguimiento debe empezar con https://';
  end if;
  update reservas set derivado_enlace = v_enlace,
         derivado_conductor = nullif(left(trim(coalesce(p_conductor, '')), 80), ''),
         derivado_vehiculo = nullif(left(trim(coalesce(p_vehiculo, '')), 80), ''),
         derivado_patente = nullif(upper(left(trim(coalesce(p_patente, '')), 12)), '')
   where id = p_reserva;
  insert into reserva_eventos (reserva_id, estado, nota, usuario_id)
  select id, estado, 'Datos del partner: ' || concat_ws(' · ', derivado_conductor, derivado_vehiculo, derivado_patente,
         case when derivado_enlace is not null then 'con enlace de seguimiento' end), auth.uid()
    from reservas where id = p_reserva;
end $$;
revoke all on function public.staff_datos_derivado(uuid, text, text, text, text) from public, anon;
grant execute on function public.staff_datos_derivado(uuid, text, text, text, text) to authenticated;

-- Vista pública del seguimiento (v4): igual que v3, más los datos del partner cuando la reserva está derivada
create or replace function public.ver_reserva_publica_v4(p_token uuid)
 returns table(o_codigo text, o_estado estado_reserva, o_fecha_hora timestamptz, o_origen text, o_destino text, o_conductor text, o_movil text,
               o_vehiculo text, o_patente text, o_color text, o_anio integer, o_foto_conductor text, o_foto_vehiculo text, o_calificacion numeric,
               o_n_calif integer, o_tipo_servicio text, o_vuelo text, o_categoria text, o_capacidad integer, o_derivado boolean, o_enlace_externo text)
 language sql stable security definer set search_path to 'public' as $$
  select r.codigo, r.estado, r.fecha_hora, r.origen, r.destino,
         case when d then r.derivado_conductor else p.nombre end,
         case when d then null else p.movil end,
         case when d then r.derivado_vehiculo else nullif(trim(concat_ws(' ', v.marca, v.modelo)), '') end,
         case when d then r.derivado_patente else v.patente end,
         case when d then null else v.color end,
         case when d then null else v.anio end,
         case when d then null else p.foto_path end,
         case when d then null else v.foto_path end,
         case when d then null else (select round(avg(c.estrellas)::numeric, 1) from calificaciones c where c.conductor_id = r.conductor_id and c.autor = 'pasajero') end,
         case when d then null else (select count(*)::int from calificaciones c where c.conductor_id = r.conductor_id and c.autor = 'pasajero') end,
         r.tipo_servicio::text, r.vuelo,
         case when d then null else v.categoria end,
         case when d then null else v.capacidad end,
         d, case when d then r.derivado_enlace end
  from reservas r
  cross join lateral (select r.derivado_a is not null as d) x
  left join perfiles p on p.id = r.conductor_id
  left join vehiculos v on v.id = coalesce(r.vehiculo_id,
       (select id from vehiculos where conductor_habitual = r.conductor_id and activo order by creado_en limit 1))
  where r.token_seguimiento = p_token
$$;
revoke all on function public.ver_reserva_publica_v4(uuid) from public;
grant execute on function public.ver_reserva_publica_v4(uuid) to anon, authenticated;
