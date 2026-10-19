// Aplica o comprovante do gateway no banco (pagamentos + pedidos).
// Usado pelo webhook e pela consulta ativa (fallback). Idempotente.

import type { SupabaseClient } from 'npm:@supabase/supabase-js@2';

export function rotuloMetodo(metodo: string): string {
  switch (metodo) {
    case 'pix':
      return 'PIX';
    case 'credito':
      return 'Cartão de crédito';
    case 'debito':
      return 'Cartão de débito';
    case 'boleto':
      return 'Boleto';
    default:
      return metodo;
  }
}

export async function aplicarComprovante(
  admin: SupabaseClient,
  pagamentoId: number,
  comprovante: Record<string, unknown>,
) {
  const patch: Record<string, unknown> = {
    updated_at: new Date().toISOString(),
  };
  const campos = [
    'gateway_order_id',
    'gateway_charge_id',
    'pix_copia_cola',
    'pix_qr_image_url',
    'pix_e2e_id',
    'boleto_linha_digitavel',
    'boleto_codigo_barras',
    'boleto_pdf_url',
    'boleto_vencimento',
    'cartao_bandeira',
    'cartao_last4',
    'cartao_autorizacao',
    'cartao_nsu',
  ] as const;
  for (const campo of campos) {
    const valor = comprovante[campo];
    if (valor !== undefined && valor !== null) patch[campo] = valor;
  }
  if (comprovante['status']) patch['status'] = comprovante['status'];
  if (comprovante['paid_at']) patch['pago_em'] = comprovante['paid_at'];
  if (comprovante['expira_em']) patch['expira_em'] = comprovante['expira_em'];
  if (comprovante['gateway_status']) {
    patch['gateway_dados'] = {
      status: comprovante['gateway_status'],
      payment_response: comprovante['payment_response'] ?? null,
    };
  }
  const resposta = comprovante['payment_response'] as Record<string, unknown> | undefined;
  if (comprovante['status'] === 'recusado') {
    patch['motivo_recusa'] = (resposta?.['message'] as string | undefined) ?? 'Pagamento recusado';
  }

  const { data: pagamento } = await admin
    .from('pagamentos')
    .update(patch)
    .eq('id', pagamentoId)
    .select('id, metodo, status')
    .maybeSingle();

  if (!pagamento) return null;

  if (pagamento['status'] === 'pago') {
    await admin
      .from('pedidos')
      .update({
        status: 'pago',
        pagamento: rotuloMetodo(pagamento['metodo'] as string),
        transacao_id: (comprovante['gateway_charge_id'] as string | undefined) ?? null,
        pagamento_detalhes: montarDetalhes(pagamento['metodo'] as string, comprovante),
        pago_em: (comprovante['paid_at'] as string | undefined) ?? new Date().toISOString(),
      })
      .eq('pagamento_id', pagamentoId)
      .eq('status', 'pendente');
  }

  return pagamento;
}

function montarDetalhes(metodo: string, comprovante: Record<string, unknown>): string {
  const partes: string[] = [];
  if (metodo === 'pix') {
    partes.push('PIX');
    if (comprovante['pix_e2e_id']) partes.push(`E2E ${comprovante['pix_e2e_id']}`);
  } else if (metodo === 'boleto') {
    partes.push('Boleto');
    if (comprovante['boleto_linha_digitavel']) {
      partes.push(`Linha ${comprovante['boleto_linha_digitavel']}`);
    }
  } else {
    partes.push(rotuloMetodo(metodo));
    if (comprovante['cartao_bandeira'] && comprovante['cartao_last4']) {
      partes.push(`${comprovante['cartao_bandeira']} •••• ${comprovante['cartao_last4']}`);
    }
    if (comprovante['cartao_autorizacao']) {
      partes.push(`Autorização ${comprovante['cartao_autorizacao']}`);
    }
  }
  if (comprovante['gateway_charge_id']) partes.push(String(comprovante['gateway_charge_id']));
  return partes.join(' • ');
}
