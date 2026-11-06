-- ═══════════════════════════════════════════════════════════════
-- O PEST - SHOP · BLINDAGEM DA COMPRA + OPERAÇÃO DO ADMIN · v2
--
-- 1) Pedidos/itens/pagamentos só são escritos por RPC e Edge Function.
--    Fecha o INSERT/UPDATE direto que permitia forjar desconto/frete e
--    confirmar pagamento sem dinheiro.
-- 2) Checkout idempotente (finalizar_checkout_v4 + checkout_idempotencia).
-- 3) Valor do pagamento revalidado no servidor antes de cobrar.
-- 4) Pagamento manual auditável para a loja.
-- 5) Status do pedido: cliente não confirma pagamento; gestor entra na
--    máquina de estados; histórico/auditoria completos.
-- 6) Lista de pedidos do admin paginada e filtrada no servidor.
-- 7) Rastreio e resolução de revisão manual auditáveis.
-- 8) RLS de pagamentos/histórico para gestor e atendente da unidade.
--
-- Idempotente: pode rodar mais de uma vez.
-- ═══════════════════════════════════════════════════════════════

-- ── 1) Escrita de pedidos somente via RPC ─────────────────────

revoke insert, update, delete on table public.pedidos from anon, authenticated;
revoke insert, update, delete on table public.pedido_itens from anon, authenticated;
revoke insert, update, delete on table public.pagamentos from anon, authenticated;
revoke insert, update, delete on table public.pagamentos_eventos from anon, authenticated;
revoke insert, update, delete on table public.pedido_historico from anon, authenticated;

grant select on table public.pedidos to authenticated;
grant select on table public.pedido_itens to authenticated;
grant select on table public.pagamentos to authenticated;
grant select on table public.pedido_historico to authenticated;

drop policy if exists "pedidos_proprio_insert" on public.pedidos;
drop policy if exists "pedidos_update" on public.pedidos;
drop policy if exists "pedido_itens_proprio_insert" on public.pedido_itens;

-- ── 2) Idempotência do checkout ──────────────────────────────

create table if not exists public.checkout_idempotencia (
  user_id uuid not null references public.perfis(id) on delete cascade,
  chave uuid not null,
  resposta jsonb not null,
  criado_em timestamptz not null default now(),
  primary key (user_id, chave)
);

alter table public.checkout_idempotencia enable row level security;
revoke all on table public.checkout_idempotencia from anon, authenticated;

create index if not exists idx_pedidos_checkout
  on public.pedidos(user_id, checkout_id);

-- ── 3) Auditoria de ações do pedido ──────────────────────────

create table if not exists public.pedido_auditoria (
  id bigint generated always as identity primary key,
  pedido_id bigint not null references public.pedidos(id) on delete cascade,
  usuario_id uuid references public.perfis(id) on delete set null,
  acao text not null,
  detalhe jsonb,
  criado_em timestamptz not null default now()
);

create index if not exists idx_pedido_auditoria_pedido
  on public.pedido_auditoria(pedido_id, criado_em desc);

alter table public.pedido_auditoria enable row level security;
revoke insert, update, delete on table public.pedido_auditoria from anon, authenticated;
grant select on table public.pedido_auditoria to authenticated;

drop policy if exists "pedido_auditoria_select" on public.pedido_auditoria;
create policy "pedido_auditoria_select" on public.pedido_auditoria
  for select to authenticated
  using (
    public.funcao_usuario() = 'admin'
    or exists (
      select 1 from public.pedidos o
      where o.id = pedido_auditoria.pedido_id
        and (
          o.user_id = auth.uid()
          or o.entregador_id = auth.uid()
          or (
            public.funcao_usuario() in ('atendente','gestor')
            and o.unidade_id = (select unidade_id from public.perfis where id = auth.uid())
          )
        )
    )
  );

-- ── 4) Pagamentos: revisão resolvida + método manual ─────────

alter table public.pagamentos add column if not exists revisao_resolvida_em timestamptz;
alter table public.pagamentos add column if not exists revisao_resolvida_por uuid
  references public.perfis(id) on delete set null;
alter table public.pagamentos add column if not exists revisao_resolucao text;

do $$
declare
  v_constraint record;
begin
  for v_constraint in
    select conname
      from pg_constraint
     where conrelid = 'public.pagamentos'::regclass
       and contype = 'c'
       and pg_get_constraintdef(oid) ilike '%metodo%'
  loop
    execute format('alter table public.pagamentos drop constraint %I', v_constraint.conname);
  end loop;
end $$;

alter table public.pagamentos add constraint pagamentos_metodo_check
  check (metodo in ('pix', 'credito', 'debito', 'boleto', 'manual'));

-- ── 5) RLS: gestor/atendente veem o pagamento da própria unidade ─

drop policy if exists "Cliente - ver pagamentos" on public.pagamentos;
drop policy if exists "pagamentos_select" on public.pagamentos;
create policy "pagamentos_select" on public.pagamentos
  for select to authenticated
  using (
    user_id = auth.uid()
    or public.funcao_usuario() = 'admin'
    or (
      public.funcao_usuario() in ('atendente','gestor')
      and exists (
        select 1 from public.pedidos o
        where o.pagamento_id = pagamentos.id
          and o.unidade_id = (select unidade_id from public.perfis where id = auth.uid())
      )
    )
  );

drop policy if exists "pedido_historico_select" on public.pedido_historico;
create policy "pedido_historico_select" on public.pedido_historico
  for select to authenticated
  using (
    public.funcao_usuario() = 'admin'
    or exists (
      select 1 from public.pedidos o
      where o.id = pedido_historico.pedido_id
        and (
          o.user_id = auth.uid()
          or o.entregador_id = auth.uid()
          or (
            public.funcao_usuario() in ('atendente','gestor')
            and o.unidade_id = (select unidade_id from public.perfis where id = auth.uid())
          )
        )
    )
  );

-- ── 6) Cliente não confirma pagamento nem por update direto ──

create or replace function public.bloqueia_pagamento_pelo_cliente()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'pago'
     and old.status is distinct from 'pago'
     and auth.uid() is not null
     and auth.uid() = old.user_id then
    raise exception 'O pagamento é confirmado pelo gateway. Atualize a página para ver o status.';
  end if;
  return new;
end $$;

drop trigger if exists trg_aaa_bloqueia_pago_cliente on public.pedidos;
create trigger trg_aaa_bloqueia_pago_cliente
  before update on public.pedidos
  for each row execute function public.bloqueia_pagamento_pelo_cliente();

-- ── 7) Máquina de estados atual (pagamento só com cobrança paga) ─

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

  if tg_op = 'INSERT' and new.origem = 'mercadolivre' then
    if new.desconto_cupom is null then
      new.desconto_cupom := 0;
    end if;
    if new.status = 'pago' then
      new.pago_em := coalesce(new.pago_em, now());
    end if;
    insert into public.pedido_historico (pedido_id, status, alterado_por)
    values (new.id, new.status, v_uid);
    return new;
  end if;

  if tg_op = 'UPDATE' and old.origem = 'mercadolivre' and auth.uid() is null then
    if new.status is distinct from old.status then
      if new.status = 'cancelado' then
        if exists (
          select 1 from public.estoque_movimentacoes
           where pedido_id = old.id and tipo = 'venda'
        ) and not exists (
          select 1 from public.estoque_movimentacoes
           where pedido_id = old.id and tipo = 'devolucao'
        ) then
          for v_item in select * from public.pedido_itens where pedido_id = old.id loop
            update public.produtos
               set estoque = estoque + v_item.quantidade
             where id = v_item.produto_id;

            insert into public.estoque_movimentacoes
              (produto_id, pedido_id, tipo, quantidade, motivo, criado_por)
            values
              (v_item.produto_id, old.id, 'devolucao', v_item.quantidade,
               'Cancelamento Mercado Livre do pedido ' || old.id, null);
          end loop;
        end if;
        new.cancelado_em := now();
      elsif new.status = 'entregue' then
        new.entregue_em := now();
      end if;

      insert into public.pedido_historico (pedido_id, status, alterado_por)
      values (old.id, new.status, null);
    end if;

    new.updated_at := now();
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.status := 'pendente';
    if new.desconto_cupom is null then
      new.desconto_cupom := 0;
    end if;
    insert into public.pedido_historico (pedido_id, status, alterado_por)
    values (new.id, 'pendente', v_uid);
    return new;
  end if;

  if new.status = old.status and new.entregador_id is distinct from old.entregador_id then
    if v_funcao not in ('admin', 'atendente', 'gestor') then
      raise exception 'Somente a loja pode atribuir entregador';
    end if;
    if v_funcao in ('atendente', 'gestor') and v_unidade is distinct from old.unidade_id then
      raise exception 'Sem permissão para pedidos de outra unidade';
    end if;
    return new;
  end if;

  if new.status = old.status then return new; end if;

  if new.status = 'cancelado' then
    if v_uid is null then
      null;
    elsif v_uid = old.user_id then
      if old.status not in ('pendente', 'pago', 'em_preparo') then
        raise exception 'O pedido já saiu para entrega; somente a loja pode cancelar';
      end if;
    elsif v_funcao = 'admin' then
      null;
    elsif v_funcao in ('atendente', 'gestor') and v_unidade = old.unidade_id then
      null;
    else
      raise exception 'Sem permissão para cancelar este pedido';
    end if;

    if exists (
      select 1 from public.estoque_movimentacoes
       where pedido_id = old.id and tipo = 'venda'
    ) and not exists (
      select 1 from public.estoque_movimentacoes
       where pedido_id = old.id and tipo = 'devolucao'
    ) then
      for v_item in select * from public.pedido_itens where pedido_id = old.id loop
        update public.produtos
           set estoque = estoque + v_item.quantidade
         where id = v_item.produto_id;

        insert into public.estoque_movimentacoes
          (produto_id, pedido_id, tipo, quantidade, motivo, criado_por)
        values
          (v_item.produto_id, old.id, 'devolucao', v_item.quantidade,
           'Cancelamento do pedido ' || old.id, v_uid);
      end loop;
    end if;

    new.cancelado_em := now();
    insert into public.pedido_historico (pedido_id, status, alterado_por)
    values (old.id, 'cancelado', v_uid);
    return new;
  end if;

  if new.status = 'pago' then
    if old.status <> 'pendente' then
      raise exception 'Transição inválida: % para pago', old.status;
    end if;

    -- Service_role (webhook/conciliação/estorno) não tem auth.uid e pode
    -- confirmar o pagamento. Usuário autenticado só confirma se for a loja
    -- e existir uma cobrança realmente paga vinculada ao pedido.
    if v_uid is not null then
      if v_funcao not in ('admin', 'atendente', 'gestor') then
        raise exception 'O pagamento é confirmado pelo gateway. Atualize a página.';
      end if;
      if not exists (
        select 1 from public.pagamentos pg
         where pg.id = new.pagamento_id
           and pg.status = 'pago'
      ) then
        raise exception 'Confirme o pagamento pelo gateway ou registre o pagamento manual';
      end if;
    end if;

    if not exists (
      select 1 from public.estoque_movimentacoes
       where pedido_id = old.id and tipo = 'venda'
    ) then
      for v_item in select * from public.pedido_itens where pedido_id = old.id loop
        select estoque into v_estoque
          from public.produtos where id = v_item.produto_id for update;
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
      end loop;
    end if;

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
      raise exception 'Transição inválida: % para pronto_para_entrega', old.status;
    end if;
    if v_funcao not in ('admin', 'atendente', 'gestor') then
      raise exception 'Somente a loja pode marcar pronto para entrega';
    end if;
    if v_funcao in ('atendente', 'gestor') and v_unidade is distinct from old.unidade_id then
      raise exception 'Sem permissão para pedidos de outra unidade';
    end if;
    if old.tipo_entrega <> 'retirada' and new.entregador_id is null then
      raise exception 'Atribua um entregador antes de marcar pronto para entrega';
    end if;
  elsif new.status = 'saiu_para_entrega' then
    if old.status <> 'pronto_para_entrega' then
      raise exception 'Transição inválida: % para saiu_para_entrega', old.status;
    end if;
    if v_uid is distinct from old.entregador_id and v_funcao <> 'admin' then
      raise exception 'Somente o entregador atribuído pode iniciar a entrega';
    end if;
  elsif new.status = 'entregue' then
    if old.tipo_entrega = 'retirada' then
      if old.status <> 'pronto_para_entrega' then
        raise exception 'Transição inválida: % para entregue (retirada)', old.status;
      end if;
      if v_funcao not in ('admin', 'atendente', 'gestor') then
        raise exception 'Somente a loja pode confirmar a retirada';
      end if;
      if v_funcao in ('atendente', 'gestor') and v_unidade is distinct from old.unidade_id then
        raise exception 'Sem permissão para pedidos de outra unidade';
      end if;
    else
      if old.status <> 'saiu_para_entrega' then
        raise exception 'Transição inválida: % para entregue', old.status;
      end if;
      if v_uid is distinct from old.entregador_id and v_funcao <> 'admin' then
        raise exception 'Somente o entregador atribuído pode confirmar a entrega';
      end if;
      if new.recebedor_nome is null or length(trim(new.recebedor_nome)) = 0 then
        raise exception 'Informe o nome de quem recebeu';
      end if;
    end if;
    new.entregue_em := now();
  else
    raise exception 'Transição não permitida: % para %', old.status, new.status;
  end if;

  insert into public.pedido_historico (pedido_id, status, alterado_por)
  values (old.id, new.status, v_uid);
  new.updated_at := now();
  return new;
end $$;

-- ── 8) RPC de status com auditoria e trava de "pago" ─────────

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

  if p_status = 'pago' and not exists (
    select 1 from public.pagamentos p
     where p.id = v_pedido.pagamento_id
       and p.status = 'pago'
  ) then
    raise exception 'Confirme o pagamento pelo gateway ou registre o pagamento manual';
  end if;

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

  insert into public.pedido_auditoria (pedido_id, usuario_id, acao, detalhe)
  values (
    p_pedido_id,
    auth.uid(),
    'status',
    jsonb_build_object('de', v_pedido.status, 'para', p_status, 'recebedor', p_recebedor)
  );
end $$;

create or replace function public.cancelar_pedido(p_pedido_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
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

  select status into v_status from public.pedidos where id = p_pedido_id;

  update public.pedidos
     set status = 'cancelado'
   where id = p_pedido_id
     and (user_id = auth.uid()
          or public.funcao_usuario() = 'admin'
          or (public.funcao_usuario() in ('atendente','gestor')
              and unidade_id = (select unidade_id from public.perfis where id = auth.uid())));
  if not found then
    raise exception 'Sem permissão para cancelar este pedido';
  end if;

  insert into public.pedido_auditoria (pedido_id, usuario_id, acao, detalhe)
  values (
    p_pedido_id,
    auth.uid(),
    'cancelamento',
    jsonb_build_object('de', v_status, 'para', 'cancelado')
  );
end $$;

-- ── 9) Pagamento manual (auditável) ──────────────────────────

create or replace function public.confirmar_pagamento_manual(
  p_pedido_id bigint,
  p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_funcao text := public.funcao_usuario();
  v_unidade int;
  v_pedido public.pedidos%rowtype;
  v_pagamento_id bigint;
  v_motivo text := nullif(trim(coalesce(p_motivo, '')), '');
begin
  if v_funcao not in ('admin','atendente','gestor') then
    raise exception 'Somente a loja pode confirmar pagamento manual';
  end if;
  if v_motivo is null or length(v_motivo) < 5 then
    raise exception 'Informe o motivo do pagamento manual';
  end if;

  perform pg_advisory_xact_lock(p_pedido_id);

  select * into v_pedido from public.pedidos where id = p_pedido_id for update;
  if v_pedido.id is null then
    raise exception 'Pedido não encontrado';
  end if;

  if v_funcao in ('atendente','gestor') then
    v_unidade := (select unidade_id from public.perfis where id = auth.uid());
    if v_pedido.unidade_id is distinct from v_unidade then
      raise exception 'Sem permissão para pedidos de outra loja';
    end if;
  end if;

  if v_pedido.status <> 'pendente' then
    raise exception 'Este pedido não está aguardando pagamento (status: %)', v_pedido.status;
  end if;

  if exists (
    select 1 from public.pagamentos p
     where p.id = v_pedido.pagamento_id
       and p.status in ('pago','pendente','em_analise')
  ) then
    raise exception 'Já existe uma cobrança para este pedido. Use o gateway ou estorne a cobrança atual.';
  end if;

  insert into public.pagamentos
    (user_id, gateway, metodo, valor, status, pago_em, gateway_dados)
  values
    (v_pedido.user_id, 'manual', 'manual', v_pedido.total, 'pago', now(),
     jsonb_build_object(
       'manual', true,
       'motivo', v_motivo,
       'confirmado_por', auth.uid(),
       'confirmado_em', now()
     ))
  returning id into v_pagamento_id;

  update public.pedidos
     set status = 'pago',
         pagamento_id = v_pagamento_id,
         pagamento = 'Manual',
         transacao_id = 'manual-' || v_pagamento_id,
         pagamento_detalhes = 'Pagamento manual: ' || v_motivo,
         pago_em = now()
   where id = p_pedido_id;

  insert into public.pedido_auditoria (pedido_id, usuario_id, acao, detalhe)
  values (
    p_pedido_id,
    auth.uid(),
    'pagamento_manual',
    jsonb_build_object(
      'pagamento_id', v_pagamento_id,
      'motivo', v_motivo,
      'valor', v_pedido.total
    )
  );

  return v_pagamento_id;
end $$;

-- ── 10) Validação do valor antes de criar a cobrança ─────────

create or replace function public.validar_pedidos_pagamento(
  p_pedido_ids bigint[],
  p_user_id uuid
)
returns numeric
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pedido public.pedidos%rowtype;
  v_itens numeric;
  v_esperado numeric;
  v_total numeric := 0;
  v_encontrados int := 0;
begin
  if p_pedido_ids is null or array_length(p_pedido_ids, 1) is null then
    raise exception 'Nenhum pedido informado';
  end if;
  if p_user_id is null then
    raise exception 'Usuário não informado';
  end if;

  for v_pedido in
    select * from public.pedidos
     where id = any(p_pedido_ids)
     order by id
     for update
  loop
    v_encontrados := v_encontrados + 1;

    if v_pedido.user_id is distinct from p_user_id then
      raise exception 'Pedido #% não pertence a você', v_pedido.id;
    end if;
    if v_pedido.status <> 'pendente' then
      raise exception 'Pedido #% não está mais aguardando pagamento', v_pedido.id;
    end if;

    select coalesce(sum(i.quantidade * i.preco_unitario), 0)
      into v_itens
      from public.pedido_itens i
     where i.pedido_id = v_pedido.id;

    if v_itens <= 0 then
      raise exception 'Pedido #% está sem itens válidos', v_pedido.id;
    end if;
    if coalesce(v_pedido.desconto_cupom, 0) < 0
       or coalesce(v_pedido.desconto_cupom, 0) > v_itens then
      raise exception 'Pedido #% está com desconto inválido', v_pedido.id;
    end if;
    if coalesce(v_pedido.taxa_entrega, 0) < 0 then
      raise exception 'Pedido #% está com frete inválido', v_pedido.id;
    end if;

    v_esperado := v_itens
      - coalesce(v_pedido.desconto_cupom, 0)
      + coalesce(v_pedido.taxa_entrega, 0);

    if abs(v_esperado - coalesce(v_pedido.total, 0)) > 0.01 then
      raise exception 'Pedido #% está com total divergente do carrinho. Refazer o checkout.', v_pedido.id;
    end if;
    if coalesce(v_pedido.total, 0) <= 0 then
      raise exception 'Pedido #% está com total inválido', v_pedido.id;
    end if;

    v_total := v_total + v_pedido.total;
  end loop;

  if v_encontrados <> (
    select count(distinct x) from unnest(p_pedido_ids) as x
  ) then
    raise exception 'Um ou mais pedidos não foram encontrados';
  end if;

  return round(v_total, 2);
end $$;

-- ── 11) Checkout idempotente (v4) ────────────────────────────

create or replace function public.finalizar_checkout_v4(
  p_user_id uuid,
  p_itens jsonb,
  p_cupom_desconto_total numeric default 0,
  p_cupom_id bigint default null,
  p_tipo_entrega text default 'retirada',
  p_endereco_entrega text default null,
  p_cep_entrega text default null,
  p_endereco_lat double precision default null,
  p_endereco_lng double precision default null,
  p_cotacoes jsonb default '[]'::jsonb,
  p_idempotency_key uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_chave uuid := coalesce(p_idempotency_key, gen_random_uuid());
  v_existente jsonb;
  v_ret jsonb;
begin
  if p_user_id is distinct from auth.uid() then
    raise exception 'Você não pode criar pedidos para outro usuário';
  end if;
  if jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception 'Carrinho vazio';
  end if;

  -- Serializa tentativas simultâneas da mesma compra.
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text || ':' || v_chave::text, 0));

  select resposta into v_existente
    from public.checkout_idempotencia
   where user_id = p_user_id and chave = v_chave;

  if v_existente is not null then
    return v_existente;
  end if;

  if jsonb_array_length(coalesce(p_cotacoes, '[]'::jsonb)) > 0 then
    v_ret := public.finalizar_checkout_v3(
      p_user_id, p_itens, p_cupom_desconto_total, p_cupom_id,
      p_tipo_entrega, p_endereco_entrega, p_cep_entrega,
      p_endereco_lat, p_endereco_lng, p_cotacoes
    );
  else
    v_ret := public.finalizar_checkout_v2(
      p_user_id, p_itens, p_cupom_desconto_total, p_cupom_id,
      p_tipo_entrega, p_endereco_entrega, p_cep_entrega,
      p_endereco_lat, p_endereco_lng
    );
  end if;

  -- Agrupa o checkout pela chave do app (devolve cupom/estorno no lugar certo)
  -- e permite reconhecer retries idênticos.
  update public.pedidos o
     set checkout_id = v_chave
   where o.id in (
     select (value->>'id')::bigint
       from jsonb_array_elements(v_ret)
   );

  insert into public.checkout_idempotencia (user_id, chave, resposta)
  values (p_user_id, v_chave, v_ret);

  return v_ret;
end $$;

-- ── 12) Lista paginada de pedidos para o admin ───────────────

create or replace function public.admin_listar_pedidos(
  p_busca text default null,
  p_status text default null,
  p_unidade_id bigint default null,
  p_limit int default 50,
  p_offset int default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_funcao text := public.funcao_usuario();
  v_unidade int;
  v_limit int := greatest(least(coalesce(p_limit, 50), 200), 1);
  v_offset int := greatest(coalesce(p_offset, 0), 0);
  v_busca text := nullif(trim(coalesce(p_busca, '')), '');
  v_status text := nullif(trim(coalesce(p_status, '')), '');
begin
  if v_funcao not in ('admin','atendente','gestor') then
    raise exception 'Sem permissão para listar pedidos';
  end if;

  if v_funcao in ('atendente','gestor') then
    v_unidade := (select unidade_id from public.perfis where id = auth.uid());
    if v_unidade is null then
      raise exception 'Usuário sem loja vinculada';
    end if;
  end if;

  return coalesce((
    select jsonb_agg(t.obj order by t.created_at desc)
    from (
      select
        o.created_at,
        to_jsonb(o) || jsonb_build_object(
          'pedido_itens', coalesce((
            select jsonb_agg(
              to_jsonb(i) || jsonb_build_object(
                'produtos', jsonb_build_object('nome', pr.nome, 'url_imagem', pr.url_imagem)
              )
              order by i.id
            )
            from public.pedido_itens i
            left join public.produtos pr on pr.id = i.produto_id
            where i.pedido_id = o.id
          ), '[]'::jsonb),
          'perfis', (
            select jsonb_build_object('nome', pf.nome, 'email', pf.email, 'telefone', pf.telefone)
            from public.perfis pf
            where pf.id = o.user_id
          ),
          'unidades', (
            select jsonb_build_object('nome', u.nome)
            from public.unidades u
            where u.id = o.unidade_id
          ),
          'pagamentos', (
            select to_jsonb(pg)
            from public.pagamentos pg
            where pg.id = o.pagamento_id
          )
        ) as obj
      from public.pedidos o
      where (v_status is null or o.status = v_status)
        and (p_unidade_id is null or o.unidade_id = p_unidade_id)
        and (v_funcao = 'admin' or o.unidade_id = v_unidade)
        and (
          v_busca is null
          or o.id::text = v_busca
          or coalesce(o.comprador_nome, '') ilike '%' || v_busca || '%'
          or coalesce(o.comprador_email, '') ilike '%' || v_busca || '%'
          or exists (
            select 1 from public.perfis pf
            where pf.id = o.user_id
              and (
                coalesce(pf.nome, '') ilike '%' || v_busca || '%'
                or coalesce(pf.email, '') ilike '%' || v_busca || '%'
              )
          )
        )
      order by o.created_at desc
      limit v_limit offset v_offset
    ) t
  ), '[]'::jsonb);
end $$;

-- ── 13) Revisão manual e rastreio (com auditoria) ────────────

create or replace function public.resolver_revisao_pagamento(
  p_pagamento_id bigint,
  p_resolucao text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_funcao text := public.funcao_usuario();
  v_unidade int;
  v_resolucao text := nullif(trim(coalesce(p_resolucao, '')), '');
begin
  if v_funcao not in ('admin','atendente','gestor') then
    raise exception 'Sem permissão para resolver revisão de pagamento';
  end if;
  if v_resolucao is null or length(v_resolucao) < 5 then
    raise exception 'Descreva a resolução da revisão';
  end if;

  if v_funcao in ('atendente','gestor') then
    v_unidade := (select unidade_id from public.perfis where id = auth.uid());
    if not exists (
      select 1 from public.pedidos o
       where o.pagamento_id = p_pagamento_id
         and o.unidade_id = v_unidade
    ) then
      raise exception 'Sem permissão para este pagamento';
    end if;
  end if;

  update public.pagamentos
     set revisao_manual = false,
         revisao_motivo = null,
         revisao_resolvida_em = now(),
         revisao_resolvida_por = auth.uid(),
         revisao_resolucao = v_resolucao,
         updated_at = now()
   where id = p_pagamento_id;

  if not found then
    raise exception 'Pagamento não encontrado';
  end if;

  insert into public.pedido_auditoria (pedido_id, usuario_id, acao, detalhe)
  select o.id, auth.uid(), 'revisao_pagamento',
         jsonb_build_object(
           'pagamento_id', p_pagamento_id,
           'resolucao', v_resolucao
         )
    from public.pedidos o
   where o.pagamento_id = p_pagamento_id;
end $$;

create or replace function public.atualizar_rastreio(
  p_pedido_id bigint,
  p_codigo text,
  p_url text
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
  v_codigo text := nullif(trim(coalesce(p_codigo, '')), '');
  v_url text := nullif(trim(coalesce(p_url, '')), '');
begin
  if v_funcao not in ('admin','atendente','gestor') then
    raise exception 'Sem permissão para atualizar o rastreio';
  end if;

  select * into v_pedido from public.pedidos where id = p_pedido_id;
  if v_pedido.id is null then
    raise exception 'Pedido não encontrado';
  end if;

  if v_funcao in ('atendente','gestor') then
    v_unidade := (select unidade_id from public.perfis where id = auth.uid());
    if v_pedido.unidade_id is distinct from v_unidade then
      raise exception 'Sem permissão para pedidos de outra loja';
    end if;
  end if;

  update public.pedidos
     set codigo_rastreio = v_codigo,
         url_rastreio = v_url,
         updated_at = now()
   where id = p_pedido_id;

  insert into public.pedido_auditoria (pedido_id, usuario_id, acao, detalhe)
  values (
    p_pedido_id,
    auth.uid(),
    'rastreio',
    jsonb_build_object('codigo', v_codigo, 'url', v_url)
  );
end $$;

-- ── 14) Grants ───────────────────────────────────────────────

revoke all on function public.bloqueia_pagamento_pelo_cliente() from public, anon, authenticated;
revoke all on function public.fn_pedido_status() from public, anon, authenticated;

revoke all on function public.alterar_status_pedido(bigint, text, text) from public, anon;
grant execute on function public.alterar_status_pedido(bigint, text, text) to authenticated;

revoke all on function public.cancelar_pedido(bigint) from public, anon;
grant execute on function public.cancelar_pedido(bigint) to authenticated;

revoke all on function public.confirmar_pagamento_manual(bigint, text) from public, anon, authenticated;
grant execute on function public.confirmar_pagamento_manual(bigint, text) to authenticated;

revoke all on function public.validar_pedidos_pagamento(bigint[], uuid) from public, anon, authenticated;
grant execute on function public.validar_pedidos_pagamento(bigint[], uuid) to service_role;

revoke all on function public.finalizar_checkout_v4(
  uuid, jsonb, numeric, bigint, text, text, text, double precision, double precision, jsonb, uuid
) from public, anon;
grant execute on function public.finalizar_checkout_v4(
  uuid, jsonb, numeric, bigint, text, text, text, double precision, double precision, jsonb, uuid
) to authenticated;

revoke all on function public.admin_listar_pedidos(text, text, bigint, int, int) from public, anon;
grant execute on function public.admin_listar_pedidos(text, text, bigint, int, int) to authenticated;

revoke all on function public.resolver_revisao_pagamento(bigint, text) from public, anon;
grant execute on function public.resolver_revisao_pagamento(bigint, text) to authenticated;

revoke all on function public.atualizar_rastreio(bigint, text, text) from public, anon;
grant execute on function public.atualizar_rastreio(bigint, text, text) to authenticated;

notify pgrst, 'reload schema';
