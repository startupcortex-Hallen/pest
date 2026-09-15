-- ═══════════════════════════════════════════════════════════════
-- CHECKOUT: RLS + estoque atômico + método de pagamento
-- ═══════════════════════════════════════════════════════════════

-- 1) Coluna de método de pagamento no pedido
alter table pedidos add column if not exists pagamento text;

-- 2) RPC de baixa de estoque (atômico + validação) — SECURITY DEFINER
--    O app chama esta função; o cliente NUNCA edita produtos diretamente.
create or replace function decrementar_estoque(produto_id bigint, quantidade int)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_estoque int;
begin
  if quantidade <= 0 then
    raise exception 'Quantidade inválida';
  end if;

  select estoque into v_estoque from produtos where id = produto_id for update;
  if v_estoque is null then
    raise exception 'Produto não encontrado';
  end if;
  if v_estoque < quantidade then
    raise exception 'Estoque insuficiente para o produto % (disponível: %)', produto_id, v_estoque;
  end if;

  update produtos set estoque = v_estoque - quantidade where id = produto_id;
  return v_estoque - quantidade;
end;
$$;

-- 3) RLS: usuário cria os PRÓPRIOS pedidos
do $$
begin
  if not exists (select 1 from pg_policy where polname = 'pedidos_proprio_insert') then
    execute 'create policy "pedidos_proprio_insert" on pedidos
             for insert to authenticated
             with check (user_id = auth.uid())';
  end if;
end $$;

-- 4) RLS: itens apenas em pedidos do próprio usuário
do $$
begin
  if not exists (select 1 from pg_policy where polname = 'pedido_itens_proprio_insert') then
    execute 'create policy "pedido_itens_proprio_insert" on pedido_itens
             for insert to authenticated
             with check (exists (
               select 1 from pedidos
               where pedidos.id = pedido_itens.pedido_id
                 and pedidos.user_id = auth.uid()
             ))';
  end if;
end $$;
