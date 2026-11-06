-- Endurecimento final de segurança:
--   1) cliente não consegue se desbloquear/alterar pontos/status por API direta;
--   2) pagamento manual restrito ao admin;
--   3) tabelas legadas de academia/nutrição sem acesso de anon/authenticated.

begin;

-- ── 1) PROTEÇÃO DO PERFIL ──────────────────────────────────────────────

create or replace function public.protege_funcao_perfil()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_funcao_atual text;
begin
  -- service_role / SQL Editor: auth.uid() nulo, pode tudo.
  if auth.uid() is null then
    return new;
  end if;

  select funcao into v_funcao_atual
    from public.perfis
   where id = auth.uid();

  if tg_op = 'INSERT' then
    -- No cadastro o usuário só pode nascer como cliente/usuario (ou null).
    if coalesce(new.funcao, 'cliente') not in ('cliente', 'usuario', '') then
      if coalesce(v_funcao_atual, '') <> 'admin' then
        raise exception 'Somente admin pode criar perfil com essa funcao'
          using errcode = '42501';
      end if;
    end if;

    -- Campos administrativos não podem ser auto-atribuídos no cadastro.
    if coalesce(v_funcao_atual, '') <> 'admin' then
      new.status_conta := 'ativo';
      new.bloqueado_em := null;
      new.anonimizado_em := null;
      new.pontos := 0;
    end if;
    return new;
  end if;

  -- Função e unidade só podem ser alteradas por admin.
  if (new.funcao is distinct from old.funcao
      or new.unidade_id is distinct from old.unidade_id)
     and coalesce(v_funcao_atual, '') <> 'admin' then
    raise exception 'Somente admin pode alterar funcao ou unidade de um perfil'
      using errcode = '42501';
  end if;

  -- Status/pontos/anonimização são campos administrativos. Sem isso, um
  -- usuário bloqueado poderia voltar para "ativo" direto pela API.
  if coalesce(v_funcao_atual, '') <> 'admin' then
    new.status_conta := old.status_conta;
    new.bloqueado_em := old.bloqueado_em;
    new.anonimizado_em := old.anonimizado_em;
    new.pontos := old.pontos;
  end if;

  return new;
end $$;

drop trigger if exists trg_protege_funcao_perfil on public.perfis;
create trigger trg_protege_funcao_perfil
  before insert or update on public.perfis
  for each row execute function public.protege_funcao_perfil();

-- ── 2) PAGAMENTO MANUAL SOMENTE ADMIN ──────────────────────────────────

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
  v_pedido public.pedidos%rowtype;
  v_pagamento_id bigint;
  v_motivo text := nullif(trim(coalesce(p_motivo, '')), '');
begin
  if v_funcao <> 'admin' then
    raise exception 'Somente o admin pode confirmar pagamento manual';
  end if;
  if v_motivo is null or length(v_motivo) < 5 then
    raise exception 'Informe o motivo do pagamento manual';
  end if;

  perform pg_advisory_xact_lock(p_pedido_id);

  select * into v_pedido from public.pedidos where id = p_pedido_id for update;
  if v_pedido.id is null then
    raise exception 'Pedido não encontrado';
  end if;

  if v_pedido.status <> 'pendente' then
    raise exception 'Este pedido não está aguardando pagamento (status: %)', v_pedido.status;
  end if;

  if exists (
    select 1 from public.pagamentos p
     where p.id = v_pedido.pagamento_id
       and p.status in ('pago', 'pendente', 'em_analise')
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

revoke all on function public.confirmar_pagamento_manual(bigint, text)
  from public, anon;
grant execute on function public.confirmar_pagamento_manual(bigint, text)
  to authenticated;

-- ── 3) TABELAS LEGADAS SEM ACESSO PÚBLICO ──────────────────────────────

do $$
declare
  v_tabela text;
  v_tabelas text[] := array[
    'assinaturas', 'aulas', 'aulas_inscricao', 'personal_sessoes',
    'avaliacoes', 'progresso_fotos', 'desafios', 'desafios_participantes',
    'indicacoes', 'nutricionistas', 'consultas', 'treinos', 'exercicios',
    'plano_refeicoes', 'agua_registro', 'perfis_unidades', 'candidaturas'
  ];
begin
  foreach v_tabela in array v_tabelas loop
    if to_regclass('public.' || v_tabela) is not null then
      execute format('revoke all on public.%I from anon, authenticated', v_tabela);
    end if;
  end loop;
end $$;

notify pgrst, 'reload schema';

commit;
