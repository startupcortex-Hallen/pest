-- ═══════════════════════════════════════════════════════════════
-- O PEST - SHOP · REFORÇO DE PERMISSÕES DAS FUNÇÕES (RPC)
--
-- PROBLEMA: no PostgreSQL, `create function` concede EXECUTE a PUBLIC
-- por padrão. Revogar apenas de `authenticated` NÃO bloqueia o cliente
-- (ele herda a permissão de PUBLIC). Isso deixava o cliente ainda
-- conseguir chamar `confirmar_pagamento` / `processar_pagamento_cartao`
-- (o antigo "Já paguei" / cartão simulado).
--
-- Este script revoga de PUBLIC/anon/authenticated e devolve o acesso
-- somente para quem deve usar:
--   • confirmação de pagamento / estoque → service_role (Edge Functions)
--   • fluxo da loja (checkout, status, entregador) → authenticated
--
-- Idempotente. Rode DEPOIS dos outros dois SQLs.
-- ═══════════════════════════════════════════════════════════════

-- ── Pagamento/estoque: SOMENTE server-side ─────────────────────
do $$
begin
  begin
    revoke execute on function public.confirmar_pagamento(bigint, text)
      from public, anon, authenticated;
  exception when undefined_function then null;
  end;
  begin
    grant execute on function public.confirmar_pagamento(bigint, text)
      to service_role;
  exception when undefined_function then null;
  end;

  begin
    revoke execute on function public.processar_pagamento_cartao(bigint, bigint, int)
      from public, anon, authenticated;
  exception when undefined_function then null;
  end;
  begin
    grant execute on function public.processar_pagamento_cartao(bigint, bigint, int)
      to service_role;
  exception when undefined_function then null;
  end;

  begin
    revoke execute on function public.decrementar_estoque(bigint, int)
      from public, anon, authenticated;
  exception when undefined_function then null;
  end;
  begin
    grant execute on function public.decrementar_estoque(bigint, int)
      to service_role;
  exception when undefined_function then null;
  end;
end $$;

-- ── Fluxo da loja: somente usuários autenticados ───────────────
do $$
begin
  -- finalizar_checkout
  begin
    revoke execute on function public.finalizar_checkout(uuid, jsonb, numeric, bigint, text, text, text)
      from public, anon;
  exception when undefined_function then null;
  end;
  begin
    grant execute on function public.finalizar_checkout(uuid, jsonb, numeric, bigint, text, text, text)
      to authenticated;
  exception when undefined_function then null;
  end;

  -- alterar_status_pedido
  begin
    revoke execute on function public.alterar_status_pedido(bigint, text, text)
      from public, anon;
  exception when undefined_function then null;
  end;
  begin
    grant execute on function public.alterar_status_pedido(bigint, text, text)
      to authenticated;
  exception when undefined_function then null;
  end;

  -- atribuir_entregador
  begin
    revoke execute on function public.atribuir_entregador(bigint, uuid)
      from public, anon;
  exception when undefined_function then null;
  end;
  begin
    grant execute on function public.atribuir_entregador(bigint, uuid)
      to authenticated;
  exception when undefined_function then null;
  end;

  -- cancelar_pedido
  begin
    revoke execute on function public.cancelar_pedido(bigint)
      from public, anon;
  exception when undefined_function then null;
  end;
  begin
    grant execute on function public.cancelar_pedido(bigint)
      to authenticated;
  exception when undefined_function then null;
  end;

  -- cancelar_pendentes_expirados
  begin
    revoke execute on function public.cancelar_pendentes_expirados(int)
      from public, anon;
  exception when undefined_function then null;
  end;
  begin
    grant execute on function public.cancelar_pendentes_expirados(int)
      to authenticated;
  exception when undefined_function then null;
  end;

  -- funcao_usuario (usada nas policies de RLS)
  begin
    revoke execute on function public.funcao_usuario()
      from public, anon;
  exception when undefined_function then null;
  end;
  begin
    grant execute on function public.funcao_usuario()
      to authenticated;
  exception when undefined_function then null;
  end;
end $$;

-- ── Verificação: lista funções e quem pode executar ────────────
select
  p.proname as funcao,
  pg_get_function_identity_arguments(p.oid) as argumentos,
  coalesce(
    (select string_agg(distinct case when a.grantee = 0 then 'PUBLIC' else a.grantee::regrole::text end, ', ')
       from aclexplode(p.proacl) a
      where a.privilege_type = 'EXECUTE'),
    'sem ACL explícita (default)'
  ) as executam
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'confirmar_pagamento', 'processar_pagamento_cartao', 'decrementar_estoque',
    'finalizar_checkout', 'alterar_status_pedido', 'atribuir_entregador',
    'cancelar_pedido', 'cancelar_pendentes_expirados', 'funcao_usuario'
  )
order by p.proname;
