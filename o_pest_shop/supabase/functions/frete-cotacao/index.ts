import { createClient } from 'npm:@supabase/supabase-js@2';
import md5 from 'npm:blueimp-md5@2.19.0';
import { getCorsHeaders, json } from '../_shared/cors.ts';
import {
  CORREIOS_SIMULACAO,
  CorreiosError,
  cotarCorreios,
} from '../_shared/correios.ts';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

type ProdutoCarrinho = {
  quantidade: number;
  produtos: {
    id: number;
    nome?: string;
    preco?: number;
    preco_promocional?: number;
    em_promocao?: boolean;
    peso_kg?: number;
    comprimento_cm?: number;
    largura_cm?: number;
    altura_cm?: number;
    unidade_id?: number;
    frete_gratis?: boolean;
  } | null;
};

type OpcaoFrete = {
  provider: 'correios' | 'melhor_envio';
  servico: string;
  servico_codigo?: string;
  transportadora: string;
  valor: number;
  prazo_dias: number;
};

function somenteDigitos(valor: unknown): string {
  return String(valor ?? '').replace(/\D/g, '');
}

function numero(valor: unknown, padrao = 0): number {
  const n = Number(valor);
  return Number.isFinite(n) ? n : padrao;
}

function arredondar2(valor: number): number {
  return Math.round(valor * 100) / 100;
}

async function cotarMelhorEnvio(
  cepOrigem: string,
  cepDestino: string,
  itens: Array<{
    id: number;
    quantidade: number;
    peso: number;
    comprimento: number;
    largura: number;
    altura: number;
    valor: number;
  }>,
): Promise<OpcaoFrete[]> {
  const token = Deno.env.get('MELHOR_ENVIO_TOKEN');
  if (!token) {
    throw new Error('MELHOR_ENVIO_TOKEN não configurado nas Edge Functions.');
  }

  const sandbox =
    (Deno.env.get('MELHOR_ENVIO_ENV') ?? 'production') === 'sandbox';
  const base = sandbox
    ? 'https://sandbox.melhorenvio.com.br'
    : 'https://melhorenvio.com.br';

  const resposta = await fetch(`${base}/api/v2/me/shipment/calculate`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': 'O Pest Shop (contato@opest.com.br)',
    },
    body: JSON.stringify({
      from: { postal_code: cepOrigem },
      to: { postal_code: cepDestino },
      products: itens.map((item) => ({
        id: String(item.id),
        width: Math.max(Math.round(item.largura), 11),
        height: Math.max(Math.round(item.altura), 2),
        length: Math.max(Math.round(item.comprimento), 16),
        weight: Math.max(item.peso, 0.3),
        insurance_value: Math.max(item.valor, 0),
        quantity: item.quantidade,
      })),
    }),
  });

  const texto = await resposta.text();
  if (!resposta.ok) {
    throw new Error(`Melhor Envio respondeu ${resposta.status}.`);
  }

  let dados: unknown;
  try {
    dados = JSON.parse(texto);
  } catch (_) {
    throw new Error('Melhor Envio retornou uma resposta inválida.');
  }
  if (!Array.isArray(dados)) {
    throw new Error('Melhor Envio não retornou opções de frete.');
  }

  const opcoes: OpcaoFrete[] = [];
  for (const bruto of dados) {
    if (!bruto || typeof bruto !== 'object') continue;
    const item = bruto as Record<string, unknown>;
    if (item.error) continue;
    const valor = numero(item.price);
    if (valor <= 0) continue;
    const empresa = item.company as Record<string, unknown> | undefined;
    opcoes.push({
      provider: 'melhor_envio',
      servico: String(item.name ?? item.id ?? 'Envio'),
      servico_codigo: String(item.id ?? ''),
      transportadora: String(empresa?.name ?? 'Melhor Envio'),
      valor,
      prazo_dias: numero(item.delivery_time),
    });
  }

  if (opcoes.length === 0) {
    throw new Error('Melhor Envio não retornou opção válida para este CEP.');
  }
  return opcoes;
}

Deno.serve(async (req) => {
  const cors = getCorsHeaders(req);
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') {
    return json({ error: 'Método não permitido.' }, 405, cors);
  }

  const authHeader = req.headers.get('Authorization') ?? '';
  const cliente = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: auth, error: authError } = await cliente.auth.getUser();
  if (authError || !auth.user) {
    return json({ error: 'Faça login para calcular o frete.' }, 401, cors);
  }

  const body = await req.json().catch(() => ({}));
  const unidadeId = numero(body.unidade_id);
  const cepDestino = somenteDigitos(body.cep_destino);
  if (!unidadeId || cepDestino.length !== 8) {
    return json(
      { error: 'Informe a loja e um CEP de destino válido.' },
      400,
      cors,
    );
  }

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
    auth: { persistSession: false },
  });

  const { data: unidade, error: unidadeError } = await admin
    .from('unidades')
    .select('id, nome, cep, frete_modo, frete_gratis_acima')
    .eq('id', unidadeId)
    .maybeSingle();
  if (unidadeError || !unidade) {
    return json({ error: 'Loja não encontrada.' }, 404, cors);
  }

  const modo = String(unidade.frete_modo ?? '');
  if (modo !== 'correios' && modo !== 'melhor_envio') {
    return json(
      { error: 'Esta loja não usa cotação por transportadora.' },
      422,
      cors,
    );
  }

  const cepOrigem = somenteDigitos(unidade.cep);
  if (cepOrigem.length !== 8) {
    return json(
      { error: 'A loja precisa ter um CEP de origem cadastrado.' },
      422,
      cors,
    );
  }

  const { data: carrinho, error: carrinhoError } = await admin
    .from('carrinho')
    .select(
      'quantidade, produtos(id, nome, preco, preco_promocional, em_promocao, peso_kg, comprimento_cm, largura_cm, altura_cm, unidade_id, frete_gratis)',
    )
    .eq('user_id', auth.user.id);

  if (carrinhoError) {
    return json({ error: 'Não foi possível ler o carrinho.' }, 500, cors);
  }

  const linhas = ((carrinho ?? []) as unknown as ProdutoCarrinho[]).filter(
    (linha) => linha.produtos?.unidade_id === unidadeId,
  );
  if (linhas.length === 0) {
    return json({ error: 'Carrinho vazio para esta loja.' }, 422, cors);
  }

  let peso = 0;
  let comprimento = 0;
  let largura = 0;
  let altura = 0;
  let valorDeclarado = 0;
  const itens = linhas.map((linha) => {
    const produto = linha.produtos!;
    const precoPromo = numero(produto.preco_promocional);
    const preco =
      produto.em_promocao === true && precoPromo > 0
        ? precoPromo
        : numero(produto.preco);
    const qtd = Math.max(Math.round(linha.quantidade), 1);
    const pesoItem = Math.max(numero(produto.peso_kg), 0.3);
    const comprimentoItem = Math.max(numero(produto.comprimento_cm, 16), 16);
    const larguraItem = Math.max(numero(produto.largura_cm, 11), 11);
    const alturaItem = Math.max(numero(produto.altura_cm, 2), 2);

    peso += pesoItem * qtd;
    comprimento = Math.max(comprimento, comprimentoItem);
    largura = Math.max(largura, larguraItem);
    altura = Math.min(altura + alturaItem * qtd, 100);
    valorDeclarado += preco * qtd;

    return {
      id: produto.id,
      quantidade: qtd,
      peso: pesoItem,
      comprimento: comprimentoItem,
      largura: larguraItem,
      altura: alturaItem,
      valor: preco,
    };
  });

  const subtotal = valorDeclarado;
  const todosGratis = linhas.every(
    (linha) => linha.produtos?.frete_gratis === true,
  );
  const gratis =
    todosGratis ||
    (unidade.frete_gratis_acima != null &&
      subtotal >= numero(unidade.frete_gratis_acima));

  // Hash canônico dos itens desta loja. O checkout v6 recalcula em SQL e
  // recusa a cotação se o carrinho mudou entre a cotação e a compra.
  // O formato precisa ser idêntico ao jsonb do Postgres (espaço após vírgula).
  const paresItens = linhas
    .map((linha) => [
      Number(linha.produtos!.id),
      Math.max(Math.round(linha.quantidade), 1),
    ])
    .sort((a, b) => Number(a[0]) - Number(b[0]));
  const carrinhoCanonico = `[${paresItens.map(([id, qtd]) => `[${id}, ${qtd}]`).join(', ')}]`;
  const carrinhoHash = md5(carrinhoCanonico);

  try {
    let opcoes: OpcaoFrete[];
    if (gratis) {
      try {
        if (modo === 'correios') {
          opcoes = (await cotarCorreios({
            cepOrigem,
            cepDestino,
            pesoKg: peso,
            comprimentoCm: comprimento,
            larguraCm: largura,
            alturaCm: altura,
            valorDeclarado,
          })).map((o) => ({ ...o, valor: 0 }));
        } else {
          opcoes = (await cotarMelhorEnvio(cepOrigem, cepDestino, itens))
            .map((o) => ({ ...o, valor: 0 }));
        }
      } catch (_) {
        opcoes = [
          {
            provider: modo as 'correios' | 'melhor_envio',
            servico: 'Frete grátis',
            servico_codigo: '',
            transportadora: 'Loja',
            valor: 0,
            prazo_dias: 0,
          },
        ];
      }
    } else if (modo === 'correios') {
      opcoes = await cotarCorreios({
        cepOrigem,
        cepDestino,
        pesoKg: peso,
        comprimentoCm: comprimento,
        larguraCm: largura,
        alturaCm: altura,
        valorDeclarado,
      });
    } else {
      opcoes = await cotarMelhorEnvio(cepOrigem, cepDestino, itens);
    }

    opcoes.sort((a, b) => a.valor - b.valor);

    // Uma cotação por opção: o cliente escolhe no app e o checkout aplica
    // exatamente o ID escolhido (o servidor revalida valor/expiração).
    const opcoesComId: Array<OpcaoFrete & { cotacao_id: string }> = [];
    for (const opcao of opcoes) {
      const { data: cotacao, error: insertError } = await admin
        .from('frete_cotacoes')
        .insert({
          user_id: auth.user.id,
          unidade_id: unidadeId,
          provider: opcao.provider,
          servico: opcao.servico,
          servico_codigo: opcao.servico_codigo || null,
          transportadora: opcao.transportadora,
          valor: arredondar2(opcao.valor),
          prazo_dias: opcao.prazo_dias,
          peso_kg: arredondar2(peso),
          cep_origem: cepOrigem,
          cep_destino: cepDestino,
          payload: {
            opcoes,
            carrinho_hash: carrinhoHash,
            itens: linhas.map((linha) => ({
              produto_id: linha.produtos!.id,
              quantidade: Math.max(Math.round(linha.quantidade), 1),
            })),
          },
        })
        .select('id')
        .single();

      if (insertError || !cotacao) {
        throw new Error('Não foi possível registrar a cotação.');
      }

      opcoesComId.push({ ...opcao, cotacao_id: cotacao.id });
    }

    const escolhida = opcoesComId[0];
    return json(
      {
        cotacao_id: escolhida.cotacao_id,
        provider: escolhida.provider,
        servico: escolhida.servico,
        servico_codigo: escolhida.servico_codigo,
        transportadora: escolhida.transportadora,
        valor: arredondar2(escolhida.valor),
        prazo_dias: escolhida.prazo_dias,
        peso_kg: arredondar2(peso),
        simulado: modo === 'correios' && CORREIOS_SIMULACAO,
        opcoes: opcoesComId.map((o) => ({
          ...o,
          valor: arredondar2(o.valor),
        })),
      },
      200,
      cors,
    );
  } catch (erro) {
    const mensagem =
      erro instanceof CorreiosError || erro instanceof Error
        ? erro.message
        : 'Falha na cotação.';
    console.error('frete-cotacao:', mensagem);
    const status = erro instanceof CorreiosError ? erro.status : 502;
    return json({ error: mensagem }, status, cors);
  }
});
