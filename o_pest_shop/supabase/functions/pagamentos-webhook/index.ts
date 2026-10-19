// Edge Function `pagamentos-webhook` — recebe as notificações do PagBank.
//
// Segurança:
//   • Valida a assinatura `x-authenticity-token` = SHA-256(token + "-" + body)
//   • Idempotente: cada payload é processado uma única vez (pagamentos_eventos)
//
// Deploy OBRIGATORIAMENTE com --no-verify-jwt (o PagBank não envia JWT):
//   supabase functions deploy pagamentos-webhook --no-verify-jwt

import { createClient } from 'npm:@supabase/supabase-js@2';
import { extrairComprovante, mapearStatus } from '../_shared/pagbank.ts';
import { aplicarComprovante } from '../_shared/pagamentos_db.ts';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

async function sha256hex(texto: string): Promise<string> {
  const dados = new TextEncoder().encode(texto);
  const digest = await crypto.subtle.digest('SHA-256', dados);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('method not allowed', { status: 405 });
  }
  const raw = await req.text();
  const token = Deno.env.get('PAGBANK_TOKEN') ?? '';
  const assinatura = req.headers.get('x-authenticity-token') ?? '';

  if (!token) {
    console.error('PAGBANK_TOKEN não configurado — webhook recusado.');
    return new Response('configuração ausente', { status: 500 });
  }
  if (!assinatura) {
    console.warn('webhook sem header de autenticidade');
    return new Response('assinatura ausente', { status: 401 });
  }
  const esperada = await sha256hex(`${token}-${raw}`);
  if (assinatura !== esperada) {
    console.warn('webhook com assinatura inválida');
    return new Response('assinatura inválida', { status: 401 });
  }

  let corpo: Record<string, unknown>;
  try {
    corpo = JSON.parse(raw);
  } catch {
    return new Response('payload inválido', { status: 400 });
  }

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
    auth: { persistSession: false },
  });

  // Idempotência: mesmo payload processado 1x só.
  const eventoId = await sha256hex(raw);
  const { error: erroEvento } = await admin
    .from('pagamentos_eventos')
    .insert({ evento_id: eventoId });
  if (erroEvento) {
    // Duplicado → já processado.
    return new Response('ok (duplicado)', { status: 200 });
  }

  try {
    const orderId = corpo['id'] as string | undefined;
    const charges = Array.isArray(corpo['charges'])
      ? (corpo['charges'] as Record<string, unknown>[])
      : [corpo];

    for (const charge of charges) {
      const chargeId = charge['id'] as string | undefined;
      const metadata = (charge['metadata'] as Record<string, unknown> | undefined) ?? {};
      const psOrderId = (metadata['ps_order_id'] as string | undefined) ??
        (orderId?.startsWith('ORDE_') ? orderId : undefined);

      if (!chargeId && !psOrderId) continue;

      let pagamento: Record<string, unknown> | null = null;
      if (chargeId) {
        const { data } = await admin
          .from('pagamentos')
          .select('id')
          .eq('gateway_charge_id', chargeId)
          .maybeSingle();
        pagamento = data ?? null;
      }
      if (!pagamento && psOrderId) {
        const { data } = await admin
          .from('pagamentos')
          .select('id')
          .eq('gateway_order_id', psOrderId)
          .maybeSingle();
        pagamento = data ?? null;
      }
      if (!pagamento) {
        console.warn('webhook: cobrança sem pagamento local', chargeId, psOrderId);
        continue;
      }

      const pseudoOrder = psOrderId
        ? { id: psOrderId, charges: [charge] }
        : { charges: [charge] };
      const { comprovante } = extrairComprovante(pseudoOrder);
      if (comprovante['status']) {
        comprovante['status'] = mapearStatus((charge['status'] as string) ?? '');
      }
      await aplicarComprovante(admin, pagamento['id'] as number, comprovante);
    }
  } catch (e) {
    console.error('webhook erro ao processar:', e);
    // 200 mesmo em falha interna: o gateway reenviaria em loop.
    // O polling da tela (consultar) reconcilia casos raros.
  }

  return new Response('ok', { status: 200 });
});
