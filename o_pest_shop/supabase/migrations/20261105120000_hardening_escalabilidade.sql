-- ============================================================================
-- O PEST - HARDENING PARA ALTO TRÁFEGO (Supabase Free)
-- ============================================================================
-- Objetivo:
--   1) Fechar o furo de preço adulterado no checkout (P0 financeiro).
--   2) Substituir advisory lock de sessão por lock atômico em tabela.
--   3) Serializar o processamento de comprovantes por pagamento.
--   4) Expor somente colunas públicas ao cliente (custo/PIX/repasse ficam
--      acessíveis apenas via RPC administrativa).
--   5) Liberar leitura anônima do catálogo/feed com colunas controladas.
--   6) Criar feature flags para desligar checkout/pagamentos emergencialmente.
--   7) Criar índices e rotina de limpeza para reduzir consumo no Free.
--
-- IMPORTANTE:
--   - Não remove funcionalidades.
--   - Não altera dados existentes (apenas cria estruturas e corrige o
--     comportamento de novas compras).
--   - Rodar primeiro em staging. Não aplicar em produção sem autorização.
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- 1) PREÇO DEFINITIVO VEM DO BANCO (P0)
-- ----------------------------------------------------------------------------
-- O checkout antigo gravava pedido_itens.preco_unitario a partir do
-- "preco_atual" enviado pelo cliente. O total do pedido é recalculado por
-- fn_recalcula_total_pedido() a partir desse valor, permitindo comprar por
-- qualquer preço (ex.: R$ 1,00). Este trigger sobrescreve o preço com o valor
-- atual do produto, antes do cálculo do total.
create or replace function public.fn_forcar_preco_produto()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_produto record;
begin
  select p.id, p.preco, p.preco_promocional, p.em_promocao
    into v_produto
    from public.produtos p
   where p.id = new.produto_id;

  if not found then
    raise exception 'Produto % não encontrado', new.produto_id;
  end if;

  new.preco_unitario := case
    when coalesce(v_produto.em_promocao, false)
         and v_produto.preco_promocional is not null
      then v_produto.preco_promocional
    else coalesce(v_produto.preco, 0)
  end;

  return new;
end $$;

drop trigger if exists trg_forcar_preco_produto on public.pedido_itens;
create trigger trg_forcar_preco_produto
  before insert or update of produto_id, preco_unitario
  on public.pedido_itens
  for each row execute function public.fn_forcar_preco_produto();

comment on function public.fn_forcar_preco_produto() is
  'Impede preço enviado pelo cliente: pedido_itens.preco_unitario sempre vem de produtos.';

-- ----------------------------------------------------------------------------
-- 2) LOCK DE COBRANÇA ATÔMICO (substitui pg_advisory_lock de sessão)
-- ----------------------------------------------------------------------------
create table if not exists public.cobranca_locks (
  chave text primary key,
  criado_em timestamptz not null default now(),
  expira_em timestamptz not null
);

alter table public.cobranca_locks enable row level security;
revoke all on public.cobranca_locks from public, anon, authenticated;
grant all on public.cobranca_locks to service_role;

create index if not exists idx_cobranca_locks_expira
  on public.cobranca_locks(expira_em);

-- A assinatura antiga (1 argumento) é removida para não gerar ambiguidade.
drop function if exists public.adquirir_lock_cobranca(text);
drop function if exists public.liberar_lock_cobranca(text);

create or replace function public.adquirir_lock_cobranca(
  p_chave text,
  p_ttl_segundos int default 120
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ok boolean := false;
  v_expira timestamptz := now()
    + make_interval(secs => greatest(coalesce(p_ttl_segundos, 120), 10));
begin
  if p_chave is null or length(trim(p_chave)) = 0 then
    return false;
  end if;

  insert into public.cobranca_locks as l (chave, criado_em, expira_em)
  values (p_chave, now(), v_expira)
  on conflict (chave) do update
     set criado_em = now(),
         expira_em = v_expira
   where l.expira_em < now()
  returning true into v_ok;

  return coalesce(v_ok, false);
end $$;

create or replace function public.liberar_lock_cobranca(p_chave text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ok boolean := false;
begin
  delete from public.cobranca_locks
   where chave = p_chave
  returning true into v_ok;
  return coalesce(v_ok, false);
end $$;

revoke all on function public.adquirir_lock_cobranca(text, int) from public, anon, authenticated;
revoke all on function public.liberar_lock_cobranca(text) from public, anon, authenticated;
grant execute on function public.adquirir_lock_cobranca(text, int) to service_role;
grant execute on function public.liberar_lock_cobranca(text) to service_role;

-- ----------------------------------------------------------------------------
-- 3) SERIALIZAÇÃO DO PROCESSAMENTO DE COMPROVANTE
-- ----------------------------------------------------------------------------
-- Evita que webhook + consulta ativa + conciliação apliquem o mesmo
-- comprovante ao mesmo tempo. O processamento adquire o pagamento por TTL.
alter table public.pagamentos
  add column if not exists processando_em timestamptz;

create or replace function public.adquirir_processamento_pagamento(
  p_pagamento_id bigint,
  p_ttl_segundos int default 30
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ok boolean := false;
  v_limite timestamptz := now()
    - make_interval(secs => greatest(coalesce(p_ttl_segundos, 30), 10));
begin
  update public.pagamentos
     set processando_em = now()
   where id = p_pagamento_id
     and (processando_em is null or processando_em < v_limite)
  returning true into v_ok;
  return coalesce(v_ok, false);
end $$;

create or replace function public.liberar_processamento_pagamento(
  p_pagamento_id bigint
)
returns void
language sql
security definer
set search_path = public
as $$
  update public.pagamentos
     set processando_em = null
   where id = p_pagamento_id;
$$;

-- Marca a última consulta sem sobrescrever status/cancelamento já gravados.
create or replace function public.registrar_consulta_pagamento(
  p_pagamento_id bigint
)
returns void
language sql
security definer
set search_path = public
as $$
  update public.pagamentos
     set gateway_dados = coalesce(gateway_dados, '{}'::jsonb)
       || jsonb_build_object('ultima_consulta', now())
   where id = p_pagamento_id;
$$;

revoke all on function public.adquirir_processamento_pagamento(bigint, int)
  from public, anon, authenticated;
revoke all on function public.liberar_processamento_pagamento(bigint)
  from public, anon, authenticated;
revoke all on function public.registrar_consulta_pagamento(bigint)
  from public, anon, authenticated;
grant execute on function public.adquirir_processamento_pagamento(bigint, int)
  to service_role;
grant execute on function public.liberar_processamento_pagamento(bigint)
  to service_role;
grant execute on function public.registrar_consulta_pagamento(bigint)
  to service_role;

-- ----------------------------------------------------------------------------
-- 4) FEATURE FLAGS / CONFIGURAÇÃO PÚBLICA SEGURA
-- ----------------------------------------------------------------------------
create table if not exists public.app_config (
  chave text primary key,
  valor jsonb not null default '{}'::jsonb,
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid references public.perfis(id) on delete set null
);

alter table public.app_config enable row level security;
revoke all on public.app_config from public, anon, authenticated;
grant all on public.app_config to service_role;

insert into public.app_config (chave, valor) values
  ('checkout',   '{"ativo": true}'::jsonb),
  ('pagamentos', '{"ativo": true, "pix_only": false}'::jsonb),
  ('frete',      '{"ativo": true}'::jsonb),
  ('manutencao', '{"ativo": false, "mensagem": null}'::jsonb)
on conflict (chave) do nothing;

create or replace view public.app_config_publica
with (security_invoker = false)
as
select chave, valor
  from public.app_config
 where chave in ('checkout', 'pagamentos', 'frete', 'manutencao');

grant select on public.app_config_publica to anon, authenticated;

create or replace function public.admin_definir_config(
  p_chave text,
  p_valor jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- auth.uid() nulo = SQL Editor/service_role (emergência). Usuário logado
  -- precisa ser admin.
  if auth.uid() is not null
     and coalesce(public.funcao_usuario(), '') <> 'admin' then
    raise exception 'Somente o admin pode alterar a configuração';
  end if;

  insert into public.app_config (chave, valor, atualizado_em, atualizado_por)
  values (p_chave, coalesce(p_valor, '{}'::jsonb), now(), auth.uid())
  on conflict (chave) do update
     set valor = excluded.valor,
         atualizado_em = now(),
         atualizado_por = auth.uid();
end $$;

revoke all on function public.admin_definir_config(text, jsonb)
  from public, anon;
grant execute on function public.admin_definir_config(text, jsonb)
  to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 5) VIEWS PÚBLICAS (SEM CUSTO/PIX/REPASSE)
-- ----------------------------------------------------------------------------
create or replace view public.produtos_publicos
with (security_invoker = false)
as
select
  p.id,
  p.nome,
  p.descricao,
  p.preco,
  p.preco_promocional,
  p.em_promocao,
  p.url_imagem,
  p.categoria_id,
  p.marca_id,
  p.estoque,
  p.unidade_id,
  p.vendas,
  p.frete_gratis,
  p.percentual_desconto,
  p.garantia,
  p.parcelas,
  p.cores,
  p.sku,
  p.gtin,
  p.peso_kg,
  p.comprimento_cm,
  p.largura_cm,
  p.altura_cm,
  p.condicao,
  p.ativo,
  p.created_at,
  c.nome as categoria_nome,
  m.nome as marca_nome,
  u.nome as unidade_nome
from public.produtos p
left join public.categorias c on c.id = p.categoria_id
left join public.marcas m on m.id = p.marca_id
left join public.unidades u on u.id = p.unidade_id
where coalesce(p.ativo, true) = true
  and coalesce(u.ativa, true) = true
  and u.deleted_at is null;

grant select on public.produtos_publicos to anon, authenticated;

create or replace view public.unidades_publicas
with (security_invoker = false)
as
select
  u.id, u.nome, u.slug, u.logo_url, u.endereco, u.bairro, u.cidade,
  u.foto_url, u.cep, u.numero, u.complemento, u.uf,
  u.horario_seg, u.horario_ter, u.horario_qua, u.horario_qui,
  u.horario_sex, u.horario_sab, u.horario_dom,
  u.ordem, u.distancia, u.ativa, u.prazo_retirada_min, u.prazo_entrega_min,
  u.created_at, u.latitude, u.longitude,
  u.taxa_entrega, u.frete_gratis_acima, u.frete_modo, u.frete_taxa_base,
  u.frete_valor_km, u.frete_km_minimo, u.frete_raio_max_km,
  u.frete_fator_rota, u.frete_tempo_km_min, u.frete_peso_incluso_kg,
  u.frete_valor_kg_extra, u.tipo_loja
from public.unidades u
where coalesce(u.ativa, true) = true
  and u.deleted_at is null;

grant select on public.unidades_publicas to anon, authenticated;

-- ----------------------------------------------------------------------------
-- 6) COLUNAS PÚBLICAS NAS TABELAS BASE
-- ----------------------------------------------------------------------------
-- Usuários autenticados continuam podendo fazer os embeds de pedidos/carrinho
-- (nome, preço, imagem, dimensões), mas não podem ler custo, PIX ou repasse.
revoke select on table public.produtos from anon, authenticated;
grant select (
  id, nome, descricao, preco, preco_promocional, em_promocao, url_imagem,
  categoria_id, marca_id, estoque, unidade_id, created_at, vendas,
  frete_gratis, percentual_desconto, garantia, parcelas, cores, sku, gtin,
  ncm, peso_kg, comprimento_cm, largura_cm, altura_cm, condicao,
  ml_category_id, ml_domain_id, ml_attributes, ml_listing_type,
  ml_shipping_mode, ml_status, ml_item_id, ml_user_product_id, ml_permalink,
  ml_sync_enabled, ml_last_sync_at, ml_sync_error, ativo
) on public.produtos to authenticated;

revoke select on table public.unidades from anon, authenticated;
grant select (
  id, nome, slug, logo_url, endereco, bairro, cidade, foto_url, cep, numero,
  complemento, uf, horario_seg, horario_ter, horario_qua, horario_qui,
  horario_sex, horario_sab, horario_dom, ordem, distancia, ativa,
  prazo_retirada_min, prazo_entrega_min, created_at, latitude, longitude,
  taxa_entrega, frete_gratis_acima, frete_modo, frete_taxa_base,
  frete_valor_km, frete_km_minimo, frete_raio_max_km, frete_fator_rota,
  frete_tempo_km_min, frete_peso_incluso_kg, frete_valor_kg_extra, tipo_loja
) on public.unidades to authenticated, anon;

-- Garante que o admin/parceiro continue podendo inserir/atualizar/remover.
grant insert, update, delete on public.produtos to authenticated;
grant insert, update, delete on public.unidades to authenticated;

-- RLS de unidades: hoje só existe UPDATE; sem insert/delete o admin não cria
-- nem remove lojas. Mantém o comportamento existente e adiciona o necessário.
drop policy if exists "unidades_admin_insert" on public.unidades;
create policy "unidades_admin_insert" on public.unidades
  for insert to authenticated
  with check (public.funcao_usuario() = 'admin');

drop policy if exists "unidades_admin_delete" on public.unidades;
create policy "unidades_admin_delete" on public.unidades
  for delete to authenticated
  using (public.funcao_usuario() = 'admin');

-- ----------------------------------------------------------------------------
-- 7) LEITURA ANÔNIMA DO CATÁLOGO/FEED (somente conteúdo público)
-- ----------------------------------------------------------------------------
drop policy if exists "unidades_select_anon" on public.unidades;
create policy "unidades_select_anon" on public.unidades
  for select to anon using (true);

drop policy if exists "categorias_select_anon" on public.categorias;
create policy "categorias_select_anon" on public.categorias
  for select to anon using (true);
grant select on public.categorias to anon;

drop policy if exists "marcas_select_anon" on public.marcas;
create policy "marcas_select_anon" on public.marcas
  for select to anon using (true);
grant select on public.marcas to anon;

drop policy if exists "galeria_produtos_select_anon" on public.galeria_produtos;
create policy "galeria_produtos_select_anon" on public.galeria_produtos
  for select to anon using (true);
grant select on public.galeria_produtos to anon;

drop policy if exists "banners_select_anon" on public.banners;
create policy "banners_select_anon" on public.banners
  for select to anon
  using (
    ativo = true
    and (data_inicio is null or data_inicio <= now())
    and (data_fim is null or data_fim >= now())
  );
grant select on public.banners to anon;

drop policy if exists "posts_feed_select_anon" on public.posts_feed;
create policy "posts_feed_select_anon" on public.posts_feed
  for select to anon using (true);
grant select on public.posts_feed to anon;

drop policy if exists "post_likes_select_anon" on public.post_likes;
create policy "post_likes_select_anon" on public.post_likes
  for select to anon using (true);
grant select on public.post_likes to anon;

drop policy if exists "post_comentarios_select_anon" on public.post_comentarios;
create policy "post_comentarios_select_anon" on public.post_comentarios
  for select to anon using (true);
grant select on public.post_comentarios to anon;

-- Categorias do feed sem varrer a tabela inteira no cliente.
create or replace function public.feed_categorias()
returns table(categoria text)
language sql
stable
security definer
set search_path = public
as $$
  select distinct p.categoria
    from public.posts_feed p
   where p.categoria is not null
     and btrim(p.categoria) <> ''
   order by 1;
$$;

revoke all on function public.feed_categorias() from public;
grant execute on function public.feed_categorias() to anon, authenticated;

-- ----------------------------------------------------------------------------
-- 8) RPCS ADMINISTRATIVAS PARA CAMPOS SENSÍVEIS
-- ----------------------------------------------------------------------------
create or replace function public.admin_listar_produtos(
  p_unidade_id bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_funcao text := public.funcao_usuario();
  v_unidade bigint;
begin
  if coalesce(v_funcao, '') not in ('admin', 'gestor', 'atendente') then
    raise exception 'Sem permissão para listar produtos';
  end if;

  if v_funcao <> 'admin' then
    v_unidade := public.unidade_usuario();
    if v_unidade is null then
      raise exception 'Usuário sem loja vinculada';
    end if;
  end if;

  return coalesce((
    select jsonb_agg(
             to_jsonb(p)
             || jsonb_build_object(
                  'categorias', jsonb_build_object('nome', c.nome),
                  'marcas', jsonb_build_object('nome', m.nome),
                  'unidades', jsonb_build_object('id', u.id, 'nome', u.nome)
                )
             order by p.id
           )
      from public.produtos p
      left join public.categorias c on c.id = p.categoria_id
      left join public.marcas m on m.id = p.marca_id
      left join public.unidades u on u.id = p.unidade_id
     where (p_unidade_id is null or p.unidade_id = p_unidade_id)
       and (v_funcao = 'admin' or p.unidade_id = v_unidade)
  ), '[]'::jsonb);
end $$;

revoke all on function public.admin_listar_produtos(bigint) from public, anon;
grant execute on function public.admin_listar_produtos(bigint) to authenticated;

create or replace function public.admin_listar_unidades(
  p_unidade_id bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_funcao text := public.funcao_usuario();
  v_unidade bigint;
begin
  if coalesce(v_funcao, '') not in ('admin', 'gestor', 'atendente') then
    raise exception 'Sem permissão para listar unidades';
  end if;

  if v_funcao <> 'admin' then
    v_unidade := public.unidade_usuario();
    if v_unidade is null then
      raise exception 'Usuário sem loja vinculada';
    end if;
  end if;

  return coalesce((
    select jsonb_agg(to_jsonb(u) order by u.ordem, u.id)
      from public.unidades u
     where (p_unidade_id is null or u.id = p_unidade_id)
       and (v_funcao = 'admin' or u.id = v_unidade)
  ), '[]'::jsonb);
end $$;

revoke all on function public.admin_listar_unidades(bigint) from public, anon;
grant execute on function public.admin_listar_unidades(bigint) to authenticated;

-- ----------------------------------------------------------------------------
-- 9) CHECKOUT V6 COM GUARD DE FEATURE FLAG
-- ----------------------------------------------------------------------------
create or replace function public.finalizar_checkout_v6(
  p_user_id uuid,
  p_itens jsonb,
  p_cupom_desconto_total numeric default 0,
  p_cupom_id bigint default null,
  p_tipo_entrega text default 'retirada',
  p_endereco_entrega text default null,
  p_cep_entrega text default null,
  p_endereco_lat double precision default null,
  p_endereco_lng double precision default null,
  p_cotacoes jsonb default '[]'::jsonb,
  p_idempotency_key uuid default null,
  p_endereco jsonb default null,
  p_destinatario_cpf text default null,
  p_destinatario_telefone text default null,
  p_fretes jsonb default '[]'::jsonb,
  p_endereco_usuario_id bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cep text := regexp_replace(
    coalesce(p_cep_entrega, p_endereco->>'cep', ''),
    '\D', '', 'g'
  );
  v_endereco record;
  v_lat double precision := p_endereco_lat;
  v_lng double precision := p_endereco_lng;
  v_precisa_endereco boolean;
begin
  -- Desliga o checkout sem deploy do app.
  if not coalesce((
    select (valor->>'ativo')::boolean
      from public.app_config
     where chave = 'checkout'
  ), true) then
    raise exception 'O checkout está temporariamente indisponível. Tente novamente em instantes.';
  end if;

  if p_user_id is distinct from auth.uid() then
    raise exception 'Você não pode criar pedidos para outro usuário';
  end if;

  if p_tipo_entrega = 'entrega' then
    if length(v_cep) <> 8 then
      raise exception 'Informe um CEP válido para entrega';
    end if;

    select exists (
      select 1
        from jsonb_array_elements(p_itens) as t(item)
        join public.produtos p on p.id = (t.item->>'produto_id')::bigint
        join public.unidades u on u.id = coalesce(p.unidade_id, (t.item->>'unidade_id')::bigint, 1)
       where u.frete_modo in ('distancia', 'faixas')
    ) into v_precisa_endereco;

    if v_precisa_endereco then
      if p_endereco_usuario_id is null then
        raise exception 'Salve o endereço com localização antes de finalizar a entrega';
      end if;

      select * into v_endereco
        from public.enderecos_usuario
       where id = p_endereco_usuario_id
         and user_id = p_user_id;

      if not found then
        raise exception 'Endereço não encontrado. Salve o endereço novamente.';
      end if;
      if v_endereco.latitude is null or v_endereco.longitude is null then
        raise exception 'Endereço sem localização. Informe o endereço e calcule a entrega novamente.';
      end if;
      if regexp_replace(coalesce(v_endereco.cep, ''), '\D', '', 'g') <> v_cep then
        raise exception 'O CEP do endereço não confere com o informado';
      end if;

      v_lat := v_endereco.latitude;
      v_lng := v_endereco.longitude;
    end if;
  end if;

  return public.finalizar_checkout_v6_legacy(
    p_user_id, p_itens, p_cupom_desconto_total, p_cupom_id,
    p_tipo_entrega, p_endereco_entrega, v_cep,
    v_lat, v_lng, p_cotacoes, p_idempotency_key,
    p_endereco, p_destinatario_cpf, p_destinatario_telefone,
    p_fretes, p_endereco_usuario_id
  );
end $$;

revoke all on function public.finalizar_checkout_v6(
  uuid, jsonb, numeric, bigint, text, text, text, double precision, double precision,
  jsonb, uuid, jsonb, text, text, jsonb, bigint
) from public, anon;
grant execute on function public.finalizar_checkout_v6(
  uuid, jsonb, numeric, bigint, text, text, text, double precision, double precision,
  jsonb, uuid, jsonb, text, text, jsonb, bigint
) to authenticated;

-- ----------------------------------------------------------------------------
-- 10) ÍNDICES PARA OS PADRÕES DE CONSULTA DO APP
-- ----------------------------------------------------------------------------
create extension if not exists pg_trgm;

create index if not exists idx_produtos_ativo_id
  on public.produtos(ativo, id);
create index if not exists idx_produtos_ativo_categoria_id
  on public.produtos(ativo, categoria_id, id);
create index if not exists idx_produtos_ativo_marca_id
  on public.produtos(ativo, marca_id, id);
create index if not exists idx_produtos_ativo_unidade_id
  on public.produtos(ativo, unidade_id, id);
create index if not exists idx_produtos_nome_trgm
  on public.produtos using gin (nome gin_trgm_ops);

create index if not exists idx_pedidos_user_created
  on public.pedidos(user_id, created_at desc);
create index if not exists idx_pedidos_status_created
  on public.pedidos(status, created_at desc);
create index if not exists idx_pedidos_pagamento
  on public.pedidos(pagamento_id);

create index if not exists idx_pagamentos_status_created
  on public.pagamentos(status, created_at desc);
create index if not exists idx_pagamentos_status_metodo_expira
  on public.pagamentos(status, metodo, expira_em);
create index if not exists idx_pagamentos_processando
  on public.pagamentos(processando_em)
  where processando_em is not null;

create index if not exists idx_perfis_created
  on public.perfis(created_at desc);
create index if not exists idx_perfis_unidade_funcao
  on public.perfis(unidade_id, funcao);
create index if not exists idx_perfis_nome_trgm
  on public.perfis using gin (nome gin_trgm_ops);

create index if not exists idx_mensagens_conversa_created
  on public.mensagens(conversa_id, created_at);

create index if not exists idx_frete_cotacoes_pendentes
  on public.frete_cotacoes(user_id, unidade_id, usado_em, expira_em);

create index if not exists idx_post_comentarios_post_created
  on public.post_comentarios(post_id, created_at);

create index if not exists idx_banners_home_ativo
  on public.banners(ativo, ordem, data_inicio, data_fim);

-- Unique de conversa por (usuário, unidade), somente se não houver duplicatas
-- antigas (a migration não apaga histórico).
do $$
begin
  if to_regclass('public.conversas') is not null
     and not exists (
       select 1
         from public.conversas
        group by usuario_id, unidade_id
       having count(*) > 1
     ) then
    execute 'create unique index if not exists uq_conversas_usuario_unidade
             on public.conversas(usuario_id, unidade_id)';
  else
    raise notice 'conversas com duplicatas: índice único não criado (limpar antes).';
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- 11) LIMPEZA DE DADOS TEMPORÁRIOS
-- ----------------------------------------------------------------------------
create or replace function public.limpar_registros_temporarios()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_idempotencia int := 0;
  v_eventos int := 0;
  v_cotacoes int := 0;
  v_locks int := 0;
  v_processando int := 0;
begin
  delete from public.checkout_idempotencia
   where criado_em < now() - interval '7 days';
  get diagnostics v_idempotencia = row_count;

  delete from public.pagamentos_eventos
   where processado_em is not null
     and processado_em < now() - interval '30 days';
  get diagnostics v_eventos = row_count;

  delete from public.frete_cotacoes
   where usado_em is null
     and expira_em < now() - interval '1 day';
  get diagnostics v_cotacoes = row_count;

  delete from public.cobranca_locks
   where expira_em < now();
  get diagnostics v_locks = row_count;

  update public.pagamentos
     set processando_em = null
   where processando_em is not null
     and processando_em < now() - interval '5 minutes';
  get diagnostics v_processando = row_count;

  return jsonb_build_object(
    'idempotencia', v_idempotencia,
    'eventos', v_eventos,
    'cotacoes', v_cotacoes,
    'locks', v_locks,
    'processando', v_processando
  );
end $$;

revoke all on function public.limpar_registros_temporarios()
  from public, anon, authenticated;
grant execute on function public.limpar_registros_temporarios()
  to service_role;

do $$
begin
  if to_regnamespace('cron') is null then
    raise notice 'pg_cron ausente: rode limpar_registros_temporarios() manualmente/por agendador.';
    return;
  end if;

  perform cron.unschedule(jobname)
    from cron.job
   where jobname = 'opest-limpeza';

  perform cron.schedule(
    'opest-limpeza',
    '*/30 * * * *',
    'select public.limpar_registros_temporarios()'
  );
exception when others then
  raise notice 'Não foi possível agendar a limpeza: %', sqlerrm;
end $$;

-- ----------------------------------------------------------------------------
-- 12) CHECK DE SANIDADE (não altera dados)
-- ----------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1
      from pg_trigger
     where tgname = 'trg_forcar_preco_produto'
       and not tgisinternal
  ) then
    raise exception 'Trigger de preço não foi criado';
  end if;
end $$;

notify pgrst, 'reload schema';

commit;
