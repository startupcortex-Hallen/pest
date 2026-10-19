-- ═══════════════════════════════════════════════════════════════
-- O PEST - SHOP · PAGAMENTOS REAIS (PAGBANK) — v1
--
-- 1) Tabela `pagamentos`: cobrança única por carrinho (PIX, crédito,
--    débito, boleto), com QR Code, linha digitável, comprovante etc.
-- 2) `pedidos.pagamento_id`: vincula os pedidos das unidades à cobrança.
-- 3) `pagamentos_eventos`: idempotência dos webhooks do gateway.
-- 4) RLS: cliente lê os próprios pagamentos; admin/atendente leem todos.
--    Escritas acontecem SOMENTE via service_role (Edge Functions).
-- 5) SEGURANÇA: revoga do cliente as RPCs antigas de confirmação manual
--    ("Já paguei" / cartão simulado) — confirmação agora vem do webhook.
-- 6) Expiração de pendentes também encerra o pagamento vinculado.
--
-- Idempotente: pode rodar mais de uma vez.
-- ═══════════════════════════════════════════════════════════════

-- ── 1) Cobranças (uma por carrinho/checkout, cobre N pedidos) ──
create table if not exists public.pagamentos (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.perfis(id) on delete cascade,
  gateway text not null default 'pagbank',
  metodo text not null check (metodo in ('pix', 'credito', 'debito', 'boleto')),
  valor numeric(10,2) not null,
  status text not null default 'pendente'
    check (status in ('pendente', 'em_analise', 'pago', 'recusado', 'expirado', 'cancelado', 'estornado')),
  gateway_order_id text,
  gateway_charge_id text,
  -- Comprovante PIX
  pix_copia_cola text,
  pix_qr_image_url text,
  pix_e2e_id text,
  -- Comprovante Boleto
  boleto_linha_digitavel text,
  boleto_codigo_barras text,
  boleto_pdf_url text,
  boleto_vencimento date,
  -- Comprovante Cartão
  cartao_bandeira text,
  cartao_last4 text,
  cartao_autorizacao text,
  cartao_nsu text,
  parcelas int not null default 1,
  -- Controle
  motivo_recusa text,
  expira_em timestamptz,
  pago_em timestamptz,
  gateway_dados jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_pagamentos_user on public.pagamentos(user_id, created_at desc);
create index if not exists idx_pagamentos_charge on public.pagamentos(gateway_charge_id);
create index if not exists idx_pagamentos_order on public.pagamentos(gateway_order_id);

-- ── 2) Pedidos → cobrança ──────────────────────────────────────
alter table public.pedidos add column if not exists pagamento_id bigint
  references public.pagamentos(id) on delete set null;
create index if not exists idx_pedidos_pagamento on public.pedidos(pagamento_id);

-- ── 2.1) Cartões salvos agora são tokenizados no gateway ───────
alter table public.cartoes_usuario add column if not exists gateway_card_id text;
alter table public.cartoes_usuario add column if not exists holder_cpf text;

-- ── 3) Idempotência dos webhooks ───────────────────────────────
create table if not exists public.pagamentos_eventos (
  evento_id text primary key,
  recebido_em timestamptz not null default now()
);
alter table public.pagamentos_eventos enable row level security;
-- Sem policies: acessível apenas via service_role (Edge Function).

-- ── 4) RLS de pagamentos ───────────────────────────────────────
alter table public.pagamentos enable row level security;

drop policy if exists "Cliente - ver pagamentos" on public.pagamentos;
create policy "Cliente - ver pagamentos" on public.pagamentos
  for select to authenticated
  using (
    user_id = auth.uid()
    or (select funcao from public.perfis where id = auth.uid()) in ('admin', 'atendente')
  );
-- Sem policies de INSERT/UPDATE/DELETE: clientes não escrevem.
-- O service_role (Edge Functions) ignora RLS.

-- ── 5) Realtime para acompanhar pagamento ao vivo ──────────────
do $$
begin
  begin
    alter publication supabase_realtime add table public.pagamentos;
  exception when duplicate_object then
    null; -- já está na publicação
  end;
end $$;

-- ── 6) Expiração de pendentes encerra o pagamento vinculado ────
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

  -- Encerra cobranças pendentes vinculadas a pedidos que vão expirar
  update public.pagamentos p
     set status = 'expirado', updated_at = now()
   where p.status = 'pendente'
     and exists (
       select 1 from public.pedidos o
        where o.pagamento_id = p.id
          and o.user_id = auth.uid()
          and o.status = 'pendente'
          and o.created_at < now() - make_interval(mins => p_minutos)
     );

  update public.pedidos
     set status = 'cancelado'
   where user_id = auth.uid()
     and status = 'pendente'
     and created_at < now() - make_interval(mins => p_minutos);
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

grant execute on function public.cancelar_pendentes_expirados(int) to authenticated;

-- ── 7) FIM DA CONFIRMAÇÃO MANUAL PELO CLIENTE ──────────────────
-- Fraude fechada: o app não pode mais marcar pedido como pago.
-- A confirmação agora só acontece pelo webhook assinado do PagBank
-- (service_role). As funções continuam existindo para eventual uso
-- administrativo server-side, mas perdem o acesso do cliente.
do $$
begin
  begin
    -- IMPORTANTE: revogar de PUBLIC também (create function concede a PUBLIC
    -- por padrão; revogar só de authenticated não bloqueia o cliente).
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
    revoke execute on function public.confirmar_pagamento(bigint, text)
      from public, anon, authenticated;
  exception when undefined_function then null;
  end;
  begin
    grant execute on function public.confirmar_pagamento(bigint, text)
      to service_role;
  exception when undefined_function then null;
  end;
end $$;

-- ── 8) Comprovante: view pronta para admin/cliente ─────────────
-- `pagamentos` já contém tudo; expõe um rótulo amigável do método
-- e o total dos pedidos vinculados para conferência (o "comprovante").
drop view if exists public.pagamentos_comprovante;
create view public.pagamentos_comprovante
with (security_invoker = true) as
select
  p.*,
  case p.metodo
    when 'pix' then 'PIX'
    when 'credito' then 'Cartão de crédito'
    when 'debito' then 'Cartão de débito'
    when 'boleto' then 'Boleto'
  end as metodo_rotulo,
  (select coalesce(sum(o.total), 0) from public.pedidos o where o.pagamento_id = p.id) as pedidos_total,
  (select count(*) from public.pedidos o where o.pagamento_id = p.id) as pedidos_count
from public.pagamentos p;

grant select on public.pagamentos_comprovante to authenticated;
