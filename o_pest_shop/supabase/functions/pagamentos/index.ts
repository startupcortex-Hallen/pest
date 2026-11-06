// Edge Function `pagamentos` — cria e consulta cobranças reais no PagBank
// (PIX, cartão de crédito, cartão de débito com 3DS e boleto) para os
// pedidos criados por `finalizar_checkout`.
//
// Ações (body.acao):
//   chave_publica — devolve a chave pública p/ criptografar cartão no navegador
//   sessao_3ds    — devolve uma sessão 3DS (obrigatória p/ cartão de débito)
//   criar         — cria a cobrança única do carrinho e vincula os pedidos
//   consultar     — status atualizado da cobrança (fallback do webhook)
//   cancelar      — cancela/estorna no gateway e encerra os pedidos vinculados
//
// O valor é SEMPRE recalculado aqui a partir do banco — o app nunca manda preço.

import { createClient } from 'npm:@supabase/supabase-js@2';
import { getCorsHeaders, json } from '../_shared/cors.ts';
import {
  extrairComprovante,
  IS_PROD,
  obterChavePublica,
  obterSessao3ds,
  pagbankFetch,
  PagBankError,
} from '../_shared/pagbank.ts';
import { aplicarComprovante } from '../_shared/pagamentos_db.ts';
import { cpfValido, mascararCpf, somenteDigitos } from '../_shared/validacao.ts';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const SIMULACAO = !IS_PROD &&
  (Deno.env.get('SIMULACAO_PAGAMENTO') ?? 'false').toLowerCase() === 'true';

// deno-lint-ignore no-explicit-any
type Json = Record<string, any>;

Deno.serve(async (req) => {
  const cors = getCorsHeaders(req);
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: cors });
  }
  try {
    const user = await autenticar(req);
    if (!user) return json({ erro: 'Faça login para continuar.' }, 401, cors);

    const body: Json = req.method === 'POST'
      ? await req.json().catch(() => ({}))
      : Object.fromEntries(new URL(req.url).searchParams.entries());
    const acao = (body['acao'] as string) ?? 'criar';

    switch (acao) {
      case 'chave_publica':
        return json({ public_key: await obterChavePublica() }, 200, cors);
      case 'sessao_3ds':
        return json({
          session: await obterSessao3ds(),
          env: IS_PROD ? 'PROD' : 'SANDBOX',
        }, 200, cors);
      case 'simulacao_disponivel':
        return json({ disponivel: SIMULACAO }, 200, cors);
      case 'simular':
        return await simular(user, body, cors);
      case 'consultar':
        return await consultar(user.id, body, cors);
      case 'cancelar':
        return await cancelar(user.id, body, cors);
      case 'criar':
      default:
        return await criarComLock(user, body, cors);
    }
  } catch (e) {
    if (e instanceof PagBankError) {
      return json({ erro: e.message, detalhes: e.detalhes }, 422, cors);
    }
    const mensagem = e instanceof Error ? e.message : 'Erro inesperado ao processar o pagamento.';
    console.error('pagamentos erro:', e);
    return json({ erro: mensagem }, 500, cors);
  }
});

async function autenticar(req: Request) {
  const authHeader = req.headers.get('Authorization') ?? '';
  if (!authHeader) return null;
  const client = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  const { data, error } = await client.auth.getUser();
  if (error) return null;
  return data.user;
}

function adminClient() {
  return createClient(SUPABASE_URL, SERVICE_ROLE, {
    auth: { persistSession: false },
  });
}

type ContextoUsuario = {
  funcao: string;
  unidadeId: number | null;
};

async function contextoUsuario(
  admin: ReturnType<typeof adminClient>,
  userId: string,
): Promise<ContextoUsuario> {
  const { data } = await admin
    .from('perfis')
    .select('funcao, unidade_id')
    .eq('id', userId)
    .maybeSingle();
  return {
    funcao: (data?.['funcao'] as string | undefined) ?? '',
    unidadeId: (data?.['unidade_id'] as number | null | undefined) ?? null,
  };
}

// Dono sempre pode; admin vê tudo; atendente/gestor só a própria loja.
async function acessoPagamento(
  admin: ReturnType<typeof adminClient>,
  userId: string,
  pagamento: Json,
): Promise<{ dono: boolean; funcao: string } | null> {
  if (pagamento['user_id'] === userId) {
    return { dono: true, funcao: 'cliente' };
  }

  const ctx = await contextoUsuario(admin, userId);
  if (ctx.funcao === 'admin') {
    return { dono: false, funcao: 'admin' };
  }
  if (ctx.funcao === 'atendente' || ctx.funcao === 'gestor') {
    const { data } = await admin
      .from('pedidos')
      .select('id')
      .eq('pagamento_id', pagamento['id'])
      .eq('unidade_id', ctx.unidadeId ?? -1)
      .limit(1);
    if (((data ?? []) as Json[]).length > 0) {
      return { dono: false, funcao: ctx.funcao };
    }
  }
  return null;
}

function nomeCompletoValido(nome: string): boolean {
  return nome.trim().split(/\s+/).filter((p) => p.length >= 2).length >= 2;
}

function ehPagamentoLocal(pagamento: Json): boolean {
  const dados = (pagamento['gateway_dados'] as Json | null) ?? null;
  return pagamento['gateway'] === 'simulacao' ||
    pagamento['gateway'] === 'manual' ||
    dados?.['simulado'] === true;
}

async function carregarPedidosValidos(
  admin: ReturnType<typeof adminClient>,
  user: { id: string; email?: string },
  pedidoIds: number[],
): Promise<{
  pedidos: Json[];
  perfilDados: Json;
  nome: string;
  email: string;
  cpf: string;
  telefone: string;
}> {
  const ids = [...new Set(pedidoIds)];
  const { data: pedidosBanco, error: erroPedidos } = await admin
    .from('pedidos')
    .select(
      'id, user_id, status, total, pagamento_id, tipo_entrega, endereco_entrega, cep_entrega, unidades(nome, endereco, bairro, cidade)',
    )
    .in('id', ids);
  if (erroPedidos) throw new Error('Não foi possível carregar os pedidos.');
  const pedidos = (pedidosBanco ?? []) as Json[];
  if (pedidos.length !== ids.length) throw new Error('Pedido não encontrado.');
  if (pedidos.some((p) => p['user_id'] !== user.id)) {
    throw new Error('Pedido não pertence a você.');
  }
  if (pedidos.some((p) => p['status'] !== 'pendente')) {
    throw new Error('Um dos pedidos não está mais aguardando pagamento.');
  }

  const { data: itensBanco, error: erroItens } = await admin
    .from('pedido_itens')
    .select('pedido_id, produto_id, quantidade, cor, preco_unitario, produtos(nome, cores, estoque)')
    .in('pedido_id', ids);
  if (erroItens) throw new Error('Não foi possível carregar os itens dos pedidos.');
  const itens = (itensBanco ?? []) as Json[];
  const porPedido = new Map<number, Json[]>();
  for (const item of itens) {
    const pedidoId = Number(item['pedido_id']);
    porPedido.set(pedidoId, [...(porPedido.get(pedidoId) ?? []), item]);
  }

  for (const pedido of pedidos) {
    const pedidoId = Number(pedido['id']);
    const itensPedido = porPedido.get(pedidoId) ?? [];
    if (itensPedido.length === 0) {
      throw new Error(`Pedido #${pedidoId} está sem itens. Refaça o pedido.`);
    }
    if (Number(pedido['total'] ?? 0) <= 0) {
      throw new Error(`Pedido #${pedidoId} está com total inválido.`);
    }
    if (String(pedido['tipo_entrega'] ?? 'retirada') === 'entrega') {
      const endereco = String(pedido['endereco_entrega'] ?? '').trim();
      const cep = somenteDigitos(pedido['cep_entrega']);
      if (endereco.length < 10 || cep.length !== 8) {
        throw new Error(`Pedido #${pedidoId}: informe o endereço completo e o CEP para entrega.`);
      }
    }

    for (const item of itensPedido) {
      const produto = (item['produtos'] as Json | null) ?? null;
      const nomeProduto = String(produto?.['nome'] ?? `produto ${item['produto_id']}`);
      if (!produto) throw new Error(`Pedido #${pedidoId}: produto não encontrado.`);
      const qtd = Number(item['quantidade'] ?? 0);
      const preco = Number(item['preco_unitario'] ?? 0);
      if (qtd <= 0) throw new Error(`Pedido #${pedidoId}: quantidade inválida em "${nomeProduto}".`);
      if (preco <= 0) throw new Error(`Pedido #${pedidoId}: preço inválido em "${nomeProduto}".`);

      const coresRaw = produto['cores'];
      const cores = Array.isArray(coresRaw)
        ? coresRaw.map((c) => String(c).trim()).filter((c) => c.length > 0)
        : typeof coresRaw === 'string' && coresRaw.trim().length > 0
          ? coresRaw.replace(/[{}]/g, '').split(',').map((c) => c.trim()).filter((c) => c.length > 0)
          : [];
      if (cores.length > 0) {
        const cor = String(item['cor'] ?? '').trim();
        if (!cor) {
          throw new Error(`Pedido #${pedidoId}: escolha a cor de "${nomeProduto}".`);
        }
        if (!cores.some((c) => c.toLowerCase() === cor.toLowerCase())) {
          throw new Error(`Pedido #${pedidoId}: a cor "${cor}" não existe para "${nomeProduto}".`);
        }
      }
    }
  }

  // O valor cobrado nunca confia no total gravado: o banco recalcula a partir
  // dos itens, desconto e frete e bloqueia divergências antes da cobrança.
  const { data: totalValidado, error: erroValidacao } = await admin.rpc(
    'validar_pedidos_pagamento',
    { p_pedido_ids: ids, p_user_id: user.id },
  );
  if (erroValidacao) {
    throw new Error(`Não foi possível validar o valor do pedido: ${erroValidacao.message}`);
  }
  const somaPedidos = pedidos.reduce((soma, p) => soma + Number(p['total'] ?? 0), 0);
  if (Math.abs(Number(totalValidado ?? 0) - somaPedidos) > 0.01) {
    throw new Error('O valor do pedido divergiu do carrinho. Refazer o checkout.');
  }

  const { data: perfil } = await admin
    .from('perfis')
    .select('nome, nome_completo, email, cpf, telefone')
    .eq('id', user.id)
    .maybeSingle();
  const perfilDados = (perfil ?? {}) as Json;
  const nome = ((perfilDados['nome_completo'] as string) || (perfilDados['nome'] as string) || '').trim();
  const email = (perfilDados['email'] as string) || user['email'] || '';
  const cpf = somenteDigitos(perfilDados['cpf']);
  const telefone = somenteDigitos(perfilDados['telefone']);

  if (!email) throw new Error('Complete seu email no perfil para pagar.');
  if (!nomeCompletoValido(nome)) {
    throw new Error('Cadastre seu nome completo no perfil (Editar dados) para pagar.');
  }
  if (!cpf) {
    throw new Error('Cadastre seu CPF no perfil (Editar dados) para pagar.');
  }
  if (!cpfValido(cpf)) {
    throw new Error('CPF cadastrado no perfil é inválido. Corrija em Editar dados.');
  }
  if (telefone.length < 10) {
    throw new Error('Cadastre seu telefone com DDD no perfil para pagar.');
  }

  return { pedidos, perfilDados, nome, email, cpf, telefone };
}

async function criarComLock(
  user: { id: string; email?: string },
  body: Json,
  cors: Record<string, string>,
) {
  const pedidoIds: number[] = [...new Set<number>(
    ((body['pedido_ids'] ?? []) as unknown[])
      .map((v) => Number(v))
      .filter((v) => Number.isFinite(v) && v > 0),
  )].sort((a, b) => a - b);
  const metodo = String(body['metodo'] ?? '');
  if (pedidoIds.length === 0) return await criarInterno(user, body, cors);

  // O lock é por (usuário + pedidos + método). Ele serializa duas chamadas
  // simultâneas do mesmo checkout e impede cobrança duplicada no PagBank.
  const chave = `cobranca:${user.id}:${pedidoIds.join('-')}:${metodo}`;
  const admin = adminClient();
  let lockResult = await admin.rpc(
    'adquirir_lock_cobranca',
    { p_chave: chave, p_ttl_segundos: 120 },
  );
  // Deploy da function antes da migration: cai na assinatura antiga para
  // não derrubar o checkout. A migration deve ser aplicada em seguida.
  if (lockResult.error) {
    lockResult = await admin.rpc('adquirir_lock_cobranca', { p_chave: chave });
  }
  const lockOk = lockResult.data;
  const lockError = lockResult.error;
  if (lockError) {
    console.error('falha ao adquirir lock de cobrança:', lockError);
    throw new Error('Não foi possível iniciar a cobrança. Tente novamente.');
  }
  if (lockOk !== true) {
    return json({
      erro: 'Já existe uma cobrança sendo criada para este pedido. Aguarde alguns segundos.',
    }, 409, cors);
  }

  try {
    return await criarInterno(user, body, cors);
  } finally {
    const { error } = await admin.rpc('liberar_lock_cobranca', { p_chave: chave });
    if (error) console.error('falha ao liberar lock de cobrança:', error);
  }
}

async function criarInterno(
  user: { id: string; email?: string },
  body: Json,
  cors: Record<string, string>,
) {
  const pedidoIds: number[] = (body['pedido_ids'] ?? [])
    .map((v: unknown) => Number(v))
    .filter((v: number) => Number.isFinite(v) && v > 0);
  const metodo = String(body['metodo'] ?? '');
  if (pedidoIds.length === 0) throw new Error('Nenhum pedido para pagar.');
  if (!['pix', 'credito', 'debito', 'boleto'].includes(metodo)) {
    throw new Error('Forma de pagamento inválida.');
  }

  const admin = adminClient();

  // Feature flags: permite desligar pagamentos ou forçar PIX sem deploy do app.
  const { data: configPagamento } = await admin
    .from('app_config')
    .select('valor')
    .eq('chave', 'pagamentos')
    .maybeSingle();
  const config = (configPagamento?.['valor'] as Json | null) ?? {};
  if (config['ativo'] === false) {
    return json({
      erro: 'Os pagamentos estão temporariamente indisponíveis. Tente novamente em instantes.',
    }, 503, cors);
  }
  if (config['pix_only'] === true && metodo !== 'pix') {
    return json({
      erro: 'No momento estamos aceitando apenas PIX. Escolha PIX para concluir.',
    }, 422, cors);
  }

  // ── Rate limit (proteção contra teste de cartão / abuso) ──
  const janela10 = new Date(Date.now() - 10 * 60_000).toISOString();
  const { count: tentativas } = await admin
    .from('pagamentos')
    .select('id', { count: 'exact', head: true })
    .eq('user_id', user.id)
    .gte('created_at', janela10);
  if ((tentativas ?? 0) >= 5) {
    return json({
      erro: 'Muitas tentativas de pagamento em pouco tempo. Aguarde alguns minutos e tente novamente.',
    }, 429, cors);
  }
  if (metodo === 'credito' || metodo === 'debito') {
    const janela15 = new Date(Date.now() - 15 * 60_000).toISOString();
    const { count: tentativasCartao } = await admin
      .from('pagamentos')
      .select('id', { count: 'exact', head: true })
      .eq('user_id', user.id)
      .in('metodo', ['credito', 'debito'])
      .gte('created_at', janela15);
    if ((tentativasCartao ?? 0) >= 3) {
      return json({
        erro: 'Muitas tentativas com cartão. Aguarde 15 minutos ou pague com PIX/boleto.',
      }, 429, cors);
    }
  }

  const { pedidos, perfilDados, nome, email, cpf, telefone } =
    await carregarPedidosValidos(admin, user, pedidoIds);

  // Já existe cobrança ativa para estes pedidos?
  //   • MESMO método pendente → reaproveita (idempotência, evita 2ª cobrança)
  //   • método diferente ou expirada → cancela no gateway e cria nova
  const idsVinculados = [...new Set(pedidos.map((p) => p['pagamento_id']).filter(Boolean))];
  if (idsVinculados.length > 0) {
    const { data: ativos } = await admin
      .from('pagamentos')
      .select('*')
      .in('id', idsVinculados as number[])
      .in('status', ['pendente', 'em_analise']);
    const ativo = (ativos ?? []).find((a: Json) => {
      const exp = a['expira_em'] ? new Date(a['expira_em'] as string).getTime() : Infinity;
      return exp > Date.now();
    }) as Json | undefined;
    const cobreTodos = ativo &&
      idsVinculados.length === 1 &&
      pedidos.every((p) => p['pagamento_id'] === ativo['id']);
    if (cobreTodos && ativo!['metodo'] === metodo) {
      return json({ pagamento: ativo, reutilizado: true }, 200, cors);
    }
    // Substitui a cobrança antiga. Se o gateway não confirmar o cancelamento,
    // NÃO cria outra cobrança (evita cliente pagar duas vezes).
    for (const antigo of (ativos ?? []) as Json[]) {
      const chargeId = antigo['gateway_charge_id'] as string | undefined;
      if (chargeId) {
        try {
          await pagbankFetch(`/charges/${chargeId}/cancel`, { method: 'POST' });
        } catch (e) {
          // 404 = já não existe/foi cancelada no gateway; segue para a nova.
          if (e instanceof PagBankError && e.status === 404) {
            console.warn('cobrança antiga já não existe no PagBank:', chargeId);
          } else {
            console.error('falha ao cancelar cobrança antiga:', e);
            throw new Error(
              'Não foi possível cancelar a cobrança anterior no PagBank. ' +
              'Aguarde alguns minutos e tente novamente.',
            );
          }
        }
      }
      await admin
        .from('pagamentos')
        .update({ status: 'cancelado', updated_at: new Date().toISOString() })
        .eq('id', antigo['id']);
    }
  }

  const cliente: Json = {
    name: nome,
    email,
    tax_id: cpf,
  };
  if (telefone.length >= 10) {
    cliente['phones'] = [
      {
        country: '55',
        area: telefone.substring(0, 2),
        number: telefone.substring(2),
        type: 'MOBILE',
      },
    ];
  }

  const itens = pedidos.map((p: Json) => ({
    reference_id: `pedido-${p['id']}`,
    name: `Pedido #${p['id']} · ${(p['unidades'] as Json | null)?.['nome'] ?? 'Loja'}`,
    quantity: 1,
    unit_amount: Math.round(Number(p['total'] ?? 0) * 100),
  }));
  const totalCentavos = itens.reduce((s, i) => s + i['unit_amount'], 0);
  if (totalCentavos < 100) throw new Error('Valor mínimo de R$ 1,00 por pagamento.');

  const charge: Json = {
    reference_id: `checkout-${pedidoIds.join('-')}-${Date.now()}`,
    description: `Pedido O Pest (${pedidos.length} ${pedidos.length === 1 ? 'loja' : 'lojas'})`,
    amount: { value: totalCentavos, currency: 'BRL' },
    payment_method: montarPagamento(metodo, body, perfilDados, cpf, pedidos),
  };

  const orderPayload: Json = {
    reference_id: charge['reference_id'],
    customer: cliente,
    items: itens,
    charges: [charge],
  };

  const webhookUrl = `${SUPABASE_URL}/functions/v1/pagamentos-webhook`;
  orderPayload['notification_urls'] = [webhookUrl];

  const order = await pagbankFetch('/orders', {
    method: 'POST',
    body: JSON.stringify(orderPayload),
  });

  const { comprovante } = extrairComprovante(order);

  // Boleto fica "aguardando" até compensar; cartão pode voltar recusado.
  if (comprovante['status'] === 'recusado') {
    comprovante['motivo_recusa'] =
      ((comprovante['payment_response'] as Json | undefined)?.['message'] as string) ??
      'Pagamento recusado pela operadora.';
  }

  const agora = new Date();
  const expira = metodo === 'pix'
    ? new Date(agora.getTime() + 30 * 60_000).toISOString()
    : metodo === 'boleto'
      ? new Date(agora.getTime() + 3 * 24 * 60 * 60_000).toISOString()
      : (comprovante['expira_em'] as string | undefined) ?? null;

  const row: Json = {
    user_id: user.id,
    gateway: 'pagbank',
    metodo,
    valor: totalCentavos / 100,
    status: comprovante['status'] ?? 'pendente',
    parcelas: metodo === 'credito' ? Math.max(1, Number(body['parcelas'] ?? 1)) : 1,
    expira_em: expira,
    created_at: agora.toISOString(),
    updated_at: agora.toISOString(),
  };
  for (const campo of [
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
    'motivo_recusa',
  ] as const) {
    if (comprovante[campo]) row[campo] = comprovante[campo];
  }
  if (comprovante['gateway_status']) {
    row['gateway_dados'] = {
      status: comprovante['gateway_status'],
      payment_response: comprovante['payment_response'] ?? null,
    };
  }

  const { data: pagamento, error: erroInsert } = await admin
    .from('pagamentos')
    .insert(row)
    .select('*')
    .single();
  if (erroInsert || !pagamento) {
    // A cobrança já existe no gateway; se o banco falhar, cancela para não
    // deixar dinheiro preso sem pedido local (compensação explícita).
    const chargeId = ((order['charges'] as Json[] | undefined)?.[0]?.['id']) as
      | string
      | undefined;
    if (chargeId) {
      try {
        await cancelarCobrancaGateway({
          gateway_charge_id: chargeId,
          status: comprovante['status'] ?? 'pendente',
          valor: totalCentavos / 100,
        });
      } catch (cancelError) {
        console.error('cobrança órfã: falha ao cancelar no PagBank', cancelError);
      }
    }
    console.error('falha ao registrar pagamento no banco:', erroInsert);
    throw new Error(
      'A cobrança foi criada no PagBank, mas não foi possível registrar no banco. ' +
      'Se o pagamento aparecer, a equipe fará o estorno.',
    );
  }

  const { error: erroVinculo } = await admin
    .from('pedidos')
    .update({ pagamento_id: pagamento['id'] })
    .in('id', pedidoIds)
    .eq('status', 'pendente');
  if (erroVinculo) {
    // A cobrança existe no gateway mas não foi vinculada: tenta cancelar para
    // não deixar dinheiro preso sem pedido correspondente.
    let gatewayCancelado = true;
    try {
      await cancelarCobrancaGateway(pagamento);
    } catch (e) {
      gatewayCancelado = false;
      console.error('falha ao cancelar cobrança sem vínculo:', e);
    }
    await admin
      .from('pagamentos')
      .update({
        status: gatewayCancelado ? 'cancelado' : (pagamento['status'] as string | undefined) ?? 'pendente',
        revisao_manual: !gatewayCancelado,
        revisao_motivo: gatewayCancelado
          ? null
          : 'Cobrança criada, mas não vinculada aos pedidos e sem confirmação de cancelamento no gateway.',
        motivo_recusa: 'Falha ao vincular a cobrança aos pedidos.',
        updated_at: new Date().toISOString(),
      })
      .eq('id', pagamento['id']);
    throw new Error(
      gatewayCancelado
        ? 'Não foi possível vincular o pagamento aos pedidos. A cobrança foi cancelada.'
        : 'Cobrança criada, mas não vinculada aos pedidos. A equipe precisa revisar/estornar no PagBank.',
    );
  }

  // Cartão aprovado na hora: confirma os pedidos JÁ (o webhook também
  // chega, mas isso garante estoque/status imediatos para o cliente).
  if ((comprovante['status'] as string) === 'pago') {
    await aplicarComprovante(admin, pagamento['id'], {
      ...comprovante,
      status: 'pago',
      paid_at: comprovante['paid_at'] ?? agora.toISOString(),
    });
  }

  await salvarCartaoSePedido(admin, user.id, body, order);

  const { data: pagamentoFinal } = await admin
    .from('pagamentos')
    .select('*')
    .eq('id', pagamento['id'])
    .maybeSingle();

  return json({ pagamento: pagamentoFinal ?? pagamento }, 200, cors);
}

async function simular(
  user: { id: string; email?: string },
  body: Json,
  cors: Record<string, string>,
) {
  if (!SIMULACAO) {
    throw new Error(
      'Pagamento simulado desativado. Configure o secret SIMULACAO_PAGAMENTO=true para testar.',
    );
  }

  const pedidoIds: number[] = [...new Set<number>(
    ((body['pedido_ids'] ?? []) as unknown[])
      .map((v) => Number(v))
      .filter((v) => Number.isFinite(v) && v > 0),
  )];
  const metodo = String(body['metodo'] ?? '');
  if (pedidoIds.length === 0) throw new Error('Nenhum pedido para pagar.');
  if (!['pix', 'credito', 'debito', 'boleto'].includes(metodo)) {
    throw new Error('Forma de pagamento inválida.');
  }

  const admin = adminClient();
  const { pedidos, nome, email, cpf, telefone } =
    await carregarPedidosValidos(admin, user, pedidoIds);

  const idsVinculados = [...new Set(pedidos.map((p) => p['pagamento_id']).filter(Boolean))];
  if (idsVinculados.length > 0) {
    const { data: ativos } = await admin
      .from('pagamentos')
      .select('id, status')
      .in('id', idsVinculados as number[])
      .in('status', ['pendente', 'em_analise']);
    if ((ativos ?? []).length > 0) {
      throw new Error('Já existe uma cobrança ativa para este pedido. Cancele ou aguarde expirar.');
    }
  }

  const total = pedidos.reduce((soma, p) => soma + Number(p['total'] ?? 0), 0);
  if (total < 1) throw new Error('Valor mínimo de R$ 1,00 por pagamento.');

  const agora = new Date().toISOString();
  const sufixo = `${Date.now()}-${pedidoIds.join('-')}`;
  const chargeId = `SIM-${metodo.toUpperCase()}-${sufixo}`;
  const cartaoInfo = (body['cartao'] as Json | undefined) ?? {};
  const cartaoBandeira = String(cartaoInfo['bandeira'] ?? 'SIMULADO').slice(0, 30);
  const cartaoLast4 = somenteDigitos(cartaoInfo['last4']).slice(-4) || '4242';
  const cartaoTitular = String(cartaoInfo['holder_nome'] ?? nome).slice(0, 80);

  const row: Json = {
    user_id: user.id,
    gateway: 'simulacao',
    metodo,
    valor: total,
    status: 'pago',
    parcelas: metodo === 'credito' ? Math.min(12, Math.max(1, Number(body['parcelas'] ?? 1))) : 1,
    pago_em: agora,
    expira_em: agora,
    gateway_order_id: null,
    gateway_charge_id: chargeId,
    gateway_dados: {
      simulado: true,
      ambiente: 'simulacao',
      cliente: { nome, email, cpf: mascararCpf(cpf), telefone },
    },
  };

  if (metodo === 'pix') {
    row['pix_copia_cola'] = `SIMULACAO-PIX-${sufixo}`;
    row['pix_e2e_id'] = `E2E-SIM-${sufixo}`;
  } else if (metodo === 'boleto') {
    row['boleto_linha_digitavel'] = `SIMULACAO-BOLETO-${sufixo}`;
    row['boleto_codigo_barras'] = `SIM${sufixo}`;
    row['boleto_vencimento'] = new Date(Date.now() + 3 * 24 * 60 * 60_000)
      .toISOString()
      .slice(0, 10);
  } else {
    row['cartao_bandeira'] = cartaoBandeira;
    row['cartao_last4'] = cartaoLast4;
    row['cartao_autorizacao'] = `AUTH-SIM-${sufixo}`;
    row['cartao_nsu'] = `NSU-SIM-${sufixo}`;
    (row['gateway_dados'] as Json)['cartao'] = {
      bandeira: cartaoBandeira,
      last4: cartaoLast4,
      titular: cartaoTitular,
      simulado: true,
    };
  }

  const { data: pagamento, error: erroInsert } = await admin
    .from('pagamentos')
    .insert(row)
    .select('*')
    .single();
  if (erroInsert || !pagamento) {
    throw new Error('Falha ao registrar o pagamento simulado.');
  }

  const { error: erroVinculo } = await admin
    .from('pedidos')
    .update({ pagamento_id: pagamento['id'] })
    .in('id', pedidoIds)
    .eq('status', 'pendente');
  if (erroVinculo) {
    await admin
      .from('pagamentos')
      .update({
        status: 'cancelado',
        motivo_recusa: 'Falha ao vincular o pagamento simulado aos pedidos.',
        updated_at: new Date().toISOString(),
      })
      .eq('id', pagamento['id']);
    throw new Error('Não foi possível vincular o pagamento simulado aos pedidos.');
  }

  const comprovante: Json = {
    status: 'pago',
    paid_at: agora,
    gateway_charge_id: chargeId,
  };
  if (metodo === 'pix') {
    comprovante['pix_copia_cola'] = row['pix_copia_cola'];
    comprovante['pix_e2e_id'] = row['pix_e2e_id'];
  } else if (metodo === 'boleto') {
    comprovante['boleto_linha_digitavel'] = row['boleto_linha_digitavel'];
    comprovante['boleto_codigo_barras'] = row['boleto_codigo_barras'];
    comprovante['boleto_vencimento'] = row['boleto_vencimento'];
  } else {
    comprovante['cartao_bandeira'] = row['cartao_bandeira'];
    comprovante['cartao_last4'] = row['cartao_last4'];
    comprovante['cartao_autorizacao'] = row['cartao_autorizacao'];
    comprovante['cartao_nsu'] = row['cartao_nsu'];
  }

  await aplicarComprovante(admin, pagamento['id'], comprovante);

  const { data: pagamentoFinal } = await admin
    .from('pagamentos')
    .select('*')
    .eq('id', pagamento['id'])
    .maybeSingle();

  return json({
    pagamento: pagamentoFinal ?? pagamento,
    simulado: true,
  }, 200, cors);
}

async function cancelarCobrancaGateway(pagamento: Json): Promise<void> {
  const chargeId = pagamento['gateway_charge_id'] as string | undefined;
  if (!chargeId) return;
  const pago = String(pagamento['status'] ?? '') === 'pago';
  const centavos = Math.round(Number(pagamento['valor'] ?? 0) * 100);
  await pagbankFetch(`/charges/${chargeId}/cancel`, {
    method: 'POST',
    ...(pago && centavos > 0
      ? {
        body: JSON.stringify({ amount: { value: centavos } }),
        headers: { 'Content-Type': 'application/json' },
      }
      : {}),
  });
}

// ─── Cancelamento / estorno ───────────────────────────────────

async function cancelar(userId: string, body: Json, cors: Record<string, string>) {
  const pagamentoId = Number(body['pagamento_id'] ?? 0);
  if (!Number.isFinite(pagamentoId) || pagamentoId <= 0) {
    throw new Error('Cobrança não informada.');
  }

  const admin = adminClient();
  const { data: pagamento, error } = await admin
    .from('pagamentos')
    .select('*')
    .eq('id', pagamentoId)
    .maybeSingle();
  if (error || !pagamento) throw new Error('Cobrança não encontrada.');

  const acesso = await acessoPagamento(admin, userId, pagamento as Json);
  if (!acesso) throw new Error('Cobrança não encontrada.');
  const dono = acesso.dono;
  const funcao = acesso.funcao;

  const status = String(pagamento['status'] ?? '');
  const simulado = ehPagamentoLocal(pagamento);
  if (status === 'estornado' || status === 'cancelado' || status === 'expirado') {
    return json({ pagamento, jaEncerrado: true }, 200, cors);
  }

  const { data: pedidosBanco } = await admin
    .from('pedidos')
    .select('id, status')
    .eq('pagamento_id', pagamentoId);
  const pedidos = (pedidosBanco ?? []) as Array<{ id: number; status: string }>;
  const statusPermitidos = dono
    ? ['pendente', 'pago', 'em_preparo', 'cancelado']
    : ['pendente', 'pago', 'em_preparo', 'pronto_para_entrega', 'cancelado'];
  const bloqueados = pedidos.filter((p) => !statusPermitidos.includes(p.status));
  if (bloqueados.length > 0) {
    const pedido = bloqueados[0];
    throw new Error(
      `O pedido #${pedido.id} está em "${pedido.status}" e não pode ser cancelado ` +
      'automaticamente. Finalize o fluxo de entrega ou faça o estorno manual no PagBank.',
    );
  }
  const statusParaCancelar = dono
    ? ['pendente', 'pago', 'em_preparo']
    : ['pendente', 'pago', 'em_preparo', 'pronto_para_entrega'];

  // Recusado não tem valor capturado: encerra só no banco.
  // Simulado não chama o PagBank: o estorno é local, com a mesma trilha.
  if (!simulado && status !== 'recusado') {
    const chargeId = pagamento['gateway_charge_id'] as string | undefined;
    if (!chargeId && status === 'pago') {
      throw new Error(
        'Pagamento marcado como pago, mas sem ID da cobrança no gateway. ' +
        'Estorne manualmente pelo painel do PagBank e sinalize o suporte.',
      );
    }
    if (chargeId) {
      try {
        await cancelarCobrancaGateway(pagamento as Json);
      } catch (e) {
        // Cobrança pendente que já não existe no gateway pode ser encerrada
        // localmente. Para pago, 404 é erro: pode haver dinheiro sem cobrança.
        if (status !== 'pago' && e instanceof PagBankError && e.status === 404) {
          console.warn('cobrança pendente já não existe no PagBank:', chargeId);
        } else {
          const detalhe = e instanceof Error ? e.message : String(e);
          console.error('falha ao cancelar/estornar no PagBank:', e);
          throw new Error(
            `Não foi possível ${status === 'pago' ? 'estornar' : 'cancelar'} no PagBank: ${detalhe}. ` +
            'Nenhum pedido foi alterado.',
          );
        }
      }
    }
  }

  const novoStatus = status === 'pago' ? 'estornado' : 'cancelado';
  const agora = new Date().toISOString();
  const gatewayDados = {
    ...((pagamento['gateway_dados'] as Json | null) ?? {}),
    cancelamento: {
      em: agora,
      por: userId,
      funcao: dono ? 'cliente' : funcao,
      estorno: status === 'pago',
    },
  };
  const patch: Json = {
    status: novoStatus,
    updated_at: agora,
    gateway_dados: gatewayDados,
  };
  if (status === 'pago') patch['estornado_em'] = agora;

  const { data: atualizado, error: erroPagamento } = await admin
    .from('pagamentos')
    .update(patch)
    .eq('id', pagamentoId)
    .select('*')
    .maybeSingle();
  if (erroPagamento || !atualizado) {
    throw new Error('Falha ao registrar o cancelamento no banco.');
  }

  // Encerra os pedidos cobertos por esta cobrança. O trigger do banco
  // devolve o estoque e restaura o cupom (uma única vez por checkout).
  const { data: pedidosAfetados, error: erroPedidos } = await admin
    .from('pedidos')
    .update({ status: 'cancelado' })
    .eq('pagamento_id', pagamentoId)
    .in('status', statusParaCancelar)
    .select('id, status');
  if (erroPedidos) {
    console.error('cancelamento no gateway ok, mas pedidos não encerrados:', erroPedidos);
    await admin
      .from('pagamentos')
      .update({
        revisao_manual: true,
        revisao_motivo: 'Cancelamento/estorno feito no gateway, mas os pedidos precisam de revisão manual.',
        updated_at: new Date().toISOString(),
      })
      .eq('id', pagamentoId);
    throw new Error(
      'O estorno foi processado, mas os pedidos não puderam ser encerrados. ' +
      'A equipe foi sinalizada para revisar.',
    );
  }

  return json({
    pagamento: atualizado,
    estornado: status === 'pago',
    pedidos_encerrados: (pedidosAfetados ?? []).length,
  }, 200, cors);
}

// ─── Montagem do payment_method por método ────────────────────

function montarPagamento(
  metodo: string,
  body: Json,
  perfil: Json,
  cpf: string,
  pedidos: Json[],
): Json {
  if (metodo === 'pix') {
    const expiracao = new Date(Date.now() + 30 * 60_000).toISOString();
    return { type: 'PIX', pix: { expiration_date: expiracao } };
  }

  if (metodo === 'boleto') {
    const vencimento = new Date(Date.now() + 3 * 24 * 60 * 60_000);
    const dueDate = vencimento.toISOString().substring(0, 10);
    const endereco = enderecoDoPedido(pedidos[0]);
    return {
      type: 'BOLETO',
      boleto: {
        template: 'proposta',
        due_date: dueDate,
        holder: {
          name: (body['holder_nome'] as string) || (perfil['nome_completo'] as string) || (perfil['nome'] as string) || 'Cliente',
          tax_id: cpf,
          email: (perfil['email'] as string) ?? '',
          address: endereco,
        },
      },
    };
  }

  // Cartão (crédito/débito) — dados do cartão SEMPRE chegam criptografados
  // (criptografia feita no navegador com a chave pública do PagBank) ou como
  // token de um cartão já salvo no gateway. Nada de PAN em texto puro.
  const cartao = (body['cartao'] as Json | undefined) ?? {};
  const holder = {
    name: (cartao['holder_nome'] as string) || (body['holder_nome'] as string) ||
      (perfil['nome_completo'] as string) || (perfil['nome'] as string) || 'Cliente',
    tax_id: somenteDigitos(cartao['holder_cpf']) || cpf,
  };
  if (!holder.tax_id) {
    throw new Error('Informe o CPF do titular do cartão.');
  }
  if (!cpfValido(holder.tax_id)) {
    throw new Error('CPF do titular do cartão é inválido.');
  }

  const card: Json = {};
  if (cartao['card_id']) {
    card['id'] = cartao['card_id'];
    if (cartao['security_code']) card['security_code'] = String(cartao['security_code']);
  } else if (cartao['encrypted']) {
    card['encrypted'] = cartao['encrypted'];
    if (metodo === 'credito') card['store'] = cartao['salvar'] === true;
  } else {
    throw new Error('Dados do cartão não recebidos.');
  }

  if (metodo === 'debito') {
    const tresdsId = body['tresds_id'] as string | undefined;
    if (!tresdsId) {
      throw new Error('Autenticação 3DS do débito não concluída. Tente novamente.');
    }
    return {
      type: 'DEBIT_CARD',
      installments: 1,
      card,
      holder,
      authentication_method: { type: 'THREEDS', id: tresdsId },
    };
  }

  const parcelas = Math.min(12, Math.max(1, Number(body['parcelas'] ?? 1)));
  const tresdsId = body['tresds_id'] as string | undefined;
  if (!tresdsId) {
    throw new Error('Autenticação 3DS não concluída. Tente novamente.');
  }
  return {
    type: 'CREDIT_CARD',
    installments: parcelas,
    capture: true,
    soft_descriptor: 'OPEST SHOP',
    card,
    holder,
    authentication_method: { type: 'THREEDS', id: tresdsId },
  };
}

// Monta o endereço do sacado (boleto) a partir do pedido:
// usa o endereço de entrega quando existir (formato "Rua, Nº, ..., Cidade - UF, CEP x")
// e cai para o endereço da unidade quando for retirada.
function enderecoDoPedido(pedido: Json | undefined): Json {
  const padrao: Json = {
    street: 'Não informado',
    number: '0',
    locality: 'Centro',
    city: 'São Paulo',
    region: 'SP',
    region_code: 'SP',
    country: 'Brasil',
    postal_code: '01001000',
  };
  if (!pedido) return padrao;

  const unidade = (pedido['unidades'] as Json | null) ?? null;
  const entrega = (pedido['endereco_entrega'] as string | undefined)?.trim() ?? '';
  const cepPedido = somenteDigitos(pedido['cep_entrega']);

  let rua = '';
  let numero = '';
  let bairro = '';
  let cidade = '';
  let uf = '';

  if (entrega) {
    const semCep = entrega.replace(/,\s*CEP\s*\d{0,8}\s*$/i, '');
    const partes = semCep.split(',').map((p) => p.trim()).filter((p) => p.length > 0);
    if (partes.length > 0) {
      rua = partes[0];
      if (partes.length > 1 && /\d/.test(partes[1])) numero = partes[1];
      const idxCidade = partes.findIndex((p) => /\s-\s[A-Za-z]{2}$/.test(p));
      const parteCidade = idxCidade >= 0 ? partes[idxCidade] : partes[partes.length - 1];
      if (/^.+ - [A-Za-z]{2}$/.test(parteCidade)) {
        const [cid, estado] = parteCidade.split(' - ');
        cidade = cid.trim();
        uf = estado.trim().toUpperCase();
      }
      const fimBairro = idxCidade >= 0 ? idxCidade : partes.length - 1;
      bairro = partes[fimBairro - 1] ?? '';
      if (bairro === numero || bairro === rua) bairro = '';
    }
  }

  if (!rua && unidade) {
    rua = (unidade['endereco'] as string | undefined) ?? '';
    bairro = bairro || ((unidade['bairro'] as string | undefined) ?? '');
    cidade = cidade || ((unidade['cidade'] as string | undefined) ?? '');
  }

  return {
    street: rua || padrao['street'],
    number: numero || padrao['number'],
    locality: bairro || padrao['locality'],
    city: cidade || padrao['city'],
    region: uf || padrao['region'],
    region_code: uf || padrao['region_code'],
    country: 'Brasil',
    postal_code: cepPedido.length === 8 ? cepPedido : (cepPedido || padrao['postal_code']),
  };
}

async function salvarCartaoSePedido(
  admin: ReturnType<typeof adminClient>,
  userId: string,
  body: Json,
  order: Json,
) {
  const cartao = (body['cartao'] as Json | undefined) ?? {};
  if (cartao['salvar'] !== true) return;
  const charges = (order['charges'] as Json[] | undefined) ?? [];
  const cardResp = ((charges[0]?.['payment_method'] as Json | undefined)?.['card'] ?? {}) as Json;
  const cardId = cardResp['id'] as string | undefined;
  if (!cardId) return; // só cartões tokenizados podem ser salvos (crédito)
  const last4 = (cardResp['last_digits'] as string | undefined) ?? (cartao['last4'] as string | undefined) ?? '';
  const bandeira = (cardResp['brand'] as string | undefined) ?? (cartao['bandeira'] as string | undefined) ?? '';
  const mes = parseInt(String(cardResp['exp_month'] ?? '1')) || 1;
  const ano = parseInt(String(cardResp['exp_year'] ?? '2030')) || 2030;
  await admin.from('cartoes_usuario').insert({
    user_id: userId,
    apelido: `${bandeira || 'Cartão'} •••• ${last4}`,
    numero_mascarado: `•••• •••• •••• ${last4}`,
    bandeira: bandeira || 'cartao',
    titular: (cartao['holder_nome'] as string) ?? '',
    mes_validade: mes,
    ano_validade: ano,
    padrao: false,
    gateway_card_id: cardId,
    // LGPD: guardamos apenas o CPF mascarado; a cobrança usa o CPF de `perfis`.
    holder_cpf: cartao['holder_cpf'] ? mascararCpf(String(cartao['holder_cpf'])) : null,
  });
}

// ─── Consulta (fallback do webhook / polling da tela) ──────────

async function consultar(
  userId: string,
  body: Json,
  cors: Record<string, string>,
) {
  const pagamentoId = Number(body['pagamento_id'] ?? 0);
  if (!pagamentoId) throw new Error('Cobrança não informada.');
  const admin = adminClient();

  const { data: pagamento } = await admin
    .from('pagamentos')
    .select('*')
    .eq('id', pagamentoId)
    .maybeSingle();
  if (!pagamento) throw new Error('Cobrança não encontrada.');

  const acesso = await acessoPagamento(admin, userId, pagamento as Json);
  if (!acesso) throw new Error('Cobrança não encontrada.');

  // Sincroniza com o gateway enquanto pendente (webhook pode atrasar).
  // O app lê o status direto da tabela com frequência; aqui só vamos ao
  // PagBank no máximo a cada 30s por pagamento.
  const status = pagamento['status'] as string;
  if (
    (status === 'pendente' || status === 'em_analise') &&
    pagamento['gateway_order_id'] &&
    !ehPagamentoLocal(pagamento)
  ) {
    const dados = (pagamento['gateway_dados'] as Json | null) ?? {};
    const ultima = dados['ultima_consulta']
      ? Date.parse(String(dados['ultima_consulta']))
      : 0;
    if (Number.isFinite(ultima) && Date.now() - ultima < 30_000) {
      return json({ pagamento }, 200, cors);
    }

    try {
      const order = await pagbankFetch(`/orders/${pagamento['gateway_order_id']}`);
      const { comprovante } = extrairComprovante(order);
      if (comprovante['status'] && comprovante['status'] !== status) {
        await aplicarComprovante(admin, pagamentoId, comprovante);
        const { data: atualizado } = await admin
          .from('pagamentos')
          .select('*')
          .eq('id', pagamentoId)
          .maybeSingle();
        await registrarConsulta(admin, pagamentoId);
        return json({ pagamento: atualizado ?? pagamento }, 200, cors);
      }
      await registrarConsulta(admin, pagamentoId);
    } catch (e) {
      console.error('consultar sync falhou:', e);
    }
  }

  return json({ pagamento }, 200, cors);
}

async function registrarConsulta(
  admin: ReturnType<typeof adminClient>,
  pagamentoId: number,
) {
  const { error } = await admin.rpc('registrar_consulta_pagamento', {
    p_pagamento_id: pagamentoId,
  });
  if (error) {
    console.error('falha ao registrar consulta do pagamento:', error.message);
  }
}
