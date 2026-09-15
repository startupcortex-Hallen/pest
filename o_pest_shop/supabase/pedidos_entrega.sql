-- ═══════════════════════════════════════════════════════════════
-- PEDIDOS: entrega/retirada, entregador e timestamps
-- ═══════════════════════════════════════════════════════════════

alter table pedidos add column if not exists tipo_entrega text default 'retirada';
alter table pedidos add column if not exists endereco_entrega text;
alter table pedidos add column if not exists entregador_id uuid references perfis(id);
alter table pedidos add column if not exists pago_em timestamptz;
alter table pedidos add column if not exists entregue_em timestamptz;
alter table pedidos add column if not exists cancelado_em timestamptz;
alter table pedidos add column if not exists updated_at timestamptz default now();

alter table unidades add column if not exists prazo_retirada_min int default 60;
alter table unidades add column if not exists prazo_entrega_min int default 120;

-- RLS entregador: vê e atualiza apenas as entregas atribuídas a ele
-- (se o RLS de pedidos estiver habilitado no futuro)
do $$
begin
  if not exists (select 1 from pg_policy where polname = 'pedidos_entregador_select') then
    execute 'create policy "pedidos_entregador_select" on pedidos
             for select to authenticated
             using (entregador_id = auth.uid())';
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_policy where polname = 'pedidos_entregador_update') then
    execute 'create policy "pedidos_entregador_update" on pedidos
             for update to authenticated
             using (entregador_id = auth.uid())
             with check (entregador_id = auth.uid())';
  end if;
end $$;
