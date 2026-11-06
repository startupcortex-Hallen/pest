-- ═══════════════════════════════════════════════════════════════
-- O PEST - SHOP · FLUXO DE COMPRA E ENTREGA (cole e rode inteiro)
-- 1) Coluna de COR no carrinho e nos itens do pedido
-- 2) RPCs que o app chama: confirmar_pagamento, alterar_status_pedido,
--    atribuir_entregador
-- Todos idempotentes (pode rodar mais de uma vez).
-- ═══════════════════════════════════════════════════════════════

-- 1) COR SELECIONÁVEL NA COMPRA ─────────────────────────────────

alter table carrinho add column if not exists cor text;
alter table pedido_itens add column if not exists cor text;

-- Carrinho passa a aceitar o MESMO produto em cores diferentes
alter table carrinho drop constraint if exists carrinho_user_id_produto_id_key;
alter table carrinho
  add constraint carrinho_user_id_produto_id_cor_key
  unique (user_id, produto_id, cor);

-- Índice de busca por cor no carrinho
create index if not exists idx_carrinho_user_produto_cor
  on carrinho (user_id, produto_id, cor);

-- 2) RPCs DO FLUXO ──────────────────────────────────────────────

-- 2.1 Confirmação de pagamento (app: checkout_service.dart)
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
  v_result jsonb;
begin
  select * into v_pedido from public.pedidos where id = p_pedido_id;

  if v_pedido.id is null then
    raise exception 'Pedido % não encontrado', p_pedido_id;
  end if;

  if v_pedido.user_id <> auth.uid() and public.funcao_usuario() <> 'admin' then
    raise exception 'Você não pode confirmar o pagamento deste pedido';
  end if;

  if v_pedido.status <> 'pendente' then
    select jsonb_build_object(
      'id', p_pedido_id,
      'status', v_pedido.status,
      'total', v_pedido.total
    ) into v_result;
    return v_result;
  end if;

  update public.pedidos
     set pagamento = p_metodo,
         status = 'pago'
   where id = p_pedido_id;

  select jsonb_build_object(
    'id', v_pedido.id,
    'status', status,
    'total', total
  ) into v_result
  from public.pedidos
  where id = p_pedido_id;

  return v_result;
end;
$$;

-- 2.2 Loja altera o status (app: admin_service.dart → alterar_status_pedido)
create or replace function public.alterar_status_pedido(
  p_pedido_id bigint,
  p_status text
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
    raise exception 'Sem permissão para alterar pedidos';
  end if;

  if p_status = v_pedido.status then return; end if;
  -- A máquina de estados (trigger fn_pedido_status) valida a transição
  update public.pedidos set status = p_status where id = p_pedido_id;
end;
$$;

-- 2.3 Loja atribui/remove entregador (app: admin tabs → atribuir_entregador)
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

grant execute on function public.confirmar_pagamento(bigint, text) to authenticated;
grant execute on function public.alterar_status_pedido(bigint, text) to authenticated;
grant execute on function public.atribuir_entregador(bigint, uuid) to authenticated;