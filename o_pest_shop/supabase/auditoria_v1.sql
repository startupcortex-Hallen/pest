-- ═══════════════════════════════════════════════════════════════
-- AUDITORIA V1 — Segurança, máquina de estados e estoque
-- ═══════════════════════════════════════════════════════════════

-- ── 1. TABELAS DE AUDITORIA ────────────────────────────────────

create table if not exists estoque_movimentacoes (
  id bigint generated always as identity primary key,
  produto_id bigint not null references produtos(id) on delete cascade,
  pedido_id bigint references pedidos(id),
  tipo text not null check (tipo in ('venda','devolucao','reposicao','ajuste')),
  quantidade int not null check (quantidade <> 0),
  motivo text,
  criado_por uuid references perfis(id),
  criado_em timestamptz not null default now(),
  unique (pedido_id, tipo)
);

create table if not exists pedido_historico (
  id bigint generated always as identity primary key,
  pedido_id bigint not null references pedidos(id) on delete cascade,
  status text not null,
  alterado_por uuid references perfis(id),
  criado_em timestamptz not null default now()
);

create index if not exists idx_estoque_mov_pedido on estoque_movimentacoes (pedido_id);
create index if not exists idx_estoque_mov_produto on estoque_movimentacoes (produto_id);
create index if not exists idx_pedido_historico_pedido on pedido_historico (pedido_id, criado_em desc);

-- ── 2. CONSTRAINTS ─────────────────────────────────────────────

update produtos set estoque = 0 where estoque < 0;
alter table produtos drop constraint if exists chk_estoque_nao_negativo;
alter table produtos add constraint chk_estoque_nao_negativo check (estoque >= 0);

alter table pedidos drop constraint if exists chk_status_valido;
alter table pedidos add constraint chk_status_valido check (
  status in ('pendente','pago','em_preparo','pronto_para_entrega','saiu_para_entrega','entregue','cancelado')
);

create index if not exists idx_pedidos_status on pedidos (status);
create index if not exists idx_pedidos_entregador on pedidos (entregador_id) where entregador_id is not null;
create index if not exists idx_pedido_itens_produto on pedido_itens (produto_id);

-- ── 3. RLS ─────────────────────────────────────────────────────

-- pedidos: leitura por papel (insert próprio já existe; update/delete via RPC)
alter table pedidos enable row level security;

do $$
begin
  if not exists (select 1 from pg_policy where polname = 'pedidos_select_cliente') then
    execute 'create policy "pedidos_select_cliente" on pedidos for select to authenticated using (user_id = auth.uid())';
  end if;
  if not exists (select 1 from pg_policy where polname = 'pedidos_select_admin') then
    execute 'create policy "pedidos_select_admin" on pedidos for select to authenticated
             using ((select funcao from perfis where id = auth.uid()) = ''admin'')';
  end if;
  if not exists (select 1 from pg_policy where polname = 'pedidos_select_loja') then
    execute 'create policy "pedidos_select_loja" on pedidos for select to authenticated
             using ((select funcao from perfis where id = auth.uid()) = ''atendente''
               and unidade_id = (select unidade_id from perfis where id = auth.uid()))';
  end if;
end $$;

-- pedido_itens: leitura vinculada ao pedido (por papel)
alter table pedido_itens enable row level security;

do $$
begin
  if not exists (select 1 from pg_policy where polname = 'pedido_itens_select_cliente') then
    execute 'create policy "pedido_itens_select_cliente" on pedido_itens for select to authenticated
             using (exists (select 1 from pedidos where pedidos.id = pedido_itens.pedido_id and pedidos.user_id = auth.uid()))';
  end if;
  if not exists (select 1 from pg_policy where polname = 'pedido_itens_select_admin') then
    execute 'create policy "pedido_itens_select_admin" on pedido_itens for select to authenticated
             using ((select funcao from perfis where id = auth.uid()) = ''admin'')';
  end if;
  if not exists (select 1 from pg_policy where polname = 'pedido_itens_select_loja') then
    execute 'create policy "pedido_itens_select_loja" on pedido_itens for select to authenticated
             using (exists (select 1 from pedidos where pedidos.id = pedido_itens.pedido_id
               and (select funcao from perfis where id = auth.uid()) = ''atendente''
               and pedidos.unidade_id = (select unidade_id from perfis where id = auth.uid())))';
  end if;
  if not exists (select 1 from pg_policy where polname = 'pedido_itens_select_entregador') then
    execute 'create policy "pedido_itens_select_entregador" on pedido_itens for select to authenticated
             using (exists (select 1 from pedidos where pedidos.id = pedido_itens.pedido_id and pedidos.entregador_id = auth.uid()))';
  end if;
end $$;

-- cartoes_usuario: somente o próprio usuário
alter table cartoes_usuario enable row level security;

do $$
begin
  if not exists (select 1 from pg_policy where polname = 'cartoes_own_all') then
    execute 'create policy "cartoes_own_all" on cartoes_usuario for all to authenticated
             using (user_id = auth.uid()) with check (user_id = auth.uid())';
  end if;
end $$;

-- carrinho / favoritos: somente o próprio usuário
alter table carrinho enable row level security;
do $$
begin
  if not exists (select 1 from pg_policy where polname = 'carrinho_own_all') then
    execute 'create policy "carrinho_own_all" on carrinho for all to authenticated
             using (user_id = auth.uid()) with check (user_id = auth.uid())';
  end if;
end $$;

alter table favoritos enable row level security;
do $$
begin
  if not exists (select 1 from pg_policy where polname = 'favoritos_own_all') then
    execute 'create policy "favoritos_own_all" on favoritos for all to authenticated
             using (user_id = auth.uid()) with check (user_id = auth.uid())';
  end if;
end $$;

-- cupons: leitura pública, escrita apenas admin
alter table cupons enable row level security;
do $$
begin
  if not exists (select 1 from pg_policy where polname = 'cupons_select_all') then
    execute 'create policy "cupons_select_all" on cupons for select to authenticated using (true)';
  end if;
  if not exists (select 1 from pg_policy where polname = 'cupons_write_admin') then
    execute 'create policy "cupons_write_admin" on cupons for all to authenticated
             using ((select funcao from perfis where id = auth.uid()) = ''admin'')
             with check ((select funcao from perfis where id = auth.uid()) = ''admin'')';
  end if;
end $$;

-- produtos: leitura autenticada, escrita admin ou atendente da unidade
alter table produtos enable row level security;
do $$
begin
  if not exists (select 1 from pg_policy where polname = 'produtos_select_all') then
    execute 'create policy "produtos_select_all" on produtos for select to authenticated using (true)';
  end if;
  if not exists (select 1 from pg_policy where polname = 'produtos_write_admin') then
    execute 'create policy "produtos_write_admin" on produtos for all to authenticated
             using ((select funcao from perfis where id = auth.uid()) = ''admin'')
             with check ((select funcao from perfis where id = auth.uid()) = ''admin'')';
  end if;
  if not exists (select 1 from pg_policy where polname = 'produtos_write_atendente') then
    execute 'create policy "produtos_write_atendente" on produtos for all to authenticated
             using (unidade_id = (select unidade_id from perfis where id = auth.uid()))
             with check (unidade_id = (select unidade_id from perfis where id = auth.uid()))';
  end if;
end $$;

-- perfis: equipe (atendente/entregador) precisa ler dados de contato dos clientes
do $$
begin
  if not exists (select 1 from pg_policy where polname = 'perfis_select_equipe') then
    execute 'create policy "perfis_select_equipe" on perfis for select to authenticated
             using ((select funcao from perfis where id = auth.uid()) in (''admin'',''atendente'',''entregador''))';
  end if;
end $$;

-- histórico: leitura por papel (escrita apenas pelo trigger)
alter table pedido_historico enable row level security;
do $$
begin
  if not exists (select 1 from pg_policy where polname = 'hist_select') then
    execute 'create policy "hist_select" on pedido_historico for select to authenticated
             using (exists (select 1 from pedidos where pedidos.id = pedido_historico.pedido_id and (
               pedidos.user_id = auth.uid()
               or pedidos.entregador_id = auth.uid()
               or (select funcao from perfis where id = auth.uid()) = ''admin''
               or ((select funcao from perfis where id = auth.uid()) = ''atendente''
                   and pedidos.unidade_id = (select unidade_id from perfis where id = auth.uid()))
             )))';
  end if;
end $$;

-- movimentações de estoque: leitura apenas loja/admin (escrita pelo trigger)
alter table estoque_movimentacoes enable row level security;
do $$
begin
  if not exists (select 1 from pg_policy where polname = 'mov_select_loja') then
    execute 'create policy "mov_select_loja" on estoque_movimentacoes for select to authenticated
             using ((select funcao from perfis where id = auth.uid()) in (''admin'',''atendente''))';
  end if;
end $$;

-- ── 4. REVOKE: transições de pedido SOMENTE via RPC ───────────

revoke update, delete on pedidos from authenticated;
revoke update, delete on pedido_itens from authenticated;

-- ── 5. TRIGGER — MÁQUINA DE ESTADOS + ESTOQUE ─────────────────

create or replace function fn_pedido_status()
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
  v_funcao := coalesce((select funcao from perfis where id = v_uid), '');
  v_unidade := (select unidade_id from perfis where id = v_uid);

  -- INSERT: nasce pendente + histórico
  if tg_op = 'INSERT' then
    new.status := 'pendente';
    insert into pedido_historico (pedido_id, status, alterado_por) values (new.id, 'pendente', v_uid);
    return new;
  end if;

  -- Atribuição de entregador (status inalterado): somente loja/admin
  if new.status = old.status and new.entregador_id is distinct from old.entregador_id then
    if v_funcao not in ('admin','atendente') then
      raise exception 'Somente a loja pode atribuir entregador';
    end if;
    if v_funcao = 'atendente' and v_unidade is distinct from old.unidade_id then
      raise exception 'Sem permissão para pedidos de outra unidade';
    end if;
    return new;
  end if;

  -- Sem mudança de status
  if new.status = old.status then return new; end if;

  -- CANCELADO (idempotente: devolução 1x)
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

    if exists (select 1 from estoque_movimentacoes where pedido_id = old.id and tipo = 'venda')
       and not exists (select 1 from estoque_movimentacoes where pedido_id = old.id and tipo = 'devolucao') then
      for v_item in select * from pedido_itens where pedido_id = old.id loop
        update produtos set estoque = estoque + v_item.quantidade where id = v_item.produto_id;
        insert into estoque_movimentacoes (produto_id, pedido_id, tipo, quantidade, motivo, criado_por)
        values (v_item.produto_id, old.id, 'devolucao', v_item.quantidade,
                'Cancelamento do pedido ' || old.id, v_uid);
      end loop;
    end if;
    new.cancelado_em := now();
    insert into pedido_historico (pedido_id, status, alterado_por) values (old.id, 'cancelado', v_uid);
    return new;
  end if;

  -- PAGO (dono ou admin) → baixa atômica → em_preparo automático
  if new.status = 'pago' then
    if old.status <> 'pendente' then
      raise exception 'Transição inválida: % → pago', old.status;
    end if;
    if v_uid <> old.user_id and v_funcao <> 'admin' then
      raise exception 'Apenas o cliente dono ou o admin podem confirmar o pagamento';
    end if;

    if not exists (select 1 from estoque_movimentacoes where pedido_id = old.id and tipo = 'venda') then
      for v_item in select * from pedido_itens where pedido_id = old.id loop
        select estoque into v_estoque from produtos where id = v_item.produto_id for update;
        if v_estoque is null then
          raise exception 'Produto % não encontrado', v_item.produto_id;
        end if;
        if v_estoque < v_item.quantidade then
          raise exception 'Estoque insuficiente para "%" (disponível: %, pedido: %)',
            (select nome from produtos where id = v_item.produto_id), v_estoque, v_item.quantidade;
        end if;
        update produtos set estoque = v_estoque - v_item.quantidade where id = v_item.produto_id;
        insert into estoque_movimentacoes (produto_id, pedido_id, tipo, quantidade, motivo, criado_por)
        values (v_item.produto_id, old.id, 'venda', -v_item.quantidade,
                'Venda do pedido ' || old.id, v_uid);
      end loop;
    end if;

    new.pago_em := now();
    insert into pedido_historico (pedido_id, status, alterado_por) values (old.id, 'pago', v_uid);

    -- pago → em_preparo automático
    new.status := 'em_preparo';
    insert into pedido_historico (pedido_id, status, alterado_por) values (old.id, 'em_preparo', v_uid);
    return new;
  end if;

  -- Demais transições (loja / entregador)
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
    if new.entregador_id is null then
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
    if old.status <> 'saiu_para_entrega' then
      raise exception 'Transição inválida: % → entregue', old.status;
    end if;
    if v_uid is distinct from old.entregador_id then
      raise exception 'Somente o entregador atribuído pode confirmar a entrega';
    end if;
    if new.recebedor_nome is null or length(trim(new.recebedor_nome)) = 0 then
      raise exception 'Informe o nome de quem recebeu';
    end if;
    new.entregue_em := now();
  else
    raise exception 'Transição não permitida: % → %', old.status, new.status;
  end if;

  insert into pedido_historico (pedido_id, status, alterado_por) values (old.id, new.status, v_uid);
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_pedido_status on pedidos;
create trigger trg_pedido_status
  before insert or update on pedidos
  for each row execute function fn_pedido_status();

-- ── 6. RPCs DE TRANSIÇÃO (defensivas; o trigger valida tudo) ──

create or replace function confirmar_pagamento(p_pedido_id bigint, p_metodo text)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  update pedidos
  set status = 'pago', pagamento = p_metodo
  where id = p_pedido_id and user_id = auth.uid() and status = 'pendente';
end;
$$;

create or replace function cancelar_pedido(p_pedido_id bigint)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  update pedidos
  set status = 'cancelado'
  where id = p_pedido_id
    and (user_id = auth.uid()
      or (select funcao from perfis where id = auth.uid()) in ('admin','atendente'));
end;
$$;

create or replace function alterar_status_pedido(p_pedido_id bigint, p_status text, p_recebedor text default null)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  update pedidos
  set status = p_status,
      recebedor_nome = coalesce(p_recebedor, recebedor_nome)
  where id = p_pedido_id;
end;
$$;

create or replace function atribuir_entregador(p_pedido_id bigint, p_entregador_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  update pedidos set entregador_id = p_entregador_id where id = p_pedido_id;
end;
$$;

-- blindagem do RPC antigo de baixa (só loja/admin; baixa real é do trigger)
create or replace function decrementar_estoque(produto_id bigint, quantidade int)
returns int
language plpgsql security definer set search_path = public
as $$
declare
  v_estoque int;
  v_funcao text;
begin
  v_funcao := coalesce((select funcao from perfis where id = auth.uid()), '');
  if v_funcao not in ('admin','atendente') then
    raise exception 'Sem permissão para alterar estoque';
  end if;
  if quantidade <= 0 then raise exception 'Quantidade inválida'; end if;
  select estoque into v_estoque from produtos where id = produto_id for update;
  if v_estoque is null then raise exception 'Produto não encontrado'; end if;
  if v_estoque < quantidade then
    raise exception 'Estoque insuficiente para o produto % (disponível: %)', produto_id, v_estoque;
  end if;
  update produtos set estoque = v_estoque - quantidade where id = produto_id;
  insert into estoque_movimentacoes (produto_id, tipo, quantidade, motivo, criado_por)
  values (produto_id, 'ajuste', -quantidade, 'Ajuste manual', auth.uid());
  return v_estoque - quantidade;
end;
$$;
