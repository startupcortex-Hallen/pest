// Aplica o comprovante do gateway no banco (pagamentos + pedidos).
// Usado pelo webhook, pela consulta ativa e pela conciliação. Idempotente.
//
// Regras:
//  - status nunca regride (pago não volta para pendente);
//  - estorno/cancelamento/chargeback encerra o pedido e devolve estoque/cupom;
//  - valor recebido divergente não libera o pedido e entra em revisão manual.

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
    case 'manual':
      return 'Manual';
    default:
      return metodo;
  }
}

export type ResultadoAplicar = {
  pagamento: Record<string, unknown> | null;
  pedidosAtualizados: number;
  pedidosPendentes: number;
  revisaoManual: boolean;
  revisaoMotivo: string | null;
};

type PedidoResumo = {
  id: number;
  status: string;
};

const ORDEM_STATUS: Record<string, number> = {
  pendente: 0,
  em_analise: 1,
  pago: 2,
  recusado: 3,
  expirado: 3,
  cancelado: 4,
  estornado: 5,
};

function podeAplicarStatus(atual: string, novo: string): boolean {
  if (!novo) return false;
  if (novo === atual) return true;
  if (atual === 'estornado') return false;
  if (atual === 'pago') {
    return novo === 'estornado' || novo === 'cancelado';
  }
  // Pagamento que apareceu depois de recusa/expiração/cancelamento não pode
  // ser ignorado (pode haver dinheiro). Entra como pago e a revisão manual
  // decide se libera o pedido ou estorna.
  if (atual === 'recusado' || atual === 'expirado' || atual === 'cancelado') {
    return novo === 'pago';
  }
  return (ORDEM_STATUS[novo] ?? 0) >= (ORDEM_STATUS[atual] ?? 0);
}

async function aplicarComprovanteInterno(
  admin: SupabaseClient,
  pagamentoId: number,
  comprovante: Record<string, unknown>,
): Promise<ResultadoAplicar> {
  const { data: pagamentoAtual, error: erroAtual } = await admin
    .from('pagamentos')
    .select('*')
    .eq('id', pagamentoId)
    .maybeSingle();
  if (erroAtual) {
    throw new Error(`Falha ao carregar o pagamento: ${erroAtual.message}`);
  }
  if (!pagamentoAtual) {
    return {
      pagamento: null,
      pedidosAtualizados: 0,
      pedidosPendentes: 0,
      revisaoManual: false,
      revisaoMotivo: null,
    };
  }

  const pagamentoBase = pagamentoAtual as Record<string, unknown>;
  const statusAtual = String(pagamentoBase['status'] ?? '');
  const statusRecebido = String(comprovante['status'] ?? '');
  const statusAplicado = statusRecebido && podeAplicarStatus(statusAtual, statusRecebido)
    ? statusRecebido
    : statusAtual;

  const patch: Record<string, unknown> = {
    updated_at: new Date().toISOString(),
    status: statusAplicado,
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
  if (comprovante['paid_at'] && statusAplicado === 'pago') {
    patch['pago_em'] = comprovante['paid_at'];
  }
  if (comprovante['expira_em'] && statusAplicado !== 'pago') {
    patch['expira_em'] = comprovante['expira_em'];
  }
  if (comprovante['gateway_status']) {
    const dadosAnteriores =
      (pagamentoBase['gateway_dados'] as Record<string, unknown> | null) ?? {};
    patch['gateway_dados'] = {
      ...dadosAnteriores,
      status: comprovante['gateway_status'],
      payment_response: comprovante['payment_response'] ?? null,
    };
  }
  const resposta = comprovante['payment_response'] as Record<string, unknown> | undefined;
  if (comprovante['status'] === 'recusado') {
    patch['motivo_recusa'] =
      (resposta?.['message'] as string | undefined) ?? 'Pagamento recusado';
  }

  let valorDivergente = false;
  let valorRecebido = 0;
  let valorEsperado = 0;
  if (statusAplicado === 'pago') {
    valorRecebido = Number(comprovante['valor_centavos'] ?? 0);
    valorEsperado = Math.round(Number(pagamentoBase['valor'] ?? 0) * 100);
    if (valorRecebido > 0 && Math.abs(valorRecebido - valorEsperado) > 1) {
      valorDivergente = true;
      patch['revisao_manual'] = true;
      patch['revisao_motivo'] =
        `Valor recebido (${(valorRecebido / 100).toFixed(2)}) difere da cobrança ` +
        `(${(valorEsperado / 100).toFixed(2)}). Pedido não liberado.`;
    }
  }

  const { data: pagamentoAtualizado, error: erroPagamento } = await admin
    .from('pagamentos')
    .update(patch)
    .eq('id', pagamentoId)
    .select('id, metodo, status, user_id, valor')
    .maybeSingle();
  if (erroPagamento) {
    throw new Error(`Falha ao atualizar o pagamento: ${erroPagamento.message}`);
  }
  if (!pagamentoAtualizado) {
    return {
      pagamento: null,
      pedidosAtualizados: 0,
      pedidosPendentes: 0,
      revisaoManual: false,
      revisaoMotivo: null,
    };
  }

  const pagamento = pagamentoAtualizado as Record<string, unknown>;
  const metodo = String(pagamento['metodo'] ?? '');
  const status = String(pagamento['status'] ?? '');
  let pedidosAtualizados = 0;
  let pedidosPendentes = 0;
  let revisaoManual = valorDivergente;
  let revisaoMotivo: string | null = valorDivergente
    ? `Valor recebido (${(valorRecebido / 100).toFixed(2)}) difere da cobrança ` +
      `(${(valorEsperado / 100).toFixed(2)}). Pedido não liberado.`
    : null;

  const { data: pedidosBanco, error: erroPedidos } = await admin
    .from('pedidos')
    .select('id, status')
    .eq('pagamento_id', pagamentoId);

  if (erroPedidos) {
    revisaoManual = true;
    revisaoMotivo =
      `Pagamento confirmado, mas não foi possível carregar os pedidos: ${erroPedidos.message}`;
  } else {
    const pedidos = (pedidosBanco ?? []) as PedidoResumo[];

    if (status === 'pago' && pedidos.length === 0) {
      revisaoManual = true;
      revisaoMotivo =
        'Pagamento aprovado sem pedido vinculado. Verifique e estorne manualmente se necessário.';
    }

    if (status === 'pago' && !valorDivergente && pedidos.length > 0) {
      const pendentes = pedidos.filter((p) => p.status === 'pendente');
      pedidosPendentes = pendentes.length;

      for (const pedido of pendentes) {
        const { error: erroStatus } = await admin
          .from('pedidos')
          .update({
            status: 'pago',
            pagamento: rotuloMetodo(metodo),
            transacao_id: (comprovante['gateway_charge_id'] as string | undefined) ?? null,
            pagamento_detalhes: montarDetalhes(metodo, comprovante),
            pago_em: (comprovante['paid_at'] as string | undefined) ?? new Date().toISOString(),
          })
          .eq('id', pedido['id'])
          .eq('status', 'pendente');

        if (erroStatus) {
          revisaoManual = true;
          revisaoMotivo =
            `Pagamento aprovado, mas o pedido #${pedido['id']} não foi liberado: ${erroStatus.message}`;
          console.error('pedido não liberado após pagamento:', pedido['id'], erroStatus);
        } else {
          pedidosAtualizados++;
        }
      }

      const cancelados = pedidos.filter((p) => p.status === 'cancelado');
      if (cancelados.length > 0) {
        revisaoManual = true;
        revisaoMotivo = revisaoMotivo ??
          `Pagamento aprovado, mas ${cancelados.length} pedido(s) já estava(m) cancelado(s). ` +
          'Estorne ou reative manualmente.';
      }
    }

    if ((status === 'estornado' || status === 'cancelado') && pedidos.length > 0) {
      const cancelaveis = pedidos.filter((p) =>
        ['pendente', 'pago', 'em_preparo', 'pronto_para_entrega'].includes(p.status)
      );
      const emTransito = pedidos.filter((p) =>
        ['saiu_para_entrega', 'entregue'].includes(p.status)
      );

      for (const pedido of cancelaveis) {
        const { error: erroStatus } = await admin
          .from('pedidos')
          .update({ status: 'cancelado' })
          .eq('id', pedido['id'])
          .in('status', ['pendente', 'pago', 'em_preparo', 'pronto_para_entrega']);

        if (erroStatus) {
          revisaoManual = true;
          revisaoMotivo =
            `Estorno/cancelamento recebido, mas o pedido #${pedido['id']} não foi encerrado: ${erroStatus.message}`;
          console.error('pedido não encerrado após estorno:', pedido['id'], erroStatus);
        } else {
          pedidosAtualizados++;
        }
      }

      if (emTransito.length > 0) {
        revisaoManual = true;
        revisaoMotivo = revisaoMotivo ??
          `Estorno/cancelamento recebido com ${emTransito.length} pedido(s) em trânsito/entregue(s). ` +
          'Trate manualmente com o cliente e a transportadora.';
      }
    }

    if ((status === 'estornado' || status === 'cancelado') && pedidos.length === 0) {
      // Cobrança antiga substituída por outra forma de pagamento é cancelada
      // sem pedido vinculado; isso é esperado. Só alerta se havia dinheiro.
      if (statusAtual === 'pago') {
        revisaoManual = true;
        revisaoMotivo = revisaoMotivo ??
          'Estorno/cancelamento de pagamento pago sem pedido vinculado. Verifique manualmente.';
      }
    }
  }

  // Uma revisão não resolvida continua visível até o admin agir; um webhook
  // posterior não pode "apagar" o alerta silenciosamente.
  const revisaoAnterior =
    pagamentoBase['revisao_manual'] === true &&
    pagamentoBase['revisao_resolvida_em'] == null;
  const revisaoFinal = revisaoManual || revisaoAnterior;
  const motivoFinal = revisaoMotivo ??
    (revisaoAnterior ? (pagamentoBase['revisao_motivo'] as string | null) : null);

  await admin
    .from('pagamentos')
    .update({
      revisao_manual: revisaoFinal,
      revisao_motivo: motivoFinal,
      updated_at: new Date().toISOString(),
    })
    .eq('id', pagamentoId);

  const { data: pagamentoFinal } = await admin
    .from('pagamentos')
    .select('*')
    .eq('id', pagamentoId)
    .maybeSingle();

  return {
    pagamento: (pagamentoFinal as Record<string, unknown> | null) ?? pagamento,
    pedidosAtualizados,
    pedidosPendentes,
    revisaoManual: revisaoFinal,
    revisaoMotivo: motivoFinal,
  };
}

// Serializa webhook + consulta + conciliação por pagamento. Sem isso, duas
// entregas concorrentes podem aplicar o mesmo comprovante ao mesmo tempo.
export async function aplicarComprovante(
  admin: SupabaseClient,
  pagamentoId: number,
  comprovante: Record<string, unknown>,
): Promise<ResultadoAplicar> {
  const { data: lockOk, error: lockError } = await admin.rpc(
    'adquirir_processamento_pagamento',
    { p_pagamento_id: pagamentoId, p_ttl_segundos: 30 },
  );

  // Migration nova ainda não aplicada: mantém o comportamento antigo.
  if (lockError) {
    console.error('lock de processamento indisponível:', lockError.message);
    return await aplicarComprovanteInterno(admin, pagamentoId, comprovante);
  }

  if (lockOk !== true) {
    const { data: atual } = await admin
      .from('pagamentos')
      .select('*')
      .eq('id', pagamentoId)
      .maybeSingle();
    return {
      pagamento: (atual as Record<string, unknown> | null) ?? null,
      pedidosAtualizados: 0,
      pedidosPendentes: 0,
      revisaoManual: false,
      revisaoMotivo: null,
    };
  }

  try {
    return await aplicarComprovanteInterno(admin, pagamentoId, comprovante);
  } finally {
    const { error } = await admin.rpc('liberar_processamento_pagamento', {
      p_pagamento_id: pagamentoId,
    });
    if (error) {
      console.error('falha ao liberar processamento do pagamento:', error.message);
    }
  }
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
