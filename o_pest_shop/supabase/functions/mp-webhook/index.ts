// =====================================================================
// O Pest - Shop | Edge Function: mp-webhook
//
// Recebe a notificacao do Mercado Pago, confere o valor de verdade e
// marca o pedido como pago. Usa a SERVICE ROLE (ignora RLS), por isso
// roda com --no-verify-jwt e valida a assinatura x-signature.
//
// Secrets necessarios:
//   supabase secrets set MP_ACCESS_TOKEN=TEST-...
//   supabase secrets set MP_WEBHOOK_SECRET=...   (Painel MP > Webhooks > chave secreta)
//
// Deploy:
//   supabase functions deploy mp-webhook --no-verify-jwt
//
// No painel do Mercado Pago, cadastre a URL de notificacao:
//   https://<PROJECT_REF>.supabase.co/functions/v1/mp-webhook
// =====================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

/** Confere a assinatura enviada pelo Mercado Pago (HMAC SHA-256). */
async function assinaturaValida(req: Request, dataId: string | null): Promise<boolean> {
  const secret = Deno.env.get('MP_WEBHOOK_SECRET');
  if (!secret) return true; // sem secret configurado, nao bloqueia (configure em producao)

  const sigHeader = req.headers.get('x-signature') ?? '';
  const requestId = req.headers.get('x-request-id') ?? '';
  if (!sigHeader || !dataId) return false;

  const partes = Object.fromEntries(
    sigHeader.split(',').map((p) => p.split('=').map((s) => s.trim()) as [string, string]),
  );
  const ts = partes['ts'];
  const v1 = partes['v1'];
  if (!ts || !v1) return false;

  const manifest = `id:${dataId};request-id:${requestId};ts:${ts};`;
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const assinatura = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(manifest));
  const esperado = btoa(String.fromCharCode(...new Uint8Array(assinatura)));

  return esperado === v1;
}

Deno.serve(async (req) => {
  try {
    const url = new URL(req.url);
    const raw = await req.text();

    let body: Record<string, unknown> = {};
    try { body = JSON.parse(raw); } catch { /* MP as vezes manda query string */ }

    const tipo = (body?.type as string) ?? url.searchParams.get('type') ?? '';
    const dataId = ((body?.data as Record<string, unknown>)?.id as string)
      ?? url.searchParams.get('data.id');

    // So tratamos notificacao de pagamento; o resto responde 200 para o MP parar de tentar.
    if (tipo !== 'payment' || !dataId) return new Response('ignored', { status: 200 });

    if (!(await assinaturaValida(req, dataId))) {
      return new Response('assinatura invalida', { status: 401 });
    }

    const mpToken = Deno.env.get('MP_ACCESS_TOKEN')!;
    const mpRes = await fetch(`https://api.mercadopago.com/v1/payments/${dataId}`, {
      headers: { Authorization: `Bearer ${mpToken}` },
    });
    if (!mpRes.ok) return new Response('mp error', { status: 200 });
    const pagamento = await mpRes.json();

    const pedidoId = Number(pagamento?.external_reference);
    if (!pedidoId) return new Response('sem external_reference', { status: 200 });

    // Service role: ignora RLS (o cliente nao pode fazer isso).
    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    const { data: pedido } = await admin
      .from('pedidos')
      .select('id, total, status')
      .eq('id', pedidoId)
      .maybeSingle();

    if (!pedido) return new Response('pedido inexistente', { status: 200 });

    // Confere o valor cobrado contra o valor real do pedido antes de liberar.
    const valorPago = Number(pagamento?.transaction_amount ?? 0);
    const valorPedido = Number(pedido.total ?? 0);
    if (Math.abs(valorPago - valorPedido) > 0.01) {
      return new Response('valor divergente', { status: 200 });
    }

    const status = pagamento?.status as string | undefined;

    if (status === 'approved' && pedido.status === 'pendente') {
      await admin.from('pedidos').update({
        status: 'pago',
        pagamento: pagamento?.payment_method_id ?? 'mercadopago',
        transacao_id: String(pagamento.id),
        pagamento_detalhes: 'approved',
      }).eq('id', pedido.id);
    } else if (status === 'refunded' || status === 'charged_back') {
      await admin.from('pedidos').update({
        status: 'cancelado',
        pagamento_detalhes: status,
      }).eq('id', pedido.id);
    } else if (status === 'rejected' || status === 'cancelled') {
      await admin.from('pedidos').update({
        pagamento_detalhes: status,
      }).eq('id', pedido.id);
    }

    return new Response('ok', { status: 200 });
  } catch (e) {
    // Sempre 200 para o MP nao ficar reenviando em loop infinito.
    console.error('mp-webhook erro:', e);
    return new Response('ok', { status: 200 });
  }
});
