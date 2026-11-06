// Edge Function `pagamentos-webhook` — recebe as notificações do PagBank.
//
// Segurança:
//   • Valida a assinatura `x-authenticity-token` = SHA-256(token + "-" + body)
//   • Idempotente: cada payload é processado uma única vez (pagamentos_eventos)
//   • Devolve 5xx quando o processamento falha para o PagBank reenviar
//
// Deploy OBRIGATORIAMENTE com --no-verify-jwt (o PagBank não envia JWT):
//   supabase functions deploy pagamentos-webhook --no-verify-jwt

import { createClient } from 'npm:@supabase/supabase-js@2';
import { extrairComprovante, mapearStatus } from '../_shared/pagbank.ts';
import { aplicarComprovante } from '../_shared/pagamentos_db.ts';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const MAX_TENTATIVAS = 8;

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

  // Idempotência com contador de tentativas: uma falha real NÃO vira
  // "duplicado". O PagBank recebe 500 e reenvia.
  const eventoId = await sha256hex(raw);
  const { data: existente } = await admin
    .from('pagamentos_eventos')
    .select('evento_id, processado_em, tentativas')
    .eq('evento_id', eventoId)
    .maybeSingle();
  if (existente?.['processado_em']) {
    return new Response('ok (duplicado)', { status: 200 });
  }

  const tentativas = Number(existente?.['tentativas'] ?? 0) + 1;
  if (existente && tentativas > MAX_TENTATIVAS) {
    await admin
      .from('pagamentos_eventos')
      .update({
        erro: 'Limite de tentativas atingido; revisar na conciliação.',
        processado_em: new Date().toISOString(),
      })
      .eq('evento_id', eventoId);
    console.error('webhook: limite de tentativas atingido', eventoId);
    return new Response('ok (limite de tentativas)', { status: 200 });
  }

  if (existente) {
    await admin
      .from('pagamentos_eventos')
      .update({ tentativas })
      .eq('evento_id', eventoId);
  } else {
    const { error: erroInsert } = await admin
      .from('pagamentos_eventos')
      .insert({ evento_id: eventoId, payload: corpo, tentativas });
    if (erroInsert) {
      // Corrida com outro reenvio do mesmo payload: deixa o outro processar.
      if (erroInsert.code === '23505') {
        return new Response('ok (em processamento)', { status: 200 });
      }
      console.error('webhook: falha ao registrar evento:', erroInsert);
      return new Response('falha ao registrar evento', { status: 500 });
    }
  }

  try {
    const orderId = corpo['id'] as string | undefined;
    const charges = Array.isArray(corpo['charges'])
      ? (corpo['charges'] as Record<string, unknown>[])
      : [corpo];

    let encontrados = 0;
    let naoEncontrados = 0;

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
        naoEncontrados++;
        console.warn('webhook: cobrança sem pagamento local', chargeId, psOrderId);
        continue;
      }

      const pseudoOrder = psOrderId
        ? { id: psOrderId, charges: [charge] }
        : { charges: [charge] };
      const { comprovante } = extrairComprovante(pseudoOrder);
      const statusGateway = typeof charge['status'] === 'string' ? charge['status'] : '';
      if (statusGateway) {
        comprovante['status'] = mapearStatus(statusGateway);
      }

      const resultado = await aplicarComprovante(
        admin,
        pagamento['id'] as number,
        comprovante,
      );
      if (resultado.revisaoManual) {
        console.error(
          'webhook: pagamento exige revisão manual:',
          pagamento['id'],
          resultado.revisaoMotivo,
        );
      }
      encontrados++;
    }

    if (encontrados === 0 && naoEncontrados > 0) {
      // Provável corrida: o webhook chegou antes do INSERT do pagamento.
      throw new Error('Cobrança ainda não registrada no banco local.');
    }

    await admin
      .from('pagamentos_eventos')
      .update({
        processado_em: new Date().toISOString(),
        erro: null,
      })
      .eq('evento_id', eventoId);

    return new Response('ok', { status: 200 });
  } catch (e) {
    const mensagem = e instanceof Error ? e.message : String(e);
    console.error('webhook erro ao processar:', e);
    await admin
      .from('pagamentos_eventos')
      .update({ erro: mensagem, tentativas })
      .eq('evento_id', eventoId);
    // 500 → o PagBank reenvia. A consulta ativa (`consultar`) também reconcilia.
    return new Response('erro interno; tentaremos novamente', { status: 500 });
  }
});
