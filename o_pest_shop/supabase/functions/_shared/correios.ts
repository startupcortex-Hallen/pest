// Integração direta com as APIs REST oficiais dos Correios.
//
// Serviços usados:
//   • Token (Basic Auth com usuário/código de acesso do CWS)
//   • Preço e Prazo (cotação)
//   • Pré-Postagem (criação da etiqueta e PDF do rótulo)
//   • SRO/Rastro (eventos de rastreio)
//
// Credenciais (Supabase Secrets):
//   CORREIOS_ENV=homolog|production
//   CORREIOS_USUARIO=...            (Meu Correios; em homologação use o CNPJ)
//   CORREIOS_CODIGO_ACESSO=...      (gerado no CWS, não é a senha do site)
//   CORREIOS_CNPJ=...
//   CORREIOS_CONTRATO=...           (opcional, mas recomendado)
//   CORREIOS_CARTAO_POSTAGEM=...    (opcional)
//   CORREIOS_DR=...                 (opcional)
//   CORREIOS_SERVICOS=03298:PAC,03220:SEDEX
//   CORREIOS_SIMULACAO=true         (testa o fluxo sem chamar os Correios)
//
// O token vale 24h e aceita no máximo 3 requisições/s. Ele é cacheado no
// isolate da Edge Function e renovado perto de expirar.

import { PDFDocument, StandardFonts, rgb } from 'npm:pdf-lib@1.17.1';

export type CorreiosServico = { codigo: string; nome: string };

export type CorreiosOpcao = {
  provider: 'correios';
  servico: string;
  servico_codigo: string;
  transportadora: string;
  valor: number;
  prazo_dias: number;
};

export type CorreiosEvento = {
  codigo: string;
  tipo: string;
  descricao: string;
  detalhe: string;
  ocorrido_em: string | null;
  payload: Record<string, unknown>;
};

export type CorreiosPrePostagem = {
  id: string;
  codigoObjeto: string;
  statusAtual: number;
  descStatusAtual?: string;
  precoPrePostagem?: number;
  payload: Record<string, unknown>;
};

export class CorreiosError extends Error {
  status: number;
  detalhes: unknown;

  constructor(mensagem: string, status = 502, detalhes: unknown = null) {
    super(mensagem);
    this.name = 'CorreiosError';
    this.status = status;
    this.detalhes = detalhes;
  }
}

export class RotuloEmGeracao extends Error {
  constructor() {
    super('A etiqueta ainda está sendo gerada pelos Correios.');
    this.name = 'RotuloEmGeracao';
  }
}

export class PrePostagemPendente extends Error {
  constructor() {
    super('A pré-postagem ainda está pendente nos Correios.');
    this.name = 'PrePostagemPendente';
  }
}

const IS_PROD = (Deno.env.get('CORREIOS_ENV') ?? 'homolog').toLowerCase() === 'production';
const BASE = IS_PROD
  ? 'https://api.correios.com.br'
  : 'https://apihom.correios.com.br';

export const CORREIOS_SIMULACAO =
  !IS_PROD &&
  ((Deno.env.get('CORREIOS_SIMULACAO') ?? 'false').toLowerCase() === 'true' ||
    (Deno.env.get('CORREIOS_ENV') ?? '').toLowerCase() === 'simulacao');

export function correiosConfigurado(): boolean {
  return Boolean(
    Deno.env.get('CORREIOS_USUARIO') && Deno.env.get('CORREIOS_CODIGO_ACESSO'),
  );
}

export function correiosAmbiente(): 'homolog' | 'production' {
  return IS_PROD ? 'production' : 'homolog';
}

export function correiosLayoutPadrao(): string {
  return (Deno.env.get('CORREIOS_LAYOUT') ?? 'PADRAO').toUpperCase();
}

export function correiosServicos(): CorreiosServico[] {
  const bruto = Deno.env.get('CORREIOS_SERVICOS') ?? '03298:PAC,03220:SEDEX';
  return bruto
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean)
    .map((item) => {
      const [codigo, ...resto] = item.split(':');
      return {
        codigo: codigo.trim(),
        nome: (resto.join(':').trim() || codigo.trim()).toUpperCase(),
      };
    });
}

function somenteDigitos(valor: unknown): string {
  return String(valor ?? '').replace(/\D/g, '');
}

function numero(valor: unknown, padrao = 0): number {
  if (typeof valor === 'number' && Number.isFinite(valor)) return valor;
  const texto = String(valor ?? '').trim();
  if (!texto) return padrao;
  const normalizado = texto.includes(',')
    ? texto.replace(/\./g, '').replace(',', '.')
    : texto;
  const n = Number(normalizado);
  return Number.isFinite(n) ? n : padrao;
}

function arredondar2(valor: number): number {
  return Math.round(valor * 100) / 100;
}

function dinheiro(valor: number): string {
  return arredondar2(valor).toFixed(2);
}

function limitar(valor: unknown, max: number): string {
  return String(valor ?? '').trim().slice(0, max);
}

function dataHora(valor: unknown): string | null {
  const texto = String(valor ?? '').trim();
  if (!texto) return null;
  const data = new Date(texto);
  return Number.isNaN(data.getTime()) ? null : data.toISOString();
}

type TokenCache = { token: string; expiraEm: number };
let tokenCache: TokenCache | null = null;

export async function obterTokenCorreios(): Promise<string> {
  if (CORREIOS_SIMULACAO) return 'simulacao';

  const usuario = Deno.env.get('CORREIOS_USUARIO') ?? '';
  const codigo = Deno.env.get('CORREIOS_CODIGO_ACESSO') ?? '';
  if (!usuario || !codigo) {
    throw new CorreiosError(
      'Correios não configurados. Defina CORREIOS_USUARIO e CORREIOS_CODIGO_ACESSO nos secrets.',
      503,
    );
  }

  if (tokenCache && Date.now() < tokenCache.expiraEm - 5 * 60 * 1000) {
    return tokenCache.token;
  }

  const contrato = somenteDigitos(Deno.env.get('CORREIOS_CONTRATO'));
  const cartao = somenteDigitos(Deno.env.get('CORREIOS_CARTAO_POSTAGEM'));
  const dr = somenteDigitos(Deno.env.get('CORREIOS_DR'));

  let endpoint = `${BASE}/token/v1/autentica`;
  let corpo: Record<string, unknown> | undefined;
  if (contrato) {
    endpoint = `${BASE}/token/v1/autentica/contrato`;
    corpo = { numero: contrato };
    if (dr) corpo['dr'] = Number(dr);
  } else if (cartao) {
    endpoint = `${BASE}/token/v1/autentica/cartaopostagem`;
    corpo = { numero: cartao };
    if (contrato) corpo['contrato'] = contrato;
    if (dr) corpo['dr'] = Number(dr);
  }

  const resposta = await fetch(endpoint, {
    method: 'POST',
    headers: {
      Authorization: `Basic ${btoa(`${usuario}:${codigo}`)}`,
      'Content-Type': 'application/json',
      Accept: 'application/json',
    },
    body: corpo ? JSON.stringify(corpo) : undefined,
  });

  const texto = await resposta.text();
  let dados: Record<string, unknown> = {};
  try {
    dados = texto ? JSON.parse(texto) : {};
  } catch {
    dados = { mensagem: texto };
  }

  if (!resposta.ok) {
    throw new CorreiosError(
      mensagemErro(dados, `Falha ao autenticar nos Correios (${resposta.status})`),
      resposta.status === 401 ? 503 : 502,
      dados,
    );
  }

  const token = String(dados['token'] ?? '');
  if (!token) {
    throw new CorreiosError('Correios não retornou o token de acesso.', 502, dados);
  }

  const expira = dados['expiraEm']
    ? new Date(String(dados['expiraEm'])).getTime()
    : Date.now() + 23 * 60 * 60 * 1000;

  tokenCache = {
    token,
    expiraEm: Number.isFinite(expira) ? expira : Date.now() + 23 * 60 * 60 * 1000,
  };
  return token;
}

function mensagemErro(dados: Record<string, unknown>, fallback: string): string {
  const msgs = dados['msgs'];
  if (Array.isArray(msgs) && msgs.length > 0) {
    return msgs.map((m) => String(m)).join(' | ');
  }
  return String(dados['mensagem'] ?? dados['message'] ?? dados['erro'] ?? fallback);
}

async function correiosFetch(
  caminho: string,
  init: RequestInit = {},
): Promise<Response> {
  const token = await obterTokenCorreios();
  const headers = new Headers(init.headers);
  headers.set('Authorization', `Bearer ${token}`);
  headers.set('Accept', 'application/json');
  if (init.body && !headers.has('Content-Type')) {
    headers.set('Content-Type', 'application/json');
  }

  const resposta = await fetch(`${BASE}${caminho}`, { ...init, headers });
  if (!resposta.ok) {
    const texto = await resposta.text().catch(() => '');
    let dados: Record<string, unknown> = {};
    try {
      dados = texto ? JSON.parse(texto) : {};
    } catch {
      dados = { mensagem: texto };
    }
    throw new CorreiosError(
      mensagemErro(dados, `Correios respondeu ${resposta.status}`),
      resposta.status,
      dados,
    );
  }
  return resposta;
}

async function correiosJson(
  caminho: string,
  init: RequestInit = {},
): Promise<Record<string, unknown>> {
  const resposta = await correiosFetch(caminho, init);
  const texto = await resposta.text();
  if (!texto) return {};
  try {
    return JSON.parse(texto) as Record<string, unknown>;
  } catch {
    return { mensagem: texto };
  }
}

// ── COTAÇÃO ──────────────────────────────────────────────────────────────

export type CotacaoEntrada = {
  cepOrigem: string;
  cepDestino: string;
  pesoKg: number;
  comprimentoCm: number;
  larguraCm: number;
  alturaCm: number;
  valorDeclarado: number;
};

export async function cotarCorreios(
  entrada: CotacaoEntrada,
): Promise<CorreiosOpcao[]> {
  if (CORREIOS_SIMULACAO) return simularCotacao(entrada);

  const cepOrigem = somenteDigitos(entrada.cepOrigem);
  const cepDestino = somenteDigitos(entrada.cepDestino);
  if (cepOrigem.length !== 8 || cepDestino.length !== 8) {
    throw new CorreiosError('CEP de origem/destino inválido para cotação.', 422);
  }

  const contrato = somenteDigitos(Deno.env.get('CORREIOS_CONTRATO'));
  const dr = somenteDigitos(Deno.env.get('CORREIOS_DR'));
  const pesoGramas = Math.max(Math.round(entrada.pesoKg * 1000), 300);
  const comprimento = Math.max(Math.round(entrada.comprimentoCm), 16);
  const largura = Math.max(Math.round(entrada.larguraCm), 11);
  const altura = Math.max(Math.round(entrada.alturaCm), 2);

  const consultas = correiosServicos().map(async (servico) => {
    const params = new URLSearchParams({
      cepOrigem,
      cepDestino,
      psObjeto: String(pesoGramas),
      tpObjeto: '2',
      comprimento: String(comprimento),
      largura: String(largura),
      altura: String(altura),
      vlDeclarado: dinheiro(entrada.valorDeclarado),
    });
    if (contrato) params.set('nuContrato', contrato);
    if (dr) params.set('nuDR', dr);

    const [preco, prazo] = await Promise.all([
      correiosJson(`/preco/v1/nacional/${servico.codigo}?${params.toString()}`),
      correiosJson(
        `/prazo/v1/nacional/${servico.codigo}?cepOrigem=${cepOrigem}&cepDestino=${cepDestino}`,
      ).catch(() => ({}) as Record<string, unknown>),
    ]);

    const valor = numero(preco['pcFinal'] ?? preco['pcBaseGeral'] ?? preco['pcBase']);
    if (valor <= 0) {
      throw new CorreiosError(
        `Correios não retornou preço para ${servico.nome}.`,
        502,
        preco,
      );
    }

    return {
      provider: 'correios' as const,
      servico: servico.nome,
      servico_codigo: servico.codigo,
      transportadora: 'Correios',
      valor: arredondar2(valor),
      prazo_dias: Math.max(Math.round(numero(prazo['prazoEntrega'])), 0),
    };
  });

  const resultados = await Promise.allSettled(consultas);
  const opcoes = resultados
    .filter(
      (r): r is PromiseFulfilledResult<CorreiosOpcao> => r.status === 'fulfilled',
    )
    .map((r) => r.value);

  if (opcoes.length === 0) {
    const primeiroErro = resultados.find(
      (r): r is PromiseRejectedResult => r.status === 'rejected',
    );
    if (primeiroErro?.reason instanceof CorreiosError) throw primeiroErro.reason;
    throw new CorreiosError(
      'Não foi possível cotar PAC/SEDEX nos Correios.',
      502,
      primeiroErro?.reason,
    );
  }

  return opcoes.sort((a, b) => a.valor - b.valor);
}

function simularCotacao(entrada: CotacaoEntrada): CorreiosOpcao[] {
  const peso = Math.max(entrada.pesoKg, 0.3);
  return [
    {
      provider: 'correios',
      servico: 'PAC',
      servico_codigo: '03298',
      transportadora: 'Correios',
      valor: arredondar2(18.9 + Math.max(peso - 1, 0) * 2.1),
      prazo_dias: 7,
    },
    {
      provider: 'correios',
      servico: 'SEDEX',
      servico_codigo: '03220',
      transportadora: 'Correios',
      valor: arredondar2(32.5 + Math.max(peso - 1, 0) * 3.4),
      prazo_dias: 3,
    },
  ];
}

// ── PRÉ-POSTAGEM ─────────────────────────────────────────────────────────

export type PrePostagemEntrada = {
  pedidoId: number;
  servicoCodigo: string;
  pesoKg: number;
  comprimentoCm: number;
  larguraCm: number;
  alturaCm: number;
  valorDeclarado: number;
  remetente: {
    nome: string;
    documento: string;
    email?: string | null;
    telefone?: string | null;
    endereco: EnderecoCorreios;
  };
  destinatario: {
    nome: string;
    documento: string;
    email?: string | null;
    telefone?: string | null;
    endereco: EnderecoCorreios;
  };
  itens: Array<{ descricao: string; quantidade: number; valorUnitario: number }>;
  chaveNFe?: string | null;
  numeroNFe?: string | null;
  contribuinteIcms: boolean;
  observacao?: string | null;
};

export type EnderecoCorreios = {
  cep: string;
  logradouro: string;
  numero: string;
  complemento?: string | null;
  bairro: string;
  cidade: string;
  uf: string;
};

export async function criarPrePostagemCorreios(
  entrada: PrePostagemEntrada,
): Promise<CorreiosPrePostagem> {
  if (CORREIOS_SIMULACAO) return simularPrePostagem(entrada);

  const chaveNFe = somenteDigitos(entrada.chaveNFe);
  const numeroNFe = somenteDigitos(entrada.numeroNFe);

  if (entrada.contribuinteIcms && chaveNFe.length !== 44) {
    throw new CorreiosError(
      'A loja é contribuinte do ICMS: informe a chave da NF-e (44 dígitos) antes de gerar a etiqueta.',
      422,
    );
  }

  const telefoneRemetente = separarTelefone(entrada.remetente.telefone);
  const telefoneDestinatario = separarTelefone(entrada.destinatario.telefone);

  const remetenteContato: Record<string, string> = {};
  if (telefoneRemetente.ddd && telefoneRemetente.numero) {
    if (telefoneRemetente.numero.length >= 9) {
      remetenteContato['dddCelular'] = telefoneRemetente.ddd;
      remetenteContato['celular'] = telefoneRemetente.numero.slice(0, 9);
    } else {
      remetenteContato['dddTelefone'] = telefoneRemetente.ddd;
      remetenteContato['telefone'] = telefoneRemetente.numero.slice(0, 8);
    }
  }

  const destinatarioContato: Record<string, string> = {};
  if (telefoneDestinatario.ddd && telefoneDestinatario.numero) {
    if (telefoneDestinatario.numero.length >= 9) {
      destinatarioContato['dddCelular'] = telefoneDestinatario.ddd;
      destinatarioContato['celular'] = telefoneDestinatario.numero.slice(0, 9);
    } else {
      destinatarioContato['dddTelefone'] = telefoneDestinatario.ddd;
      destinatarioContato['telefone'] = telefoneDestinatario.numero.slice(0, 8);
    }
  }

  const payload: Record<string, unknown> = {
    remetente: {
      nome: limitar(entrada.remetente.nome, 50),
      cpfCnpj: somenteDigitos(entrada.remetente.documento),
      email: limitar(entrada.remetente.email, 255) || undefined,
      ...remetenteContato,
      endereco: enderecoParaApi(entrada.remetente.endereco),
    },
    destinatario: {
      nome: limitar(entrada.destinatario.nome, 50),
      cpfCnpj: somenteDigitos(entrada.destinatario.documento),
      email: limitar(entrada.destinatario.email, 255) || undefined,
      ...destinatarioContato,
      endereco: enderecoParaApi(entrada.destinatario.endereco, true),
    },
    codigoServico: entrada.servicoCodigo,
    pesoInformado: String(Math.max(Math.round(entrada.pesoKg * 1000), 300)),
    codigoFormatoObjetoInformado: '2',
    alturaInformada: String(Math.max(Math.round(entrada.alturaCm), 2)),
    larguraInformada: String(Math.max(Math.round(entrada.larguraCm), 11)),
    comprimentoInformado: String(Math.max(Math.round(entrada.comprimentoCm), 16)),
    itensDeclaracaoConteudo: entrada.itens.map((item) => ({
      conteudo: limitar(item.descricao || 'Produto', 60),
      quantidade: String(Math.max(Math.round(item.quantidade), 1)),
      valor: dinheiro(item.valorUnitario),
    })),
    cienteObjetoNaoProibido: '1',
    modalidadePagamento: '2',
    observacao: limitar(entrada.observacao ?? `Pedido ${entrada.pedidoId}`, 50),
    pedidoExternoOrigem: String(entrada.pedidoId),
  };

  if (chaveNFe.length === 44) {
    payload['chaveNFe'] = chaveNFe;
    payload['emiteDCe'] = 'N';
    if (numeroNFe) payload['numeroNotaFiscal'] = limitar(numeroNFe, 12);
  } else {
    payload['emiteDCe'] = 'S';
    if (numeroNFe) payload['numeroNotaFiscal'] = limitar(numeroNFe, 12);
  }

  const dados = await correiosJson('/v1/prepostagens', {
    method: 'POST',
    body: JSON.stringify(payload),
  });

  const id = String(dados['id'] ?? '');
  const codigo = String(dados['codigoObjeto'] ?? '');
  if (!id || !codigo) {
    throw new CorreiosError(
      'Correios não retornou o identificador/código do objeto.',
      502,
      dados,
    );
  }

  return {
    id,
    codigoObjeto: codigo,
    statusAtual: Number(dados['statusAtual'] ?? 1),
    descStatusAtual: String(dados['descStatusAtual'] ?? ''),
    precoPrePostagem: numero(dados['precoPrePostagem']),
    payload: dados,
  };
}

function enderecoParaApi(
  endereco: EnderecoCorreios,
  incluirRegiao = false,
): Record<string, string> {
  const resultado: Record<string, string> = {
    cep: somenteDigitos(endereco.cep),
    logradouro: limitar(endereco.logradouro, 50),
    numero: limitar(endereco.numero || 'S/N', 6),
    bairro: limitar(endereco.bairro, 30),
    cidade: limitar(endereco.cidade, 30),
    uf: limitar(endereco.uf, 2).toUpperCase(),
    pais: 'Brasil',
  };
  const complemento = limitar(endereco.complemento, 30);
  if (complemento) resultado['complemento'] = complemento;
  if (incluirRegiao) resultado['regiao'] = resultado['uf'];
  return resultado;
}

function separarTelefone(valor: unknown): { ddd: string; numero: string } {
  const digitos = somenteDigitos(valor);
  if (digitos.length >= 10) {
    return {
      ddd: digitos.slice(0, 2),
      numero: digitos.slice(2),
    };
  }
  return { ddd: '', numero: digitos };
}

function simularPrePostagem(entrada: PrePostagemEntrada): CorreiosPrePostagem {
  const codigo = `OP${String(entrada.pedidoId).padStart(9, '0')}BR`;
  return {
    id: `sim-${entrada.pedidoId}`,
    codigoObjeto: codigo,
    statusAtual: 2,
    descStatusAtual: 'PREPOSTADO (simulação)',
    precoPrePostagem: 0,
    payload: { simulacao: true, ...entrada },
  };
}

// ── RÓTULO ───────────────────────────────────────────────────────────────

async function solicitarRotulo(
  idPrePostagem: string,
  layout: string,
): Promise<string | null> {
  const dados = await correiosJson('/v1/prepostagens/rotulo/assincrono/pdf', {
    method: 'POST',
    body: JSON.stringify({
      idsPrePostagem: [idPrePostagem],
      tipoRotulo: 'P',
      formatoRotulo: 'ET',
      layoutImpressao: layout,
      imprimeRemetente: 'S',
    }),
  });

  const recibo = dados['idRecibo'] ?? dados['recibo'] ?? dados['id'];
  if (recibo != null && String(recibo).trim() !== '') return String(recibo);
  return null;
}

export async function baixarRotuloCorreios(
  idPrePostagem: string,
  layout: string,
  reciboExistente?: string | null,
): Promise<{ pdf: Uint8Array; recibo: string | null }> {
  if (CORREIOS_SIMULACAO) return { pdf: new Uint8Array(), recibo: null };

  let recibo = reciboExistente ?? (await solicitarRotulo(idPrePostagem, layout));
  const delays = [2000, 3000, 5000, 8000, 13000];

  for (let tentativa = 0; tentativa <= delays.length; tentativa++) {
    if (!recibo) {
      recibo = await solicitarRotulo(idPrePostagem, layout);
    }

    if (recibo) {
      const resposta = await correiosFetch(
        `/v1/prepostagens/rotulo/download/assincrono/${encodeURIComponent(recibo)}`,
      );
      const contentType = (resposta.headers.get('content-type') ?? '').toLowerCase();

      if (contentType.includes('pdf') || contentType.includes('octet-stream')) {
        return { pdf: new Uint8Array(await resposta.arrayBuffer()), recibo };
      }

      const texto = await resposta.text();
      let dados: Record<string, unknown> = {};
      try {
        dados = texto ? JSON.parse(texto) : {};
      } catch {
        dados = { mensagem: texto };
      }

      const erro = `${dados['mensagem'] ?? ''} ${dados['codigo'] ?? ''} ${dados['erro'] ?? ''}`;
      if (erro.includes('PPN-291') || erro.toLowerCase().includes('geração')) {
        // Mesmo recibo: tenta novamente.
      } else if (erro.includes('PPN-288') || erro.toLowerCase().includes('pendente')) {
        recibo = null; // recibo novo
      } else {
        const base64 = dados['base64'] ?? dados['pdfBase64'] ?? dados['conteudo'];
        if (typeof base64 === 'string' && base64.length > 100) {
          return { pdf: base64ParaBytes(base64), recibo };
        }
        const url = dados['url'] ?? dados['link'] ?? dados['arquivo'];
        if (typeof url === 'string' && url.startsWith('http')) {
          const arquivo = await fetch(url);
          if (arquivo.ok) {
            return {
              pdf: new Uint8Array(await arquivo.arrayBuffer()),
              recibo,
            };
          }
        }
        if (texto.startsWith('%PDF')) {
          return { pdf: textoParaBytes(texto), recibo };
        }
        throw new CorreiosError(
          mensagemErro(dados, 'Correios não retornaram o PDF da etiqueta.'),
          502,
          dados,
        );
      }
    }

    if (tentativa < delays.length) {
      await new Promise((resolve) => setTimeout(resolve, delays[tentativa]));
    }
  }

  throw new RotuloEmGeracao();
}

function base64ParaBytes(base64: string): Uint8Array {
  const limpo = base64.replace(/^data:application\/pdf;base64,/, '');
  const binario = atob(limpo);
  const bytes = new Uint8Array(binario.length);
  for (let i = 0; i < binario.length; i++) bytes[i] = binario.charCodeAt(i);
  return bytes;
}

function textoParaBytes(texto: string): Uint8Array {
  return new TextEncoder().encode(texto);
}

// ── CANCELAMENTO ─────────────────────────────────────────────────────────

export async function cancelarPrePostagemCorreios(id: string): Promise<void> {
  if (CORREIOS_SIMULACAO) return;
  await correiosFetch(`/v1/prepostagens/${encodeURIComponent(id)}`, {
    method: 'DELETE',
  });
}

// ── RASTREIO ─────────────────────────────────────────────────────────────

export async function rastrearCorreios(
  codigoObjeto: string,
): Promise<CorreiosEvento[]> {
  if (CORREIOS_SIMULACAO) return [];

  const dados = await correiosJson(
    `/srorastro/v1/objetos/${encodeURIComponent(codigoObjeto)}?resultado=T`,
  );

  const objetos = dados['objetos'];
  if (!Array.isArray(objetos) || objetos.length === 0) return [];

  const objeto = objetos[0] as Record<string, unknown>;
  const eventos = objeto['eventos'];
  if (!Array.isArray(eventos)) return [];

  return eventos
    .filter((e): e is Record<string, unknown> => Boolean(e) && typeof e === 'object')
    .map((evento) => ({
      codigo: String(evento['codigo'] ?? ''),
      tipo: String(evento['tipo'] ?? ''),
      descricao: String(evento['descricao'] ?? ''),
      detalhe: String(evento['detalhe'] ?? ''),
      ocorrido_em: dataHora(evento['dtHrCriado']),
      payload: evento,
    }))
    .sort((a, b) => {
      const da = a.ocorrido_em ? new Date(a.ocorrido_em).getTime() : 0;
      const db = b.ocorrido_em ? new Date(b.ocorrido_em).getTime() : 0;
      return db - da;
    });
}

export function statusEnvioPorEventos(
  eventos: CorreiosEvento[],
): 'aguardando_postagem' | 'postado' | 'em_transito' | 'entregue' | 'cancelado' | 'problema' | null {
  if (eventos.length === 0) return null;
  const evento = eventos[0];
  const codigo = evento.codigo.toUpperCase();
  const texto = `${evento.descricao} ${evento.detalhe}`.toLowerCase();

  if (codigo.startsWith('EST')) {
    return statusEnvioPorEventos(eventos.slice(1));
  }
  if (texto.includes('cancelad') || codigo.startsWith('CAN')) return 'cancelado';
  if (
    codigo.startsWith('BDE') ||
    texto.includes('entregue') ||
    texto.includes('entrega realizada')
  ) {
    return 'entregue';
  }
  if (codigo.startsWith('FC') || texto.includes('aguardando postagem')) {
    return 'aguardando_postagem';
  }
  if (codigo.startsWith('PO') || texto.includes('postado')) return 'postado';
  if (
    codigo.startsWith('RO') ||
    codigo.startsWith('DO') ||
    codigo.startsWith('OEC') ||
    codigo.startsWith('PAR') ||
    texto.includes('trânsito') ||
    texto.includes('transito') ||
    texto.includes('encaminhado') ||
    texto.includes('em transporte')
  ) {
    return 'em_transito';
  }
  if (
    texto.includes('não entregue') ||
    texto.includes('nao entregue') ||
    texto.includes('devolv') ||
    texto.includes('ausente') ||
    texto.includes('recusad')
  ) {
    return 'problema';
  }
  return null;
}

// ── PDF DE SIMULAÇÃO ─────────────────────────────────────────────────────

export async function criarPdfSimulado(dados: {
  codigoObjeto: string;
  pedidoId: number;
  servico: string;
  remetente: string;
  destinatario: string;
  endereco: string;
  pesoKg: number;
}): Promise<Uint8Array> {
  const pdf = await PDFDocument.create();
  const pagina = pdf.addPage([595, 842]); // A4
  const fonte = await pdf.embedFont(StandardFonts.Helvetica);
  const fonteNegrito = await pdf.embedFont(StandardFonts.HelveticaBold);
  const { height } = pagina.getSize();

  pagina.drawText('ETIQUETA SIMULADA — CORREIOS', {
    x: 40,
    y: height - 60,
    size: 18,
    font: fonteNegrito,
    color: rgb(0.85, 0.1, 0.1),
  });
  pagina.drawText('MODO DE TESTE (CORREIOS_SIMULACAO=true)', {
    x: 40,
    y: height - 82,
    size: 10,
    font: fonte,
    color: rgb(0.3, 0.3, 0.3),
  });

  const linhas = [
    ['Código do objeto', dados.codigoObjeto],
    ['Pedido', `#${dados.pedidoId}`],
    ['Serviço', dados.servico],
    ['Peso', `${dados.pesoKg.toFixed(2)} kg`],
    ['Remetente', dados.remetente],
    ['Destinatário', dados.destinatario],
    ['Endereço', dados.endereco],
  ];

  let y = height - 130;
  for (const [rotulo, valor] of linhas) {
    pagina.drawText(rotulo, {
      x: 40,
      y,
      size: 9,
      font: fonteNegrito,
      color: rgb(0.2, 0.2, 0.2),
    });
    pagina.drawText(valor, {
      x: 170,
      y,
      size: 11,
      font: fonte,
      color: rgb(0, 0, 0),
      maxWidth: 380,
    });
    y -= 30;
  }

  // Bloco de barras apenas ilustrativo.
  y -= 20;
  for (let i = 0; i < 48; i++) {
    const largura = i % 3 === 0 ? 4 : 2;
    pagina.drawRectangle({
      x: 40 + i * 10,
      y,
      width: largura,
      height: 70,
      color: rgb(0, 0, 0),
    });
  }
  pagina.drawText(dados.codigoObjeto, {
    x: 190,
    y: y - 22,
    size: 14,
    font: fonteNegrito,
    color: rgb(0, 0, 0),
  });

  return new Uint8Array(await pdf.save());
}
