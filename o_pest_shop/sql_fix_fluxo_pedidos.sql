-- ═══════════════════════════════════════════════════════════════
-- O PEST - SHOP · CORREÇÃO DO FLUXO DE PEDIDOS (rode inteiro)
-- Resolve: (1) conflito de assinaturas das RPCs (2 args vs 3 args),
-- (2) falta de GRANT nas versões do supabase/, (3) checkout não
-- atômico que criava pedidos "fantasma", (4) realtime desligado.
-- Idempotente: pode rodar mais de uma vez.
-- ═══════════════════════════════════════════════════════════════

-- ── 0) Remove versões conflitantes (return type/signature) ─────
drop function if exists public.confirmar_pagamento(text, text);
drop function if exists public.confirmar_pagamento(bigint, text);
drop function if exists public.alterar_status_pedido(bigint, text);
drop function if exists public.alterar_status_pedido(bigint, text, text);
drop function if exists public.atribuir_entregador(bigint, uuid);
drop function if exists public.cancelar_pedido(bigint);
drop function if exists public.finalizar_checkout(uuid, jsonb, numeric, bigint, text, text, text);

-- ── 1) Confirmação de pagamento (cliente/admin) ────────────────
-- idempotente; o trigger fn_pedido_status baixa o estoque e avança
-- para 'em_preparo'.
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
  v_pedido pedidos%rowtype;
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
end;
$$;

-- ── 2) Alterar status (loja + entregador atribuído) ─────────────
-- Assinatura ÚNICA com p_recebedor default null: o admin chama com 2
-- args e o entregador com 3 (envia o nome de quem recebeu).
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
  v_pedido pedidos%rowtype;
begin
  select * into v_pedido from public.pedidos where id = p_pedido_id;
  if v_pedido.id is null then
    raise exception 'Pedido não encontrado';
  end if;

  if v_funcao = 'admin' then
    null;
  elsif v_funcao in ('atendente','gestor') then
    v_unidade := (select unidade_id from perfis where id = auth.uid());
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
end;
$$;

-- ── 3) Atribuir/remover entregador (loja) ───────────────────────
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
  v_pedido pedidos%rowtype;
begin
  select * into v_pedido from public.pedidos where id = p_pedido_id;
  if v_pedido.id is null then
    raise exception 'Pedido não encontrado';
  end if;

  if v_funcao = 'admin' then
    null;
  elsif v_funcao in ('atendente','gestor') then
    v_unidade := (select unidade_id from perfis where id = auth.uid());
    if v_pedido.unidade_id is distinct from v_unidade then
      raise exception 'Sem permissão para pedidos de outra loja';
    end if;
  else
    raise exception 'Sem permissão para atribuir entregador';
  end if;

  update public.pedidos set entregador_id = p_entregador_id where id = p_pedido_id;
end;
$$;

-- ── 4) Cancelar pedido (dono/admin/atendente da unidade) ────────
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
             and unidade_id = (select unidade_id from perfis where id = auth.uid())));
  if not found then
    raise exception 'Sem permissão para cancelar este pedido';
  end if;
end;
$$;

-- ── 5) CHECKOUT ATÔMICO ─────────────────────────────────────────
-- Cria os pedidos (1 por unidade) + itens em UMA transação server-side.
-- Se qualquer inserção falhar, TUDO é revertido (sem pedidos órfãos).
-- p_itens: jsonb array com {produto_id, quantidade, cor, preco_atual,
-- total, unidade_id}. Retorna jsonb array com os pedidos criados.
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
  v_produto_nome text;
  v_unidade_nome text;
  v_pix text;
  v_subtotal_unidade numeric := 0;
  v_subtotal_geral numeric := 0;
  v_desconto_unidade numeric := 0;
  v_total numeric := 0;
  v_pedido_id bigint;
  v_pedidos jsonb := '[]'::jsonb;
begin
  if p_user_id is distinct from auth.uid() then
    raise exception 'Você não pode criar pedidos para outro usuário';
  end if;

  if jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception 'Carrinho vazio';
  end if;

  -- Re-valida estoque NO momento da compra (locks nas linhas de produto)
  for v_item in select * from jsonb_array_elements(p_itens) as t(item) loop
    v_el := v_item.item;
    v_produto_id := (v_el->>'produto_id')::bigint;
    v_qtd := (v_el->>'quantidade')::int;
    if v_qtd <= 0 then
      raise exception 'Quantidade inválida para o produto';
    end if;
    select estoque, nome into v_estoque, v_produto_nome
      from produtos where id = v_produto_id for update;
    if not found then
      raise exception 'Produto não encontrado';
    end if;
    if v_estoque < v_qtd then
      raise exception '"%" com estoque insuficiente (restam %, pedido: %)',
        v_produto_nome, v_estoque, v_qtd;
    end if;
    v_subtotal_geral := v_subtotal_geral + coalesce((v_el->>'total')::numeric, 0);
  end loop;

  -- Agrupa por unidade (marketplace)
  for v_linha in
    select coalesce((t.item->>'unidade_id')::bigint, 1) as unidade_id,
           jsonb_agg(t.item order by (t.item->>'produto_id')::bigint) as itens
      from jsonb_array_elements(p_itens) as t(item)
     group by 1
  loop
    v_subtotal_unidade := 0;
    for v_item in select * from jsonb_array_elements(v_linha.itens) as t(item) loop
      v_subtotal_unidade := v_subtotal_unidade + coalesce((v_item.item->>'total')::numeric, 0);
    end loop;

    v_desconto_unidade := 0;
    if p_cupom_desconto_total > 0 and v_subtotal_geral > 0 then
      v_desconto_unidade := p_cupom_desconto_total * (v_subtotal_unidade / v_subtotal_geral);
    end if;
    v_total := greatest(v_subtotal_unidade - v_desconto_unidade, 0);

    v_unidade_nome := 'Loja';
    v_pix := null;
    select nome, pix_key into v_unidade_nome, v_pix
      from unidades where id = v_linha.unidade_id;

    insert into pedidos (user_id, unidade_id, status, total, pix_copia_cola,
                         tipo_entrega, endereco_entrega, cep_entrega)
    values (p_user_id, v_linha.unidade_id, 'pendente', v_total, v_pix,
            p_tipo_entrega,
            case when p_tipo_entrega = 'entrega' then p_endereco_entrega else null end,
            case when p_tipo_entrega = 'entrega' then p_cep_entrega else null end)
    returning id into v_pedido_id;

    insert into pedido_itens (pedido_id, produto_id, quantidade, preco_unitario, cor)
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

  -- Uso do cupom (incremento atômico dentro da transação)
  if p_cupom_id is not null then
    update cupons set usos_atuais = usos_atuais + 1 where id = p_cupom_id;
  end if;

  return v_pedidos;
end;
$$;

-- ── 6) GRANTS para o app (authenticated) ────────────────────────
grant execute on function public.confirmar_pagamento(bigint, text) to authenticated;
grant execute on function public.alterar_status_pedido(bigint, text, text) to authenticated;
grant execute on function public.atribuir_entregador(bigint, uuid) to authenticated;
grant execute on function public.cancelar_pedido(bigint) to authenticated;
grant execute on function public.finalizar_checkout(uuid, jsonb, numeric, bigint, text, text, text) to authenticated;

-- ── 7) REALTIME: pedidos + histórico na publication ─────────────
-- Sem isso o painel do admin e a tela do cliente (PostgresChanges)
-- nunca recebem atualizações ao vivo.
do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'pedidos') then
    execute 'alter publication supabase_realtime add table public.pedidos';
  end if;
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'pedido_historico') then
    execute 'alter publication supabase_realtime add table public.pedido_historico';
  end if;
end $$;
