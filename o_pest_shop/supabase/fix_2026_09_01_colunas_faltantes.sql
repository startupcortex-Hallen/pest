-- =====================================================================
-- O Pest - Shop | Corrige colunas que o app usa e NAO existiam no banco.
-- Rodar no Supabase > SQL Editor (pode rodar mais de uma vez, e idempotente).
-- =====================================================================

-- 1) "Frete gratis" do card do produto nunca aparecia porque a coluna nao existia.
alter table public.produtos
  add column if not exists frete_gratis boolean not null default false;

-- 2) A tela de Favoritos quebrava: o app ordena por created_at e a coluna nao existia.
alter table public.favoritos
  add column if not exists created_at timestamptz not null default now();

-- 3) Mesmo problema na listagem de Assinaturas.
alter table public.assinaturas
  add column if not exists created_at timestamptz not null default now();

-- 4) Chat com profissional usava conversas.profissional_id (join com perfis).
alter table public.conversas
  add column if not exists profissional_id uuid references public.perfis(id) on delete set null;

-- 5) Indices de apoio para as consultas mais comuns.
create index if not exists idx_favoritos_user            on public.favoritos(user_id);
create index if not exists idx_assinaturas_user          on public.assinaturas(user_id);
create index if not exists idx_conversas_profissional    on public.conversas(profissional_id);
create index if not exists idx_carrinho_user             on public.carrinho(user_id);
create index if not exists idx_pedidos_user              on public.pedidos(user_id);
create index if not exists idx_pedidos_unidade           on public.pedidos(unidade_id);
create index if not exists idx_pedido_itens_pedido       on public.pedido_itens(pedido_id);

-- 6) Carrinho: evita duplicar a mesma linha quando nao ha cor informada.
--    (No Postgres NULL e distinto de NULL, entao o UNIQUE nao protegia.)
create unique index if not exists uq_carrinho_user_produto_coresem_null
  on public.carrinho(user_id, produto_id)
  where cor is null;
