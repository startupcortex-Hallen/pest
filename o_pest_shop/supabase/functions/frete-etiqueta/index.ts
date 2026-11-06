// Edge Function `frete-etiqueta` — gera, imprime, cancela e sincroniza
// etiquetas oficiais dos Correios (Pré-Postagem) para pedidos pagos.
//
// Ações (body.acao):
//   gerar       — cria a pré-postagem e baixa o PDF oficial
//   imprimir    — devolve uma URL assinada do PDF já gerado
//   cancelar    — cancela a pré-postagem nos Correios
//   sincronizar — consulta o rastreio e atualiza envio/pedido
//   simular_evento — só em CORREIOS_SIMULACAO=true (teste do fluxo)
//
// Deploy:
//   supabase functions deploy frete-etiqueta
//
// Requer os secrets CORREIOS_* documentados em _shared/correios.ts.

import { createClient } from 'npm:@supabase/supabase-js@2';
import { getCorsHeaders, json } from '../_shared/cors.ts';
import {
  baixarRotuloCorreios,
  cancelarPrePostagemCorreios,
  CORREIOS_SIMULACAO,
  CorreiosError,
  correiosServicos,
  criarPdfSimulado,
  criarPrePostagemCorreios,
  PrePostagemPendente,
  rastrearCorreios,
  RotuloEmGeracao,
  statusEnvioPorEventos,
} from '../_shared/correios.ts';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const BUCKET = 'etiquetas';

type Json = Record<string, unknown>;
type Role = 'admin' | 'atendente' | 'gestor' | 'cliente' | 'entregador' | '';

Deno.serve(async (req) => {
  const cors = getCorsHeaders(req);
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') {
    return json({ erro: 'Método não permitido.' }, 405, cors);
  }

  try {
    const usuario = await autenticar(req);
    if (!usuario) return json({ erro: 'Faça login para continuar.' }, 401, cors);

    const body = await req.json().catch(() => ({}));
    const acao = String(body['acao'] ?? 'gerar');
    const pedidoId = Number(body['pedido_id'] ?? 0);
    if (!pedidoId) {
      return json({ erro: 'Informe o pedido.' }, 400, cors);
    }

    const admin = criarAdmin();
    const contexto = await contextoUsuario(admin, usuario.id);
    if (!['admin', 'atendente', 'gestor'].includes(contexto.funcao)) {
      return json({ erro: 'Sem permissão para gerenciar etiquetas.' }, 403, cors);
    }

    const pedido = await carregarPedido(admin, pedidoId);
    if (!pedido) return json({ erro: 'Pedido não encontrado.' }, 404, cors);

    if (
      contexto.funcao !== 'admin' &&
      Number(pedido['unidade_id']) !== Number(contexto.unidadeId)
    ) {
      return json({ erro: 'Sem permissão para pedidos de outra loja.' }, 403, cors);
    }

    switch (acao) {
      case 'gerar':
        return await gerar(admin, pedido, body, cors);
      case 'imprimir':
        return await imprimir(admin, pedido, body, cors);
      case 'cancelar':
        return await cancelar(admin, pedido, cors);
      case 'sincronizar':
        return await sincronizar(admin, pedido, cors);
      case 'simular_evento':
        return await simularEvento(admin, pedido, body, cors);
      default:
        return json({ erro: `Ação desconhecida: ${acao}` }, 400, cors);
    }
  } catch (e) {
    if (e instanceof RotuloEmGeracao || e instanceof PrePostagemPendente) {
      return json({ erro: e.message, pendente: true }, 202, cors);
    }
    if (e instanceof CorreiosError) {
      return json({ erro: e.message, detalhes: e.detalhes }, e.status, cors);
    }
    const mensagem = e instanceof Error ? e.message : 'Erro inesperado no envio.';
    console.error('frete-etiqueta erro:', e);
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

function criarAdmin() {
  return createClient(SUPABASE_URL, SERVICE_ROLE, {
    auth: { persistSession: false },
  });
}

async function contextoUsuario(
  admin: ReturnType<typeof criarAdmin>,
  userId: string,
): Promise<{ funcao: Role; unidadeId: number | null }> {
  const { data } = await admin
    .from('perfis')
    .select('funcao, unidade_id')
    .eq('id', userId)
    .maybeSingle();
  return {
    funcao: (data?.['funcao'] as Role | undefined) ?? '',
    unidadeId: (data?.['unidade_id'] as number | null | undefined) ?? null,
  };
}

async function carregarPedido(
  admin: ReturnType<typeof criarAdmin>,
  pedidoId: number,
): Promise<Json | null> {
  const { data, error } = await admin
    .from('pedidos')
    .select(
      '*, pedido_itens(*, produtos!produto_id(nome, peso_kg, comprimento_cm, largura_cm, altura_cm)), ' +
        'unidades(*), perfis!pedidos_user_id_fkey(nome, email, telefone, cpf), envios(*)',
    )
    .eq('id', pedidoId)
    .maybeSingle();
  if (error) throw new Error('Não foi possível carregar o pedido.');
  return data ? (data as unknown as Json) : null;
}

function envioDoPedido(pedido: Json): Json | null {
  const bruto = pedido['envios'];
  if (!bruto) return null;
  if (Array.isArray(bruto)) return (bruto[0] as Json) ?? null;
  return bruto as Json;
}

function itensDoPedido(pedido: Json): Json[] {
  const bruto = pedido['pedido_itens'];
  return Array.isArray(bruto) ? (bruto as Json[]) : [];
}

function unidadeDoPedido(pedido: Json): Json {
  const bruto = pedido['unidades'];
  return bruto && typeof bruto === 'object' ? (bruto as Json) : {};
}

function clienteDoPedido(pedido: Json): Json {
  const bruto = pedido['perfis'];
  return bruto && typeof bruto === 'object' ? (bruto as Json) : {};
}

function somenteDigitos(valor: unknown): string {
  return String(valor ?? '').replace(/\D/g, '');
}

function numero(valor: unknown, padrao = 0): number {
  const n = Number(valor);
  return Number.isFinite(n) ? n : padrao;
}

function texto(valor: unknown): string {
  return String(valor ?? '').trim();
}

function enderecoDoPedido(pedido: Json): {
  cep: string;
  logradouro: string;
  numero: string;
  complemento: string;
  bairro: string;
  cidade: string;
  uf: string;
} {
  const cep = somenteDigitos(pedido['cep_entrega'] ?? pedido['endereco_cep']);
  let rua = texto(pedido['endereco_rua']);
  let numero = texto(pedido['endereco_numero']);
  let complemento = texto(pedido['endereco_complemento']);
  let bairro = texto(pedido['endereco_bairro']);
  let cidade = texto(pedido['endereco_cidade']);
  let uf = texto(pedido['endereco_uf']);

  if (!rua) {
    // Pedidos antigos guardavam o endereço em texto livre:
    // "Rua X, 123, Apto 4, Centro, Barreiras - BA".
    const partes = texto(pedido['endereco_entrega'])
      .split(',')
      .map((p) => p.trim())
      .filter(Boolean);
    if (partes.length > 0) {
      rua = partes[0];
      numero = partes[1] ?? numero;
      complemento = partes[2] ?? complemento;
      bairro = partes[3] ?? bairro;
      const cidadeUf = partes[4] ?? '';
      const match = cidadeUf.match(/^(.*?)\s*-\s*([A-Za-z]{2})$/);
      if (match) {
        cidade = match[1].trim();
        uf = match[2].toUpperCase();
      } else if (cidadeUf) {
        cidade = cidadeUf;
      }
    }
  }

  return {
    cep,
    logradouro: rua,
    numero: numero || 'S/N',
    complemento,
    bairro,
    cidade,
    uf: uf.toUpperCase().slice(0, 2),
  };
}

function enderecoRemetente(unidade: Json): {
  cep: string;
  logradouro: string;
  numero: string;
  complemento: string;
  bairro: string;
  cidade: string;
  uf: string;
} {
  const bruto = texto(unidade['endereco']);
  let rua = bruto;
  let numero = texto(unidade['numero']);
  let complemento = texto(unidade['complemento']);

  if (!numero) {
    const partes = bruto.split(',').map((p) => p.trim());
    if (partes.length > 1) {
      rua = partes[0];
      numero = partes[1] ?? '';
      complemento = partes[2] ?? complemento;
    }
  }

  let cidade = texto(unidade['cidade']);
  let uf = texto(unidade['uf']).toUpperCase().slice(0, 2);
  if (!uf) {
    const match = cidade.match(/^(.*?)\s*-\s*([A-Za-z]{2})$/);
    if (match) {
      cidade = match[1].trim();
      uf = match[2].toUpperCase();
    }
  }

  return {
    cep: somenteDigitos(unidade['cep']),
    logradouro: rua,
    numero: numero || 'S/N',
    complemento,
    bairro: texto(unidade['bairro']),
    cidade,
    uf,
  };
}

function agregarVolumes(pedido: Json) {
  let peso = 0;
  let comprimento = 0;
  let largura = 0;
  let altura = 0;
  let valorDeclarado = 0;
  const itens = itensDoPedido(pedido).map((item) => {
    const produto = (item['produtos'] ?? {}) as Json;
    const qtd = Math.max(Math.round(numero(item['quantidade'], 1)), 1);
    const preco = numero(item['preco_unitario']);
    const pesoItem = Math.max(numero(produto['peso_kg']), 0.3);
    const comprimentoItem = Math.max(numero(produto['comprimento_cm'], 16), 16);
    const larguraItem = Math.max(numero(produto['largura_cm'], 11), 11);
    const alturaItem = Math.max(numero(produto['altura_cm'], 2), 2);

    peso += pesoItem * qtd;
    comprimento = Math.max(comprimento, comprimentoItem);
    largura = Math.max(largura, larguraItem);
    altura = Math.min(altura + alturaItem * qtd, 100);
    valorDeclarado += preco * qtd;

    return {
      descricao: texto(produto['nome']) || `Produto ${item['produto_id'] ?? ''}`,
      quantidade: qtd,
      valorUnitario: preco,
    };
  });

  return { peso, comprimento, largura, altura, valorDeclarado, itens };
}

async function gerar(
  admin: ReturnType<typeof criarAdmin>,
  pedido: Json,
  body: Json,
  cors: Record<string, string>,
) {
  const pedidoId = Number(pedido['id']);
  const status = texto(pedido['status']);
  const tipoEntrega = texto(pedido['tipo_entrega'] ?? 'retirada');
  const unidade = unidadeDoPedido(pedido);
  const cliente = clienteDoPedido(pedido);

  if (tipoEntrega !== 'entrega') {
    return json(
      { erro: 'Este pedido é de retirada; não precisa de etiqueta.' },
      422,
      cors,
    );
  }
  if (!['pago', 'em_preparo', 'pronto_para_entrega'].includes(status)) {
    return json(
      { erro: 'A etiqueta só pode ser gerada para pedido pago.' },
      422,
      cors,
    );
  }

  const modo = texto(pedido['frete_provider'] ?? unidade['frete_modo']);
  if (modo !== 'correios') {
    return json(
      {
        erro:
          'A etiqueta desta loja não está configurada para os Correios. ' +
          'Selecione o modo Correios na loja ou use o Melhor Envio.',
      },
      422,
      cors,
    );
  }

  const endereco = enderecoDoPedido(pedido);
  const faltando: string[] = [];
  if (!endereco.cep || endereco.cep.length !== 8) faltando.push('CEP');
  if (!endereco.logradouro) faltando.push('rua');
  if (!endereco.bairro) faltando.push('bairro');
  if (!endereco.cidade) faltando.push('cidade');
  if (!endereco.uf) faltando.push('UF');
  if (faltando.length > 0) {
    return json(
      {
        erro:
          `Endereço do pedido incompleto (${faltando.join(', ')}). ` +
          'Peça ao cliente para atualizar o endereço ou recrie o pedido.',
      },
      422,
      cors,
    );
  }

  const cpf = somenteDigitos(
    pedido['destinatario_cpf'] ?? cliente['cpf'],
  );
  if (cpf.length !== 11) {
    return json(
      {
        erro:
          'CPF do destinatário ausente/inválido. Atualize o cadastro/perfil do cliente antes de gerar a etiqueta.',
      },
      422,
      cors,
    );
  }

  const remetenteEndereco = enderecoRemetente(unidade);
  const remetenteDoc = somenteDigitos(unidade['cnpj'] ?? Deno.env.get('CORREIOS_CNPJ'));
  if (remetenteDoc.length !== 14) {
    return json(
      { erro: 'A loja precisa ter CNPJ cadastrado para emitir etiqueta.' },
      422,
      cors,
    );
  }
  if (
    !remetenteEndereco.cep ||
    !remetenteEndereco.logradouro ||
    !remetenteEndereco.bairro ||
    !remetenteEndereco.cidade ||
    !remetenteEndereco.uf
  ) {
    return json(
      {
        erro:
          'Endereço do remetente incompleto. Preencha número/UF na loja (Admin > Lojas).',
      },
      422,
      cors,
    );
  }

  const volumes = agregarVolumes(pedido);
  const servicoCodigo =
    texto(body['servico_codigo'] ?? pedido['frete_servico_codigo']) ||
    (correiosServicos()[0]?.codigo ?? '');
  if (!servicoCodigo) {
    return json(
      { erro: 'Serviço dos Correios não definido no pedido (PAC/SEDEX).' },
      422,
      cors,
    );
  }

  const existente = envioDoPedido(pedido);
  if (
    existente &&
    texto(existente['etiqueta_id']) &&
    texto(existente['status']) !== 'cancelado'
  ) {
    // Já existe pré-postagem: tenta apenas baixar/imprimir o PDF (evita
    // cobrar/criar uma segunda etiqueta no Correios).
    return await imprimir(admin, pedido, body, cors);
  }

  // Claim idempotente: grava/atualiza a linha antes de chamar os Correios.
  // Se duas requisições chegarem juntas, só uma consegue mudar o status para
  // "gerando"; a outra recebe 409 e não cria uma segunda pré-postagem.
  const agoraClaim = new Date().toISOString();
  let envioId = texto(existente?.['id']);
  if (envioId) {
    const statusAnterior = texto(existente?.['status']);
    if (
      statusAnterior === 'gerando' &&
      existente?.['updated_at'] &&
      Date.now() - new Date(String(existente['updated_at'])).getTime() < 120_000
    ) {
      return json(
        { erro: 'A etiqueta deste pedido já está sendo gerada. Aguarde.' },
        409,
        cors,
      );
    }
    const { data: claim, error: claimError } = await admin
      .from('envios')
      .update({
        status: 'gerando',
        erro: null,
        etiqueta_id: null,
        etiqueta_pdf_path: null,
        codigo_objeto: null,
        payload: null,
        updated_at: agoraClaim,
      })
      .eq('id', envioId)
      .eq('status', statusAnterior)
      .select('id');
    if (claimError || !claim || claim.length === 0) {
      return json(
        { erro: 'A etiqueta deste pedido já está sendo gerada. Aguarde.' },
        409,
        cors,
      );
    }
  } else {
    const { data: claim, error: claimError } = await admin
      .from('envios')
      .insert({
        pedido_id: pedidoId,
        unidade_id: pedido['unidade_id'],
        provider: 'correios',
        servico: texto(pedido['frete_servico']) || servicoCodigo,
        servico_codigo: servicoCodigo,
        transportadora: 'Correios',
        status: 'gerando',
        peso_kg: Math.round(volumes.peso * 100) / 100,
        updated_at: agoraClaim,
      })
      .select('id')
      .single();
    if (claimError || !claim) {
      return json(
        { erro: 'Não foi possível reservar a geração da etiqueta. Tente novamente.' },
        409,
        cors,
      );
    }
    envioId = String(claim['id']);
  }

  let prePostagem;
  try {
    prePostagem = await criarPrePostagemCorreios({
    pedidoId,
    servicoCodigo,
    pesoKg: volumes.peso,
    comprimentoCm: volumes.comprimento,
    larguraCm: volumes.largura,
    alturaCm: volumes.altura,
    valorDeclarado: volumes.valorDeclarado,
    remetente: {
      nome: texto(unidade['nome_remetente']) || texto(unidade['nome']),
      documento: remetenteDoc,
      email: texto(unidade['email_contato']) || undefined,
      telefone: texto(unidade['telefone_contato']) || undefined,
      endereco: remetenteEndereco,
    },
    destinatario: {
      nome: texto(cliente['nome']) || texto(pedido['comprador_nome']) || 'Cliente',
      documento: cpf,
      email: texto(cliente['email']) || undefined,
      telefone:
        texto(pedido['destinatario_telefone']) ||
        texto(cliente['telefone']) ||
        undefined,
      endereco,
    },
    itens: volumes.itens,
    chaveNFe: texto(pedido['nota_fiscal_chave']) || null,
    numeroNFe: texto(pedido['nota_fiscal_numero']) || null,
    contribuinteIcms: unidade['contribuinte_icms'] === true,
    observacao: `Pedido ${pedidoId}`,
    });
  } catch (e) {
    await admin
      .from('envios')
      .update({
        status: 'erro',
        erro: e instanceof Error ? e.message : 'Falha ao criar a pré-postagem.',
        updated_at: new Date().toISOString(),
      })
      .eq('id', envioId);
    throw e;
  }

  // Persiste a pré-postagem IMEDIATAMENTE. Se o download do PDF falhar, o
  // retry encontra o etiqueta_id e apenas tenta baixar de novo — nunca cria
  // uma segunda etiqueta no Correios.
  const urlRastreio =
    `https://rastreamento.correios.com.br/app/index.php?objeto=${prePostagem.codigoObjeto}`;
  const agoraPre = new Date().toISOString();
  await admin
    .from('envios')
    .update({
      status: 'prepostado',
      status_correios: prePostagem.descStatusAtual ?? null,
      codigo_objeto: prePostagem.codigoObjeto,
      etiqueta_id: prePostagem.id,
      payload: prePostagem.payload,
      erro: null,
      gerado_em: agoraPre,
      updated_at: agoraPre,
    })
    .eq('id', envioId);

  await admin
    .from('pedidos')
    .update({
      etiqueta_status: 'prepostado',
      etiqueta_id: prePostagem.id,
      codigo_objeto: prePostagem.codigoObjeto,
      codigo_rastreio: prePostagem.codigoObjeto,
      url_rastreio: urlRastreio,
      etiqueta_gerada_em: agoraPre,
      frete_provider: 'correios',
      updated_at: agoraPre,
    })
    .eq('id', pedidoId);

  const agora = new Date().toISOString();
  let pdf: Uint8Array | null = null;
  let recibo: string | null = null;
  let statusEtiqueta = 'prepostado';
  let erro: string | null = null;

  try {
    if (CORREIOS_SIMULACAO) {
      pdf = await criarPdfSimulado({
        codigoObjeto: prePostagem.codigoObjeto,
        pedidoId,
        servico: texto(pedido['frete_servico']) || servicoCodigo,
        remetente: texto(unidade['nome_remetente']) || texto(unidade['nome']),
        destinatario:
          texto(cliente['nome']) || texto(pedido['comprador_nome']) || 'Cliente',
        endereco:
          `${endereco.logradouro}, ${endereco.numero} - ${endereco.bairro}, ` +
          `${endereco.cidade} - ${endereco.uf}, ${endereco.cep}`,
        pesoKg: volumes.peso,
      });
      statusEtiqueta = 'gerada';
    } else {
      const layout = texto(body['layout'] ?? Deno.env.get('CORREIOS_LAYOUT') ?? 'PADRAO');
      const baixado = await baixarRotuloCorreios(prePostagem.id, layout);
      pdf = baixado.pdf;
      recibo = baixado.recibo;
      statusEtiqueta = 'gerada';
    }
  } catch (e) {
    if (e instanceof RotuloEmGeracao || e instanceof PrePostagemPendente) {
      erro = e.message;
      statusEtiqueta = 'pendente';
    } else {
      throw e;
    }
  }

  let pdfPath: string | null = null;
  if (pdf && pdf.length > 0) {
    pdfPath = `${pedidoId}/${prePostagem.codigoObjeto}.pdf`;
    const { error: uploadError } = await admin.storage
      .from(BUCKET)
      .upload(pdfPath, pdf, {
        contentType: 'application/pdf',
        upsert: true,
      });
    if (uploadError) {
      throw new Error(`Falha ao salvar a etiqueta: ${uploadError.message}`);
    }
  }

  const dadosEnvio = {
    pedido_id: pedidoId,
    unidade_id: pedido['unidade_id'],
    provider: 'correios',
    servico: texto(pedido['frete_servico']) || servicoCodigo,
    servico_codigo: servicoCodigo,
    transportadora: 'Correios',
    status: statusEtiqueta,
    status_correios: prePostagem.descStatusAtual ?? null,
    codigo_objeto: prePostagem.codigoObjeto,
    etiqueta_id: prePostagem.id,
    etiqueta_pdf_path: pdfPath,
    recibo_rotulo: recibo,
    peso_kg: Math.round(volumes.peso * 100) / 100,
    comprimento_cm: Math.round(volumes.comprimento),
    largura_cm: Math.round(volumes.largura),
    altura_cm: Math.round(volumes.altura),
    valor_declarado: Math.round(volumes.valorDeclarado * 100) / 100,
    payload: prePostagem.payload,
    erro,
    gerado_em: agora,
    updated_at: agora,
  };

  const { data: envio, error: envioError } = await admin
    .from('envios')
    .update(dadosEnvio)
    .eq('id', envioId)
    .select('*')
    .single();
  if (envioError) {
    throw new Error(`Falha ao registrar o envio: ${envioError.message}`);
  }

  await admin
    .from('pedidos')
    .update({
      etiqueta_status: statusEtiqueta,
      etiqueta_id: prePostagem.id,
      etiqueta_pdf_path: pdfPath,
      codigo_objeto: prePostagem.codigoObjeto,
      codigo_rastreio: prePostagem.codigoObjeto,
      url_rastreio: urlRastreio,
      etiqueta_gerada_em: agora,
      frete_provider: 'correios',
      updated_at: agora,
    })
    .eq('id', pedidoId);

  await registrarEvento(admin, String(envio['id']), {
    codigo: 'FC',
    tipo: '82',
    descricao: CORREIOS_SIMULACAO
      ? 'Etiqueta simulada emitida'
      : 'Etiqueta emitida',
    detalhe: prePostagem.descStatusAtual ?? null,
    ocorrido_em: agora,
    payload: { simulacao: CORREIOS_SIMULACAO },
  });

  return await responderComEnvio(admin, pedido, envio as Json, cors);
}

async function responderComEnvio(
  admin: ReturnType<typeof criarAdmin>,
  pedido: Json,
  envio: Json,
  cors: Record<string, string>,
) {
  let pdfUrl: string | null = null;
  const pdfPath = texto(envio['etiqueta_pdf_path']);
  if (pdfPath) {
    const { data } = await admin.storage
      .from(BUCKET)
      .createSignedUrl(pdfPath, 60 * 60);
    pdfUrl = data?.signedUrl ?? null;
  }

  return json(
    {
      ok: true,
      envio,
      pedido_id: pedido['id'],
      pdf_url: pdfUrl,
      simulado: CORREIOS_SIMULACAO,
      pendente: texto(envio['status']) === 'pendente',
    },
    200,
    cors,
  );
}

async function imprimir(
  admin: ReturnType<typeof criarAdmin>,
  pedido: Json,
  body: Json,
  cors: Record<string, string>,
) {
  let envio = envioDoPedido(pedido);
  if (!envio) {
    return json({ erro: 'Gere a etiqueta antes de imprimir.' }, 422, cors);
  }

  let pdfPath = texto(envio['etiqueta_pdf_path']);
  if (!pdfPath) {
    const id = texto(envio['etiqueta_id']);
    if (!id) {
      return json({ erro: 'Etiqueta ainda não criada.' }, 422, cors);
    }
    const layout = texto(
      body['layout'] ??
        envio['layout_impressao'] ??
        Deno.env.get('CORREIOS_LAYOUT') ??
        'PADRAO',
    );
    const baixado = await baixarRotuloCorreios(
      id,
      layout,
      texto(envio['recibo_rotulo']) || null,
    );
    pdfPath = `${pedido['id']}/${texto(envio['codigo_objeto'])}.pdf`;
    const { error } = await admin.storage
      .from(BUCKET)
      .upload(pdfPath, baixado.pdf, {
        contentType: 'application/pdf',
        upsert: true,
      });
    if (error) throw new Error(`Falha ao salvar a etiqueta: ${error.message}`);

    const { data: atualizado } = await admin
      .from('envios')
      .update({
        etiqueta_pdf_path: pdfPath,
        recibo_rotulo: baixado.recibo,
        status: 'gerada',
        gerado_em: new Date().toISOString(),
        erro: null,
        updated_at: new Date().toISOString(),
      })
      .eq('id', envio['id'])
      .select('*')
      .single();
    if (atualizado) envio = atualizado as Json;

    await admin
      .from('pedidos')
      .update({
        etiqueta_status: 'gerada',
        etiqueta_pdf_path: pdfPath,
        etiqueta_gerada_em: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      .eq('id', pedido['id']);
  }

  const { data, error } = await admin.storage
    .from(BUCKET)
    .createSignedUrl(pdfPath, 60 * 60);
  if (error || !data?.signedUrl) {
    throw new Error('Não foi possível gerar o link da etiqueta.');
  }

  return json({ ok: true, pdf_url: data.signedUrl, envio }, 200, cors);
}

async function cancelar(
  admin: ReturnType<typeof criarAdmin>,
  pedido: Json,
  cors: Record<string, string>,
) {
  const envio = envioDoPedido(pedido);
  if (!envio) {
    return json({ erro: 'Este pedido não possui etiqueta.' }, 422, cors);
  }
  const id = texto(envio['etiqueta_id']);
  if (id) {
    await cancelarPrePostagemCorreios(id);
  }

  const agora = new Date().toISOString();
  const { data: atualizado } = await admin
    .from('envios')
    .update({
      status: 'cancelado',
      erro: null,
      updated_at: agora,
    })
    .eq('id', envio['id'])
    .select('*')
    .single();

  await admin
    .from('pedidos')
    .update({
      etiqueta_status: 'cancelado',
      updated_at: agora,
    })
    .eq('id', pedido['id']);

  return json({ ok: true, envio: atualizado }, 200, cors);
}

async function sincronizar(
  admin: ReturnType<typeof criarAdmin>,
  pedido: Json,
  cors: Record<string, string>,
) {
  const envio = envioDoPedido(pedido);
  if (!envio) {
    return json({ erro: 'Gere a etiqueta antes de sincronizar.' }, 422, cors);
  }
  const codigo = texto(envio['codigo_objeto']);
  if (!codigo) {
    return json({ erro: 'Envio sem código de objeto.' }, 422, cors);
  }

  const eventos = await rastrearCorreios(codigo);
  for (const evento of eventos) {
    await registrarEvento(admin, String(envio['id']), evento);
  }

  const status = statusEnvioPorEventos(eventos);
  return await aplicarStatusEnvio(admin, pedido, envio, status, eventos, cors);
}

async function simularEvento(
  admin: ReturnType<typeof criarAdmin>,
  pedido: Json,
  body: Json,
  cors: Record<string, string>,
) {
  if (!CORREIOS_SIMULACAO) {
    return json(
      { erro: 'A simulação de evento só funciona com CORREIOS_SIMULACAO=true.' },
      403,
      cors,
    );
  }
  const envio = envioDoPedido(pedido);
  if (!envio) {
    return json({ erro: 'Gere a etiqueta antes de simular.' }, 422, cors);
  }

  const status = texto(body['status'] ?? 'postado');
  const mapa: Record<string, { codigo: string; descricao: string }> = {
    aguardando_postagem: { codigo: 'FC', descricao: 'Aguardando postagem' },
    postado: { codigo: 'PO', descricao: 'Objeto postado' },
    em_transito: { codigo: 'RO', descricao: 'Objeto em trânsito' },
    entregue: { codigo: 'BDE', descricao: 'Objeto entregue ao destinatário' },
    cancelado: { codigo: 'CAN', descricao: 'Objeto cancelado' },
    problema: { codigo: 'BDR', descricao: 'Problema na entrega' },
  };
  const evento = mapa[status];
  if (!evento) {
    return json({ erro: 'Status de simulação inválido.' }, 400, cors);
  }

  const agora = new Date().toISOString();
  const eventos = [
    {
      codigo: evento.codigo,
      tipo: '01',
      descricao: evento.descricao,
      detalhe: 'Evento simulado',
      ocorrido_em: agora,
      payload: { simulacao: true },
    },
  ];
  for (const e of eventos) {
    await registrarEvento(admin, String(envio['id']), e);
  }

  return await aplicarStatusEnvio(
    admin,
    pedido,
    envio,
    status as 'postado' | 'em_transito' | 'entregue' | 'cancelado' | 'problema',
    eventos,
    cors,
  );
}

async function aplicarStatusEnvio(
  admin: ReturnType<typeof criarAdmin>,
  pedido: Json,
  envio: Json,
  status:
    | 'aguardando_postagem'
    | 'postado'
    | 'em_transito'
    | 'entregue'
    | 'cancelado'
    | 'problema'
    | null,
  eventos: Array<Record<string, unknown>>,
  cors: Record<string, string>,
) {
  if (!status) {
    return json(
      {
        ok: true,
        envio,
        status: envio['status'],
        eventos,
        mensagem: 'Nenhum evento novo de rastreio.',
      },
      200,
      cors,
    );
  }

  if (texto(pedido['status']) === 'cancelado') {
    return json(
      { erro: 'Pedido cancelado: o rastreio não será aplicado.' },
      422,
      cors,
    );
  }

  const agora = new Date().toISOString();
  const atualizacao: Json = {
    status,
    status_correios: status,
    ultima_sincronizacao: agora,
    updated_at: agora,
  };
  if (status === 'postado') atualizacao['postado_em'] = agora;
  if (status === 'entregue') atualizacao['entregue_em'] = agora;

  const { data: envioAtualizado } = await admin
    .from('envios')
    .update(atualizacao)
    .eq('id', envio['id'])
    .select('*')
    .single();

  const pedidoAtualizacao: Json = {
    etiqueta_status: status,
    updated_at: agora,
  };
  if (status === 'postado') {
    pedidoAtualizacao['status'] = 'postado';
    pedidoAtualizacao['postado_em'] = agora;
  } else if (status === 'em_transito') {
    // Só promove se o pedido já saiu do preparo; evita pular etapas.
    const statusAtual = texto(pedido['status']);
    if (['pago', 'em_preparo', 'postado'].includes(statusAtual)) {
      pedidoAtualizacao['status'] = 'em_transito';
    }
  } else if (status === 'entregue') {
    pedidoAtualizacao['status'] = 'entregue';
    pedidoAtualizacao['entregue_em'] = agora;
  }

  await admin
    .from('pedidos')
    .update(pedidoAtualizacao)
    .eq('id', pedido['id']);

  return json(
    {
      ok: true,
      envio: envioAtualizado ?? envio,
      status,
      eventos,
    },
    200,
    cors,
  );
}

async function registrarEvento(
  admin: ReturnType<typeof criarAdmin>,
  envioId: string,
  evento: Record<string, unknown>,
) {
  await admin
    .from('envio_eventos')
    .upsert(
      {
        envio_id: envioId,
        codigo: evento['codigo'] ?? null,
        tipo: evento['tipo'] ?? null,
        descricao: evento['descricao'] ?? null,
        detalhe: evento['detalhe'] ?? null,
        ocorrido_em: evento['ocorrido_em'] ?? new Date().toISOString(),
        payload: evento['payload'] ?? null,
      },
      {
        onConflict: 'envio_id,codigo,ocorrido_em',
        ignoreDuplicates: true,
      },
    );
}
