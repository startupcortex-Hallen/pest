-- ═══════════════════════════════════════════════════════════════════════
-- O PEST - SHOP · FASE 2 — ENDEREÇOS DE ENTREGA + TAXA DE FRETE
-- Rodar no Supabase > SQL Editor DEPOIS do CONSOLIDACAO_FINAL.sql.
-- É IDEMPOTENTE: pode rodar mais de uma vez.
-- ═══════════════════════════════════════════════════════════════════════
-- O QUE ESTE SCRIPT FAZ:
--   1. Cria a tabela enderecos_usuario (CRUD de endereços do cliente)
--   2. Adiciona taxa_entrega e frete_gratis_acima nas unidades
--   3. Adiciona taxa_entrega nos pedidos
--   4. Recalcula o total do pedido como: itens - cupom + taxa de entrega
--   5. Atualiza o finalizar_checkout para cobrar a taxa NO SERVIDOR
--      (com frete grátis por produto e regra de valor mínimo da loja)
-- ═══════════════════════════════════════════════════════════════════════

-- 1) ENDEREÇOS DO USUÁRIO ─────────────────────────────────────────────

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

do $$
begin
  if not exists (select 1 from pg_policy
                 where polname = 'enderecos_own_all'
                   and polrelid = 'public.enderecos_usuario'::regclass) then
    execute $sql$create policy "enderecos_own_all" on public.enderecos_usuario
      for all to authenticated
      using (user_id = auth.uid())
      with check (user_id = auth.uid())$sql$;
  end if;

  if not exists (select 1 from pg_policy
                 where polname = 'enderecos_admin_select'
                   and polrelid = 'public.enderecos_usuario'::regclass) then
    execute $sql$create policy "enderecos_admin_select" on public.enderecos_usuario
      for select to authenticated
      using (public.funcao_usuario() = 'admin')$sql$;
  end if;
end $$;

-- 2) COLUNAS DE FRETE ─────────────────────────────────────────────────

alter table public.unidades add column if not exists taxa_entrega numeric not null default 0;
alter table public.unidades add column if not exists frete_gratis_acima numeric;
alter table public.pedidos add column if not exists taxa_entrega numeric not null default 0;

-- 3) TOTAL DO PEDIDO = ITENS − CUPOM + TAXA ───────────────────────────

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

-- 4) CHECKOUT COM TAXA DE ENTREGA (calculada no SERVIDOR) ─────────────

drop function if exists public.finalizar_checkout(uuid, jsonb, numeric, bigint, text, text, text);

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
  v_taxa_unidade numeric;
  v_taxa_base numeric;
  v_frete_acima numeric;
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

    -- Taxa de entrega da unidade (só para entrega; retirada é grátis)
    v_taxa_unidade := 0;
    if p_tipo_entrega = 'entrega' then
      select coalesce(u.taxa_entrega, 0), u.frete_gratis_acima
        into v_taxa_base, v_frete_acima
        from public.unidades u where u.id = v_linha.unidade_id;

      v_taxa_unidade := coalesce(v_taxa_base, 0);

      -- Todos os itens da unidade têm frete grátis? Então não cobra.
      if not exists (
        select 1
          from jsonb_array_elements(v_linha.itens) as t(item)
          join public.produtos p on p.id = (t.item->>'produto_id')::bigint
         where coalesce(p.frete_gratis, false) = false
      ) then
        v_taxa_unidade := 0;
      end if;

      -- Atingiu o valor mínimo para frete grátis da loja?
      if v_frete_acima is not null and v_subtotal_unidade >= v_frete_acima then
        v_taxa_unidade := 0;
      end if;
    end if;

    v_total := greatest(v_subtotal_unidade - v_desconto_unidade, 0) + v_taxa_unidade;

    v_unidade_nome := 'Loja';
    v_pix := null;
    select nome, pix_key into v_unidade_nome, v_pix
      from public.unidades where id = v_linha.unidade_id;

    insert into public.pedidos (user_id, unidade_id, status, total, desconto_cupom, cupom_id,
                                taxa_entrega, pix_copia_cola, tipo_entrega,
                                endereco_entrega, cep_entrega)
    values (p_user_id, v_linha.unidade_id, 'pendente', v_total, v_desconto_unidade, p_cupom_id,
            v_taxa_unidade, v_pix, p_tipo_entrega,
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
      'desconto_cupom', v_desconto_unidade,
      'taxa_entrega', v_taxa_unidade,
      'itens_count', jsonb_array_length(v_linha.itens)
    );
  end loop;

  return v_pedidos;
end $$;

-- 5) GRANTS ───────────────────────────────────────────────────────────

revoke all on function public.finalizar_checkout(uuid, jsonb, numeric, bigint, text, text, text) from public, anon;
grant execute on function public.finalizar_checkout(uuid, jsonb, numeric, bigint, text, text, text) to authenticated;

do $$
begin
  begin
    execute 'grant execute on function public.finalizar_checkout(uuid, jsonb, numeric, bigint, text, text, text) to service_role';
  exception when others then
    raise notice 'Grant para service_role falhou: %', sqlerrm;
  end;
end $$;

notify pgrst, 'reload schema';

-- FIM — teste: faça uma compra "Entrega" e confira o total do pedido
-- (itens − cupom + taxa) e que retirada continua sem taxa.
