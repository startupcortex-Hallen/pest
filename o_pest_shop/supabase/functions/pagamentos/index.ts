// Edge Function `pagamentos` — cria e consulta cobranças reais no PagBank
// (PIX, cartão de crédito, cartão de débito com 3DS e boleto) para os
// pedidos criados por `finalizar_checkout`.
//
// Ações (body.acao):
//   chave_publica — devolve a chave pública p/ criptografar cartão no navegador
//   sessao_3ds    — devolve uma sessão 3DS (obrigatória p/ cartão de débito)
//   criar         — cria a cobrança única do carrinho e vincula os pedidos
//   consultar     — status atualizado da cobrança (fallback do webhook)
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
import { aplicarComprovante, rotuloMetodo } from '../_shared/pagamentos_db.ts';
import { cpfValido, mascararCpf, somenteDigitos } from '../_shared/validacao.ts';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

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
      case 'consultar':
        return await consultar(user.id, body, cors);
      case 'criar':
      default:
        return await criar(user, body, cors);
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

async function criar(
  user: { id: string },
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

  const { data: pedidosBanco, error: erroPedidos } = await admin
    .from('pedidos')
    .select(
      'id, user_id, status, total, pagamento_id, tipo_entrega, endereco_entrega, cep_entrega, unidades(nome, endereco, bairro, cidade)',
    )
    .in('id', pedidoIds);
  if (erroPedidos) throw new Error('Não foi possível carregar os pedidos.');
  const pedidos = (pedidosBanco ?? []) as Json[];
  if (pedidos.length !== pedidoIds.length) throw new Error('Pedido não encontrado.');
  if (pedidos.some((p) => p['user_id'] !== user.id)) throw new Error('Pedido não pertence a você.');
  if (pedidos.some((p) => p['status'] !== 'pendente')) {
    throw new Error('Um dos pedidos não está mais aguardando pagamento.');
  }

  // Já existe cobrança ativa para estes pedidos?
  //   • MESMO método pendente → reaproveita (idempotência, evita 2ª cobrança)
  //   • método diferente ou expirada → cancela no gateway e cria nova
  const idsVinculados = [...new Set(pedidos.map((p) => p['pagamento_id']).filter(Boolean))];
  if (idsVinculados.length > 0) {
    const { data: ativos } = await admin
      .from('pagamentos')
      .select('*')
      .in('id', idsVinculados as number[])
      .eq('status', 'pendente');
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
    // Substitui a cobrança antiga: cancela no gateway (best-effort) e segue.
    for (const antigo of (ativos ?? []) as Json[]) {
      const chargeId = antigo['gateway_charge_id'] as string | undefined;
      if (chargeId) {
        try {
          await pagbankFetch(`/charges/${chargeId}/cancel`, { method: 'POST' });
        } catch (e) {
          console.warn('falha ao cancelar cobrança antiga:', e);
        }
      }
      await admin
        .from('pagamentos')
        .update({ status: 'cancelado', updated_at: new Date().toISOString() })
        .eq('id', antigo['id']);
    }
  }

  const { data: perfil } = await admin
    .from('perfis')
    .select('nome, nome_completo, email, cpf, telefone')
    .eq('id', user.id)
    .maybeSingle();
  const perfilDados = (perfil ?? {}) as Json;
  const nome = (perfilDados['nome_completo'] as string) || (perfilDados['nome'] as string) || 'Cliente';
  const email = (perfilDados['email'] as string) || user['email'] || '';
  const cpf = somenteDigitos(perfilDados['cpf']);
  const telefone = somenteDigitos(perfilDados['telefone']);

  if (!email) throw new Error('Complete seu email no perfil para pagar.');
  if (!cpf && metodo !== 'pix') {
    throw new Error('Cadastre seu CPF no perfil (Editar dados) para pagar com ' + rotuloMetodo(metodo) + '.');
  }
  if (cpf && !cpfValido(cpf)) {
    throw new Error('CPF cadastrado no perfil é inválido. Corrija em Editar dados.');
  }

  const cliente: Json = {
    name: nome,
    email,
  };
  if (cpf) cliente['tax_id'] = cpf;
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
    payment_method: await montarPagamento(metodo, body, perfilDados, cpf, pedidos),
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
    throw new Error('Cobrança criada no PagBank, mas falhou ao registrar no banco. Fale com o suporte.');
  }

  await admin
    .from('pedidos')
    .update({ pagamento_id: pagamento['id'] })
    .in('id', pedidoIds)
    .eq('status', 'pendente');

  // Cartão aprovado na hora: confirma os pedidos JÁ (o webhook também
  // chega, mas isso garante estoque/status imediatos para o cliente).
  if ((comprovante['status'] as string) === 'pago') {
    await aplicarComprovante(admin, pagamento['id'], {
      ...comprovante,
      status: 'pago',
      paid_at: comprovante['paid_at'] ?? agora.toISOString(),
    });
  }

  await salvarCartaoSePedido(admin, user.id, body, comprovante, order);

  return json({ pagamento }, 200, cors);
}

// ─── Montagem do payment_method por método ────────────────────

async function montarPagamento(
  metodo: string,
  body: Json,
  perfil: Json,
  cpf: string,
  pedidos: Json[],
): Promise<Json> {
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
  comprovante: Json,
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

  const dono = pagamento['user_id'] === userId;
  if (!dono) {
    const { data: perfil } = await admin
      .from('perfis')
      .select('funcao')
      .eq('id', userId)
      .maybeSingle();
    const funcao = perfil?.['funcao'];
    if (funcao !== 'admin' && funcao !== 'atendente') {
      throw new Error('Cobrança não encontrada.');
    }
  }

  // Sincroniza com o gateway enquanto pendente (webhook pode atrasar).
  const status = pagamento['status'] as string;
  if (
    dono &&
    (status === 'pendente' || status === 'em_analise') &&
    pagamento['gateway_order_id']
  ) {
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
        return json({ pagamento: atualizado ?? pagamento }, 200, cors);
      }
    } catch (e) {
      console.error('consultar sync falhou:', e);
    }
  }

  return json({ pagamento }, 200, cors);
}
