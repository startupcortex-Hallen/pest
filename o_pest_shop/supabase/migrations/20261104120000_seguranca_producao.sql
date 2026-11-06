-- ═══════════════════════════════════════════════════════════════════════
-- O PEST · BLINDAGEM DE PRODUÇÃO (P0/P1 da auditoria)
--
-- Roda DEPOIS de 20261103150000_pedido_historico_perfil_fk.sql.
-- Idempotente: pode ser executado mais de uma vez.
--
-- Contém:
--   1) Checkout v6: frete/estoque/loja validados no servidor e idempotência
--      com hash do payload (não altera pedido existente em retry divergente).
--   2) v4 deixa de cair no v2 quando a loja usa transportadora.
--   3) Cotação vinculada a CEP, peso e itens do carrinho.
--   4) Exclusão de perfil bloqueada + FK de pedidos/pagamentos restritiva.
--   5) Anonimização LGPD e bloqueio de conta.
--   6) Último admin não pode ser rebaixado nem excluído.
--   7) Dashboard com todos os status pagos e clientes corretos.
--   8) Comissão do parceiro protegida.
--   9) RLS de perfis limitada por loja/entregador.
--  10) Cupom por cliente com uso atômico e histórico.
--  11) Produto ativo/inativo e bloqueio de loja inativa.
--  12) Cron versionado de rastreio e conciliação (quando configurado).
-- ═══════════════════════════════════════════════════════════════════════

begin;

-- ── 1) PRODUTO ATIVO / LOJA ATIVA ──────────────────────────────────────

alter table public.produtos
  add column if not exists ativo boolean not null default true;

create index if not exists idx_produtos_ativo
  on public.produtos(unidade_id, ativo) where ativo = true;

alter table public.unidades
  add column if not exists deleted_at timestamptz;

-- ── 2) CONTA: STATUS / LGPD ────────────────────────────────────────────

alter table public.perfis
  add column if not exists status_conta text not null default 'ativo',
  add column if not exists bloqueado_em timestamptz,
  add column if not exists anonimizado_em timestamptz;

do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.perfis'::regclass
       and conname = 'perfis_status_conta_check'
  ) then
    alter table public.perfis
      add constraint perfis_status_conta_check
      check (status_conta in ('ativo', 'bloqueado', 'anonimizado')) not valid;
  end if;
end $$;

alter table public.perfis validate constraint perfis_status_conta_check;

-- ── 3) IDEMPOTÊNCIA DO CHECKOUT COM HASH ───────────────────────────────

alter table public.checkout_idempotencia
  add column if not exists payload_hash text;

-- ── 4) CUPOM POR CLIENTE / HISTÓRICO ───────────────────────────────────

alter table public.cupons
  add column if not exists uso_por_cliente int;

create table if not exists public.cupom_usos (
  id bigint generated always as identity primary key,
  cupom_id bigint not null references public.cupons(id) on delete cascade,
  user_id uuid not null references public.perfis(id) on delete cascade,
  pedido_id bigint not null references public.pedidos(id) on delete cascade,
  valor_desconto numeric not null default 0,
  created_at timestamptz not null default now(),
  unique (pedido_id)
);

create index if not exists idx_cupom_usos_cliente
  on public.cupom_usos(cupom_id, user_id);

alter table public.cupom_usos enable row level security;

drop policy if exists "cupom_usos_select" on public.cupom_usos;
create policy "cupom_usos_select" on public.cupom_usos
  for select to authenticated
  using (user_id = auth.uid() or public.funcao_usuario() = 'admin');

revoke insert, update, delete on public.cupom_usos from anon, authenticated;
grant select on public.cupom_usos to authenticated;
grant all on public.cupom_usos to service_role;

create or replace function public.fn_consumir_cupom_pedido()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cupom public.cupons%rowtype;
  v_usos_cliente int;
begin
  if new.cupom_id is null then
    return new;
  end if;

  select * into v_cupom
    from public.cupons
   where id = new.cupom_id
   for update;

  if not found then
    raise exception 'Cupom não encontrado';
  end if;

  -- O checkout base incrementa usos_atuais antes do insert. Nesta altura o
  -- valor já inclui este pedido; se passou do limite, a transação inteira
  -- (inclusive o incremento) é revertida.
  if v_cupom.uso_maximo is not null
     and coalesce(v_cupom.usos_atuais, 0) > v_cupom.uso_maximo then
    raise exception 'Cupom esgotado (limite de usos atingido)';
  end if;

  if v_cupom.uso_por_cliente is not null then
    select count(*) into v_usos_cliente
      from public.cupom_usos u
      join public.pedidos p on p.id = u.pedido_id
     where u.cupom_id = new.cupom_id
       and u.user_id = new.user_id
       and p.status <> 'cancelado';
    if v_usos_cliente >= v_cupom.uso_por_cliente then
      raise exception 'Este cupom já foi utilizado o número máximo de vezes por você';
    end if;
  end if;

  return new;
end $$;

drop trigger if exists trg_consumir_cupom_pedido on public.pedidos;
create trigger trg_consumir_cupom_pedido
  before insert on public.pedidos
  for each row execute function public.fn_consumir_cupom_pedido();

create or replace function public.fn_registrar_uso_cupom()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.cupom_id is not null then
    insert into public.cupom_usos (cupom_id, user_id, pedido_id, valor_desconto)
    values (new.cupom_id, new.user_id, new.id, coalesce(new.desconto_cupom, 0))
    on conflict (pedido_id) do nothing;
  end if;
  return new;
end $$;

drop trigger if exists trg_registrar_uso_cupom on public.pedidos;
create trigger trg_registrar_uso_cupom
  after insert on public.pedidos
  for each row execute function public.fn_registrar_uso_cupom();

-- ── 5) EXCLUSÃO DE PERFIL / PRESERVAÇÃO FINANCEIRA ─────────────────────

drop policy if exists "perfis_delete" on public.perfis;
revoke delete on public.perfis from anon, authenticated;

do $$
begin
  if exists (
    select 1 from pg_constraint
     where conrelid = 'public.pedidos'::regclass
       and conname = 'pedidos_user_id_fkey'
  ) then
    alter table public.pedidos drop constraint pedidos_user_id_fkey;
  end if;
  alter table public.pedidos
    add constraint pedidos_user_id_fkey
    foreign key (user_id) references public.perfis(id) on delete restrict;
end $$;

do $$
begin
  if exists (
    select 1 from pg_constraint
     where conrelid = 'public.pagamentos'::regclass
       and conname = 'pagamentos_user_id_fkey'
  ) then
    alter table public.pagamentos drop constraint pagamentos_user_id_fkey;
  end if;
  alter table public.pagamentos
    add constraint pagamentos_user_id_fkey
    foreign key (user_id) references public.perfis(id) on delete restrict;
end $$;

-- ── 6) ÚLTIMO ADMIN PROTEGIDO ──────────────────────────────────────────

create or replace function public.fn_protege_ultimo_admin()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admins int;
begin
  if tg_op = 'DELETE' then
    if old.funcao = 'admin' then
      select count(*) into v_admins from public.perfis where funcao = 'admin';
      if v_admins <= 1 then
        raise exception 'Não é possível excluir o último admin';
      end if;
    end if;
    return old;
  end if;

  if old.funcao = 'admin' and new.funcao is distinct from 'admin' then
    select count(*) into v_admins from public.perfis where funcao = 'admin';
    if v_admins <= 1 then
      raise exception 'Não é possível rebaixar o último admin';
    end if;
  end if;

  return new;
end $$;

drop trigger if exists trg_protege_ultimo_admin on public.perfis;
create trigger trg_protege_ultimo_admin
  before update of funcao or delete on public.perfis
  for each row execute function public.fn_protege_ultimo_admin();

-- ── 7) COMISSÃO DO PARCEIRO PROTEGIDA ──────────────────────────────────

create or replace function public.fn_protege_comissao_parceiro()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null
     and coalesce(public.funcao_usuario(), '') <> 'admin' then
    new.comissao_percentual := old.comissao_percentual;
    new.repasse_pagbank_id := old.repasse_pagbank_id;
  end if;
  return new;
end $$;

drop trigger if exists trg_protege_comissao_parceiro on public.unidades;
create trigger trg_protege_comissao_parceiro
  before update on public.unidades
  for each row execute function public.fn_protege_comissao_parceiro();

-- ── 8) RLS DE PERFIS COM ESCOPO DE LOJA ────────────────────────────────

drop policy if exists "perfis_select_equipe" on public.perfis;
create policy "perfis_select_equipe" on public.perfis
  for select to authenticated
  using (
    id = auth.uid()
    or public.funcao_usuario() = 'admin'
    or (
      public.funcao_usuario() in ('atendente', 'gestor')
      and unidade_id = (select unidade_id from public.perfis where id = auth.uid())
    )
    or (
      public.funcao_usuario() = 'entregador'
      and (
        id = auth.uid()
        or exists (
          select 1 from public.pedidos o
           where o.entregador_id = auth.uid()
             and o.user_id = perfis.id
        )
      )
    )
  );

-- ── 9) ANONIMIZAÇÃO LGPD / BLOQUEIO DE CONTA ────────────────────────────

create or replace function public.anonimizar_usuario(p_user_id uuid, p_motivo text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_funcao text := public.funcao_usuario();
  v_email text;
begin
  if v_funcao <> 'admin' then
    raise exception 'Sem permissão para anonimizar usuários';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'Você não pode anonimizar a própria conta';
  end if;
  if not exists (select 1 from public.perfis where id = p_user_id) then
    raise exception 'Usuário não encontrado';
  end if;

  v_email := 'anonimizado+' || left(p_user_id::text, 8) || '@privacidade.opest.local';

  update public.perfis
     set nome = 'Usuário anonimizado',
         nome_completo = null,
         email = v_email,
         cpf = null,
         telefone = null,
         avatar_url = null,
         objetivo = null,
         status_conta = 'anonimizado',
         anonimizado_em = now(),
         bloqueado_em = now()
   where id = p_user_id;

  -- Preserva o histórico fiscal/financeiro, mas remove PII dos pedidos.
  update public.pedidos
     set comprador_nome = 'Cliente anonimizado',
         comprador_email = null,
         comprador_telefone = null,
         endereco_entrega = 'Endereço anonimizado (LGPD)',
         endereco_rua = null,
         endereco_numero = null,
         endereco_complemento = null,
         endereco_bairro = null,
         endereco_cidade = null,
         endereco_uf = null,
         cep_entrega = null,
         destinatario_cpf = null,
         destinatario_telefone = null,
         updated_at = now()
   where user_id = p_user_id;

  delete from public.enderecos_usuario where user_id = p_user_id;
  delete from public.cartoes_usuario where user_id = p_user_id;
  delete from public.carrinho where user_id = p_user_id;
  delete from public.favoritos where user_id = p_user_id;

  insert into public.pedido_auditoria (pedido_id, usuario_id, acao, detalhe)
  select o.id, auth.uid(), 'lgpd_anonimizacao',
         jsonb_build_object('motivo', nullif(trim(coalesce(p_motivo, '')), ''))
    from public.pedidos o
   where o.user_id = p_user_id;

  -- Bloqueia o login do usuário anonimizado sem apagar o histórico.
  begin
    update auth.users
       set email = v_email,
           encrypted_password = md5(random()::text || clock_timestamp()::text),
           banned_until = 'infinity',
           raw_user_meta_data = jsonb_build_object('anonimizado', true)
     where id = p_user_id;
  exception when others then
    -- Projeto sem auth editável: o perfil já está anonimizado.
    null;
  end;
end $$;

revoke all on function public.anonimizar_usuario(uuid, text) from public, anon;
grant execute on function public.anonimizar_usuario(uuid, text) to authenticated;

create or replace function public.admin_bloquear_usuario(
  p_user_id uuid,
  p_bloquear boolean default true
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.funcao_usuario() <> 'admin' then
    raise exception 'Sem permissão para bloquear usuários';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'Você não pode bloquear a própria conta';
  end if;
  if exists (select 1 from public.perfis where id = p_user_id and funcao = 'admin') then
    raise exception 'Não é possível bloquear um administrador';
  end if;

  update public.perfis
     set status_conta = case when p_bloquear then 'bloqueado' else 'ativo' end,
         bloqueado_em = case when p_bloquear then now() else null end
   where id = p_user_id;

  if not found then
    raise exception 'Usuário não encontrado';
  end if;

  begin
    update auth.users
       set banned_until = case when p_bloquear then 'infinity' else null end
     where id = p_user_id;
  exception when others then
    null;
  end;
end $$;

revoke all on function public.admin_bloquear_usuario(uuid, boolean) from public, anon;
grant execute on function public.admin_bloquear_usuario(uuid, boolean) to authenticated;

-- ── 10) CHECKOUT V4: NUNCA CAI NO V2 PARA TRANSPORTADORA ───────────────

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

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text || ':' || v_chave::text, 0));

  select resposta into v_existente
    from public.checkout_idempotencia
   where user_id = p_user_id and chave = v_chave;

  if v_existente is not null then
    return v_existente;
  end if;

  -- v3 valida cotações e recusa loja de transportadora sem cotação.
  -- Nunca cair no v2 aqui: ele aplicaria a taxa fixa indevidamente.
  v_ret := public.finalizar_checkout_v3(
    p_user_id, p_itens, p_cupom_desconto_total, p_cupom_id,
    p_tipo_entrega, p_endereco_entrega, p_cep_entrega,
    p_endereco_lat, p_endereco_lng, p_cotacoes
  );

  update public.pedidos o
     set checkout_id = v_chave
   where o.id in (
     select (value->>'id')::bigint
       from jsonb_array_elements(v_ret)
   );

  insert into public.checkout_idempotencia (user_id, chave, resposta)
  values (p_user_id, v_chave, v_ret)
  on conflict (user_id, chave) do nothing;

  return v_ret;
end $$;

revoke all on function public.finalizar_checkout_v4(
  uuid, jsonb, numeric, bigint, text, text, text, double precision, double precision, jsonb, uuid
) from public, anon;
grant execute on function public.finalizar_checkout_v4(
  uuid, jsonb, numeric, bigint, text, text, text, double precision, double precision, jsonb, uuid
) to authenticated;

-- ── 11) CHECKOUT V6: VALIDAÇÃO SERVER-SIDE COMPLETA ────────────────────

create or replace function public.finalizar_checkout_v6(
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
  p_fretes jsonb default '[]'::jsonb,
  p_endereco_usuario_id bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_chave uuid := coalesce(p_idempotency_key, gen_random_uuid());
  v_hash text;
  v_existente record;
  v_ret jsonb;
  v_item record;
  v_produto record;
  v_unidade record;
  v_end jsonb := coalesce(p_endereco, '{}'::jsonb);
  v_cep text := regexp_replace(
    coalesce(p_cep_entrega, p_endereco->>'cep', ''),
    '\D', '', 'g'
  );
  v_endereco_salvo record;
  v_lat double precision := p_endereco_lat;
  v_lng double precision := p_endereco_lng;
  v_cot record;
  v_cotacao record;
  v_loja record;
  v_modo text;
  v_unidades_cotadas text[] := '{}';
  v_hash_carrinho text;
  v_hash_unidade text;
  v_peso numeric;
  v_pendentes int;
  v_cotacoes_validadas jsonb := '[]'::jsonb;
begin
  if p_user_id is distinct from auth.uid() then
    raise exception 'Você não pode criar pedidos para outro usuário';
  end if;
  if jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception 'Carrinho vazio';
  end if;
  if coalesce(p_tipo_entrega, 'retirada') not in ('retirada', 'entrega') then
    raise exception 'Tipo de entrega inválido';
  end if;

  -- 10.1) Produto/loja ativos + hash canônico do carrinho.
  select md5(coalesce(jsonb_agg(
           jsonb_build_array(
             (t.item->>'produto_id')::bigint,
             (t.item->>'quantidade')::int
           ) order by (t.item->>'produto_id')::bigint
         ), '[]'::jsonb)::text)
    into v_hash_carrinho
    from jsonb_array_elements(p_itens) as t(item);

  for v_item in
    select value as item from jsonb_array_elements(p_itens)
  loop
    select p.id, p.nome, p.ativo, p.estoque,
           coalesce(p.unidade_id, (v_item.item->>'unidade_id')::bigint, 1) as unidade_id,
           case when p.em_promocao and p.preco_promocional is not null
                then p.preco_promocional else p.preco end as preco,
           coalesce(p.peso_kg, 0) as peso_kg
      into v_produto
      from public.produtos p
     where p.id = (v_item.item->>'produto_id')::bigint;

    if not found then
      raise exception 'Produto não encontrado';
    end if;
    if coalesce(v_produto.ativo, true) = false then
      raise exception 'O produto "%" está indisponível', v_produto.nome;
    end if;
    if (v_item.item->>'quantidade')::int <= 0 then
      raise exception 'Quantidade inválida para "%"', v_produto.nome;
    end if;

    select * into v_unidade from public.unidades where id = v_produto.unidade_id;
    if not found or coalesce(v_unidade.ativa, true) = false
       or v_unidade.deleted_at is not null then
      raise exception 'A loja do produto "%" está indisponível', v_produto.nome;
    end if;
  end loop;

  -- 10.2) Rate limit: evita reservar estoque com dezenas de pedidos pendentes.
  perform public._cancelar_pendentes_expirados_interno(p_user_id, 60);

  select count(*) into v_pendentes
    from public.pedidos
   where user_id = p_user_id
     and status = 'pendente'
     and created_at > now() - interval '30 minutes';
  if v_pendentes >= 8 then
    raise exception 'Você tem muitos pedidos aguardando pagamento. Pague ou cancele antes de criar outro.';
  end if;

  -- 10.3) Endereço: quando informado, usa o endereço salvo no servidor e
  -- ignora coordenadas do cliente. Para entrega por distância/faixas, exige
  -- endereço salvo com coordenadas.
  if p_tipo_entrega = 'entrega' then
    if v_cep is null or length(v_cep) <> 8 then
      raise exception 'Informe um CEP válido para entrega';
    end if;

    if p_endereco_usuario_id is not null then
      select * into v_endereco_salvo
        from public.enderecos_usuario
       where id = p_endereco_usuario_id
         and user_id = p_user_id;
      if not found then
        raise exception 'Endereço não encontrado. Salve o endereço novamente.';
      end if;
      if regexp_replace(coalesce(v_endereco_salvo.cep, ''), '\D', '', 'g') <> v_cep then
        raise exception 'O CEP do endereço não confere com o informado';
      end if;
      v_lat := v_endereco_salvo.latitude;
      v_lng := v_endereco_salvo.longitude;
      v_end := v_end || jsonb_build_object(
        'rua', v_endereco_salvo.rua,
        'numero', v_endereco_salvo.numero,
        'complemento', v_endereco_salvo.complemento,
        'bairro', v_endereco_salvo.bairro,
        'cidade', v_endereco_salvo.cidade,
        'uf', v_endereco_salvo.uf,
        'cep', v_cep
      );
    end if;

    if exists (
      select 1
        from jsonb_array_elements(p_itens) as t(item)
        join public.produtos p on p.id = (t.item->>'produto_id')::bigint
        join public.unidades u on u.id = coalesce(p.unidade_id, (t.item->>'unidade_id')::bigint, 1)
       where u.frete_modo in ('distancia', 'faixas')
    ) then
      if v_lat is null or v_lng is null then
        raise exception 'Salve o endereço com localização antes de finalizar a entrega';
      end if;
      if v_lat < -90 or v_lat > 90 or v_lng < -180 or v_lng > 180 then
        raise exception 'Coordenadas de entrega inválidas';
      end if;
    end if;
  end if;

  -- 10.4) Cotações externas: CEP, peso, itens e loja precisam bater.
  for v_cot in
    select value from jsonb_array_elements(coalesce(p_cotacoes, '[]'::jsonb))
  loop
    select * into v_cotacao
      from public.frete_cotacoes
     where id = (v_cot.value->>'cotacao_id')::uuid
       and user_id = p_user_id
       and unidade_id = (v_cot.value->>'unidade_id')::bigint
       and usado_em is null
       and expira_em > now()
     for update;

    if not found then
      raise exception 'Cotação de frete expirada. Calcule a entrega novamente.';
    end if;
    if v_cotacao.cep_destino is distinct from v_cep then
      raise exception 'A cotação de frete não corresponde ao CEP da entrega';
    end if;

    select coalesce(sum(coalesce(p.peso_kg, 0) * (t.item->>'quantidade')::int), 0)
      into v_peso
      from jsonb_array_elements(p_itens) as t(item)
      join public.produtos p on p.id = (t.item->>'produto_id')::bigint
     where coalesce(p.unidade_id, (t.item->>'unidade_id')::bigint, 1) = v_cotacao.unidade_id;

    if v_cotacao.peso_kg is not null
       and abs(v_cotacao.peso_kg - greatest(v_peso, 0.3)) > greatest(0.2, v_peso * 0.1) then
      raise exception 'O peso da cotação não corresponde aos itens do carrinho';
    end if;

    if v_cotacao.payload is not null
       and v_cotacao.payload->>'carrinho_hash' is not null then
      select md5(coalesce(jsonb_agg(
               jsonb_build_array(
                 (t.item->>'produto_id')::bigint,
                 (t.item->>'quantidade')::int
               ) order by (t.item->>'produto_id')::bigint
             ), '[]'::jsonb)::text)
        into v_hash_unidade
        from jsonb_array_elements(p_itens) as t(item)
        join public.produtos p on p.id = (t.item->>'produto_id')::bigint
       where coalesce(p.unidade_id, (t.item->>'unidade_id')::bigint, 1) = v_cotacao.unidade_id;

      if v_cotacao.payload->>'carrinho_hash' <> v_hash_unidade then
        raise exception 'Os itens do carrinho mudaram desde a cotação. Calcule o frete novamente.';
      end if;
    end if;

    select frete_modo into v_modo
      from public.unidades
     where id = v_cotacao.unidade_id;
    if v_modo is null then
      raise exception 'Loja da cotação não encontrada';
    end if;
    if v_modo <> v_cotacao.provider then
      raise exception 'A cotação não pertence ao modo de frete desta loja';
    end if;

    v_unidades_cotadas := array_append(v_unidades_cotadas, v_cotacao.unidade_id::text);
    v_cotacoes_validadas := v_cotacoes_validadas || jsonb_build_object(
      'unidade_id', v_cotacao.unidade_id,
      'cotacao_id', v_cotacao.id
    );
  end loop;

  if p_tipo_entrega = 'entrega' then
    for v_loja in
      select distinct coalesce(p.unidade_id, (t.item->>'unidade_id')::bigint, 1) as id
        from jsonb_array_elements(p_itens) as t(item)
        join public.produtos p on p.id = (t.item->>'produto_id')::bigint
    loop
      select frete_modo into v_modo from public.unidades where id = v_loja.id;
      if v_modo in ('correios', 'melhor_envio')
         and not (v_loja.id::text = any(v_unidades_cotadas)) then
        raise exception 'Calcule o frete com a transportadora antes de finalizar o pedido';
      end if;
    end loop;
  end if;

  -- 10.5) Idempotência com hash do payload: retry idêntico devolve o mesmo
  -- resultado; retry com outro endereço/itens é recusado (não altera pedido).
  v_hash := md5(jsonb_build_object(
    'itens', (
      select jsonb_agg(jsonb_build_array(
               (t.item->>'produto_id')::bigint,
               (t.item->>'quantidade')::int,
               coalesce(t.item->>'cor', '')
             ) order by (t.item->>'produto_id')::bigint)
        from jsonb_array_elements(p_itens) as t(item)
    ),
    'cupom_id', p_cupom_id,
    'tipo_entrega', p_tipo_entrega,
    'cep', v_cep,
    'endereco_id', p_endereco_usuario_id,
    'endereco', v_end,
    'cotacoes', v_cotacoes_validadas
  )::text);

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text || ':' || v_chave::text, 0));

  select resposta, payload_hash into v_existente
    from public.checkout_idempotencia
   where user_id = p_user_id and chave = v_chave;

  if found then
    if v_existente.payload_hash is not null
       and v_existente.payload_hash is distinct from v_hash then
      raise exception 'Chave de idempotência reutilizada com dados diferentes. Refazer o checkout.';
    end if;
    return v_existente.resposta;
  end if;

  -- 10.6) Checkout atômico (estoque, cupom, pedidos) usando as cotações já
  -- validadas no servidor.
  v_ret := public.finalizar_checkout_v3(
    p_user_id, p_itens, p_cupom_desconto_total, p_cupom_id,
    p_tipo_entrega, p_endereco_entrega, v_cep,
    v_lat, v_lng, v_cotacoes_validadas
  );

  -- 10.7) Endereço estruturado + dados de frete (vindos do banco).
  for v_item in select value from jsonb_array_elements(v_ret)
  loop
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
           checkout_id = v_chave,
           updated_at = now()
     where o.id = (v_item.value->>'id')::bigint
       and o.user_id = p_user_id;

    if v_cotacoes_validadas <> '[]'::jsonb then
      update public.pedidos o
         set frete_provider = q.provider,
             frete_servico = q.servico,
             frete_servico_codigo = q.servico_codigo,
             frete_transportadora = q.transportadora,
             frete_cotacao_id = q.id
        from (
          select f.*
            from public.frete_cotacoes f
           where f.id in (
             select (value->>'cotacao_id')::uuid
               from jsonb_array_elements(v_cotacoes_validadas)
           )
             and f.unidade_id = (v_item.value->>'unidade_id')::bigint
           limit 1
        ) q
       where o.id = (v_item.value->>'id')::bigint
         and o.user_id = p_user_id;
    end if;
  end loop;

  insert into public.checkout_idempotencia (user_id, chave, resposta, payload_hash)
  values (p_user_id, v_chave, v_ret, v_hash)
  on conflict (user_id, chave) do update
    set resposta = excluded.resposta,
        payload_hash = excluded.payload_hash;

  return v_ret;
end $$;

revoke all on function public.finalizar_checkout_v6(
  uuid, jsonb, numeric, bigint, text, text, text, double precision, double precision,
  jsonb, uuid, jsonb, text, text, jsonb, bigint
) from public, anon;
grant execute on function public.finalizar_checkout_v6(
  uuid, jsonb, numeric, bigint, text, text, text, double precision, double precision,
  jsonb, uuid, jsonb, text, text, jsonb, bigint
) to authenticated;

-- ── 12) DASHBOARD: TODOS OS STATUS PAGOS + CLIENTES CORRETOS ───────────

create or replace function public.dashboard_resumo(
  p_unidade_id bigint default null,
  p_dias int default 30
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_funcao text;
  v_unidade_usuario bigint;
  v_unidade bigint;
  v_dias int := greatest(least(coalesce(p_dias, 30), 365), 1);
  v_inicio timestamptz := now() - make_interval(days => greatest(least(coalesce(p_dias, 30), 365), 1) - 1);
  v_vendas_hoje numeric := 0;
  v_vendas_7d numeric := 0;
  v_vendas_30d numeric := 0;
  v_pedidos_abertos int := 0;
  v_pedidos_hoje int := 0;
  v_pedidos_periodo int := 0;
  v_cancelados int := 0;
  v_clientes_novos int := 0;
  v_estoque_baixo int := 0;
  v_entregas_atrasadas int := 0;
  v_ticket_medio numeric := 0;
  v_por_status jsonb := '{}'::jsonb;
  v_por_loja jsonb := '[]'::jsonb;
  v_top_produtos jsonb := '[]'::jsonb;
  v_serie_dias jsonb := '[]'::jsonb;
  v_recebido numeric := 0;
  v_status_pagos text[] := array[
    'pago', 'em_preparo', 'pronto_para_entrega', 'postado',
    'em_transito', 'saiu_para_entrega', 'entregue'
  ];
begin
  select funcao, unidade_id
    into v_funcao, v_unidade_usuario
    from public.perfis
   where id = auth.uid();

  if v_funcao is null then
    raise exception 'Perfil não encontrado';
  end if;

  if v_funcao = 'admin' then
    v_unidade := p_unidade_id;
  elsif v_funcao in ('gestor', 'atendente') then
    if p_unidade_id is not null and p_unidade_id <> v_unidade_usuario then
      raise exception 'Sem acesso a esta loja';
    end if;
    v_unidade := v_unidade_usuario;
  else
    raise exception 'Sem acesso ao dashboard';
  end if;

  select coalesce(sum(total), 0)
    into v_vendas_hoje
    from public.pedidos
   where created_at::date = current_date
     and status = any(v_status_pagos)
     and (v_unidade is null or unidade_id = v_unidade);

  select coalesce(sum(total), 0)
    into v_vendas_7d
    from public.pedidos
   where created_at >= now() - interval '7 days'
     and status = any(v_status_pagos)
     and (v_unidade is null or unidade_id = v_unidade);

  select coalesce(sum(total), 0)
    into v_vendas_30d
    from public.pedidos
   where created_at >= v_inicio
     and status = any(v_status_pagos)
     and (v_unidade is null or unidade_id = v_unidade);

  select coalesce(sum(p.valor), 0)
    into v_recebido
    from public.pagamentos p
   where p.status = 'pago'
     and p.created_at >= v_inicio
     and (
       v_unidade is null
       or exists (
         select 1 from public.pedidos o
          where o.pagamento_id = p.id and o.unidade_id = v_unidade
       )
     );

  select count(*)
    into v_pedidos_abertos
    from public.pedidos
   where status in (
     'pendente', 'pago', 'em_preparo', 'pronto_para_entrega',
     'postado', 'em_transito', 'saiu_para_entrega'
   )
     and (v_unidade is null or unidade_id = v_unidade);

  select count(*)
    into v_pedidos_hoje
    from public.pedidos
   where created_at::date = current_date
     and (v_unidade is null or unidade_id = v_unidade);

  select count(*)
    into v_pedidos_periodo
    from public.pedidos
   where created_at >= v_inicio
     and (v_unidade is null or unidade_id = v_unidade);

  select count(*)
    into v_cancelados
    from public.pedidos
   where created_at >= v_inicio
     and status = 'cancelado'
     and (v_unidade is null or unidade_id = v_unidade);

  select count(*)
    into v_clientes_novos
    from public.perfis
   where created_at >= v_inicio
     and funcao in ('cliente', 'usuario');

  select count(*)
    into v_estoque_baixo
    from public.produtos
   where coalesce(estoque, 0) <= 3
     and coalesce(ativo, true) = true
     and (v_unidade is null or unidade_id = v_unidade);

  select count(*)
    into v_entregas_atrasadas
    from public.pedidos
   where tipo_entrega = 'entrega'
     and status in ('pago', 'em_preparo', 'pronto_para_entrega', 'postado', 'em_transito', 'saiu_para_entrega')
     and (v_unidade is null or unidade_id = v_unidade)
     and created_at + make_interval(
       mins => coalesce(previsao_entrega_min, 120)
     ) < now();

  select case
           when count(*) = 0 then 0
           else round(sum(total) / count(*), 2)
         end
    into v_ticket_medio
    from public.pedidos
   where created_at >= v_inicio
     and status = any(v_status_pagos)
     and (v_unidade is null or unidade_id = v_unidade);

  select coalesce(jsonb_object_agg(status, qtd), '{}'::jsonb)
    into v_por_status
    from (
      select status, count(*)::int as qtd
        from public.pedidos
       where created_at >= v_inicio
         and (v_unidade is null or unidade_id = v_unidade)
       group by status
    ) s;

  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'unidade_id', x.unidade_id,
               'nome', x.nome,
               'pedidos', x.pedidos,
               'receita', x.receita
             )
             order by x.receita desc
           ),
           '[]'::jsonb
         )
    into v_por_loja
    from (
      select p.unidade_id,
             coalesce(u.nome, 'Loja') as nome,
             count(*)::int as pedidos,
             round(coalesce(sum(p.total), 0), 2) as receita
        from public.pedidos p
        left join public.unidades u on u.id = p.unidade_id
       where p.created_at >= v_inicio
         and p.status = any(v_status_pagos)
         and (v_unidade is null or p.unidade_id = v_unidade)
       group by p.unidade_id, u.nome
    ) x;

  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'produto_id', x.produto_id,
               'nome', x.nome,
               'quantidade', x.quantidade,
               'receita', x.receita
             )
             order by x.quantidade desc
           ),
           '[]'::jsonb
         )
    into v_top_produtos
    from (
      select i.produto_id,
             coalesce(pr.nome, 'Produto') as nome,
             sum(i.quantidade)::int as quantidade,
             round(sum(i.quantidade * coalesce(i.preco_unitario, 0)), 2) as receita
        from public.pedido_itens i
        join public.pedidos p on p.id = i.pedido_id
        left join public.produtos pr on pr.id = i.produto_id
       where p.created_at >= v_inicio
         and p.status = any(v_status_pagos)
         and (v_unidade is null or p.unidade_id = v_unidade)
       group by i.produto_id, pr.nome
       order by quantidade desc
       limit 8
    ) x;

  select coalesce(
           jsonb_agg(
             jsonb_build_object('dia', d::date, 'total', coalesce(x.total, 0))
             order by d
           ),
           '[]'::jsonb
         )
    into v_serie_dias
    from generate_series(current_date - (v_dias - 1), current_date, interval '1 day') d
    left join (
      select created_at::date as dia, round(sum(total), 2) as total
        from public.pedidos
       where created_at >= v_inicio
         and status = any(v_status_pagos)
         and (v_unidade is null or unidade_id = v_unidade)
       group by created_at::date
    ) x on x.dia = d::date;

  return jsonb_build_object(
    'unidade_id', v_unidade,
    'dias', v_dias,
    'vendas_hoje', v_vendas_hoje,
    'vendas_7d', v_vendas_7d,
    'vendas_30d', v_vendas_30d,
    'recebido_pagamentos', v_recebido,
    'pedidos_abertos', v_pedidos_abertos,
    'pedidos_hoje', v_pedidos_hoje,
    'pedidos_periodo', v_pedidos_periodo,
    'cancelados', v_cancelados,
    'clientes_novos', v_clientes_novos,
    'estoque_baixo', v_estoque_baixo,
    'entregas_atrasadas', v_entregas_atrasadas,
    'ticket_medio', v_ticket_medio,
    'por_status', v_por_status,
    'por_loja', v_por_loja,
    'top_produtos', v_top_produtos,
    'serie_dias', v_serie_dias
  );
end $$;

revoke all on function public.dashboard_resumo(bigint, int) from public, anon;
grant execute on function public.dashboard_resumo(bigint, int) to authenticated;

-- ── 13) CRON VERSIONADO (rastreio + conciliação) ───────────────────────
-- Os segredos ficam no Vault, nunca no repositório:
--   select vault.create_secret('https://SEU_PROJECT.supabase.co', 'o_pest_project_url');
--   select vault.create_secret('SEGREDO_LONGO', 'o_pest_conciliacao_secret');
-- Sem esses secrets, o bloco apenas não agenda (não quebra a migration).

do $$
declare
  v_url text;
  v_secret text;
begin
  if to_regnamespace('cron') is null or to_regnamespace('net') is null then
    raise notice 'pg_cron/pg_net ausentes: agende rastreio/conciliação manualmente.';
    return;
  end if;

  begin
    select decrypted_secret into v_url
      from vault.decrypted_secrets
     where name = 'o_pest_project_url'
     limit 1;
    select decrypted_secret into v_secret
      from vault.decrypted_secrets
     where name = 'o_pest_conciliacao_secret'
     limit 1;
  exception when others then
    raise notice 'Vault indisponível: cron de rastreio/conciliação não agendado.';
    return;
  end;

  if v_url is null or v_secret is null then
    raise notice 'Configure o Vault para agendar rastreio/conciliação.';
    return;
  end if;

  perform cron.unschedule(jobname)
    from cron.job
   where jobname in ('o-pest-rastreio', 'o-pest-conciliacao');

  perform cron.schedule(
    'o-pest-rastreio',
    '*/15 * * * *',
    format(
      $job$select net.http_post(url := %L, headers := %L::jsonb, body := '{}'::jsonb);$job$,
      rtrim(v_url, '/') || '/functions/v1/frete-rastreio',
      jsonb_build_object(
        'Content-Type', 'application/json',
        'x-conciliacao-secret', v_secret
      )::text
    )
  );

  perform cron.schedule(
    'o-pest-conciliacao',
    '*/2 * * * *',
    format(
      $job$select net.http_post(url := %L, headers := %L::jsonb, body := '{}'::jsonb);$job$,
      rtrim(v_url, '/') || '/functions/v1/pagamentos-conciliacao',
      jsonb_build_object(
        'Content-Type', 'application/json',
        'x-conciliacao-secret', v_secret
      )::text
    )
  );
end $$;

notify pgrst, 'reload schema';

commit;
