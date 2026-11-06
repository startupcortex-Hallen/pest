-- Testes de segurança do hardening.
-- Rode no SQL Editor do STAGING (não em produção) após aplicar a migration
-- 20261105120000_hardening_escalabilidade.sql.
-- O script só consulta metadados; não altera dados.

do $$
declare
  v_ok boolean;
begin
  -- 1) Trigger de preço existe e realmente sobrescreve o valor do cliente.
  if not exists (
    select 1 from pg_trigger
     where tgname = 'trg_forcar_preco_produto'
       and not tgisinternal
  ) then
    raise exception 'FALHOU: trigger trg_forcar_preco_produto ausente';
  end if;

  if not exists (
    select 1 from pg_proc
     where proname = 'fn_forcar_preco_produto'
       and pg_get_functiondef(oid) ilike '%new.preco_unitario%'
  ) then
    raise exception 'FALHOU: função de preço não sobrescreve preco_unitario';
  end if;

  -- 2) Cliente comum não lê custo nem PIX/repasse.
  if has_column_privilege('authenticated', 'public.produtos', 'custo', 'SELECT') then
    raise exception 'FALHOU: authenticated ainda lê produtos.custo';
  end if;
  if has_column_privilege('authenticated', 'public.unidades', 'pix_key', 'SELECT') then
    raise exception 'FALHOU: authenticated ainda lê unidades.pix_key';
  end if;
  if has_column_privilege('authenticated', 'public.unidades', 'comissao_percentual', 'SELECT') then
    raise exception 'FALHOU: authenticated ainda lê unidades.comissao_percentual';
  end if;
  if has_column_privilege('authenticated', 'public.unidades', 'repasse_pagbank_id', 'SELECT') then
    raise exception 'FALHOU: authenticated ainda lê unidades.repasse_pagbank_id';
  end if;

  -- 3) O catálogo público continua legível.
  if not has_table_privilege('anon', 'public.produtos_publicos', 'SELECT') then
    raise exception 'FALHOU: anon não lê produtos_publicos';
  end if;
  if not has_table_privilege('anon', 'public.unidades_publicas', 'SELECT') then
    raise exception 'FALHOU: anon não lê unidades_publicas';
  end if;
  if not has_table_privilege('anon', 'public.app_config_publica', 'SELECT') then
    raise exception 'FALHOU: anon não lê app_config_publica';
  end if;

  -- 4) Apenas v6 está exposta ao app.
  if not exists (
    select 1 from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname = 'finalizar_checkout_v6'
       and has_function_privilege('authenticated', p.oid, 'EXECUTE')
  ) then
    raise exception 'FALHOU: finalizar_checkout_v6 não está exposta ao app';
  end if;

  if exists (
    select 1 from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in (
         'finalizar_checkout',
         'finalizar_checkout_v2',
         'finalizar_checkout_v3',
         'finalizar_checkout_v4',
         'finalizar_checkout_v5'
       )
       and has_function_privilege('authenticated', p.oid, 'EXECUTE')
  ) then
    raise exception 'FALHOU: checkout antigo ainda executável por authenticated';
  end if;

  -- 5) Lock de cobrança e processamento existem.
  if to_regclass('public.cobranca_locks') is null then
    raise exception 'FALHOU: tabela cobranca_locks ausente';
  end if;
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public'
       and table_name = 'pagamentos'
       and column_name = 'processando_em'
  ) then
    raise exception 'FALHOU: pagamentos.processando_em ausente';
  end if;

  -- 6) Feature flags padrão.
  if (select count(*) from public.app_config
       where chave in ('checkout', 'pagamentos', 'frete', 'manutencao')) < 4 then
    raise exception 'FALHOU: app_config incompleto';
  end if;

  -- 7) Limpeza disponível.
  if not exists (
    select 1 from pg_proc
     where proname = 'limpar_registros_temporarios'
  ) then
    raise exception 'FALHOU: limpar_registros_temporarios ausente';
  end if;

  raise notice 'OK: testes de segurança passaram.';
end $$;

-- Teste manual do preço (fazer em staging com um produto de teste):
-- 1. crie um pedido pendente para um usuário de teste;
-- 2. chame finalizar_checkout_v6 com p_itens contendo preco_atual=1.00;
-- 3. confirme que pedido_itens.preco_unitario e pedidos.total usam o preço
--    real do produto, nunca 1.00.
-- 4. rollback/cancele o pedido de teste.
