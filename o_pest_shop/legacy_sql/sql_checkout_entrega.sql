-- ═══════════════════════════════════════════════════════════════
-- O PEST - SHOP · CHECKOUT / ENTREGA (padrão grande varejo)
-- Adiciona o RPC de confirmação de pagamento que o app chama
-- (lib/services/checkout_service.dart -> rpc('confirmar_pagamento'))
-- O trigger fn_pedido_status (já criado) faz a baixa de estoque
-- atômica e avança o pedido para 'em_preparo' automaticamente.
-- ═══════════════════════════════════════════════════════════════

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

  -- Somente o dono (ou admin) pode confirmar o pagamento
  if v_pedido.user_id <> auth.uid() and public.funcao_usuario() <> 'admin' then
    raise exception 'Você não pode confirmar o pagamento deste pedido';
  end if;

  -- Idempotente: se já saiu de 'pendente', não faz nada e devolve o estado atual
  if v_pedido.status <> 'pendente' then
    select jsonb_build_object(
      'id', p_pedido.id,
      'status', v_pedido.status,
      'total', v_pedido.total
    ) into v_result;
    return v_result;
  end if;

  -- Marca pagamento + pago; o trigger fn_pedido_status baixa o estoque,
  -- registra histórico e avança para 'em_preparo'
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

grant execute on function public.confirmar_pagamento(bigint, text) to authenticated;

-- (Opcional — lojas grandes) Pedidos em tempo real para o admin
-- Descomente se quiser o painel admin atualizando pedidos sozinho:
-- alter publication supabase_realtime add table pedidos;