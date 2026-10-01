-- ═══════════════════════════════════════════════════════════════════════
-- O PEST - SHOP · CONSOLIDAÇÃO FINAL DO BANCO (script único)
-- ═══════════════════════════════════════════════════════════════════════
-- O QUE ESTE SCRIPT FAZ (visão geral):
--   1. Garante TODAS as colunas que o app usa (produtos, pedidos, unidades...)
--   2. Corrige cartões (mes/ano_validade texto → inteiro) e unidades (slug)
--   3. Recria as funções/triggers na versão FINAL (preço real, cupom,
--      máquina de estados, proteção de admin, estoque)
--   4. Recria as RPCs que o app chama (checkout, pagamento, status, entregador)
--   5. Consolida o RLS: fecha furos, liga RLS nas tabelas que estavam sem,
--      corrige recursão e adiciona as 14 tabelas de academia/nutrição
--   6. Liga o Realtime (pedidos, pedido_historico e MENSAGENS/chat)
--   7. Triggers de signup (perfil automático) + backfill
--   8. Índices e constraints que faltam
--
-- COMO USAR: Supabase > SQL Editor > cole o arquivo inteiro > RUN.
-- É IDEMPOTENTE: pode rodar de novo sem duplicar nada.
-- Ao final, siga o PASSO 2 (promover o primeiro admin) que está no fim.
-- ═══════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════
-- 0) HELPERS TEMPORÁRIOS (removidos no fim do script)
-- ═══════════════════════════════════════════════════════════════════════

create or replace function public._cons_ensure_policy(p_table text, p_policy text, p_sql text)
returns void
language plpgsql
as $$
begin
  if to_regclass('public.' || p_table) is null then
    return;
  end if;
  if not exists (
    select 1 from pg_policy
    where polname = p_policy and polrelid = ('public.' || p_table)::regclass
  ) then
    execute p_sql;
  end if;
end $$;

create or replace function public._cons_drop_policy(p_table text, p_policy text)
returns void
language plpgsql
as $$
begin
  if to_regclass('public.' || p_table) is null then
    return;
  end if;
  execute format('drop policy if exists %I on public.%I', p_policy, p_table);
end $$;

create or replace function public._cons_ensure_fk(
  p_table text, p_column text, p_ref_table text, p_ref_column text, p_on_delete text
)
returns void
language plpgsql
as $$
begin
  if to_regclass('public.' || p_table) is null or to_regclass('public.' || p_ref_table) is null then
    return;
  end if;
  if exists (
    select 1
    from pg_constraint c
    join pg_attribute a on a.attrelid = c.conrelid and a.attnum = any(c.conkey)
    where c.contype = 'f'
      and c.conrelid = ('public.' || p_table)::regclass
      and c.confrelid = ('public.' || p_ref_table)::regclass
      and a.attname = p_column
  ) then
    return;
  end if;
  execute format(
    'alter table public.%I add constraint %I foreign key (%I) references public.%I(%I) on delete %s not valid',
    p_table, p_table || '_' || p_column || '_fkey', p_column, p_ref_table, p_ref_column, p_on_delete
  );
end $$;

-- ═══════════════════════════════════════════════════════════════════════
-- 1) COLUNAS QUE O APP USA E PODEM NÃO EXISTIR
-- ═══════════════════════════════════════════════════════════════════════

-- Produtos
alter table public.produtos add column if not exists frete_gratis boolean not null default false;
alter table public.produtos add column if not exists cores text[];
alter table public.produtos add column if not exists vendas int default 0;
alter table public.produtos add column if not exists percentual_desconto numeric;
alter table public.produtos add column if not exists garantia text;
alter table public.produtos add column if not exists parcelas int;
alter table public.produtos add column if not exists preco_promocional numeric;
alter table public.produtos add column if not exists em_promocao boolean default false;

-- Carrinho / itens: cor
alter table public.carrinho add column if not exists cor text;
alter table public.pedido_itens add column if not exists cor text;

-- Favoritos / assinaturas: created_at
alter table public.favoritos add column if not exists created_at timestamptz not null default now();
alter table public.assinaturas add column if not exists created_at timestamptz not null default now();

-- Conversas: chat com profissional
alter table public.conversas add column if not exists profissional_id uuid;

-- Pedidos: entrega, pagamento e cupom
alter table public.pedidos add column if not exists tipo_entrega text default 'retirada';
alter table public.pedidos add column if not exists endereco_entrega text;
alter table public.pedidos add column if not exists cep_entrega text;
alter table public.pedidos add column if not exists recebedor_nome text;
alter table public.pedidos add column if not exists entregador_id uuid;
alter table public.pedidos add column if not exists pago_em timestamptz;
alter table public.pedidos add column if not exists entregue_em timestamptz;
alter table public.pedidos add column if not exists cancelado_em timestamptz;
alter table public.pedidos add column if not exists updated_at timestamptz default now();
alter table public.pedidos add column if not exists transacao_id text;
alter table public.pedidos add column if not exists pagamento_detalhes text;
alter table public.pedidos add column if not exists pix_copia_cola text;
alter table public.pedidos add column if not exists pagamento text;
-- NOVO: desconto do cupom fica gravado no pedido (auditável e recalculável)
alter table public.pedidos add column if not exists desconto_cupom numeric not null default 0;
alter table public.pedidos add column if not exists cupom_id bigint;

-- Unidades
alter table public.unidades add column if not exists slug text;
alter table public.unidades add column if not exists logo_url text;
alter table public.unidades add column if not exists pix_key text;
alter table public.unidades add column if not exists pix_nome text;
alter table public.unidades add column if not exists latitude double precision;
alter table public.unidades add column if not exists longitude double precision;
alter table public.unidades add column if not exists ordem int;
alter table public.unidades add column if not exists distancia text;
alter table public.unidades add column if not exists prazo_retirada_min int default 60;
alter table public.unidades add column if not exists prazo_entrega_min int default 120;

-- Perfis
alter table public.perfis add column if not exists codigo text;
alter table public.perfis add column if not exists pontos int default 0;
alter table public.perfis add column if not exists objetivo text;
alter table public.perfis add column if not exists telefone text;
alter table public.perfis add column if not exists avatar_url text;
alter table public.perfis add column if not exists nome_completo text;
alter table public.perfis add column if not exists cpf text;

-- Histórico de pedidos: o app lê "criado_em"; outras bases usam "created_at".
-- Garante as DUAS com default para não quebrar a timeline em nenhum banco.
alter table public.pedido_historico add column if not exists criado_em timestamptz;
alter table public.pedido_historico add column if not exists created_at timestamptz;
alter table public.pedido_historico alter column criado_em set default now();
alter table public.pedido_historico alter column created_at set default now();
update public.pedido_historico set criado_em = created_at where criado_em is null and created_at is not null;
update public.pedido_historico set created_at = criado_em where created_at is null and criado_em is not null;

-- Movimentações de estoque: idem (defesa)
alter table public.estoque_movimentacoes add column if not exists criado_em timestamptz;
alter table public.estoque_movimentacoes add column if not exists created_at timestamptz;
alter table public.estoque_movimentacoes alter column criado_em set default now();
alter table public.estoque_movimentacoes alter column created_at set default now();

-- Índices de apoio
create index if not exists idx_favoritos_user         on public.favoritos(user_id);
create index if not exists idx_assinaturas_user       on public.assinaturas(user_id);
create index if not exists idx_conversas_profissional on public.conversas(profissional_id);
create index if not exists idx_carrinho_user          on public.carrinho(user_id);
create index if not exists idx_pedidos_user           on public.pedidos(user_id);
create index if not exists idx_pedidos_unidade        on public.pedidos(unidade_id);
create index if not exists idx_pedido_itens_pedido    on public.pedido_itens(pedido_id);
create index if not exists idx_pedidos_status         on public.pedidos(status);
create index if not exists idx_pedidos_entregador     on public.pedidos(entregador_id) where entregador_id is not null;
create index if not exists idx_pedido_itens_produto   on public.pedido_itens(produto_id);
create index if not exists idx_carrinho_user_produto_cor on public.carrinho(user_id, produto_id, cor);

-- ═══════════════════════════════════════════════════════════════════════
-- 2) CARTÕES: mes/ano_validade como INTEIRO (o app faz cast para int)
-- ═══════════════════════════════════════════════════════════════════════

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'cartoes_usuario'
      and column_name = 'mes_validade' and data_type in ('text','character varying','numeric')
  ) then
    alter table public.cartoes_usuario
      alter column mes_validade type int
      using nullif(regexp_replace(coalesce(mes_validade::text, ''), '\D', '', 'g'), '')::int;
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'cartoes_usuario'
      and column_name = 'ano_validade' and data_type in ('text','character varying','numeric')
  ) then
    alter table public.cartoes_usuario
      alter column ano_validade type int
      using nullif(regexp_replace(coalesce(ano_validade::text, ''), '\D', '', 'g'), '')::int;
  end if;
end $$;

update public.cartoes_usuario set mes_validade = 1    where mes_validade is null;
update public.cartoes_usuario set ano_validade = 2030 where ano_validade is null;

-- ═══════════════════════════════════════════════════════════════════════
-- 3) UNIDADES: slug opcional + gerado automaticamente
--    (o formulário do admin não envia slug; o insert falhava)
-- ═══════════════════════════════════════════════════════════════════════

do $$
begin
  if exists (
    select 1 from pg_attribute
    where attrelid = 'public.unidades'::regclass and attname = 'slug' and attnotnull
  ) then
    alter table public.unidades alter column slug drop not null;
  end if;
end $$;

create or replace function public.fn_unidade_slug()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_base text;
begin
  if new.slug is null or btrim(new.slug) = '' then
    v_base := trim(both '-' from lower(regexp_replace(coalesce(new.nome, 'loja'), '[^a-zA-Z0-9]+', '-', 'g')));
    if v_base = '' then
      v_base := 'loja';
    end if;

    new.slug := v_base;
    if exists (select 1 from public.unidades where slug = new.slug and id is distinct from new.id) then
      new.slug := v_base || '-' || substr(md5(random()::text), 1, 6);
    end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_unidade_slug on public.unidades;
create trigger trg_unidade_slug
  before insert or update on public.unidades
  for each row execute function public.fn_unidade_slug();

-- Preenche slugs vazios de registros existentes (sem quebrar em colisão)
do $$
declare
  r record;
  v_base text;
begin
  for r in select id, nome from public.unidades where coalesce(btrim(slug), '') = '' loop
    v_base := trim(both '-' from lower(regexp_replace(coalesce(r.nome, 'loja'), '[^a-zA-Z0-9]+', '-', 'g')));
    if v_base = '' then
      v_base := 'loja';
    end if;
    begin
      update public.unidades set slug = v_base where id = r.id;
    exception when unique_violation then
      update public.unidades set slug = v_base || '-' || r.id where id = r.id;
    end;
  end loop;
end $$;

-- ═══════════════════════════════════════════════════════════════════════
-- 4) FOREIGN KEYS QUE FALTAM (embeds do app: posts/perfis/pedidos)
-- ═══════════════════════════════════════════════════════════════════════

do $$
begin
  -- posts_feed precisa do join com perfis (autor do post)
  perform public._cons_ensure_fk('posts_feed', 'user_id', 'perfis', 'id', 'set null');
  -- itens do pedido → produtos (detalhe do pedido)
  perform public._cons_ensure_fk('pedido_itens', 'produto_id', 'produtos', 'id', 'no action');
  -- chat → perfis
  perform public._cons_ensure_fk('mensagens', 'remetente_id', 'perfis', 'id', 'cascade');
  perform public._cons_ensure_fk('conversas', 'usuario_id', 'perfis', 'id', 'cascade');
  perform public._cons_ensure_fk('conversas', 'profissional_id', 'perfis', 'id', 'set null');
  -- pedido → perfis (join usado no painel do entregador/admin)
  perform public._cons_ensure_fk('pedidos', 'user_id', 'perfis', 'id', 'cascade');
  perform public._cons_ensure_fk('pedidos', 'entregador_id', 'perfis', 'id', 'set null');
end $$;

-- ═══════════════════════════════════════════════════════════════════════
-- 5) SEGURANÇA: ninguém vira admin sozinho; status "pago" protegido
-- ═══════════════════════════════════════════════════════════════════════

create or replace function public.funcao_usuario()
returns text
language sql
security definer
set search_path = public
stable
as $$
  select funcao from public.perfis where id = auth.uid();
$$;

grant execute on function public.funcao_usuario() to authenticated;

create or replace function public.protege_funcao_perfil()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_funcao_atual text;
begin
  if tg_op = 'INSERT' then
    -- No cadastro o usuário só pode nascer como cliente/usuario (ou null).
    -- Admin/service_role podem criar qualquer papel.
    if coalesce(new.funcao, 'cliente') not in ('cliente','usuario','') then
      select funcao into v_funcao_atual from public.perfis where id = auth.uid();
      if coalesce(v_funcao_atual, '') <> 'admin' and auth.uid() is not null then
        raise exception 'Somente admin pode criar perfil com essa funcao'
          using errcode = '42501';
      end if;
    end if;
    return new;
  end if;

  if new.funcao is distinct from old.funcao
     or new.unidade_id is distinct from old.unidade_id then

    select funcao into v_funcao_atual
    from public.perfis
    where id = auth.uid();

    -- admin pode tudo; service_role (sem JWT, ex.: SQL Editor) também.
    if coalesce(v_funcao_atual, '') <> 'admin' and auth.uid() is not null then
      raise exception 'Somente admin pode alterar funcao ou unidade de um perfil'
        using errcode = '42501';
    end if;
  end if;

  return new;
end $$;

drop trigger if exists trg_protege_funcao_perfil on public.perfis;
create trigger trg_protege_funcao_perfil
  before insert or update on public.perfis
  for each row execute function public.protege_funcao_perfil();

create or replace function public.protege_status_pago()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_funcao text;
begin
  -- service_role / webhook (sem auth.uid) pode marcar como pago
  if auth.uid() is null then
    return new;
  end if;

  if new.status = 'pago' and old.status is distinct from 'pago' then
    select funcao into v_funcao from public.perfis where id = auth.uid();
    if coalesce(v_funcao, '') not in ('admin', 'atendente', 'gestor') then
      raise exception 'Pagamento so pode ser confirmado pelo servidor'
        using errcode = '42501';
    end if;
  end if;

  return new;
end $$;

drop trigger if exists trg_protege_status_pago on public.pedidos;
create trigger trg_protege_status_pago
  before update on public.pedidos
  for each row execute function public.protege_status_pago();

-- Limpeza: cartões que guardaram número completo (mantém só os 4 últimos dígitos)
update public.cartoes_usuario
   set numero_mascarado = '**** **** **** ' || right(regexp_replace(numero_mascarado, '\D', '', 'g'), 4)
 where numero_mascarado is not null
   and numero_mascarado !~ '^\*'
   and length(regexp_replace(numero_mascarado, '\D', '', 'g')) >= 4;

-- ═══════════════════════════════════════════════════════════════════════
-- 6) PREÇO E TOTAL SEMPRE VÊM DO BANCO (+ CUPOM CORRETO)
-- ═══════════════════════════════════════════════════════════════════════

-- 6.1) O preço unitário do item é reescrito com o preço REAL do produto
create or replace function public.fn_pedido_item_preco_real()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_preco numeric;
begin
  select case
           when p.em_promocao and p.preco_promocional is not null then p.preco_promocional
           else p.preco
         end
    into v_preco
  from public.produtos p
  where p.id = new.produto_id;

  if v_preco is not null then
    new.preco_unitario := v_preco;
  end if;

  return new;
end $$;

drop trigger if exists trg_pedido_item_preco_real on public.pedido_itens;
create trigger trg_pedido_item_preco_real
  before insert on public.pedido_itens
  for each row execute function public.fn_pedido_item_preco_real();

-- 6.2) Total recalculado pelo servidor: soma dos itens MENOS o desconto do
--      cupom gravado no pedido (antes o desconto era descartado).
create or replace function public.fn_recalcula_total_pedido()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pedido bigint;
begin
  v_pedido := coalesce(new.pedido_id, old.pedido_id);

  update public.pedidos p
     set total = greatest(
           coalesce((
             select sum(i.quantidade * i.preco_unitario)
             from public.pedido_itens i
             where i.pedido_id = v_pedido
           ), 0) - coalesce(p.desconto_cupom, 0),
           0)
   where p.id = v_pedido;

  return null;
end $$;

drop trigger if exists trg_recalcula_total_pedido on public.pedido_itens;
create trigger trg_recalcula_total_pedido
  after insert or update or delete on public.pedido_itens
  for each row execute function public.fn_recalcula_total_pedido();

-- ═══════════════════════════════════════════════════════════════════════
-- 7) MÁQUINA DE ESTADOS DO PEDIDO (versão final, com retirada na unidade)
-- ═══════════════════════════════════════════════════════════════════════

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

  if tg_op = 'INSERT' then
    new.status := 'pendente';
    if new.desconto_cupom is null then
      new.desconto_cupom := 0;
    end if;
    insert into public.pedido_historico (pedido_id, status, alterado_por) values (new.id, 'pendente', v_uid);
    return new;
  end if;

  if new.status = old.status and new.entregador_id is distinct from old.entregador_id then
    if v_funcao not in ('admin','atendente') then
      raise exception 'Somente a loja pode atribuir entregador';
    end if;
    if v_funcao = 'atendente' and v_unidade is distinct from old.unidade_id then
      raise exception 'Sem permissão para pedidos de outra unidade';
    end if;
    return new;
  end if;

  if new.status = old.status then return new; end if;

  if new.status = 'cancelado' then
    if v_uid = old.user_id then
      if old.status not in ('pendente','pago','em_preparo') then
        raise exception 'O pedido já saiu para entrega; somente a loja pode cancelar';
      end if;
    elsif v_funcao = 'admin' then
      null;
    elsif v_funcao = 'atendente' and v_unidade = old.unidade_id then
      null;
    else
      raise exception 'Sem permissão para cancelar este pedido';
    end if;

    if exists (select 1 from public.estoque_movimentacoes where pedido_id = old.id and tipo = 'venda')
       and not exists (select 1 from public.estoque_movimentacoes where pedido_id = old.id and tipo = 'devolucao') then
      for v_item in select * from public.pedido_itens where pedido_id = old.id loop
        update public.produtos set estoque = estoque + v_item.quantidade where id = v_item.produto_id;
        insert into public.estoque_movimentacoes (produto_id, pedido_id, tipo, quantidade, motivo, criado_por)
        values (v_item.produto_id, old.id, 'devolucao', v_item.quantidade,
                'Cancelamento do pedido ' || old.id, v_uid);
      end loop;
    end if;
    new.cancelado_em := now();
    insert into public.pedido_historico (pedido_id, status, alterado_por) values (old.id, 'cancelado', v_uid);
    return new;
  end if;

  if new.status = 'pago' then
    if old.status <> 'pendente' then
      raise exception 'Transição inválida: % → pago', old.status;
    end if;
    if v_uid <> old.user_id and v_funcao <> 'admin' then
      raise exception 'Apenas o cliente dono ou o admin podem confirmar o pagamento';
    end if;

    if not exists (select 1 from public.estoque_movimentacoes where pedido_id = old.id and tipo = 'venda') then
      for v_item in select * from public.pedido_itens where pedido_id = old.id loop
        select estoque into v_estoque from public.produtos where id = v_item.produto_id for update;
        if v_estoque is null then
          raise exception 'Produto % não encontrado', v_item.produto_id;
        end if;
        if v_estoque < v_item.quantidade then
          raise exception 'Estoque insuficiente para "%" (disponível: %, pedido: %)',
            (select nome from public.produtos where id = v_item.produto_id), v_estoque, v_item.quantidade;
        end if;
        update public.produtos set estoque = v_estoque - v_item.quantidade where id = v_item.produto_id;
        insert into public.estoque_movimentacoes (produto_id, pedido_id, tipo, quantidade, motivo, criado_por)
        values (v_item.produto_id, old.id, 'venda', -v_item.quantidade,
                'Venda do pedido ' || old.id, v_uid);
      end loop;
    end if;

    new.pago_em := now();
    insert into public.pedido_historico (pedido_id, status, alterado_por) values (old.id, 'pago', v_uid);

    new.status := 'em_preparo';
    insert into public.pedido_historico (pedido_id, status, alterado_por) values (old.id, 'em_preparo', v_uid);
    return new;
  end if;

  if new.status = 'pronto_para_entrega' then
    if old.status <> 'em_preparo' then
      raise exception 'Transição inválida: % → pronto_para_entrega', old.status;
    end if;
    if v_funcao not in ('admin','atendente') then
      raise exception 'Somente a loja pode marcar pronto para entrega';
    end if;
    if v_funcao = 'atendente' and v_unidade is distinct from old.unidade_id then
      raise exception 'Sem permissão para pedidos de outra unidade';
    end if;
    -- Retirada não precisa de entregador; entrega sim
    if old.tipo_entrega <> 'retirada' and new.entregador_id is null then
      raise exception 'Atribua um entregador antes de marcar pronto para entrega';
    end if;
  elsif new.status = 'saiu_para_entrega' then
    if old.status <> 'pronto_para_entrega' then
      raise exception 'Transição inválida: % → saiu_para_entrega', old.status;
    end if;
    if v_uid is distinct from old.entregador_id then
      raise exception 'Somente o entregador atribuído pode iniciar a entrega';
    end if;
  elsif new.status = 'entregue' then
    if old.tipo_entrega = 'retirada' then
      if old.status <> 'pronto_para_entrega' then
        raise exception 'Transição inválida: % → entregue (retirada)', old.status;
      end if;
      if v_funcao not in ('admin','atendente') then
        raise exception 'Somente a loja pode confirmar a retirada';
      end if;
      if v_funcao = 'atendente' and v_unidade is distinct from old.unidade_id then
        raise exception 'Sem permissão para pedidos de outra unidade';
      end if;
    else
      if old.status <> 'saiu_para_entrega' then
        raise exception 'Transição inválida: % → entregue', old.status;
      end if;
      if v_uid is distinct from old.entregador_id then
        raise exception 'Somente o entregador atribuído pode confirmar a entrega';
      end if;
      if new.recebedor_nome is null or length(trim(new.recebedor_nome)) = 0 then
        raise exception 'Informe o nome de quem recebeu';
      end if;
    end if;
    new.entregue_em := now();
  else
    raise exception 'Transição não permitida: % → %', old.status, new.status;
  end if;

  insert into public.pedido_historico (pedido_id, status, alterado_por) values (old.id, new.status, v_uid);
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists trg_pedido_status on public.pedidos;
create trigger trg_pedido_status
  before insert or update on public.pedidos
  for each row execute function public.fn_pedido_status();

-- ═══════════════════════════════════════════════════════════════════════
-- 8) RPCs QUE O APP CHAMA (remove versões antigas/conflitantes e recria)
-- ═══════════════════════════════════════════════════════════════════════

drop function if exists public.confirmar_pagamento(text, text);
drop function if exists public.confirmar_pagamento(bigint, text);
drop function if exists public.alterar_status_pedido(bigint, text);
drop function if exists public.alterar_status_pedido(bigint, text, text);
drop function if exists public.atribuir_entregador(bigint, uuid);
drop function if exists public.cancelar_pedido(bigint);
drop function if exists public.finalizar_checkout(uuid, jsonb, numeric, bigint, text, text, text);
drop function if exists public.processar_pagamento_cartao(bigint, bigint, int);
drop function if exists public.cancelar_pendentes_expirados(int);

-- 8.1) Confirmação de pagamento (PIX) — dono ou admin; idempotente
create or replace function public.confirmar_pagamento(
  p_pedido_id bigint,
  p_metodo text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pedido public.pedidos%rowtype;
begin
  select * into v_pedido from public.pedidos where id = p_pedido_id;
  if v_pedido.id is null then
    raise exception 'Pedido % não encontrado', p_pedido_id;
  end if;

  if v_pedido.user_id <> auth.uid() and public.funcao_usuario() <> 'admin' then
    raise exception 'Você não pode confirmar o pagamento deste pedido';
  end if;

  if v_pedido.status <> 'pendente' then
    return jsonb_build_object('id', p_pedido_id, 'status', v_pedido.status, 'total', v_pedido.total);
  end if;

  update public.pedidos
     set pagamento = p_metodo,
         status = 'pago'
   where id = p_pedido_id;

  return jsonb_build_object('id', p_pedido_id, 'status', 'pago', 'total', v_pedido.total);
end $$;

-- 8.2) Loja/entregador altera status (1 assinatura; recebedor opcional)
create or replace function public.alterar_status_pedido(
  p_pedido_id bigint,
  p_status text,
  p_recebedor text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_funcao text := public.funcao_usuario();
  v_unidade int;
  v_pedido public.pedidos%rowtype;
begin
  select * into v_pedido from public.pedidos where id = p_pedido_id;
  if v_pedido.id is null then
    raise exception 'Pedido não encontrado';
  end if;

  if v_funcao = 'admin' then
    null;
  elsif v_funcao in ('atendente','gestor') then
    v_unidade := (select unidade_id from public.perfis where id = auth.uid());
    if v_pedido.unidade_id is distinct from v_unidade then
      raise exception 'Sem permissão para pedidos de outra loja';
    end if;
  elsif v_funcao = 'entregador' and auth.uid() = v_pedido.entregador_id then
    null;
  else
    raise exception 'Sem permissão para alterar pedidos';
  end if;

  if p_status = v_pedido.status then return; end if;

  update public.pedidos
     set status = p_status,
         recebedor_nome = coalesce(nullif(trim(p_recebedor), ''), recebedor_nome)
   where id = p_pedido_id;
end $$;

-- 8.3) Loja atribui/remove entregador
create or replace function public.atribuir_entregador(
  p_pedido_id bigint,
  p_entregador_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_funcao text := public.funcao_usuario();
  v_unidade int;
  v_pedido public.pedidos%rowtype;
begin
  select * into v_pedido from public.pedidos where id = p_pedido_id;
  if v_pedido.id is null then
    raise exception 'Pedido não encontrado';
  end if;

  if v_funcao = 'admin' then
    null;
  elsif v_funcao in ('atendente','gestor') then
    v_unidade := (select unidade_id from public.perfis where id = auth.uid());
    if v_pedido.unidade_id is distinct from v_unidade then
      raise exception 'Sem permissão para pedidos de outra loja';
    end if;
  else
    raise exception 'Sem permissão para atribuir entregador';
  end if;

  update public.pedidos set entregador_id = p_entregador_id where id = p_pedido_id;
end $$;

-- 8.4) Cancelar pedido (dono/admin/atendente da unidade)
create or replace function public.cancelar_pedido(p_pedido_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.pedidos
     set status = 'cancelado'
   where id = p_pedido_id
     and (user_id = auth.uid()
          or public.funcao_usuario() = 'admin'
          or (public.funcao_usuario() = 'atendente'
              and unidade_id = (select unidade_id from public.perfis where id = auth.uid())));
  if not found then
    raise exception 'Sem permissão para cancelar este pedido';
  end if;
end $$;

-- 8.5) CHECKOUT ATÔMICO (por unidade, com cupom validado NO SERVIDOR)
--      Preço, subtotal e desconto são 100% calculados aqui; o que o app
--      envia de preço/desconto é ignorado.
create or replace function public.finalizar_checkout(
  p_user_id uuid,
  p_itens jsonb,
  p_cupom_desconto_total numeric default 0,
  p_cupom_id bigint default null,
  p_tipo_entrega text default 'retirada',
  p_endereco_entrega text default null,
  p_cep_entrega text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item record;
  v_linha record;
  v_el jsonb;
  v_produto_id bigint;
  v_qtd int;
  v_estoque int;
  v_preco numeric;
  v_produto_nome text;
  v_unidade_nome text;
  v_pix text;
  v_subtotal_unidade numeric;
  v_subtotal_geral numeric := 0;
  v_desconto_geral numeric := 0;
  v_desconto_unidade numeric;
  v_total numeric;
  v_pedido_id bigint;
  v_pedidos jsonb := '[]'::jsonb;
  v_cupom public.cupons%rowtype;
begin
  if p_user_id is distinct from auth.uid() then
    raise exception 'Você não pode criar pedidos para outro usuário';
  end if;

  if jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception 'Carrinho vazio';
  end if;

  -- 1) Valida estoque e soma o subtotal REAL (preço do banco, com lock)
  for v_item in select * from jsonb_array_elements(p_itens) as t(item) loop
    v_el := v_item.item;
    v_produto_id := (v_el->>'produto_id')::bigint;
    v_qtd := (v_el->>'quantidade')::int;

    if v_qtd <= 0 then
      raise exception 'Quantidade inválida para o produto';
    end if;

    select p.estoque, p.nome,
           case when p.em_promocao and p.preco_promocional is not null then p.preco_promocional else p.preco end
      into v_estoque, v_produto_nome, v_preco
      from public.produtos p where p.id = v_produto_id
      for update;

    if not found then
      raise exception 'Produto não encontrado';
    end if;
    if v_estoque < v_qtd then
      raise exception '"%" com estoque insuficiente (restam %, pedido: %)',
        v_produto_nome, v_estoque, v_qtd;
    end if;

    v_subtotal_geral := v_subtotal_geral + (coalesce(v_preco, 0) * v_qtd);
  end loop;

  -- 2) Cupom: validado e calculado no SERVIDOR (ignora valor do app)
  if p_cupom_id is not null then
    select * into v_cupom from public.cupons where id = p_cupom_id;

    if v_cupom.id is null then
      raise exception 'Cupom não encontrado';
    end if;
    if not coalesce(v_cupom.ativo, false) then
      raise exception 'Cupom inativo';
    end if;
    if v_cupom.data_validade is not null and v_cupom.data_validade < current_date then
      raise exception 'Cupom expirado';
    end if;
    if v_cupom.uso_maximo is not null and coalesce(v_cupom.usos_atuais, 0) >= v_cupom.uso_maximo then
      raise exception 'Cupom esgotado (limite de usos atingido)';
    end if;
    if v_cupom.valor_minimo is not null and v_subtotal_geral < v_cupom.valor_minimo then
      raise exception 'Cupom exige valor mínimo de R$ %', v_cupom.valor_minimo;
    end if;

    v_desconto_geral := case
      when coalesce(v_cupom.tipo, 'percentual') = 'percentual'
        then v_subtotal_geral * coalesce(v_cupom.valor, 0) / 100.0
      else coalesce(v_cupom.valor, 0)
    end;
    v_desconto_geral := least(greatest(v_desconto_geral, 0), v_subtotal_geral);

    update public.cupons
       set usos_atuais = coalesce(usos_atuais, 0) + 1
     where id = p_cupom_id;
  end if;

  -- 3) Agrupa por unidade (marketplace) e grava pedido + itens
  for v_linha in
    select coalesce((t.item->>'unidade_id')::bigint, 1) as unidade_id,
           jsonb_agg(t.item order by (t.item->>'produto_id')::bigint) as itens
      from jsonb_array_elements(p_itens) as t(item)
     group by 1
  loop
    v_subtotal_unidade := 0;
    for v_item in select * from jsonb_array_elements(v_linha.itens) as t(item) loop
      select case when p.em_promocao and p.preco_promocional is not null then p.preco_promocional else p.preco end
        into v_preco
        from public.produtos p
       where p.id = (v_item.item->>'produto_id')::bigint;
      v_subtotal_unidade := v_subtotal_unidade + coalesce(v_preco, 0) * (v_item.item->>'quantidade')::int;
    end loop;

    v_desconto_unidade := 0;
    if v_desconto_geral > 0 and v_subtotal_geral > 0 then
      v_desconto_unidade := v_desconto_geral * (v_subtotal_unidade / v_subtotal_geral);
    end if;
    v_total := greatest(v_subtotal_unidade - v_desconto_unidade, 0);

    v_unidade_nome := 'Loja';
    v_pix := null;
    select nome, pix_key into v_unidade_nome, v_pix
      from public.unidades where id = v_linha.unidade_id;

    insert into public.pedidos (user_id, unidade_id, status, total, desconto_cupom, cupom_id,
                                pix_copia_cola, tipo_entrega, endereco_entrega, cep_entrega)
    values (p_user_id, v_linha.unidade_id, 'pendente', v_total, v_desconto_unidade, p_cupom_id,
            v_pix, p_tipo_entrega,
            case when p_tipo_entrega = 'entrega' then p_endereco_entrega else null end,
            case when p_tipo_entrega = 'entrega' then p_cep_entrega else null end)
    returning id into v_pedido_id;

    insert into public.pedido_itens (pedido_id, produto_id, quantidade, preco_unitario, cor)
    select v_pedido_id,
           (t.item->>'produto_id')::bigint,
           (t.item->>'quantidade')::int,
           coalesce((t.item->>'preco_atual')::numeric, 0),
           nullif(t.item->>'cor', '')
      from jsonb_array_elements(v_linha.itens) as t(item);

    v_pedidos := v_pedidos || jsonb_build_object(
      'id', v_pedido_id,
      'unidade_id', v_linha.unidade_id,
      'unidade_nome', v_unidade_nome,
      'pix_copia_cola', v_pix,
      'total', v_total,
      'itens_count', jsonb_array_length(v_linha.itens)
    );
  end loop;

  return v_pedidos;
end $$;

-- 8.6) Pagamento com cartão salvo (autorização simulada até plugar o MP)
create or replace function public.processar_pagamento_cartao(
  p_pedido_id bigint,
  p_cartao_id bigint,
  p_parcelas int default 1
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pedido public.pedidos%rowtype;
  v_cartao public.cartoes_usuario%rowtype;
  v_transacao uuid;
  v_hoje_ym int := extract(year from now())::int * 100 + extract(month from now())::int;
begin
  select * into v_pedido from public.pedidos where id = p_pedido_id;
  if v_pedido.id is null then
    raise exception 'Pedido não encontrado';
  end if;

  if v_pedido.user_id <> auth.uid() then
    raise exception 'Você não pode pagar este pedido';
  end if;

  if v_pedido.status <> 'pendente' then
    return jsonb_build_object('aprovado', false,
      'motivo', 'O pedido não está em aguardando pagamento',
      'status', v_pedido.status);
  end if;

  select * into v_cartao from public.cartoes_usuario
   where id = p_cartao_id and user_id = auth.uid();
  if v_cartao.id is null then
    raise exception 'Cartão não encontrado';
  end if;

  if p_parcelas <= 0 then
    raise exception 'Número de parcelas inválido';
  end if;

  if v_cartao.ano_validade * 100 + v_cartao.mes_validade < v_hoje_ym then
    return jsonb_build_object('aprovado', false, 'motivo', 'Cartão vencido');
  end if;

  v_transacao := gen_random_uuid();

  update public.pedidos
     set pagamento = 'cartao',
         transacao_id = v_transacao::text,
         pagamento_detalhes = format('%s • %sx • Transação #%s',
             v_cartao.bandeira, p_parcelas, left(v_transacao::text, 8))
   where id = p_pedido_id;

  update public.pedidos set status = 'pago'
   where id = p_pedido_id and status = 'pendente';

  return jsonb_build_object('aprovado', true,
    'transacao_id', v_transacao::text,
    'status', 'pago');
end $$;

-- 8.7) Expiração de pendentes não pagos (o app chama ao abrir "Meus Pedidos")
create or replace function public.cancelar_pendentes_expirados(
  p_minutos int default 60
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int;
begin
  if p_minutos < 1 then
    p_minutos := 60;
  end if;

  update public.pedidos
     set status = 'cancelado'
   where user_id = auth.uid()
     and status = 'pendente'
     and created_at < now() - make_interval(mins => p_minutos);
  get diagnostics v_count = row_count;
  return v_count;
end $$;

-- 8.8) Baixa manual de estoque (apenas loja/admin; o fluxo normal é o trigger)
create or replace function public.decrementar_estoque(produto_id bigint, quantidade int)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_estoque int;
  v_funcao text;
begin
  v_funcao := coalesce((select funcao from public.perfis where id = auth.uid()), '');
  if v_funcao not in ('admin','atendente') then
    raise exception 'Sem permissão para alterar estoque';
  end if;
  if quantidade <= 0 then raise exception 'Quantidade inválida'; end if;
  select estoque into v_estoque from public.produtos where id = produto_id for update;
  if v_estoque is null then raise exception 'Produto não encontrado'; end if;
  if v_estoque < quantidade then
    raise exception 'Estoque insuficiente para o produto % (disponível: %)', produto_id, v_estoque;
  end if;
  update public.produtos set estoque = v_estoque - quantidade where id = produto_id;
  insert into public.estoque_movimentacoes (produto_id, tipo, quantidade, motivo, criado_por)
  values (produto_id, 'ajuste', -quantidade, 'Ajuste manual', auth.uid());
  return v_estoque - quantidade;
end $$;

-- 8.9) Grants: RPCs apenas para usuários autenticados
revoke all on function public.confirmar_pagamento(bigint, text) from public, anon;
grant execute on function public.confirmar_pagamento(bigint, text) to authenticated;

revoke all on function public.alterar_status_pedido(bigint, text, text) from public, anon;
grant execute on function public.alterar_status_pedido(bigint, text, text) to authenticated;

revoke all on function public.atribuir_entregador(bigint, uuid) from public, anon;
grant execute on function public.atribuir_entregador(bigint, uuid) to authenticated;

revoke all on function public.cancelar_pedido(bigint) from public, anon;
grant execute on function public.cancelar_pedido(bigint) to authenticated;

revoke all on function public.finalizar_checkout(uuid, jsonb, numeric, bigint, text, text, text) from public, anon;
grant execute on function public.finalizar_checkout(uuid, jsonb, numeric, bigint, text, text, text) to authenticated;

revoke all on function public.processar_pagamento_cartao(bigint, bigint, int) from public, anon;
grant execute on function public.processar_pagamento_cartao(bigint, bigint, int) to authenticated;

revoke all on function public.cancelar_pendentes_expirados(int) from public, anon;
grant execute on function public.cancelar_pendentes_expirados(int) to authenticated;

revoke all on function public.decrementar_estoque(bigint, int) from public, anon;
grant execute on function public.decrementar_estoque(bigint, int) to authenticated;

-- service_role (webhooks/edge functions) também pode executar as RPCs
do $$
declare
  r record;
begin
  for r in
    select p.proname, pg_get_function_identity_arguments(p.oid) as args
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'confirmar_pagamento','alterar_status_pedido','atribuir_entregador',
        'cancelar_pedido','finalizar_checkout','processar_pagamento_cartao',
        'cancelar_pendentes_expirados','decrementar_estoque','funcao_usuario'
      )
  loop
    begin
      execute format('grant execute on function public.%I(%s) to service_role', r.proname, r.args);
    exception when others then
      raise notice 'Grant para service_role falhou em %: %', r.proname, sqlerrm;
    end;
  end loop;
end $$;

-- ═══════════════════════════════════════════════════════════════════════
-- 9) RLS CONSOLIDADO (fecha furos e garante o essencial)
-- ═══════════════════════════════════════════════════════════════════════

-- 9.1) LIGA O RLS ONDE ESTAVA DESLIGADO (unidades!) + tabelas novas
do $$
declare
  t text;
begin
  foreach t in array array[
    'unidades','perfis_unidades','galeria_produtos',
    'aulas','aulas_inscricao','personal_sessoes','avaliacoes','progresso_fotos',
    'desafios','desafios_participantes','indicacoes','nutricionistas','consultas',
    'treinos','exercicios','plano_refeicoes'
  ] loop
    if to_regclass('public.' || t) is not null then
      execute format('alter table public.%I enable row level security', t);
    end if;
  end loop;
end $$;

-- 9.2) FUROS A FECHAR
--  - produtos_write_atendente: não checava a função (qualquer um com unidade
--    igual podia editar produtos da loja) → removida.
--  - cupons_select_all: expunha cupons inativos → removida.
do $$
begin
  perform public._cons_drop_policy('produtos', 'produtos_write_atendente');
  perform public._cons_drop_policy('cupons', 'cupons_select_all');
  -- policies duplicadas/legadas (as versões canônicas são recriadas no 9.5)
  perform public._cons_drop_policy('pedidos', 'pedidos_select_cliente');
  perform public._cons_drop_policy('pedidos', 'pedidos_select_admin');
  perform public._cons_drop_policy('pedidos', 'pedidos_select_loja');
  perform public._cons_drop_policy('pedidos', 'pedidos_entregador_select');
  perform public._cons_drop_policy('pedidos', 'pedidos_entregador_update');
  perform public._cons_drop_policy('pedido_itens', 'pedido_itens_select_cliente');
  perform public._cons_drop_policy('pedido_itens', 'pedido_itens_select_admin');
  perform public._cons_drop_policy('pedido_itens', 'pedido_itens_select_loja');
  perform public._cons_drop_policy('pedido_itens', 'pedido_itens_select_entregador');
  perform public._cons_drop_policy('pedido_historico', 'hist_select');
  perform public._cons_drop_policy('estoque_movimentacoes', 'mov_select_loja');
  perform public._cons_drop_policy('perfis_unidades', 'perfis_unidades_admin_all');
end $$;

-- 9.3) LEITURAS BÁSICAS (público autenticado)
do $$
begin
  perform public._cons_ensure_policy('unidades', 'unidades_select',
    $sql$create policy "unidades_select" on public.unidades for select to authenticated using (true)$sql$);

  perform public._cons_ensure_policy('categorias', 'categorias_select',
    $sql$create policy "categorias_select" on public.categorias for select to authenticated using (true)$sql$);

  perform public._cons_ensure_policy('marcas', 'marcas_select',
    $sql$create policy "marcas_select" on public.marcas for select to authenticated using (true)$sql$);

  perform public._cons_ensure_policy('produtos', 'produtos_select',
    $sql$create policy "produtos_select" on public.produtos for select to authenticated using (true)$sql$);

  -- Galeria dos produtos: clientes precisavam ler as fotos extras (antes só admin)
  perform public._cons_ensure_policy('galeria_produtos', 'galeria_produtos_select',
    $sql$create policy "galeria_produtos_select" on public.galeria_produtos for select to authenticated using (true)$sql$);

  perform public._cons_ensure_policy('posts_feed', 'posts_feed_select',
    $sql$create policy "posts_feed_select" on public.posts_feed for select to authenticated using (true)$sql$);

  perform public._cons_ensure_policy('post_likes', 'post_likes_select',
    $sql$create policy "post_likes_select" on public.post_likes for select to authenticated using (true)$sql$);

  perform public._cons_ensure_policy('post_comentarios', 'post_comentarios_select',
    $sql$create policy "post_comentarios_select" on public.post_comentarios for select to authenticated using (true)$sql$);

  perform public._cons_ensure_policy('cupons', 'cupons_select',
    $sql$create policy "cupons_select" on public.cupons for select to authenticated using (ativo = true)$sql$);

  perform public._cons_ensure_policy('cartoes_usuario', 'cartoes_select',
    $sql$create policy "cartoes_select" on public.cartoes_usuario for select to authenticated using (user_id = auth.uid())$sql$);

  -- Equipe precisa ler contatos dos clientes (chat/entrega)
  perform public._cons_ensure_policy('perfis', 'perfis_select_equipe',
    $sql$create policy "perfis_select_equipe" on public.perfis for select to authenticated
        using (public.funcao_usuario() in ('admin','atendente','entregador'))$sql$);
end $$;

-- 9.4) CRUD do próprio usuário (garante carrinho/favoritos/cartões)
do $$
begin
  perform public._cons_ensure_policy('carrinho', 'carrinho_select',
    $sql$create policy "carrinho_select" on public.carrinho for select to authenticated using (user_id = auth.uid())$sql$);
  perform public._cons_ensure_policy('carrinho', 'carrinho_insert',
    $sql$create policy "carrinho_insert" on public.carrinho for insert to authenticated with check (user_id = auth.uid())$sql$);
  perform public._cons_ensure_policy('carrinho', 'carrinho_update',
    $sql$create policy "carrinho_update" on public.carrinho for update to authenticated using (user_id = auth.uid())$sql$);
  perform public._cons_ensure_policy('carrinho', 'carrinho_delete',
    $sql$create policy "carrinho_delete" on public.carrinho for delete to authenticated using (user_id = auth.uid())$sql$);

  perform public._cons_ensure_policy('favoritos', 'favoritos_select',
    $sql$create policy "favoritos_select" on public.favoritos for select to authenticated using (user_id = auth.uid())$sql$);
  perform public._cons_ensure_policy('favoritos', 'favoritos_insert',
    $sql$create policy "favoritos_insert" on public.favoritos for insert to authenticated with check (user_id = auth.uid())$sql$);
  perform public._cons_ensure_policy('favoritos', 'favoritos_delete',
    $sql$create policy "favoritos_delete" on public.favoritos for delete to authenticated using (user_id = auth.uid())$sql$);

  perform public._cons_ensure_policy('cartoes_usuario', 'cartoes_insert',
    $sql$create policy "cartoes_insert" on public.cartoes_usuario for insert to authenticated with check (user_id = auth.uid())$sql$);
  perform public._cons_ensure_policy('cartoes_usuario', 'cartoes_update',
    $sql$create policy "cartoes_update" on public.cartoes_usuario for update to authenticated using (user_id = auth.uid())$sql$);
  perform public._cons_ensure_policy('cartoes_usuario', 'cartoes_delete',
    $sql$create policy "cartoes_delete" on public.cartoes_usuario for delete to authenticated using (user_id = auth.uid())$sql$);

  perform public._cons_ensure_policy('post_likes', 'post_likes_insert',
    $sql$create policy "post_likes_insert" on public.post_likes for insert to authenticated with check (user_id = auth.uid())$sql$);
  perform public._cons_ensure_policy('post_likes', 'post_likes_delete',
    $sql$create policy "post_likes_delete" on public.post_likes for delete to authenticated using (user_id = auth.uid())$sql$);
  perform public._cons_ensure_policy('post_comentarios', 'post_comentarios_insert',
    $sql$create policy "post_comentarios_insert" on public.post_comentarios for insert to authenticated with check (user_id = auth.uid())$sql$);
  perform public._cons_ensure_policy('post_comentarios', 'post_comentarios_delete',
    $sql$create policy "post_comentarios_delete" on public.post_comentarios for delete to authenticated
        using (user_id = auth.uid() or public.funcao_usuario() = 'admin')$sql$);
  perform public._cons_ensure_policy('candidaturas', 'candidaturas_select',
    $sql$create policy "candidaturas_select" on public.candidaturas for select to authenticated
        using (user_id = auth.uid() or public.funcao_usuario() = 'admin')$sql$);
  perform public._cons_ensure_policy('candidaturas', 'candidaturas_insert',
    $sql$create policy "candidaturas_insert" on public.candidaturas for insert to authenticated with check (user_id = auth.uid())$sql$);
end $$;

-- 9.5) POLICIES CANÔNICAS (recriadas do zero — versão sem recursão)
do $$
begin
  -- PERFIS
  perform public._cons_drop_policy('perfis', 'perfis_select');
  perform public._cons_drop_policy('perfis', 'perfis_update');
  perform public._cons_drop_policy('perfis', 'perfis_delete');
  perform public._cons_ensure_policy('perfis', 'perfis_select',
    $sql$create policy "perfis_select" on public.perfis for select to authenticated
        using (id = auth.uid() or public.funcao_usuario() = 'admin')$sql$);
  perform public._cons_ensure_policy('perfis', 'perfis_update',
    $sql$create policy "perfis_update" on public.perfis for update to authenticated
        using (id = auth.uid() or public.funcao_usuario() = 'admin')$sql$);
  perform public._cons_ensure_policy('perfis', 'perfis_delete',
    $sql$create policy "perfis_delete" on public.perfis for delete to authenticated
        using (id = auth.uid() or public.funcao_usuario() = 'admin')$sql$);
  perform public._cons_ensure_policy('perfis', 'perfis_insert',
    $sql$create policy "perfis_insert" on public.perfis for insert to authenticated with check (id = auth.uid())$sql$);

  -- PEDIDOS (leitura por papel; escrita só via RPC — ver revoke)
  perform public._cons_drop_policy('pedidos', 'pedidos_select');
  perform public._cons_drop_policy('pedidos', 'pedidos_update');
  perform public._cons_ensure_policy('pedidos', 'pedidos_select',
    $sql$create policy "pedidos_select" on public.pedidos for select to authenticated
        using (
          user_id = auth.uid()
          or entregador_id = auth.uid()
          or public.funcao_usuario() = 'admin'
          or (public.funcao_usuario() in ('atendente','gestor')
              and unidade_id = (select unidade_id from public.perfis where id = auth.uid()))
        )$sql$);
  perform public._cons_ensure_policy('pedidos', 'pedidos_update',
    $sql$create policy "pedidos_update" on public.pedidos for update to authenticated
        using (
          user_id = auth.uid()
          or entregador_id = auth.uid()
          or public.funcao_usuario() = 'admin'
          or (public.funcao_usuario() in ('atendente','gestor')
              and unidade_id = (select unidade_id from public.perfis where id = auth.uid()))
        )$sql$);
  perform public._cons_ensure_policy('pedidos', 'pedidos_proprio_insert',
    $sql$create policy "pedidos_proprio_insert" on public.pedidos for insert to authenticated with check (user_id = auth.uid())$sql$);

  -- ITENS DO PEDIDO
  perform public._cons_drop_policy('pedido_itens', 'pedido_itens_select');
  perform public._cons_ensure_policy('pedido_itens', 'pedido_itens_select',
    $sql$create policy "pedido_itens_select" on public.pedido_itens for select to authenticated
        using (
          exists (
            select 1 from public.pedidos
            where pedidos.id = pedido_itens.pedido_id
              and (
                pedidos.user_id = auth.uid()
                or pedidos.entregador_id = auth.uid()
                or public.funcao_usuario() = 'admin'
                or (public.funcao_usuario() in ('atendente','gestor')
                    and pedidos.unidade_id = (select unidade_id from public.perfis where id = auth.uid()))
              )
          )
        )$sql$);
  perform public._cons_ensure_policy('pedido_itens', 'pedido_itens_proprio_insert',
    $sql$create policy "pedido_itens_proprio_insert" on public.pedido_itens for insert to authenticated
        with check (exists (
          select 1 from public.pedidos
          where pedidos.id = pedido_itens.pedido_id and pedidos.user_id = auth.uid()
        ))$sql$);

  -- HISTÓRICO
  perform public._cons_drop_policy('pedido_historico', 'pedido_historico_select');
  perform public._cons_ensure_policy('pedido_historico', 'pedido_historico_select',
    $sql$create policy "pedido_historico_select" on public.pedido_historico for select to authenticated
        using (
          public.funcao_usuario() = 'admin'
          or exists (
            select 1 from public.pedidos
            where pedidos.id = pedido_historico.pedido_id
              and (pedidos.user_id = auth.uid() or pedidos.entregador_id = auth.uid())
          )
        )$sql$);

  -- ESTOQUE
  perform public._cons_drop_policy('estoque_movimentacoes', 'estoque_movimentacoes_select');
  perform public._cons_ensure_policy('estoque_movimentacoes', 'estoque_movimentacoes_select',
    $sql$create policy "estoque_movimentacoes_select" on public.estoque_movimentacoes for select to authenticated
        using (public.funcao_usuario() in ('admin','atendente'))$sql$);

  -- CONVERSAS / MENSAGENS (inclui profissional vinculado)
  perform public._cons_drop_policy('conversas', 'conversas_select');
  perform public._cons_drop_policy('conversas', 'conversas_update');
  perform public._cons_ensure_policy('conversas', 'conversas_select',
    $sql$create policy "conversas_select" on public.conversas for select to authenticated
        using (
          usuario_id = auth.uid()
          or profissional_id = auth.uid()
          or public.funcao_usuario() = 'admin'
          or (public.funcao_usuario() in ('atendente','gestor')
              and unidade_id = (select unidade_id from public.perfis where id = auth.uid()))
        )$sql$);
  perform public._cons_ensure_policy('conversas', 'conversas_update',
    $sql$create policy "conversas_update" on public.conversas for update to authenticated
        using (
          usuario_id = auth.uid()
          or profissional_id = auth.uid()
          or public.funcao_usuario() = 'admin'
          or (public.funcao_usuario() in ('atendente','gestor')
              and unidade_id = (select unidade_id from public.perfis where id = auth.uid()))
        )$sql$);
  perform public._cons_ensure_policy('conversas', 'conversas_insert',
    $sql$create policy "conversas_insert" on public.conversas for insert to authenticated
        with check (usuario_id = auth.uid() or public.funcao_usuario() = 'admin')$sql$);

  perform public._cons_drop_policy('mensagens', 'mensagens_select');
  perform public._cons_ensure_policy('mensagens', 'mensagens_select',
    $sql$create policy "mensagens_select" on public.mensagens for select to authenticated
        using (
          remetente_id = auth.uid()
          or exists (
            select 1 from public.conversas
            where conversas.id = mensagens.conversa_id
              and (
                conversas.usuario_id = auth.uid()
                or conversas.profissional_id = auth.uid()
                or public.funcao_usuario() = 'admin'
                or (public.funcao_usuario() in ('atendente','gestor')
                    and conversas.unidade_id = (select unidade_id from public.perfis where id = auth.uid()))
              )
          )
        )$sql$);
  perform public._cons_ensure_policy('mensagens', 'mensagens_insert',
    $sql$create policy "mensagens_insert" on public.mensagens for insert to authenticated
        with check (remetente_id = auth.uid())$sql$);

  -- FILIAÇÕES DE PROFISSIONAIS
  perform public._cons_ensure_policy('perfis_unidades', 'perfis_unidades_admin_all',
    $sql$create policy "perfis_unidades_admin_all" on public.perfis_unidades for all to authenticated
        using (public.funcao_usuario() = 'admin')
        with check (public.funcao_usuario() = 'admin')$sql$);
  perform public._cons_ensure_policy('perfis_unidades', 'perfis_unidades_proprio_select',
    $sql$create policy "perfis_unidades_proprio_select" on public.perfis_unidades for select to authenticated
        using (user_id = auth.uid())$sql$);
end $$;

-- ═══════════════════════════════════════════════════════════════════════
-- 10) RLS DAS TABELAS DE ACADEMIA / NUTRIÇÃO (estavam sem policies
--     versionadas; com RLS ligado no 9.1 elas precisam destas regras)
-- ═══════════════════════════════════════════════════════════════════════

do $$
begin
  -- AULAS (catálogo visível; gestão admin)
  perform public._cons_ensure_policy('aulas', 'aulas_select_auth',
    $sql$create policy "aulas_select_auth" on public.aulas for select to authenticated using (true)$sql$);
  perform public._cons_ensure_policy('aulas', 'aulas_admin_all',
    $sql$create policy "aulas_admin_all" on public.aulas for all to authenticated
        using (public.funcao_usuario() = 'admin')
        with check (public.funcao_usuario() = 'admin')$sql$);

  -- INSCRIÇÕES EM AULAS (próprias)
  perform public._cons_ensure_policy('aulas_inscricao', 'aulas_inscricao_select_own',
    $sql$create policy "aulas_inscricao_select_own" on public.aulas_inscricao for select to authenticated
        using (user_id = auth.uid() or public.funcao_usuario() = 'admin')$sql$);
  perform public._cons_ensure_policy('aulas_inscricao', 'aulas_inscricao_insert_own',
    $sql$create policy "aulas_inscricao_insert_own" on public.aulas_inscricao for insert to authenticated
        with check (user_id = auth.uid())$sql$);
  perform public._cons_ensure_policy('aulas_inscricao', 'aulas_inscricao_delete_own',
    $sql$create policy "aulas_inscricao_delete_own" on public.aulas_inscricao for delete to authenticated
        using (user_id = auth.uid() or public.funcao_usuario() = 'admin')$sql$);

  -- PERSONAL SESSÕES (aluno/profissional/admin)
  perform public._cons_ensure_policy('personal_sessoes', 'personal_sessoes_select_own',
    $sql$create policy "personal_sessoes_select_own" on public.personal_sessoes for select to authenticated
        using (aluno_id = auth.uid() or personal_id = auth.uid() or public.funcao_usuario() = 'admin')$sql$);
  perform public._cons_ensure_policy('personal_sessoes', 'personal_sessoes_insert_own',
    $sql$create policy "personal_sessoes_insert_own" on public.personal_sessoes for insert to authenticated
        with check (aluno_id = auth.uid() or personal_id = auth.uid() or public.funcao_usuario() = 'admin')$sql$);
  perform public._cons_ensure_policy('personal_sessoes', 'personal_sessoes_update_own',
    $sql$create policy "personal_sessoes_update_own" on public.personal_sessoes for update to authenticated
        using (personal_id = auth.uid() or public.funcao_usuario() = 'admin')$sql$);
  perform public._cons_ensure_policy('personal_sessoes', 'personal_sessoes_admin_delete',
    $sql$create policy "personal_sessoes_admin_delete" on public.personal_sessoes for delete to authenticated
        using (public.funcao_usuario() = 'admin')$sql$);

  -- AVALIAÇÕES FÍSICAS (próprias)
  perform public._cons_ensure_policy('avaliacoes', 'avaliacoes_select_own',
    $sql$create policy "avaliacoes_select_own" on public.avaliacoes for select to authenticated
        using (user_id = auth.uid() or public.funcao_usuario() = 'admin')$sql$);
  perform public._cons_ensure_policy('avaliacoes', 'avaliacoes_insert_own',
    $sql$create policy "avaliacoes_insert_own" on public.avaliacoes for insert to authenticated
        with check (user_id = auth.uid())$sql$);
  perform public._cons_ensure_policy('avaliacoes', 'avaliacoes_update_own',
    $sql$create policy "avaliacoes_update_own" on public.avaliacoes for update to authenticated
        using (user_id = auth.uid() or public.funcao_usuario() = 'admin')$sql$);
  perform public._cons_ensure_policy('avaliacoes', 'avaliacoes_delete_own',
    $sql$create policy "avaliacoes_delete_own" on public.avaliacoes for delete to authenticated
        using (user_id = auth.uid() or public.funcao_usuario() = 'admin')$sql$);

  -- PROGRESSO (fotos)
  perform public._cons_ensure_policy('progresso_fotos', 'progresso_fotos_own',
    $sql$create policy "progresso_fotos_own" on public.progresso_fotos for all to authenticated
        using (user_id = auth.uid() or public.funcao_usuario() = 'admin')
        with check (user_id = auth.uid() or public.funcao_usuario() = 'admin')$sql$);

  -- DESAFIOS
  perform public._cons_ensure_policy('desafios', 'desafios_select_auth',
    $sql$create policy "desafios_select_auth" on public.desafios for select to authenticated using (true)$sql$);
  perform public._cons_ensure_policy('desafios', 'desafios_admin_all',
    $sql$create policy "desafios_admin_all" on public.desafios for all to authenticated
        using (public.funcao_usuario() = 'admin')
        with check (public.funcao_usuario() = 'admin')$sql$);

  -- PARTICIPANTES DE DESAFIOS
  perform public._cons_ensure_policy('desafios_participantes', 'desafios_participantes_select_own',
    $sql$create policy "desafios_participantes_select_own" on public.desafios_participantes for select to authenticated
        using (user_id = auth.uid() or public.funcao_usuario() = 'admin')$sql$);
  perform public._cons_ensure_policy('desafios_participantes', 'desafios_participantes_insert_own',
    $sql$create policy "desafios_participantes_insert_own" on public.desafios_participantes for insert to authenticated
        with check (user_id = auth.uid())$sql$);
  perform public._cons_ensure_policy('desafios_participantes', 'desafios_participantes_update_own',
    $sql$create policy "desafios_participantes_update_own" on public.desafios_participantes for update to authenticated
        using (user_id = auth.uid() or public.funcao_usuario() = 'admin')$sql$);
  perform public._cons_ensure_policy('desafios_participantes', 'desafios_participantes_delete_own',
    $sql$create policy "desafios_participantes_delete_own" on public.desafios_participantes for delete to authenticated
        using (user_id = auth.uid() or public.funcao_usuario() = 'admin')$sql$);

  -- INDICAÇÕES
  perform public._cons_ensure_policy('indicacoes', 'indicacoes_select_own',
    $sql$create policy "indicacoes_select_own" on public.indicacoes for select to authenticated
        using (usuario_id = auth.uid() or indicado_id = auth.uid() or public.funcao_usuario() = 'admin')$sql$);
  perform public._cons_ensure_policy('indicacoes', 'indicacoes_insert_own',
    $sql$create policy "indicacoes_insert_own" on public.indicacoes for insert to authenticated
        with check (usuario_id = auth.uid())$sql$);

  -- NUTRICIONISTAS (catálogo visível; gestão admin)
  perform public._cons_ensure_policy('nutricionistas', 'nutricionistas_select_auth',
    $sql$create policy "nutricionistas_select_auth" on public.nutricionistas for select to authenticated using (true)$sql$);
  perform public._cons_ensure_policy('nutricionistas', 'nutricionistas_admin_all',
    $sql$create policy "nutricionistas_admin_all" on public.nutricionistas for all to authenticated
        using (public.funcao_usuario() = 'admin')
        with check (public.funcao_usuario() = 'admin')$sql$);

  -- CONSULTAS
  perform public._cons_ensure_policy('consultas', 'consultas_select_own',
    $sql$create policy "consultas_select_own" on public.consultas for select to authenticated
        using (user_id = auth.uid() or public.funcao_usuario() = 'admin')$sql$);
  perform public._cons_ensure_policy('consultas', 'consultas_insert_own',
    $sql$create policy "consultas_insert_own" on public.consultas for insert to authenticated
        with check (user_id = auth.uid())$sql$);
  perform public._cons_ensure_policy('consultas', 'consultas_admin_all',
    $sql$create policy "consultas_admin_all" on public.consultas for all to authenticated
        using (public.funcao_usuario() = 'admin')
        with check (public.funcao_usuario() = 'admin')$sql$);

  -- TREINOS + EXERCÍCIOS (do usuário; admin gerencia)
  perform public._cons_ensure_policy('treinos', 'treinos_own',
    $sql$create policy "treinos_own" on public.treinos for all to authenticated
        using (user_id = auth.uid() or public.funcao_usuario() = 'admin')
        with check (user_id = auth.uid() or public.funcao_usuario() = 'admin')$sql$);
  perform public._cons_ensure_policy('exercicios', 'exercicios_select_own',
    $sql$create policy "exercicios_select_own" on public.exercicios for select to authenticated
        using (public.funcao_usuario() = 'admin'
          or exists (select 1 from public.treinos t where t.id = exercicios.treino_id and t.user_id = auth.uid()))$sql$);
  perform public._cons_ensure_policy('exercicios', 'exercicios_insert_own',
    $sql$create policy "exercicios_insert_own" on public.exercicios for insert to authenticated
        with check (public.funcao_usuario() = 'admin'
          or exists (select 1 from public.treinos t where t.id = exercicios.treino_id and t.user_id = auth.uid()))$sql$);
  perform public._cons_ensure_policy('exercicios', 'exercicios_update_own',
    $sql$create policy "exercicios_update_own" on public.exercicios for update to authenticated
        using (public.funcao_usuario() = 'admin'
          or exists (select 1 from public.treinos t where t.id = exercicios.treino_id and t.user_id = auth.uid()))$sql$);
  perform public._cons_ensure_policy('exercicios', 'exercicios_delete_own',
    $sql$create policy "exercicios_delete_own" on public.exercicios for delete to authenticated
        using (public.funcao_usuario() = 'admin'
          or exists (select 1 from public.treinos t where t.id = exercicios.treino_id and t.user_id = auth.uid()))$sql$);

  -- PLANO ALIMENTAR (refeições do usuário; admin gerencia)
  perform public._cons_ensure_policy('plano_refeicoes', 'plano_refeicoes_own',
    $sql$create policy "plano_refeicoes_own" on public.plano_refeicoes for all to authenticated
        using (user_id = auth.uid() or public.funcao_usuario() = 'admin')
        with check (user_id = auth.uid() or public.funcao_usuario() = 'admin')$sql$);
end $$;

-- ═══════════════════════════════════════════════════════════════════════
-- 11) STORAGE: políticas que faltavam (avatar do usuário: update/delete)
-- ═══════════════════════════════════════════════════════════════════════

insert into storage.buckets (id, name, public) values ('Produtos', 'Produtos', true) on conflict (id) do nothing;
insert into storage.buckets (id, name, public) values ('fotos_perfil', 'fotos_perfil', false) on conflict (id) do nothing;
insert into storage.buckets (id, name, public) values ('Curriculos', 'Curriculos', false) on conflict (id) do nothing;

do $$
begin
  if not exists (select 1 from pg_policy where polname = 'fotos_perfil_proprio_update' and polrelid = 'storage.objects'::regclass) then
    execute $sql$create policy "fotos_perfil_proprio_update" on storage.objects for update to authenticated
      using (bucket_id = 'fotos_perfil' and auth.uid()::text = (storage.foldername(name))[1])
      with check (bucket_id = 'fotos_perfil' and auth.uid()::text = (storage.foldername(name))[1])$sql$;
  end if;
  if not exists (select 1 from pg_policy where polname = 'fotos_perfil_proprio_delete' and polrelid = 'storage.objects'::regclass) then
    execute $sql$create policy "fotos_perfil_proprio_delete" on storage.objects for delete to authenticated
      using (bucket_id = 'fotos_perfil' and auth.uid()::text = (storage.foldername(name))[1])$sql$;
  end if;
  if not exists (select 1 from pg_policy where polname = 'fotos_perfil_proprio_write' and polrelid = 'storage.objects'::regclass) then
    execute $sql$create policy "fotos_perfil_proprio_write" on storage.objects for insert to authenticated
      with check (bucket_id = 'fotos_perfil' and auth.uid()::text = (storage.foldername(name))[1])$sql$;
  end if;
  if not exists (select 1 from pg_policy where polname = 'fotos_perfil_select' and polrelid = 'storage.objects'::regclass) then
    execute $sql$create policy "fotos_perfil_select" on storage.objects for select to authenticated
      using (bucket_id = 'fotos_perfil')$sql$;
  end if;
  if not exists (select 1 from pg_policy where polname = 'Produtos_admin_write' and polrelid = 'storage.objects'::regclass) then
    execute $sql$create policy "Produtos_admin_write" on storage.objects for all to authenticated
      using (bucket_id = 'Produtos' and public.funcao_usuario() = 'admin')
      with check (bucket_id = 'Produtos' and public.funcao_usuario() = 'admin')$sql$;
  end if;
  if not exists (select 1 from pg_policy where polname = 'Curriculos_proprio_insert' and polrelid = 'storage.objects'::regclass) then
    execute $sql$create policy "Curriculos_proprio_insert" on storage.objects for insert to authenticated
      with check (bucket_id = 'Curriculos' and auth.uid()::text = (storage.foldername(name))[1])$sql$;
  end if;
  if not exists (select 1 from pg_policy where polname = 'Curriculos_admin_select' and polrelid = 'storage.objects'::regclass) then
    execute $sql$create policy "Curriculos_admin_select" on storage.objects for select to authenticated
      using (bucket_id = 'Curriculos' and public.funcao_usuario() = 'admin')$sql$;
  end if;
end $$;

-- ═══════════════════════════════════════════════════════════════════════
-- 12) REALTIME: chat (mensagens) + pedidos + histórico na publication
-- ═══════════════════════════════════════════════════════════════════════

do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'mensagens') then
    execute 'alter publication supabase_realtime add table public.mensagens';
  end if;
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'pedidos') then
    execute 'alter publication supabase_realtime add table public.pedidos';
  end if;
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'pedido_historico') then
    execute 'alter publication supabase_realtime add table public.pedido_historico';
  end if;
end $$;

-- ═══════════════════════════════════════════════════════════════════════
-- 13) PERFIL AUTOMÁTICO NO SIGNUP + BACKFILL
-- ═══════════════════════════════════════════════════════════════════════

create or replace function public.criar_perfil_apos_signup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.perfis (id, nome, email, perfil, funcao)
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data ->> 'nome',
      new.raw_user_meta_data ->> 'full_name',
      split_part(new.email, '@', 1)
    ),
    new.email,
    'cliente',
    'cliente'
  )
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.criar_perfil_apos_signup();

-- Backfill: usuários do auth que ainda não têm perfil
insert into public.perfis (id, nome, email, perfil, funcao)
select
  au.id,
  coalesce(
    au.raw_user_meta_data ->> 'nome',
    au.raw_user_meta_data ->> 'full_name',
    split_part(au.email, '@', 1)
  ),
  au.email,
  'cliente',
  'cliente'
from auth.users au
left join public.perfis p on p.id = au.id
where p.id is null
on conflict (id) do nothing;

-- ═══════════════════════════════════════════════════════════════════════
-- 14) CONSTRAINTS FINAIS (validações que faltavam)
-- ═══════════════════════════════════════════════════════════════════════

-- Estoque nunca negativo
update public.produtos set estoque = 0 where estoque < 0;
do $$
begin
  if not exists (select 1 from pg_constraint
                 where conrelid = 'public.produtos'::regclass and conname = 'chk_estoque_nao_negativo') then
    alter table public.produtos add constraint chk_estoque_nao_negativo check (estoque >= 0);
  end if;
end $$;

-- Status do pedido válido
do $$
begin
  if not exists (select 1 from pg_constraint
                 where conrelid = 'public.pedidos'::regclass and conname = 'chk_status_valido') then
    alter table public.pedidos add constraint chk_status_valido check (
      status in ('pendente','pago','em_preparo','pronto_para_entrega','saiu_para_entrega','entregue','cancelado')
    );
  end if;
end $$;

-- Carrinho: um registro por (usuário, produto, cor) + um por produto sem cor
do $$
begin
  begin
    alter table public.carrinho drop constraint if exists carrinho_user_id_produto_id_key;
    alter table public.carrinho add constraint carrinho_user_id_produto_id_cor_key unique (user_id, produto_id, cor);
  exception when others then
    raise notice 'Constraint única do carrinho não atualizada (talvez existam duplicatas): %', sqlerrm;
  end;
end $$;

do $$
begin
  begin
    create unique index if not exists uq_carrinho_user_produto_coresem_null
      on public.carrinho(user_id, produto_id) where cor is null;
  exception when others then
    raise notice 'Índice único do carrinho (cor nula) não criado: %', sqlerrm;
  end;
end $$;

-- Estoque: 1 venda + 1 devolução por pedido
do $$
begin
  if not exists (select 1 from pg_constraint
                 where conrelid = 'public.estoque_movimentacoes'::regclass
                   and conname = 'estoque_movimentacoes_pedido_id_tipo_key') then
    begin
      alter table public.estoque_movimentacoes
        add constraint estoque_movimentacoes_pedido_id_tipo_key unique (pedido_id, tipo);
    exception when others then
      raise notice 'Unique de estoque_movimentacoes não criada: %', sqlerrm;
    end;
  end if;
end $$;

-- ═══════════════════════════════════════════════════════════════════════
-- 15) FINALIZAÇÃO: recarrega o schema no PostgREST e remove helpers
-- ═══════════════════════════════════════════════════════════════════════

notify pgrst, 'reload schema';

drop function if exists public._cons_ensure_policy(text, text, text);
drop function if exists public._cons_drop_policy(text, text);
drop function if exists public._cons_ensure_fk(text, text, text, text, text);

-- ═══════════════════════════════════════════════════════════════════════
-- 16) PASSO 2 — PROMOVER O PRIMEIRO ADMIN
--     (descomente, troque pelo SEU e-mail e rode este trecho sozinho)
-- ═══════════════════════════════════════════════════════════════════════
--
-- update public.perfis set funcao = 'admin' where email = 'seu-email-aqui@exemplo.com';
--
-- Confira:
-- select id, nome, email, funcao from public.perfis where email = 'seu-email-aqui@exemplo.com';
--
-- ═══════════════════════════════════════════════════════════════════════
-- 17) VERIFICAÇÕES SUGERIDAS APÓS RODAR (opcional)
-- ═══════════════════════════════════════════════════════════════════════
--
-- a) Colunas críticas existem?
-- select column_name from information_schema.columns
--  where table_name in ('produtos','pedidos','cartoes_usuario','unidades')
--    and column_name in ('frete_gratis','desconto_cupom','cupom_id','transacao_id','slug','mes_validade');
--
-- b) Realtime ligado?
-- select tablename from pg_publication_tables where pubname = 'supabase_realtime'
--  and tablename in ('mensagens','pedidos','pedido_historico');
--
-- c) Funil de vendas: crie um cupom de teste no admin (aba Cupons) e finalize
--    uma compra de teste; o total do pedido deve sair já com o desconto.
-- ═══════════════════════════════════════════════════════════════════════

