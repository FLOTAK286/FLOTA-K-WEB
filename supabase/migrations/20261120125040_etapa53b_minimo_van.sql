-- Etapa 53b: mínimo de la van en el cotizador punto a punto: $25.000 (pedido del dueño). Sube solo cuando el cálculo por distancia lo supera.
create or replace function cotizador_publico(p_empresa text default 'flota-k')
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('bajada', taxi_bajada, 'cada_200m', taxi_cada_200m, 'minimo', 12000, 'minimo_van', 25000)
  from empresas where slug = p_empresa
$$;
