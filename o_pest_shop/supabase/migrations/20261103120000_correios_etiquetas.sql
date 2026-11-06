-- ═══════════════════════════════════════════════════════════════════════
-- O PEST · ETIQUETAS OFICIAIS DOS CORREIOS (PRÉ-POSTAGEM)
--
-- Rodar DEPOIS de 20261102120000_blindagem_compra_admin.sql.
-- Idempotente: pode rodar mais de uma vez.
--
-- O que este script faz:
--   1) Completa o endereço do remetente (unidades) e do destinatário (pedidos).
--   2) Cria envios/envio_eventos para a etiqueta e o rastreio.
--   3) Cria o bucket privado `etiquetas`.
--   4) Cria o checkout v5 (guarda endereço estruturado, CPF e frete escolhido).
--   5) Ensina a máquina de estados a aceitar postado/em_trânsito/entregue
--      vindos do rastreio (service_role/Sincronização).
--   6) Cria RPC para o admin informar a NF-e antes de gerar a etiqueta.
--
-- Credenciais dos Correios NÃO ficam no banco: vão nos secrets das Edge
-- Functions (CORREIOS_*). Este script só guarda dados operacionais.
-- ═══════════════════════════════════════════════════════════════════════

begin;

-- ── 1) REMETENTE (UNIDADES) ────────────────────────────────────────────

alter table public.unidades
  add column if not exists numero text,
  add column if not exists complemento text,
  add column if not exists uf text,
  add column if not exists inscricao_estadual text,
  add column if not exists contribuinte_icms boolean not null default false,
  add column if not exists nome_remetente text;

comment on column public.unidades.contribuinte_icms is
  'Se true, a etiqueta dos Correios exige chave da NF-e (não usa DC-e).';
comment on column public.unidades.nome_remetente is
  'Nome que sai impresso na etiqueta como remetente (default: nome da loja).';

-- ── 2) DESTINATÁRIO / FRETE / ETIQUETA (PEDIDOS) ───────────────────────

alter table public.pedidos
  add column if not exists endereco_rua text,
  add column if not exists endereco_numero text,
  add column if not exists endereco_complemento text,
  add column if not exists endereco_bairro text,
  add column if not exists endereco_cidade text,
  add column if not exists endereco_uf text,
  add column if not exists destinatario_cpf text,
  add column if not exists destinatario_telefone text,
  add column if not exists frete_provider text,
  add column if not exists frete_servico text,
  add column if not exists frete_servico_codigo text,
  add column if not exists frete_transportadora text,
  add column if not exists frete_cotacao_id uuid,
  add column if not exists etiqueta_status text,
  add column if not exists etiqueta_id text,
  add column if not exists etiqueta_pdf_path text,
  add column if not exists etiqueta_gerada_em timestamptz,
  add column if not exists postado_em timestamptz,
  add column if not exists nota_fiscal_chave text,
  add column if not exists nota_fiscal_numero text;

create index if not exists idx_pedidos_etiqueta_status
  on public.pedidos(etiqueta_status, created_at desc);

-- ── 3) COTAÇÃO: CÓDIGO DO SERVIÇO ESCOLHIDO ────────────────────────────

alter table public.frete_cotacoes
  add column if not exists servico_codigo text;

-- ── 4) ENVIOS / EVENTOS ────────────────────────────────────────────────

create table if not exists public.envios (
  id uuid primary key default gen_random_uuid(),
  pedido_id bigint not null references public.pedidos(id) on delete cascade,
  unidade_id bigint references public.unidades(id) on delete set null,
  provider text not null default 'correios',
  servico text,
  servico_codigo text,
  transportadora text,
  status text not null default 'pendente',
  status_correios text,
  codigo_objeto text,
  etiqueta_id text,
  etiqueta_pdf_path text,
  etiqueta_url text,
  layout_impressao text default 'PADRAO',
  peso_kg numeric,
  comprimento_cm numeric,
  largura_cm numeric,
  altura_cm numeric,
  valor_declarado numeric,
  recibo_rotulo text,
  payload jsonb,
  erro text,
  gerado_em timestamptz,
  postado_em timestamptz,
  entregue_em timestamptz,
  ultima_sincronizacao timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (pedido_id)
);

create index if not exists idx_envios_status
  on public.envios(status, ultima_sincronizacao);

create index if not exists idx_envios_codigo
  on public.envios(codigo_objeto) where codigo_objeto is not null;

alter table public.envios enable row level security;

drop policy if exists "envios_select" on public.envios;
create policy "envios_select" on public.envios
  for select to authenticated
  using (
    public.funcao_usuario() = 'admin'
    or exists (
      select 1 from public.pedidos o
      where o.id = envios.pedido_id
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

revoke all on public.envios from anon, authenticated;
grant select on public.envios to authenticated;
grant all on public.envios to service_role;

create table if not exists public.envio_eventos (
  id bigint generated always as identity primary key,
  envio_id uuid not null references public.envios(id) on delete cascade,
  codigo text,
  tipo text,
  descricao text,
  detalhe text,
  ocorrido_em timestamptz,
  payload jsonb,
  created_at timestamptz not null default now(),
  unique (envio_id, codigo, ocorrido_em)
);

create index if not exists idx_envio_eventos_envio
  on public.envio_eventos(envio_id, ocorrido_em desc);

alter table public.envio_eventos enable row level security;

drop policy if exists "envio_eventos_select" on public.envio_eventos;
create policy "envio_eventos_select" on public.envio_eventos
  for select to authenticated
  using (
    exists (
      select 1 from public.envios e
      join public.pedidos o on o.id = e.pedido_id
      where e.id = envio_eventos.envio_id
        and (
          public.funcao_usuario() = 'admin'
          or o.user_id = auth.uid()
          or o.entregador_id = auth.uid()
          or (
            public.funcao_usuario() in ('atendente','gestor')
            and o.unidade_id = (select unidade_id from public.perfis where id = auth.uid())
          )
        )
    )
  );

revoke all on public.envio_eventos from anon, authenticated;
grant select on public.envio_eventos to authenticated;
grant all on public.envio_eventos to service_role;

-- ── 5) BUCKET PRIVADO DAS ETIQUETAS ────────────────────────────────────

insert into storage.buckets (id, name, public)
values ('etiquetas', 'etiquetas', false)
on conflict (id) do nothing;

drop policy if exists "etiquetas_admin_select" on storage.objects;
create policy "etiquetas_admin_select" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'etiquetas'
    and public.funcao_usuario() in ('admin','atendente','gestor')
  );

-- ── 6) CHECKOUT V5: ENDEREÇO ESTRUTURADO + FRETE ESCOLHIDO ─────────────

create or replace function public.finalizar_checkout_v5(
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
  p_idempotency_key uuid default null,
  p_endereco jsonb default null,
  p_destinatario_cpf text default null,
  p_destinatario_telefone text default null,
  p_fretes jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ret jsonb;
  v_end jsonb := coalesce(p_endereco, '{}'::jsonb);
  v_fretes jsonb := coalesce(p_fretes, '[]'::jsonb);
  v_item jsonb;
  v_frete jsonb;
  v_cotacao uuid;
begin
  if p_user_id is distinct from auth.uid() then
    raise exception 'Você não pode criar pedidos para outro usuário';
  end if;

  -- Mantém toda a validação/estoque/idempotência do v4.
  v_ret := public.finalizar_checkout_v4(
    p_user_id, p_itens, p_cupom_desconto_total, p_cupom_id,
    p_tipo_entrega, p_endereco_entrega, p_cep_entrega,
    p_endereco_lat, p_endereco_lng, p_cotacoes, p_idempotency_key
  );

  for v_item in select value from jsonb_array_elements(v_ret)
  loop
    select value into v_frete
      from jsonb_array_elements(v_fretes)
     where (value->>'unidade_id')::bigint = (v_item->>'unidade_id')::bigint
     limit 1;

    v_frete := coalesce(v_frete, '{}'::jsonb);

    begin
      v_cotacao := nullif(v_frete->>'cotacao_id', '')::uuid;
    exception when others then
      v_cotacao := null;
    end;

    update public.pedidos o
       set endereco_rua = coalesce(nullif(trim(v_end->>'rua'), ''), o.endereco_rua),
           endereco_numero = coalesce(nullif(trim(v_end->>'numero'), ''), o.endereco_numero),
           endereco_complemento = coalesce(nullif(trim(v_end->>'complemento'), ''), o.endereco_complemento),
           endereco_bairro = coalesce(nullif(trim(v_end->>'bairro'), ''), o.endereco_bairro),
           endereco_cidade = coalesce(nullif(trim(v_end->>'cidade'), ''), o.endereco_cidade),
           endereco_uf = coalesce(nullif(upper(trim(v_end->>'uf')), ''), o.endereco_uf),
           destinatario_cpf = coalesce(
             nullif(regexp_replace(coalesce(p_destinatario_cpf, ''), '\D', '', 'g'), ''),
             o.destinatario_cpf
           ),
           destinatario_telefone = coalesce(
             nullif(regexp_replace(coalesce(p_destinatario_telefone, ''), '\D', '', 'g'), ''),
             o.destinatario_telefone
           ),
           frete_provider = coalesce(nullif(trim(v_frete->>'provider'), ''), o.frete_provider),
           frete_servico = coalesce(nullif(trim(v_frete->>'servico'), ''), o.frete_servico),
           frete_servico_codigo = coalesce(nullif(trim(v_frete->>'servico_codigo'), ''), o.frete_servico_codigo),
           frete_transportadora = coalesce(nullif(trim(v_frete->>'transportadora'), ''), o.frete_transportadora),
           frete_cotacao_id = coalesce(v_cotacao, o.frete_cotacao_id)
     where o.id = (v_item->>'id')::bigint
       and o.user_id = p_user_id;
  end loop;

  return v_ret;
end $$;

revoke all on function public.finalizar_checkout_v5(
  uuid, jsonb, numeric, bigint, text, text, text, double precision, double precision,
  jsonb, uuid, jsonb, text, text, jsonb
) from public, anon;
grant execute on function public.finalizar_checkout_v5(
  uuid, jsonb, numeric, bigint, text, text, text, double precision, double precision,
  jsonb, uuid, jsonb, text, text, jsonb
) to authenticated;

-- ── 7) NF-E NO PEDIDO (antes de gerar a etiqueta) ──────────────────────

create or replace function public.atualizar_nota_fiscal_pedido(
  p_pedido_id bigint,
  p_chave text,
  p_numero text
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
  v_chave text := nullif(regexp_replace(coalesce(p_chave, ''), '\D', '', 'g'), '');
  v_numero text := nullif(regexp_replace(coalesce(p_numero, ''), '\D', '', 'g'), '');
begin
  if v_funcao not in ('admin','atendente','gestor') then
    raise exception 'Sem permissão para informar a NF-e';
  end if;

  if v_chave is not null and length(v_chave) <> 44 then
    raise exception 'A chave da NF-e deve ter 44 dígitos';
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
     set nota_fiscal_chave = v_chave,
         nota_fiscal_numero = v_numero,
         updated_at = now()
   where id = p_pedido_id;

  insert into public.pedido_auditoria (pedido_id, usuario_id, acao, detalhe)
  values (
    p_pedido_id,
    auth.uid(),
    'nota_fiscal',
    jsonb_build_object('chave', v_chave, 'numero', v_numero)
  );
end $$;

revoke all on function public.atualizar_nota_fiscal_pedido(bigint, text, text)
  from public, anon;
grant execute on function public.atualizar_nota_fiscal_pedido(bigint, text, text)
  to authenticated;

-- ── 8) MÁQUINA DE ESTADOS: POSTADO / EM TRÂNSITO / ENTREGUE ────────────
-- Substitui a função original incluindo o ciclo de envio por transportadora.
-- As regras de pagamento/estoque/cancelamento continuam iguais.

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

  -- Ciclo de envio por transportadora (Edge Function/cron usa service_role,
  -- portanto auth.uid() é null). Não mexe em estoque/pagamento.
  if v_uid is null and new.status is distinct from old.status then
    if new.status in ('postado', 'em_transito') then
      if old.status not in (
        'pago', 'em_preparo', 'pronto_para_entrega', 'postado', 'em_transito'
      ) then
        raise exception 'Transição inválida: % para %', old.status, new.status;
      end if;
      if new.status = 'postado' then
        new.postado_em := coalesce(new.postado_em, now());
      end if;
      insert into public.pedido_historico (pedido_id, status, alterado_por)
      values (old.id, new.status, null);
      new.updated_at := now();
      return new;
    end if;

    if new.status = 'entregue' and old.tipo_entrega <> 'retirada' then
      new.entregue_em := coalesce(new.entregue_em, now());
      insert into public.pedido_historico (pedido_id, status, alterado_por)
      values (old.id, 'entregue', null);
      new.updated_at := now();
      return new;
    end if;
  end if;

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

-- ── 9) GRANTS / RELOAD ─────────────────────────────────────────────────

revoke all on function public.fn_pedido_status() from public, anon, authenticated;

notify pgrst, 'reload schema';

commit;
