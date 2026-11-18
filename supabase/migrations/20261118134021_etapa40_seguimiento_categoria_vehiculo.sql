-- Etapa 40: el seguimiento muestra la categoría del vehículo (taxi básico, turismo, ejecutivo, SUV, van) además de marca, modelo y color.
create or replace function public.ver_reserva_publica_v3(p_token uuid)
 returns table(o_codigo text, o_estado estado_reserva, o_fecha_hora timestamptz, o_origen text, o_destino text, o_conductor text,
   o_movil text, o_vehiculo text, o_patente text, o_color text, o_anio integer, o_foto_conductor text, o_foto_vehiculo text,
   o_calificacion numeric, o_n_calif integer, o_tipo_servicio text, o_vuelo text, o_categoria text, o_capacidad integer)
 language sql stable security definer set search_path to 'public'
as $function$
  select r.codigo, r.estado, r.fecha_hora, r.origen, r.destino, p.nombre, p.movil,
         nullif(trim(concat_ws(' ', v.marca, v.modelo)), ''), v.patente, v.color, v.anio,
         p.foto_path, v.foto_path,
         (select round(avg(c.estrellas)::numeric, 1) from calificaciones c where c.conductor_id = r.conductor_id and c.autor = 'pasajero'),
         (select count(*)::int from calificaciones c where c.conductor_id = r.conductor_id and c.autor = 'pasajero'),
         r.tipo_servicio::text, r.vuelo, v.categoria, v.capacidad
  from reservas r
  left join perfiles p on p.id = r.conductor_id
  left join vehiculos v on v.id = coalesce(r.vehiculo_id,
       (select id from vehiculos where conductor_habitual = r.conductor_id and activo order by creado_en limit 1))
  where r.token_seguimiento = p_token
$function$;
revoke execute on function public.ver_reserva_publica_v3(uuid) from public;
grant execute on function public.ver_reserva_publica_v3(uuid) to anon, authenticated;
