-- ═══════════════════════════════════════════════════════════════════════
-- O PEST - SHOP · BLINDAGEM DO CHECKOUT E DOS PAGAMENTOS — v1
--
-- Rode DEPOIS de:
--   1. CONSOLIDACAO_FINAL.sql
--   2. FASE2_ENDERECOS_FRETE.sql
--   3. migrations/20261017120000_pagamentos_gateway.sql
--   4. migrations/20261018130000_revogar_rpc_publicas.sql
--
-- O que corrige:
--   • reserva de estoque no checkout (impede vender o mesmo item 2x);
--   • devolução de estoque e do cupom ao cancelar/expirar;
--   • expiração coerente com PIX (30 min) e boleto (3 dias + 1 dia de
--     carência), sem cancelar boleto que ainda pode ser pago;
--   • cancelamento server-side (service_role/cron) dos pedidos;
--   • colunas de revisão manual do pagamento e de idempotência do webhook;
--   • revogação definitiva das RPCs antigas de confirmação manual;
--   • recria o checkout com checkout_id (agrupa um carrinho com N pedidos).
--
-- Idempotente: pode rodar mais de uma vez.
-- ═══════════════════════════════════════════════════════════════════════

-- ── 0) Colunas e tabelas que podem faltar em bases antigas ─────────────

alter table public.pedidos add column if not exists pagamento text;
alter table public.pedidos add column if not exists transacao_id text;
alter table public.pedidos add column if not exists pagamento_detalhes text;
alter table public.pedidos add column if not exists pago_em timestamptz;
alter table public.pedidos add column if not exists cancelado_em timestamptz;
alter table public.pedidos add column if not exists entregue_em timestamptz;
alter table public.pedidos add column if not exists recebedor_nome text;
alter table public.pedidos add column if not exists entregador_id uuid;
alter table public.pedidos add column if not exists updated_at timestamptz default now();
alter table public.pedidos add column if not exists desconto_cupom numeric not null default 0;
alter table public.pedidos add column if not exists cupom_id bigint;
alter table public.pedidos add column if not exists taxa_entrega numeric not null default 0;
alter table public.pedidos add column if not exists checkout_id uuid;

update public.pedidos
   set checkout_id = gen_random_uuid()
 where checkout_id is null;

alter table public.pedidos alter column checkout_id set default gen_random_uuid();
create index if not exists idx_pedidos_checkout on public.pedidos(checkout_id);

do $$
begin
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'pedidos'
       and column_name = 'pagamento_id'
  ) then
    alter table public.pedidos
      add column pagamento_id bigint references public.pagamentos(id) on delete set null;
  end if;
end $$;

alter table public.unidades add column if not exists taxa_entrega numeric not null default 0;
alter table public.unidades add column if not exists frete_gratis_acima numeric;

create table if not exists public.estoque_movimentacoes (
  id bigint generated always as identity primary key,
  produto_id bigint not null references public.produtos(id) on delete cascade,
  pedido_id bigint references public.pedidos(id),
  tipo text not null check (tipo in ('venda','devolucao','reposicao','ajuste')),
  quantidade int not null check (quantidade <> 0),
  motivo text,
  criado_por uuid references public.perfis(id),
  criado_em timestamptz not null default now(),
  created_at timestamptz not null default now()
);

alter table public.estoque_movimentacoes add column if not exists criado_em timestamptz;
alter table public.estoque_movimentacoes add column if not exists created_at timestamptz;
alter table public.estoque_movimentacoes alter column criado_em set default now();
alter table public.estoque_movimentacoes alter column created_at set default now();

-- O unique (pedido_id, tipo) impedia pedidos com mais de um item.
-- A idempotência é feita por produto/tipo nas funções abaixo.
do $$
declare
  r record;
begin
  for r in
    select conname
      from pg_constraint
     where conrelid = 'public.estoque_movimentacoes'::regclass
       and contype = 'u'
       and pg_get_constraintdef(oid) ilike '%(pedido_id, tipo)%'
  loop
    execute format('alter table public.estoque_movimentacoes drop constraint %I', r.conname);
  end loop;

  for r in
    select indexname
      from pg_indexes
     where schemaname = 'public'
       and tablename = 'estoque_movimentacoes'
       and indexdef ilike '%unique%'
       and indexdef ilike '%(pedido_id, tipo)%'
  loop
    execute format('drop index if exists public.%I', r.indexname);
  end loop;
end $$;

create index if not exists idx_estoque_mov_pedido on public.estoque_movimentacoes(pedido_id);
create index if not exists idx_estoque_mov_produto on public.estoque_movimentacoes(produto_id);
create index if not exists idx_estoque_mov_pedido_tipo on public.estoque_movimentacoes(pedido_id, tipo);

create table if not exists public.pedido_historico (
  id bigint generated always as identity primary key,
  pedido_id bigint not null references public.pedidos(id) on delete cascade,
  status text not null,
  alterado_por uuid references public.perfis(id),
  criado_em timestamptz not null default now(),
  created_at timestamptz not null default now()
);

alter table public.pedido_historico add column if not exists criado_em timestamptz;
alter table public.pedido_historico add column if not exists created_at timestamptz;
alter table public.pedido_historico alter column criado_em set default now();
alter table public.pedido_historico alter column created_at set default now();

-- Endereços salvos (a tela Meus Endereços já usa esta tabela).
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

-- Revisão manual do pagamento (dinheiro entrou, mas pedido não liberou).
alter table public.pagamentos add column if not exists revisao_manual boolean not null default false;
alter table public.pagamentos add column if not exists revisao_motivo text;
alter table public.pagamentos add column if not exists estornado_em timestamptz;

-- Idempotência/conciliação dos webhooks.
alter table public.pagamentos_eventos add column if not exists payload jsonb;
alter table public.pagamentos_eventos add column if not exists processado_em timestamptz;
alter table public.pagamentos_eventos add column if not exists erro text;
alter table public.pagamentos_eventos add column if not exists tentativas int not null default 0;

create index if not exists idx_pagamentos_eventos_pendentes
  on public.pagamentos_eventos(processado_em)
  where processado_em is null;

-- ── 1) Total do pedido = itens − cupom + taxa ───────────────────────────

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
           ), 0) - coalesce(p.desconto_cupom, 0) + coalesce(p.taxa_entrega, 0),
           0)
   where p.id = v_pedido;

  return null;
end $$;

drop trigger if exists trg_recalcula_total_pedido on public.pedido_itens;
create trigger trg_recalcula_total_pedido
  after insert or update or delete on public.pedido_itens
  for each row execute function public.fn_recalcula_total_pedido();

-- ── 2) Máquina de estados (permite cancelamento server-side) ────────────

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
    if new.checkout_id is null then
      new.checkout_id := gen_random_uuid();
    end if;
    insert into public.pedido_historico (pedido_id, status, alterado_por)
    values (new.id, 'pendente', v_uid);
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
    -- v_uid nulo = service_role/cron (webhook, estorno, expiração).
    if v_uid is null then
      null;
    elsif v_uid = old.user_id then
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

    -- Devolve o estoque reservado/baixado, por produto (idempotente).
    for v_item in
      select i.produto_id, sum(i.quantidade)::int as quantidade
        from public.pedido_itens i
       where i.pedido_id = old.id
       group by i.produto_id
    loop
      if exists (
        select 1 from public.estoque_movimentacoes m
         where m.pedido_id = old.id
           and m.produto_id = v_item.produto_id
           and m.tipo = 'venda'
      ) and not exists (
        select 1 from public.estoque_movimentacoes m
         where m.pedido_id = old.id
           and m.produto_id = v_item.produto_id
           and m.tipo = 'devolucao'
      ) then
        update public.produtos
           set estoque = estoque + v_item.quantidade
         where id = v_item.produto_id;

        insert into public.estoque_movimentacoes
          (produto_id, pedido_id, tipo, quantidade, motivo, criado_por)
        values
          (v_item.produto_id, old.id, 'devolucao', v_item.quantidade,
           'Cancelamento do pedido ' || old.id, v_uid);
      end if;
    end loop;

    new.cancelado_em := now();
    insert into public.pedido_historico (pedido_id, status, alterado_por)
    values (old.id, 'cancelado', v_uid);
    return new;
  end if;

  if new.status = 'pago' then
    if old.status <> 'pendente' then
      raise exception 'Transição inválida: % → pago', old.status;
    end if;

    if v_uid is not null and v_uid <> old.user_id and v_funcao <> 'admin' then
      raise exception 'Apenas o cliente dono ou o admin podem confirmar o pagamento';
    end if;

    -- Baixa o estoque apenas se o checkout ainda não reservou (pedidos antigos).
    for v_item in
      select i.produto_id, sum(i.quantidade)::int as quantidade
        from public.pedido_itens i
       where i.pedido_id = old.id
       group by i.produto_id
    loop
      if not exists (
        select 1 from public.estoque_movimentacoes m
         where m.pedido_id = old.id
           and m.produto_id = v_item.produto_id
           and m.tipo = 'venda'
      ) then
        select estoque into v_estoque
          from public.produtos
         where id = v_item.produto_id
         for update;

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
      end if;
    end loop;

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
      raise exception 'Transição inválida: % → pronto_para_entrega', old.status;
    end if;
    if v_funcao not in ('admin','atendente') then
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

  insert into public.pedido_historico (pedido_id, status, alterado_por)
  values (old.id, new.status, v_uid);
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists trg_pedido_status on public.pedidos;
drop trigger if exists trg_pedido_status_insert on public.pedidos;
create trigger trg_pedido_status_insert
  after insert on public.pedidos
  for each row execute function public.fn_pedido_status();
drop trigger if exists trg_pedido_status_update on public.pedidos;
create trigger trg_pedido_status_update
  before update on public.pedidos
  for each row execute function public.fn_pedido_status();

-- ── 3) Cupom: só devolve quando o checkout inteiro foi cancelado ────────

create or replace function public.fn_restaura_cupom_cancelado()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restantes int := 0;
begin
  if new.status = 'cancelado'
     and old.status is distinct from 'cancelado'
     and new.cupom_id is not null then

    if new.checkout_id is not null then
      select count(*) into v_restantes
        from public.pedidos
       where checkout_id = new.checkout_id
         and id <> new.id
         and status <> 'cancelado';
    elsif new.pagamento_id is not null then
      select count(*) into v_restantes
        from public.pedidos
       where pagamento_id = new.pagamento_id
         and id <> new.id
         and status <> 'cancelado';
    end if;

    if v_restantes = 0 then
      update public.cupons
         set usos_atuais = greatest(coalesce(usos_atuais, 0) - 1, 0)
       where id = new.cupom_id;
    end if;
  end if;

  return new;
end $$;

drop trigger if exists trg_restaura_cupom_cancelado on public.pedidos;
create trigger trg_restaura_cupom_cancelado
  after update of status on public.pedidos
  for each row execute function public.fn_restaura_cupom_cancelado();

-- ── 4) Checkout atômico com reserva de estoque e checkout_id ────────────

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
  v_cores text[];
  v_unidade_nome text;
  v_pix text;
  v_subtotal_unidade numeric;
  v_subtotal_geral numeric := 0;
  v_desconto_geral numeric := 0;
  v_desconto_unidade numeric;
  v_taxa_unidade numeric;
  v_taxa_base numeric;
  v_frete_acima numeric;
  v_total numeric;
  v_pedido_id bigint;
  v_checkout_id uuid := gen_random_uuid();
  v_pedidos jsonb := '[]'::jsonb;
  v_cupom public.cupons%rowtype;
begin
  if p_user_id is distinct from auth.uid() then
    raise exception 'Você não pode criar pedidos para outro usuário';
  end if;

  if jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception 'Carrinho vazio';
  end if;

  -- 1) Valida estoque e soma o subtotal REAL (preço do banco, com lock).
  -- Ordena por produto para reduzir risco de deadlock entre checkouts.
  for v_item in
    select t.value as item
      from jsonb_array_elements(p_itens) with ordinality as t(value, ord)
     order by (t.value->>'produto_id')::bigint
  loop
    v_el := v_item.item;
    v_produto_id := (v_el->>'produto_id')::bigint;
    v_qtd := (v_el->>'quantidade')::int;

    if v_qtd <= 0 then
      raise exception 'Quantidade inválida para o produto';
    end if;

    select p.estoque, p.nome, p.cores,
           case when p.em_promocao and p.preco_promocional is not null
                then p.preco_promocional else p.preco end
      into v_estoque, v_produto_nome, v_cores, v_preco
      from public.produtos p
     where p.id = v_produto_id
     for update;

    if not found then
      raise exception 'Produto nA�o encontrado';
    end if;
    if v_estoque < v_qtd then
      raise exception '"%" com estoque insuficiente (restam %, pedido: %)',
        v_produto_nome, v_estoque, v_qtd;
    end if;

    if coalesce(array_length(v_cores, 1), 0) > 0 then
      if nullif(trim(coalesce(v_el->>'cor', '')), '') is null then
        raise exception 'Selecione a cor do produto "%".', v_produto_nome;
      end if;
      if not exists (
        select 1 from unnest(v_cores) as c
         where lower(trim(c)) = lower(trim(v_el->>'cor'))
      ) then
        raise exception 'Cor "%" invA�lida para o produto "%".', v_el->>'cor', v_produto_nome;
      end if;
    end if;

    v_subtotal_geral := v_subtotal_geral + (coalesce(v_preco, 0) * v_qtd);
  end loop;

  -- 2) Cupom: validado e calculado no SERVIDOR (ignora valor do app).
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
    if v_cupom.uso_maximo is not null
       and coalesce(v_cupom.usos_atuais, 0) >= v_cupom.uso_maximo then
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

  -- 3) Agrupa por unidade e grava pedido + itens + reserva de estoque.
  for v_linha in
    select coalesce(p.unidade_id, coalesce((t.item->>'unidade_id')::bigint, 1)) as unidade_id,
           jsonb_agg(t.item order by (t.item->>'produto_id')::bigint) as itens
      from jsonb_array_elements(p_itens) as t(item)
      join public.produtos p on p.id = (t.item->>'produto_id')::bigint
     group by 1
     order by 1
  loop
    v_subtotal_unidade := 0;
    for v_item in select * from jsonb_array_elements(v_linha.itens) as t(item) loop
      select case when p.em_promocao and p.preco_promocional is not null
                  then p.preco_promocional else p.preco end
        into v_preco
        from public.produtos p
       where p.id = (v_item.item->>'produto_id')::bigint;
      v_subtotal_unidade := v_subtotal_unidade
        + coalesce(v_preco, 0) * (v_item.item->>'quantidade')::int;
    end loop;

    v_desconto_unidade := 0;
    if v_desconto_geral > 0 and v_subtotal_geral > 0 then
      v_desconto_unidade := v_desconto_geral * (v_subtotal_unidade / v_subtotal_geral);
    end if;

    v_taxa_unidade := 0;
    if p_tipo_entrega = 'entrega' then
      select coalesce(u.taxa_entrega, 0), u.frete_gratis_acima
        into v_taxa_base, v_frete_acima
        from public.unidades u
       where u.id = v_linha.unidade_id;

      v_taxa_unidade := coalesce(v_taxa_base, 0);

      if not exists (
        select 1
          from jsonb_array_elements(v_linha.itens) as t(item)
          join public.produtos p on p.id = (t.item->>'produto_id')::bigint
         where coalesce(p.frete_gratis, false) = false
      ) then
        v_taxa_unidade := 0;
      end if;

      if v_frete_acima is not null and v_subtotal_unidade >= v_frete_acima then
        v_taxa_unidade := 0;
      end if;
    end if;

    v_total := greatest(v_subtotal_unidade - v_desconto_unidade, 0) + v_taxa_unidade;

    v_unidade_nome := 'Loja';
    v_pix := null;
    select nome, pix_key into v_unidade_nome, v_pix
      from public.unidades where id = v_linha.unidade_id;

    insert into public.pedidos
      (user_id, unidade_id, status, total, desconto_cupom, cupom_id,
       taxa_entrega, pix_copia_cola, tipo_entrega, endereco_entrega,
       cep_entrega, checkout_id)
    values
      (p_user_id, v_linha.unidade_id, 'pendente', v_total, v_desconto_unidade, p_cupom_id,
       v_taxa_unidade, v_pix, p_tipo_entrega,
       case when p_tipo_entrega = 'entrega' then p_endereco_entrega else null end,
       case when p_tipo_entrega = 'entrega' then p_cep_entrega else null end,
       v_checkout_id)
    returning id into v_pedido_id;

    insert into public.pedido_itens (pedido_id, produto_id, quantidade, preco_unitario, cor)
    select v_pedido_id,
           (t.item->>'produto_id')::bigint,
           (t.item->>'quantidade')::int,
           coalesce((t.item->>'preco_atual')::numeric, 0),
           nullif(t.item->>'cor', '')
      from jsonb_array_elements(v_linha.itens) as t(item);

    -- Reserva o estoque já no checkout (por produto, somando linhas repetidas).
    -- O trigger de "pago" detecta a reserva e não baixa duas vezes.
    for v_item in
      select (t.item->>'produto_id')::bigint as produto_id,
             sum((t.item->>'quantidade')::int)::int as quantidade
        from jsonb_array_elements(v_linha.itens) as t(item)
       group by 1
       order by 1
    loop
      select p.estoque, p.nome
        into v_estoque, v_produto_nome
        from public.produtos p
       where p.id = v_item.produto_id
       for update;

      if not found then
        raise exception 'Produto não encontrado';
      end if;
      if v_estoque < v_item.quantidade then
        raise exception '"%" com estoque insuficiente (restam %, pedido: %)',
          v_produto_nome, v_estoque, v_item.quantidade;
      end if;

      update public.produtos
         set estoque = v_estoque - v_item.quantidade
       where id = v_item.produto_id;

      insert into public.estoque_movimentacoes
        (produto_id, pedido_id, tipo, quantidade, motivo, criado_por)
      values
        (v_item.produto_id, v_pedido_id, 'venda', -v_item.quantidade,
         'Reserva do pedido ' || v_pedido_id, p_user_id);
    end loop;

    v_pedidos := v_pedidos || jsonb_build_object(
      'id', v_pedido_id,
      'checkout_id', v_checkout_id,
      'unidade_id', v_linha.unidade_id,
      'unidade_nome', v_unidade_nome,
      'pix_copia_cola', v_pix,
      'total', v_total,
      'desconto_cupom', v_desconto_unidade,
      'taxa_entrega', v_taxa_unidade,
      'itens_count', jsonb_array_length(v_linha.itens)
    );
  end loop;

  return v_pedidos;
end $$;

-- ── 5) Expiração coerente (PIX 30 min, boleto 3 dias + 1 dia) ───────────

create or replace function public._cancelar_pendentes_expirados_interno(
  p_user_id uuid,
  p_minutos int default 60
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_minutos int := greatest(coalesce(p_minutos, 60), 1);
  v_count int := 0;
  v_pedido record;
begin
  for v_pedido in
    select o.id,
           o.pagamento_id,
           p.metodo,
           p.status as pagamento_status,
           p.expira_em,
           p.boleto_vencimento
      from public.pedidos o
      left join public.pagamentos p on p.id = o.pagamento_id
     where o.status = 'pendente'
       and (p_user_id is null or o.user_id = p_user_id)
       and (
         -- Sem cobrança vinculada: expira no prazo padrão.
         ((o.pagamento_id is null or p.id is null)
           and o.created_at < now() - make_interval(mins => v_minutos))
         -- Cobrança já recusada/cancelada/expirada.
         or p.status in ('recusado','cancelado','expirado')
         -- PIX: o QR Code vale 30 min. Dá 5 min de carência.
         or (p.status in ('pendente','em_analise') and p.metodo = 'pix'
             and coalesce(p.expira_em, o.created_at + interval '30 minutes')
                 < now() - interval '5 minutes')
         -- Boleto: só cancela depois do vencimento + 1 dia (não dá para pagar).
         or (p.status in ('pendente','em_analise') and p.metodo = 'boleto'
             and coalesce(p.boleto_vencimento::timestamp, p.expira_em::timestamp)
                 < now() - interval '1 day')
         -- Cartão em análise NÃO é cancelado automaticamente: pode capturar
         -- depois. A equipe resolve pelo estorno/conciliação.
       )
  loop
    update public.pedidos
       set status = 'cancelado'
     where id = v_pedido.id
       and status = 'pendente';
    if found then
      v_count := v_count + 1;
    end if;
  end loop;

  -- Encerra as cobranças cujos pedidos foram todos cancelados.
  update public.pagamentos p
     set status = 'expirado',
         updated_at = now()
   where p.status in ('pendente','em_analise')
     and exists (select 1 from public.pedidos o where o.pagamento_id = p.id)
     and not exists (
       select 1 from public.pedidos o
        where o.pagamento_id = p.id
          and o.status <> 'cancelado'
     );

  return v_count;
end $$;

create or replace function public.cancelar_pendentes_expirados(p_minutos int default 60)
returns int
language sql
security definer
set search_path = public
as $$
  select public._cancelar_pendentes_expirados_interno(auth.uid(), coalesce(p_minutos, 60));
$$;

create or replace function public.cancelar_pendentes_expirados_todos(p_minutos int default 60)
returns int
language sql
security definer
set search_path = public
as $$
  select public._cancelar_pendentes_expirados_interno(null::uuid, coalesce(p_minutos, 60));
$$;

-- ── 6) Cancele sempre pelo gateway quando há cobrança ativa ─────────────

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

  if p_status = 'cancelado' and exists (
    select 1 from public.pagamentos p
     where p.id = v_pedido.pagamento_id
       and p.status in ('pago','pendente','em_analise')
  ) then
    raise exception 'Pedido com cobrança ativa: use o cancelamento/estorno pelo gateway';
  end if;

  update public.pedidos
     set status = p_status,
         recebedor_nome = coalesce(nullif(trim(p_recebedor), ''), recebedor_nome)
   where id = p_pedido_id;
end $$;

create or replace function public.cancelar_pedido(p_pedido_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1
      from public.pedidos o
      join public.pagamentos p on p.id = o.pagamento_id
     where o.id = p_pedido_id
       and p.status in ('pago','pendente','em_analise')
  ) then
    raise exception 'Pedido com cobrança ativa: use o cancelamento/estorno pelo gateway';
  end if;

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

-- ── 7) Grants (fecha o furo das RPCs antigas) ───────────────────────────

revoke all on function public._cancelar_pendentes_expirados_interno(uuid, int)
  from public, anon, authenticated;

revoke all on function public.cancelar_pendentes_expirados(int)
  from public, anon;
grant execute on function public.cancelar_pendentes_expirados(int)
  to authenticated;

revoke all on function public.cancelar_pendentes_expirados_todos(int)
  from public, anon, authenticated;
grant execute on function public.cancelar_pendentes_expirados_todos(int)
  to service_role;

revoke all on function public.finalizar_checkout(uuid, jsonb, numeric, bigint, text, text, text)
  from public, anon;
grant execute on function public.finalizar_checkout(uuid, jsonb, numeric, bigint, text, text, text)
  to authenticated;

revoke all on function public.alterar_status_pedido(bigint, text, text)
  from public, anon;
grant execute on function public.alterar_status_pedido(bigint, text, text)
  to authenticated;

revoke all on function public.cancelar_pedido(bigint)
  from public, anon;
grant execute on function public.cancelar_pedido(bigint)
  to authenticated;

do $$
begin
  begin
    revoke all on function public.confirmar_pagamento(bigint, text)
      from public, anon, authenticated;
    grant execute on function public.confirmar_pagamento(bigint, text)
      to service_role;
  exception when undefined_function then null;
  end;

  begin
    revoke all on function public.processar_pagamento_cartao(bigint, bigint, int)
      from public, anon, authenticated;
    grant execute on function public.processar_pagamento_cartao(bigint, bigint, int)
      to service_role;
  exception when undefined_function then null;
  end;

  begin
    revoke all on function public.decrementar_estoque(bigint, int)
      from public, anon, authenticated;
    grant execute on function public.decrementar_estoque(bigint, int)
      to service_role;
  exception when undefined_function then null;
  end;
end $$;

-- ── 8) Cron: cancela pendentes mesmo se o cliente não abrir o app ───────

do $$
begin
  begin
    create extension if not exists pg_cron;
  exception when others then
    raise notice 'pg_cron indisponível: %', sqlerrm;
  end;

  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    begin
      perform cron.unschedule('opest-expirar-pendentes');
    exception when others then
      null;
    end;

    perform cron.schedule(
      'opest-expirar-pendentes',
      '*/10 * * * *',
      'select public.cancelar_pendentes_expirados_todos(60)'
    );
  end if;
end $$;

notify pgrst, 'reload schema';
