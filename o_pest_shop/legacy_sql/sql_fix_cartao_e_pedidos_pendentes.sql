-- ═══════════════════════════════════════════════════════════════
-- O PEST - SHOP · PAGAMENTO (CARTÃO) + EXPIRAÇÃO DE PENDENTES
-- 1) Transação/acompanhamento do pagamento no pedido
-- 2) Autorização SIMULADA de cartão pelo banco (valida permissões)
-- 3) Cancelamento automático de pedidos não pagos (padrão grandes apps)
-- Idempotente: pode rodar mais de uma vez.
-- ═══════════════════════════════════════════════════════════════

-- ── 0) Colunas de acompanhamento de pagamento ──────────────────
alter table pedidos add column if not exists transacao_id text;
alter table pedidos add column if not exists pagamento_detalhes text;

-- ── 1) RPCs removidas (idempotência) ───────────────────────────
drop function if exists public.processar_pagamento_cartao(bigint, bigint, int);
drop function if exists public.cancelar_pendentes_expirados(int);

-- ── 2) Autorização SIMULADA de cartão ──────────────────────────
-- Sem gateway real (requeria conta num PSP: Pagar.me, Mercado Pago...),
-- o banco simula a autorização de forma segura e controlada:
--   • só o dono pode pagar o próprio pedido pendente;
--   • o cartão precisa pertencer ao usuário e estar "dentro da validade";
--   • gera um ID de transação e registra detalhes do pagamento.
-- Troca por uma integração real no futuro sem quebrar o fluxo do app.
create or replace function public.processar_pagamento_cartao(
  p_pedido_id bigint,
  p_cartao_id bigint,
  p_parcelas int default 1
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pedido pedidos%rowtype;
  v_cartao cartoes_usuario%rowtype;
  v_transacao uuid;
  v_hoje_ym int := extract(year from now())::int * 100 + extract(month from now())::int;
begin
  select * into v_pedido from pedidos where id = p_pedido_id;
  if v_pedido.id is null then
    raise exception 'Pedido não encontrado';
  end if;

  if v_pedido.user_id <> auth.uid() then
    raise exception 'Você não pode pagar este pedido';
  end if;

  if v_pedido.status <> 'pendente' then
    return jsonb_build_object('aprovado', false,
      'motivo', 'O pedido não está em aguardando pagamento',
      'status', v_pedido.status);
  end if;

  select * into v_cartao from cartoes_usuario
   where id = p_cartao_id and user_id = auth.uid();
  if v_cartao.id is null then
    raise exception 'Cartão não encontrado';
  end if;

  if p_parcelas <= 0 then
    raise exception 'Número de parcelas inválido';
  end if;

  -- Validade do cartão (ano armazenado por extenso, ex.: 2028)
  if v_cartao.ano_validade * 100 + v_cartao.mes_validade < v_hoje_ym then
    return jsonb_build_object('aprovado', false, 'motivo', 'Cartão vencido');
  end if;

  -- Autorização simulada aprovada + ID de transação
  v_transacao := gen_random_uuid();

  update pedidos
     set pagamento = 'cartao',
         transacao_id = v_transacao::text,
         pagamento_detalhes = format('%s • %sx • Transação #%s',
             v_cartao.bandeira, p_parcelas, left(v_transacao::text, 8))
   where id = p_pedido_id;

  -- Aprovação → trigger fn_pedido_status baixa estoque e avança p/ em_preparo
  update pedidos set status = 'pago'
   where id = p_pedido_id and status = 'pendente';

  return jsonb_build_object('aprovado', true,
    'transacao_id', v_transacao::text,
    'status', 'pago');
end;
$$;

-- ── 3) Expiração de pedidos NÃO pagos (padrão grandes apps) ─────
-- O cliente chama ao abrir "Meus Pedidos": pedidos pendentes mais
-- antigos que o prazo (padrão 60 min) são cancelados e somem da fila
-- do admin. O estoque não é baixado nesses casos (só no pagamento).
create or replace function public.cancelar_pendentes_expirados(
  p_minutos int default 60
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int;
begin
  if p_minutos < 1 then
    p_minutos := 60;
  end if;

  update pedidos
     set status = 'cancelado'
   where user_id = auth.uid()
     and status = 'pendente'
     and created_at < now() - make_interval(mins => p_minutos);
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- ── 4) Grants ──────────────────────────────────────────────────
grant execute on function public.processar_pagamento_cartao(bigint, bigint, int) to authenticated;
grant execute on function public.cancelar_pendentes_expirados(int) to authenticated;
