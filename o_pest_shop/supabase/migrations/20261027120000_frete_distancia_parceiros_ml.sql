-- ═══════════════════════════════════════════════════════════════════════
-- O PEST · FRETE POR DISTÂNCIA + LOJAS PARCEIRAS + BASE MERCADO LIVRE
-- Rodar DEPOIS de 20261019120000_pagamentos_blindagem.sql.
-- Idempotente: pode rodar mais de uma vez.
-- ═══════════════════════════════════════════════════════════════════════

begin;

-- ── 1) LOJAS: FRETE, PERFIL E ONBOARDING ───────────────────────────────

alter table public.unidades
  add column if not exists frete_modo text not null default 'fixo',
  add column if not exists frete_taxa_base numeric not null default 0,
  add column if not exists frete_valor_km numeric not null default 0,
  add column if not exists frete_km_minimo numeric not null default 0,
  add column if not exists frete_raio_max_km numeric,
  add column if not exists frete_fator_rota numeric not null default 1.30,
  add column if not exists frete_tempo_km_min numeric not null default 3,
  add column if not exists tipo_loja text not null default 'matriz',
  add column if not exists cep text,
  add column if not exists cnpj text,
  add column if not exists responsavel text,
  add column if not exists email_contato text,
  add column if not exists telefone_contato text,
  add column if not exists comissao_percentual numeric not null default 0,
  add column if not exists repasse_pagbank_id text,
  add column if not exists onboarding_status text not null default 'ativo',
  add column if not exists deleted_at timestamptz;

update public.unidades
   set frete_taxa_base = coalesce(nullif(frete_taxa_base, 0), coalesce(taxa_entrega, 0))
 where coalesce(frete_taxa_base, 0) = 0
   and coalesce(taxa_entrega, 0) > 0;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'unidades_frete_modo_check'
  ) then
    alter table public.unidades
      add constraint unidades_frete_modo_check
      check (frete_modo in ('fixo', 'distancia', 'faixas')) not valid;
  end if;
end $$;

create table if not exists public.frete_faixas (
  id bigint generated always as identity primary key,
  unidade_id bigint not null references public.unidades(id) on delete cascade,
  km_inicio numeric not null check (km_inicio >= 0),
  km_fim numeric not null check (km_fim > km_inicio),
  valor numeric not null check (valor >= 0),
  ativo boolean not null default true,
  created_at timestamptz not null default now()
);

create index if not exists idx_frete_faixas_unidade
  on public.frete_faixas(unidade_id, km_inicio);

alter table public.frete_faixas enable row level security;

-- ── 2) ENDEREÇOS: COORDENADAS PARA CÁLCULO ─────────────────────────────

create table if not exists public.enderecos_usuario (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.perfis(id) on delete cascade,
  apelido text,
  cep text,
  rua text,
  numero text,
  complemento text,
  bairro text,
  cidade text,
  uf text,
  principal boolean not null default false,
  latitude double precision,
  longitude double precision,
  geocodificado_em timestamptz,
  geocode_fonte text,
  created_at timestamptz not null default now()
);

create index if not exists idx_enderecos_usuario_user on public.enderecos_usuario(user_id);

alter table public.enderecos_usuario enable row level security;

drop policy if exists "enderecos_own_all" on public.enderecos_usuario;
create policy "enderecos_own_all" on public.enderecos_usuario
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "enderecos_admin_select" on public.enderecos_usuario;
create policy "enderecos_admin_select" on public.enderecos_usuario
  for select to authenticated
  using (public.funcao_usuario() = 'admin');

grant select, insert, update, delete on public.enderecos_usuario to authenticated;

alter table public.enderecos_usuario
  add column if not exists latitude double precision,
  add column if not exists longitude double precision,
  add column if not exists geocodificado_em timestamptz,
  add column if not exists geocode_fonte text;

-- ── 3) PEDIDOS: DISTÂNCIA, ORIGEM E DADOS DO COMPRADOR ML ──────────────

alter table public.pedidos
  alter column user_id drop not null;

alter table public.pedidos
  add column if not exists cupom_id bigint,
  add column if not exists desconto_cupom numeric not null default 0,
  add column if not exists checkout_id uuid,
  add column if not exists distancia_km numeric,
  add column if not exists frete_detalhe jsonb,
  add column if not exists previsao_entrega_min int,
  add column if not exists origem text not null default 'app',
  add column if not exists canal text,
  add column if not exists comprador_nome text,
  add column if not exists comprador_email text,
  add column if not exists comprador_telefone text,
  add column if not exists codigo_rastreio text,
  add column if not exists url_rastreio text,
  add column if not exists ml_order_id bigint;

create unique index if not exists uq_pedidos_ml_order
  on public.pedidos(ml_order_id) where ml_order_id is not null;

update public.pedidos
   set checkout_id = gen_random_uuid()
 where checkout_id is null;

alter table public.pedidos
  alter column checkout_id set default gen_random_uuid();

create index if not exists idx_pedidos_origem on public.pedidos(origem, created_at desc);
create index if not exists idx_pedidos_unidade_status on public.pedidos(unidade_id, status, created_at desc);

-- ── 4) CUPONS POR LOJA ─────────────────────────────────────────────────

alter table public.cupons
  add column if not exists unidade_id bigint references public.unidades(id) on delete cascade;

create index if not exists idx_cupons_unidade on public.cupons(unidade_id);

-- ── 5) PRODUTOS: CATÁLOGO E CAMPOS MERCADO LIVRE ───────────────────────

alter table public.produtos
  add column if not exists sku text,
  add column if not exists gtin text,
  add column if not exists ncm text,
  add column if not exists peso_kg numeric,
  add column if not exists comprimento_cm numeric,
  add column if not exists largura_cm numeric,
  add column if not exists altura_cm numeric,
  add column if not exists condicao text not null default 'new',
  add column if not exists custo numeric,
  add column if not exists ml_category_id text,
  add column if not exists ml_domain_id text,
  add column if not exists ml_attributes jsonb,
  add column if not exists ml_listing_type text default 'gold_special',
  add column if not exists ml_shipping_mode text,
  add column if not exists ml_status text,
  add column if not exists ml_item_id text,
  add column if not exists ml_user_product_id text,
  add column if not exists ml_permalink text,
  add column if not exists ml_sync_enabled boolean not null default false,
  add column if not exists ml_last_sync_at timestamptz,
  add column if not exists ml_sync_error text;

create unique index if not exists uq_produtos_unidade_sku
  on public.produtos(unidade_id, sku) where sku is not null;

create index if not exists idx_produtos_ml_item on public.produtos(ml_item_id) where ml_item_id is not null;

create table if not exists public.produto_variacoes (
  id bigint generated always as identity primary key,
  produto_id bigint not null references public.produtos(id) on delete cascade,
  sku text,
  cor text,
  tamanho text,
  gtin text,
  preco numeric,
  estoque int not null default 0,
  peso_kg numeric,
  comprimento_cm numeric,
  largura_cm numeric,
  altura_cm numeric,
  ml_variation_id text,
  ml_user_product_id text,
  ativo boolean not null default true,
  created_at timestamptz not null default now(),
  unique (produto_id, cor, tamanho)
);

create unique index if not exists uq_produto_variacoes_sku
  on public.produto_variacoes(sku) where sku is not null;

alter table public.produto_variacoes enable row level security;

-- ── 6) INTEGRAÇÃO MERCADO LIVRE ────────────────────────────────────────

create table if not exists public.integracoes_loja (
  id uuid primary key default gen_random_uuid(),
  unidade_id bigint not null unique references public.unidades(id) on delete cascade,
  plataforma text not null default 'mercadolivre',
  ml_user_id bigint,
  ml_nickname text,
  access_token text,
  refresh_token text,
  token_expira_em timestamptz,
  refresh_expira_em timestamptz,
  scopes text,
  status text not null default 'desconectado',
  erro text,
  connected_at timestamptz,
  last_sync_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.ml_oauth_states (
  id uuid primary key default gen_random_uuid(),
  state text not null unique,
  user_id uuid not null,
  unidade_id bigint not null references public.unidades(id) on delete cascade,
  code_verifier text,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);

create table if not exists public.ml_anuncios (
  id uuid primary key default gen_random_uuid(),
  unidade_id bigint not null references public.unidades(id) on delete cascade,
  produto_id bigint not null references public.produtos(id) on delete cascade,
  integracao_id uuid references public.integracoes_loja(id) on delete cascade,
  ml_item_id text unique,
  ml_user_product_id text,
  ml_family_id text,
  category_id text,
  domain_id text,
  listing_type text,
  status text,
  permalink text,
  sync_hash text,
  erro text,
  raw jsonb,
  last_sync_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (unidade_id, produto_id)
);

create table if not exists public.ml_pedidos (
  id uuid primary key default gen_random_uuid(),
  pedido_id bigint unique references public.pedidos(id) on delete cascade,
  integracao_id uuid references public.integracoes_loja(id) on delete set null,
  ml_order_id bigint not null unique,
  ml_pack_id bigint,
  ml_status text,
  ml_status_detail text,
  shipping_id bigint,
  raw jsonb,
  last_sync_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.ml_eventos (
  id uuid primary key default gen_random_uuid(),
  topic text not null,
  resource text not null,
  ml_user_id bigint,
  application_id bigint,
  payload jsonb,
  status text not null default 'pendente',
  attempts int not null default 0,
  erro text,
  created_at timestamptz not null default now(),
  processed_at timestamptz
);

create index if not exists idx_ml_eventos_status on public.ml_eventos(status, created_at);
create index if not exists idx_ml_eventos_resource on public.ml_eventos(resource);

create table if not exists public.ml_sync_fila (
  id bigint generated always as identity primary key,
  unidade_id bigint not null references public.unidades(id) on delete cascade,
  produto_id bigint references public.produtos(id) on delete cascade,
  tipo text not null,
  payload jsonb,
  status text not null default 'pendente',
  tentativas int not null default 0,
  proxima_tentativa timestamptz not null default now(),
  erro text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_ml_sync_fila_pendente
  on public.ml_sync_fila(status, proxima_tentativa);

alter table public.integracoes_loja enable row level security;
alter table public.ml_oauth_states enable row level security;
alter table public.ml_anuncios enable row level security;
alter table public.ml_pedidos enable row level security;
alter table public.ml_eventos enable row level security;
alter table public.ml_sync_fila enable row level security;

-- ── 7) FUNÇÕES AUXILIARES DE ESCOPO ────────────────────────────────────

create or replace function public.unidade_do_usuario()
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select unidade_id from public.perfis where id = auth.uid();
$$;

create or replace function public.pode_gerenciar_unidade(p_unidade_id bigint)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.perfis
     where id = auth.uid()
       and (
         funcao = 'admin'
         or (funcao in ('gestor', 'atendente') and unidade_id = p_unidade_id)
       )
  );
$$;

grant execute on function public.unidade_do_usuario() to authenticated;
grant execute on function public.pode_gerenciar_unidade(bigint) to authenticated;

-- ── 8) RLS: LOJAS PARCEIRAS ────────────────────────────────────────────

drop policy if exists "unidades_parceiro_update" on public.unidades;
create policy "unidades_parceiro_update" on public.unidades
  for update to authenticated
  using (public.pode_gerenciar_unidade(id))
  with check (public.pode_gerenciar_unidade(id));

drop policy if exists "produtos_parceiro_all" on public.produtos;
create policy "produtos_parceiro_all" on public.produtos
  for all to authenticated
  using (public.pode_gerenciar_unidade(unidade_id))
  with check (public.pode_gerenciar_unidade(unidade_id));

drop policy if exists "cupons_parceiro_all" on public.cupons;
create policy "cupons_parceiro_all" on public.cupons
  for all to authenticated
  using (
    (unidade_id is not null and public.pode_gerenciar_unidade(unidade_id))
    or (unidade_id is null and public.funcao_usuario() = 'admin')
  )
  with check (
    (unidade_id is not null and public.pode_gerenciar_unidade(unidade_id))
    or (unidade_id is null and public.funcao_usuario() = 'admin')
  );

drop policy if exists "frete_faixas_select" on public.frete_faixas;
create policy "frete_faixas_select" on public.frete_faixas
  for select to authenticated using (true);

drop policy if exists "frete_faixas_gerencia" on public.frete_faixas;
create policy "frete_faixas_gerencia" on public.frete_faixas
  for all to authenticated
  using (public.pode_gerenciar_unidade(unidade_id))
  with check (public.pode_gerenciar_unidade(unidade_id));

drop policy if exists "produto_variacoes_select" on public.produto_variacoes;
create policy "produto_variacoes_select" on public.produto_variacoes
  for select to authenticated using (true);

drop policy if exists "produto_variacoes_gerencia" on public.produto_variacoes;
create policy "produto_variacoes_gerencia" on public.produto_variacoes
  for all to authenticated
  using (
    exists (
      select 1 from public.produtos p
       where p.id = produto_id
         and public.pode_gerenciar_unidade(p.unidade_id)
    )
  )
  with check (
    exists (
      select 1 from public.produtos p
       where p.id = produto_id
         and public.pode_gerenciar_unidade(p.unidade_id)
    )
  );

drop policy if exists "integracoes_loja_select" on public.integracoes_loja;
create policy "integracoes_loja_select" on public.integracoes_loja
  for select to authenticated
  using (public.pode_gerenciar_unidade(unidade_id));

drop policy if exists "ml_anuncios_select" on public.ml_anuncios;
create policy "ml_anuncios_select" on public.ml_anuncios
  for select to authenticated
  using (public.pode_gerenciar_unidade(unidade_id));

drop policy if exists "ml_pedidos_select" on public.ml_pedidos;
create policy "ml_pedidos_select" on public.ml_pedidos
  for select to authenticated
  using (
    exists (
      select 1 from public.pedidos p
       where p.id = pedido_id
         and public.pode_gerenciar_unidade(p.unidade_id)
    )
  );

drop policy if exists "ml_eventos_admin" on public.ml_eventos;
create policy "ml_eventos_admin" on public.ml_eventos
  for select to authenticated
  using (public.funcao_usuario() = 'admin');

drop policy if exists "ml_sync_fila_admin" on public.ml_sync_fila;
create policy "ml_sync_fila_admin" on public.ml_sync_fila
  for select to authenticated
  using (public.pode_gerenciar_unidade(unidade_id));

-- Tokens são acessíveis somente pelo service_role (Edge Functions).
revoke all on public.integracoes_loja from anon, authenticated;
grant select (
  id, unidade_id, plataforma, ml_user_id, ml_nickname, status, erro,
  connected_at, last_sync_at, created_at, updated_at
) on public.integracoes_loja to authenticated;
grant all on public.integracoes_loja to service_role;
grant all on public.ml_oauth_states to service_role;
grant all on public.ml_anuncios to service_role;
grant all on public.ml_pedidos to service_role;
grant all on public.ml_eventos to service_role;
grant all on public.ml_sync_fila to service_role;

-- Upload de imagens por gestores/atendentes das lojas parceiras.
drop policy if exists "Produtos_parceiro_write" on storage.objects;
create policy "Produtos_parceiro_write" on storage.objects
  for all to authenticated
  using (
    bucket_id = 'Produtos'
    and public.funcao_usuario() in ('admin', 'gestor', 'atendente')
  )
  with check (
    bucket_id = 'Produtos'
    and public.funcao_usuario() in ('admin', 'gestor', 'atendente')
  );

-- ── 9) FRETE POR DISTÂNCIA ─────────────────────────────────────────────

create or replace function public.fn_haversine_km(
  p_lat1 double precision,
  p_lng1 double precision,
  p_lat2 double precision,
  p_lng2 double precision
)
returns double precision
language sql
immutable
as $$
  select 6371.0 * 2.0 * asin(
    sqrt(
      power(sin(radians((p_lat2 - p_lat1) / 2.0)), 2)
      + cos(radians(p_lat1)) * cos(radians(p_lat2))
        * power(sin(radians((p_lng2 - p_lng1) / 2.0)), 2)
    )
  );
$$;

create or replace function public.fn_calcular_frete_unidade(
  p_unidade_id bigint,
  p_lat double precision,
  p_lng double precision,
  p_subtotal numeric default 0,
  p_todos_frete_gratis boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_u record;
  v_dist numeric;
  v_valor numeric;
  v_eta int;
  v_gratis boolean;
begin
  select *
    into v_u
    from public.unidades
   where id = p_unidade_id
     and coalesce(ativa, true) = true
     and deleted_at is null;

  if not found then
    raise exception 'Loja indisponível para entrega';
  end if;

  if p_lat is null or p_lng is null then
    raise exception 'Endereço sem localização. Informe o endereço e calcule a entrega novamente.';
  end if;

  if v_u.latitude is not null and v_u.longitude is not null then
    v_dist := public.fn_haversine_km(
      v_u.latitude::double precision,
      v_u.longitude::double precision,
      p_lat,
      p_lng
    ) * coalesce(v_u.frete_fator_rota, 1.30);
  else
    v_dist := null;
  end if;

  v_gratis := coalesce(p_todos_frete_gratis, false)
    or (v_u.frete_gratis_acima is not null and p_subtotal >= v_u.frete_gratis_acima);

  if v_gratis then
    v_valor := 0;
  elsif v_u.frete_modo = 'distancia' and v_dist is not null then
    if v_u.frete_raio_max_km is not null and v_dist > v_u.frete_raio_max_km then
      return jsonb_build_object(
        'fora_area', true,
        'distancia_km', round(v_dist::numeric, 2),
        'valor', 0,
        'previsao_entrega_min', null,
        'gratis', false,
        'mensagem', 'Endereço fora do raio de entrega da loja'
      );
    end if;

    v_valor := coalesce(v_u.frete_taxa_base, 0)
      + greatest(v_dist - coalesce(v_u.frete_km_minimo, 0), 0)
        * coalesce(v_u.frete_valor_km, 0);
  elsif v_u.frete_modo = 'faixas' and v_dist is not null then
    select f.valor
      into v_valor
      from public.frete_faixas f
     where f.unidade_id = p_unidade_id
       and f.ativo
       and v_dist >= f.km_inicio
       and v_dist <= f.km_fim
     order by f.km_inicio
     limit 1;

    if v_valor is null then
      if v_u.frete_raio_max_km is not null and v_dist > v_u.frete_raio_max_km then
        return jsonb_build_object(
          'fora_area', true,
          'distancia_km', round(v_dist::numeric, 2),
          'valor', 0,
          'previsao_entrega_min', null,
          'gratis', false,
          'mensagem', 'Endereço fora do raio de entrega da loja'
        );
      end if;
      v_valor := coalesce(v_u.taxa_entrega, 0);
    end if;
  else
    v_valor := coalesce(v_u.taxa_entrega, 0);
  end if;

  v_valor := round(greatest(coalesce(v_valor, 0), 0)::numeric, 2);
  v_eta := coalesce(v_u.prazo_entrega_min, 120)
    + ceil(coalesce(v_dist, 0) * coalesce(v_u.frete_tempo_km_min, 3))::int;

  return jsonb_build_object(
    'fora_area', false,
    'distancia_km', case when v_dist is null then null else round(v_dist::numeric, 2) end,
    'valor', v_valor,
    'previsao_entrega_min', v_eta,
    'gratis', v_gratis,
    'mensagem', null
  );
end $$;

create or replace function public.calcular_frete(
  p_unidade_id bigint,
  p_lat double precision,
  p_lng double precision,
  p_subtotal numeric default 0,
  p_todos_frete_gratis boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Faça login para calcular o frete';
  end if;

  return public.fn_calcular_frete_unidade(
    p_unidade_id, p_lat, p_lng, p_subtotal, p_todos_frete_gratis
  );
end $$;

revoke all on function public.calcular_frete(bigint, double precision, double precision, numeric, boolean) from public, anon;
grant execute on function public.calcular_frete(bigint, double precision, double precision, numeric, boolean) to authenticated;

-- Checkout v2: usa o checkout atômico existente e troca a taxa fixa pela
-- taxa calculada no servidor com a distância real do endereço.
create or replace function public.finalizar_checkout_v2(
  p_user_id uuid,
  p_itens jsonb,
  p_cupom_desconto_total numeric default 0,
  p_cupom_id bigint default null,
  p_tipo_entrega text default 'retirada',
  p_endereco_entrega text default null,
  p_cep_entrega text default null,
  p_endereco_lat double precision default null,
  p_endereco_lng double precision default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ret jsonb;
  v_linha record;
  v_item jsonb;
  v_frete jsonb;
  v_fretes jsonb := '{}'::jsonb;
  v_subtotal numeric;
  v_todos_gratis boolean;
  v_old_taxa numeric;
  v_new_taxa numeric;
  v_dist numeric;
  v_eta int;
  v_total numeric;
  v_cupom_unidade bigint;
begin
  if p_user_id is distinct from auth.uid() then
    raise exception 'Você não pode criar pedidos para outro usuário';
  end if;

  if jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception 'Carrinho vazio';
  end if;

  -- Cupom de loja só vale se o carrinho for daquela loja.
  if p_cupom_id is not null then
    select unidade_id into v_cupom_unidade
      from public.cupons
     where id = p_cupom_id;

    if v_cupom_unidade is not null then
      if exists (
        select 1
          from jsonb_array_elements(p_itens) as t(item)
          join public.produtos p on p.id = (t.item->>'produto_id')::bigint
         where coalesce(p.unidade_id, coalesce((t.item->>'unidade_id')::bigint, 1))
               <> v_cupom_unidade
      ) then
        raise exception 'Este cupom é válido apenas para a loja selecionada';
      end if;
    end if;
  end if;

  if p_tipo_entrega = 'entrega' then
    for v_linha in
      select coalesce(p.unidade_id, coalesce((t.item->>'unidade_id')::bigint, 1)) as unidade_id,
             sum(
               coalesce(
                 case when p.em_promocao and p.preco_promocional is not null
                      then p.preco_promocional else p.preco end,
                 0
               ) * (t.item->>'quantidade')::int
             ) as subtotal,
             bool_and(coalesce(p.frete_gratis, false)) as todos_gratis
        from jsonb_array_elements(p_itens) as t(item)
        join public.produtos p on p.id = (t.item->>'produto_id')::bigint
       group by 1
    loop
      if p_endereco_lat is null or p_endereco_lng is null then
        if exists (
          select 1 from public.unidades u
           where u.id = v_linha.unidade_id
             and u.frete_modo in ('distancia', 'faixas')
        ) then
          raise exception 'Calcule a entrega pelo endereço antes de finalizar o pedido';
        end if;
        v_frete := jsonb_build_object('fora_area', false, 'distancia_km', null, 'valor', null);
      else
        v_frete := public.fn_calcular_frete_unidade(
          v_linha.unidade_id,
          p_endereco_lat,
          p_endereco_lng,
          coalesce(v_linha.subtotal, 0),
          coalesce(v_linha.todos_gratis, false)
        );
      end if;

      if coalesce((v_frete->>'fora_area')::boolean, false) then
        raise exception 'Uma das lojas não entrega neste endereço. %', coalesce(v_frete->>'mensagem', '');
      end if;

      v_fretes := jsonb_set(v_fretes, array[v_linha.unidade_id::text], v_frete, true);
    end loop;
  end if;

  v_ret := public.finalizar_checkout(
    p_user_id,
    p_itens,
    p_cupom_desconto_total,
    p_cupom_id,
    p_tipo_entrega,
    p_endereco_entrega,
    p_cep_entrega
  );

  for v_linha in
    select value as item, ordinality as ord
      from jsonb_array_elements(v_ret) with ordinality
  loop
    v_item := v_linha.item;
    v_old_taxa := coalesce((v_item->>'taxa_entrega')::numeric, 0);
    v_new_taxa := v_old_taxa;
    v_dist := null;
    v_eta := null;

    if p_tipo_entrega = 'entrega' then
      v_frete := v_fretes -> (v_item->>'unidade_id');
      if v_frete is not null and (v_frete->>'valor') is not null then
        v_new_taxa := coalesce((v_frete->>'valor')::numeric, v_old_taxa);
        v_dist := (v_frete->>'distancia_km')::numeric;
        v_eta := (v_frete->>'previsao_entrega_min')::int;
      end if;
    end if;

    update public.pedidos
       set taxa_entrega = v_new_taxa,
           distancia_km = v_dist,
           previsao_entrega_min = v_eta,
           frete_detalhe = case when v_frete is null then null else v_frete end,
           total = greatest(coalesce(total, 0) - v_old_taxa + v_new_taxa, 0)
     where id = (v_item->>'id')::bigint;

    v_total := greatest(coalesce((v_item->>'total')::numeric, 0) - v_old_taxa + v_new_taxa, 0);

    v_item := jsonb_set(v_item, '{taxa_entrega}', to_jsonb(v_new_taxa));
    v_item := jsonb_set(v_item, '{total}', to_jsonb(v_total));
    if v_dist is not null then
      v_item := jsonb_set(v_item, '{distancia_km}', to_jsonb(v_dist));
    end if;
    if v_eta is not null then
      v_item := jsonb_set(v_item, '{previsao_entrega_min}', to_jsonb(v_eta));
    end if;

    v_ret := jsonb_set(v_ret, array[(v_linha.ord - 1)::text], v_item, true);
  end loop;

  return v_ret;
end $$;

revoke all on function public.finalizar_checkout_v2(
  uuid, jsonb, numeric, bigint, text, text, text, double precision, double precision
) from public, anon;
grant execute on function public.finalizar_checkout_v2(
  uuid, jsonb, numeric, bigint, text, text, text, double precision, double precision
) to authenticated;

-- ── 10) DASHBOARD ADMIN / LOJA ─────────────────────────────────────────

create or replace function public.dashboard_resumo(
  p_unidade_id bigint default null,
  p_dias int default 30
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_funcao text;
  v_unidade_usuario bigint;
  v_unidade bigint;
  v_dias int := greatest(least(coalesce(p_dias, 30), 365), 1);
  v_inicio timestamptz := now() - make_interval(days => greatest(least(coalesce(p_dias, 30), 365), 1) - 1);
  v_vendas_hoje numeric := 0;
  v_vendas_7d numeric := 0;
  v_vendas_30d numeric := 0;
  v_pedidos_abertos int := 0;
  v_pedidos_hoje int := 0;
  v_pedidos_periodo int := 0;
  v_cancelados int := 0;
  v_clientes_novos int := 0;
  v_estoque_baixo int := 0;
  v_entregas_atrasadas int := 0;
  v_ticket_medio numeric := 0;
  v_por_status jsonb := '{}'::jsonb;
  v_por_loja jsonb := '[]'::jsonb;
  v_top_produtos jsonb := '[]'::jsonb;
  v_serie_dias jsonb := '[]'::jsonb;
begin
  select funcao, unidade_id
    into v_funcao, v_unidade_usuario
    from public.perfis
   where id = auth.uid();

  if v_funcao is null then
    raise exception 'Perfil não encontrado';
  end if;

  if v_funcao = 'admin' then
    v_unidade := p_unidade_id;
  elsif v_funcao in ('gestor', 'atendente') then
    if p_unidade_id is not null and p_unidade_id <> v_unidade_usuario then
      raise exception 'Sem acesso a esta loja';
    end if;
    v_unidade := v_unidade_usuario;
  else
    raise exception 'Sem acesso ao dashboard';
  end if;

  select coalesce(sum(total), 0)
    into v_vendas_hoje
    from public.pedidos
   where created_at::date = current_date
     and status in ('pago', 'em_preparo', 'pronto_para_entrega', 'saiu_para_entrega', 'entregue')
     and (v_unidade is null or unidade_id = v_unidade);

  select coalesce(sum(total), 0)
    into v_vendas_7d
    from public.pedidos
   where created_at >= now() - interval '7 days'
     and status in ('pago', 'em_preparo', 'pronto_para_entrega', 'saiu_para_entrega', 'entregue')
     and (v_unidade is null or unidade_id = v_unidade);

  select coalesce(sum(total), 0)
    into v_vendas_30d
    from public.pedidos
   where created_at >= v_inicio
     and status in ('pago', 'em_preparo', 'pronto_para_entrega', 'saiu_para_entrega', 'entregue')
     and (v_unidade is null or unidade_id = v_unidade);

  select count(*)
    into v_pedidos_abertos
    from public.pedidos
   where status in ('pendente', 'pago', 'em_preparo', 'pronto_para_entrega', 'saiu_para_entrega')
     and (v_unidade is null or unidade_id = v_unidade);

  select count(*)
    into v_pedidos_hoje
    from public.pedidos
   where created_at::date = current_date
     and (v_unidade is null or unidade_id = v_unidade);

  select count(*)
    into v_pedidos_periodo
    from public.pedidos
   where created_at >= v_inicio
     and (v_unidade is null or unidade_id = v_unidade);

  select count(*)
    into v_cancelados
    from public.pedidos
   where created_at >= v_inicio
     and status = 'cancelado'
     and (v_unidade is null or unidade_id = v_unidade);

  select count(*)
    into v_clientes_novos
    from public.perfis
   where created_at >= v_inicio
     and funcao = 'usuario';

  select count(*)
    into v_estoque_baixo
    from public.produtos
   where coalesce(estoque, 0) <= 3
     and (v_unidade is null or unidade_id = v_unidade);

  select count(*)
    into v_entregas_atrasadas
    from public.pedidos
   where tipo_entrega = 'entrega'
     and status in ('pago', 'em_preparo', 'pronto_para_entrega', 'saiu_para_entrega')
     and (v_unidade is null or unidade_id = v_unidade)
     and created_at + make_interval(
       mins => coalesce(previsao_entrega_min, 120)
     ) < now();

  select case
           when count(*) = 0 then 0
           else round(sum(total) / count(*), 2)
         end
    into v_ticket_medio
    from public.pedidos
   where created_at >= v_inicio
     and status in ('pago', 'em_preparo', 'pronto_para_entrega', 'saiu_para_entrega', 'entregue')
     and (v_unidade is null or unidade_id = v_unidade);

  select coalesce(jsonb_object_agg(status, qtd), '{}'::jsonb)
    into v_por_status
    from (
      select status, count(*)::int as qtd
        from public.pedidos
       where created_at >= v_inicio
         and (v_unidade is null or unidade_id = v_unidade)
       group by status
    ) s;

  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'unidade_id', x.unidade_id,
               'nome', x.nome,
               'pedidos', x.pedidos,
               'receita', x.receita
             )
             order by x.receita desc
           ),
           '[]'::jsonb
         )
    into v_por_loja
    from (
      select p.unidade_id,
             coalesce(u.nome, 'Loja') as nome,
             count(*)::int as pedidos,
             round(coalesce(sum(p.total), 0), 2) as receita
        from public.pedidos p
        left join public.unidades u on u.id = p.unidade_id
       where p.created_at >= v_inicio
         and p.status in ('pago', 'em_preparo', 'pronto_para_entrega', 'saiu_para_entrega', 'entregue')
         and (v_unidade is null or p.unidade_id = v_unidade)
       group by p.unidade_id, u.nome
    ) x;

  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'produto_id', x.produto_id,
               'nome', x.nome,
               'quantidade', x.quantidade,
               'receita', x.receita
             )
             order by x.quantidade desc
           ),
           '[]'::jsonb
         )
    into v_top_produtos
    from (
      select i.produto_id,
             coalesce(pr.nome, 'Produto') as nome,
             sum(i.quantidade)::int as quantidade,
             round(sum(i.quantidade * coalesce(i.preco_unitario, 0)), 2) as receita
        from public.pedido_itens i
        join public.pedidos p on p.id = i.pedido_id
        left join public.produtos pr on pr.id = i.produto_id
       where p.created_at >= v_inicio
         and p.status in ('pago', 'em_preparo', 'pronto_para_entrega', 'saiu_para_entrega', 'entregue')
         and (v_unidade is null or p.unidade_id = v_unidade)
       group by i.produto_id, pr.nome
       order by quantidade desc
       limit 8
    ) x;

  select coalesce(
           jsonb_agg(
             jsonb_build_object('dia', d::date, 'total', coalesce(x.total, 0))
             order by d
           ),
           '[]'::jsonb
         )
    into v_serie_dias
    from generate_series(current_date - (v_dias - 1), current_date, interval '1 day') d
    left join (
      select created_at::date as dia, round(sum(total), 2) as total
        from public.pedidos
       where created_at >= v_inicio
         and status in ('pago', 'em_preparo', 'pronto_para_entrega', 'saiu_para_entrega', 'entregue')
         and (v_unidade is null or unidade_id = v_unidade)
       group by created_at::date
    ) x on x.dia = d::date;

  return jsonb_build_object(
    'unidade_id', v_unidade,
    'dias', v_dias,
    'vendas_hoje', v_vendas_hoje,
    'vendas_7d', v_vendas_7d,
    'vendas_30d', v_vendas_30d,
    'pedidos_abertos', v_pedidos_abertos,
    'pedidos_hoje', v_pedidos_hoje,
    'pedidos_periodo', v_pedidos_periodo,
    'cancelados', v_cancelados,
    'clientes_novos', v_clientes_novos,
    'estoque_baixo', v_estoque_baixo,
    'entregas_atrasadas', v_entregas_atrasadas,
    'ticket_medio', v_ticket_medio,
    'por_status', v_por_status,
    'por_loja', v_por_loja,
    'top_produtos', v_top_produtos,
    'serie_dias', v_serie_dias
  );
end $$;

revoke all on function public.dashboard_resumo(bigint, int) from public, anon;
grant execute on function public.dashboard_resumo(bigint, int) to authenticated;

-- ── 11) ÍNDICES E NOTIFY ───────────────────────────────────────────────

create index if not exists idx_pedidos_unidade_created on public.pedidos(unidade_id, created_at desc);
create index if not exists idx_enderecos_coords on public.enderecos_usuario(latitude, longitude)
  where latitude is not null and longitude is not null;

-- ── 12) PEDIDOS DO MERCADO LIVRE: PERMITE STATUS VINDO DO SERVIDOR ────
-- O checkout normal continua obrigando "pendente" e validando todas as
-- transições. Pedidos importados do ML podem entrar como pagos e ter o status
-- sincronizado pelo webhook (service_role, sem auth.uid).

create or replace function public.fn_pedido_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_funcao text;
  v_unidade int;
  v_item record;
  v_estoque int;
begin
  v_funcao := coalesce((select funcao from public.perfis where id = v_uid), '');
  v_unidade := (select unidade_id from public.perfis where id = v_uid);

  if tg_op = 'INSERT' and new.origem = 'mercadolivre' then
    if new.desconto_cupom is null then
      new.desconto_cupom := 0;
    end if;
    if new.status = 'pago' then
      new.pago_em := coalesce(new.pago_em, now());
    end if;
    insert into public.pedido_historico (pedido_id, status, alterado_por)
    values (new.id, new.status, v_uid);
    return new;
  end if;

  if tg_op = 'UPDATE' and old.origem = 'mercadolivre' and auth.uid() is null then
    if new.status is distinct from old.status then
      if new.status = 'cancelado' then
        if exists (
          select 1 from public.estoque_movimentacoes
           where pedido_id = old.id and tipo = 'venda'
        ) and not exists (
          select 1 from public.estoque_movimentacoes
           where pedido_id = old.id and tipo = 'devolucao'
        ) then
          for v_item in select * from public.pedido_itens where pedido_id = old.id loop
            update public.produtos
               set estoque = estoque + v_item.quantidade
             where id = v_item.produto_id;

            insert into public.estoque_movimentacoes
              (produto_id, pedido_id, tipo, quantidade, motivo, criado_por)
            values
              (v_item.produto_id, old.id, 'devolucao', v_item.quantidade,
               'Cancelamento Mercado Livre do pedido ' || old.id, null);
          end loop;
        end if;
        new.cancelado_em := now();
      elsif new.status = 'entregue' then
        new.entregue_em := now();
      end if;

      insert into public.pedido_historico (pedido_id, status, alterado_por)
      values (old.id, new.status, null);
    end if;

    new.updated_at := now();
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.status := 'pendente';
    if new.desconto_cupom is null then
      new.desconto_cupom := 0;
    end if;
    insert into public.pedido_historico (pedido_id, status, alterado_por)
    values (new.id, 'pendente', v_uid);
    return new;
  end if;

  if new.status = old.status and new.entregador_id is distinct from old.entregador_id then
    if v_funcao not in ('admin', 'atendente') then
      raise exception 'Somente a loja pode atribuir entregador';
    end if;
    if v_funcao = 'atendente' and v_unidade is distinct from old.unidade_id then
      raise exception 'Sem permissão para pedidos de outra unidade';
    end if;
    return new;
  end if;

  if new.status = old.status then return new; end if;

  if new.status = 'cancelado' then
    if v_uid is null then
      null;
    elsif v_uid = old.user_id then
      if old.status not in ('pendente', 'pago', 'em_preparo') then
        raise exception 'O pedido já saiu para entrega; somente a loja pode cancelar';
      end if;
    elsif v_funcao = 'admin' then
      null;
    elsif v_funcao = 'atendente' and v_unidade = old.unidade_id then
      null;
    else
      raise exception 'Sem permissão para cancelar este pedido';
    end if;

    if exists (
      select 1 from public.estoque_movimentacoes
       where pedido_id = old.id and tipo = 'venda'
    ) and not exists (
      select 1 from public.estoque_movimentacoes
       where pedido_id = old.id and tipo = 'devolucao'
    ) then
      for v_item in select * from public.pedido_itens where pedido_id = old.id loop
        update public.produtos
           set estoque = estoque + v_item.quantidade
         where id = v_item.produto_id;

        insert into public.estoque_movimentacoes
          (produto_id, pedido_id, tipo, quantidade, motivo, criado_por)
        values
          (v_item.produto_id, old.id, 'devolucao', v_item.quantidade,
           'Cancelamento do pedido ' || old.id, v_uid);
      end loop;
    end if;

    new.cancelado_em := now();
    insert into public.pedido_historico (pedido_id, status, alterado_por)
    values (old.id, 'cancelado', v_uid);
    return new;
  end if;

  if new.status = 'pago' then
    if old.status <> 'pendente' then
      raise exception 'Transição inválida: % para pago', old.status;
    end if;
    if v_uid <> old.user_id and v_funcao <> 'admin' then
      raise exception 'Apenas o cliente dono ou o admin podem confirmar o pagamento';
    end if;

    if not exists (
      select 1 from public.estoque_movimentacoes
       where pedido_id = old.id and tipo = 'venda'
    ) then
      for v_item in select * from public.pedido_itens where pedido_id = old.id loop
        select estoque into v_estoque
          from public.produtos where id = v_item.produto_id for update;
        if v_estoque is null then
          raise exception 'Produto % não encontrado', v_item.produto_id;
        end if;
        if v_estoque < v_item.quantidade then
          raise exception 'Estoque insuficiente para "%" (disponível: %, pedido: %)',
            (select nome from public.produtos where id = v_item.produto_id),
            v_estoque, v_item.quantidade;
        end if;
        update public.produtos
           set estoque = v_estoque - v_item.quantidade
         where id = v_item.produto_id;

        insert into public.estoque_movimentacoes
          (produto_id, pedido_id, tipo, quantidade, motivo, criado_por)
        values
          (v_item.produto_id, old.id, 'venda', -v_item.quantidade,
           'Venda do pedido ' || old.id, v_uid);
      end loop;
    end if;

    new.pago_em := now();
    insert into public.pedido_historico (pedido_id, status, alterado_por)
    values (old.id, 'pago', v_uid);

    new.status := 'em_preparo';
    insert into public.pedido_historico (pedido_id, status, alterado_por)
    values (old.id, 'em_preparo', v_uid);
    return new;
  end if;

  if new.status = 'pronto_para_entrega' then
    if old.status <> 'em_preparo' then
      raise exception 'Transição inválida: % para pronto_para_entrega', old.status;
    end if;
    if v_funcao not in ('admin', 'atendente') then
      raise exception 'Somente a loja pode marcar pronto para entrega';
    end if;
    if v_funcao = 'atendente' and v_unidade is distinct from old.unidade_id then
      raise exception 'Sem permissão para pedidos de outra unidade';
    end if;
    if old.tipo_entrega <> 'retirada' and new.entregador_id is null then
      raise exception 'Atribua um entregador antes de marcar pronto para entrega';
    end if;
  elsif new.status = 'saiu_para_entrega' then
    if old.status <> 'pronto_para_entrega' then
      raise exception 'Transição inválida: % para saiu_para_entrega', old.status;
    end if;
    if v_uid is distinct from old.entregador_id and v_funcao <> 'admin' then
      raise exception 'Somente o entregador atribuído pode iniciar a entrega';
    end if;
  elsif new.status = 'entregue' then
    if old.tipo_entrega = 'retirada' then
      if old.status <> 'pronto_para_entrega' then
        raise exception 'Transição inválida: % para entregue (retirada)', old.status;
      end if;
      if v_funcao not in ('admin', 'atendente') then
        raise exception 'Somente a loja pode confirmar a retirada';
      end if;
      if v_funcao = 'atendente' and v_unidade is distinct from old.unidade_id then
        raise exception 'Sem permissão para pedidos de outra unidade';
      end if;
    else
      if old.status <> 'saiu_para_entrega' then
        raise exception 'Transição inválida: % para entregue', old.status;
      end if;
      if v_uid is distinct from old.entregador_id and v_funcao <> 'admin' then
        raise exception 'Somente o entregador atribuído pode confirmar a entrega';
      end if;
      if new.recebedor_nome is null or length(trim(new.recebedor_nome)) = 0 then
        raise exception 'Informe o nome de quem recebeu';
      end if;
    end if;
    new.entregue_em := now();
  else
    raise exception 'Transição não permitida: % para %', old.status, new.status;
  end if;

  insert into public.pedido_historico (pedido_id, status, alterado_por)
  values (old.id, new.status, v_uid);
  new.updated_at := now();
  return new;
end $$;

notify pgrst, 'reload schema';

commit;
