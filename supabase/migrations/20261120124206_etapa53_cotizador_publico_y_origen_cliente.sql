-- Etapa 53: (1) cotizador punto a punto en la página principal: parámetros públicos del taxímetro de la empresa
-- (solo bajada, cada 200 m y mínimo; el valor que ve el público es aproximado). (2) "¿Cómo nos conoció?" en las reservas.
create or replace function cotizador_publico(p_empresa text default 'flota-k')
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('bajada', taxi_bajada, 'cada_200m', taxi_cada_200m, 'minimo', 12000)
  from empresas where slug = p_empresa
$$;
revoke execute on function cotizador_publico(text) from public;
grant execute on function cotizador_publico(text) to anon, authenticated;

alter table reservas add column if not exists como_nos_conocio text check (como_nos_conocio in
  ('google', 'web', 'instagram', 'facebook', 'tiktok', 'linkedin', 'recomendacion', 'cliente_frecuente', 'empresa_convenio', 'volante', 'otro'));
