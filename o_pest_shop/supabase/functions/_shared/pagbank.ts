// Cliente da API do PagBank (Orders, chaves públicas e sessão 3DS).
// Docs: https://developer.pagbank.com.br
//
// Variáveis de ambiente (supabase secrets):
//   PAGBANK_TOKEN  — token da conta (produção ou sandbox)
//   PAGBANK_ENV    — 'sandbox' (padrão) ou 'production'

export const PAGBANK_ENV = (Deno.env.get('PAGBANK_ENV') ?? 'sandbox').toLowerCase();
export const IS_PROD = PAGBANK_ENV === 'production';

export function pagbankToken(): string {
  const token = Deno.env.get('PAGBANK_TOKEN');
  if (!token) {
    throw new Error(
      'PAGBANK_TOKEN não configurado nos secrets do Supabase (veja supabase/PAGBANK_SETUP.md).',
    );
  }
  return token;
}

const API_BASE = IS_PROD
  ? 'https://api.pagseguro.com'
  : 'https://sandbox.api.pagseguro.com';

const SDK_BASE = IS_PROD
  ? 'https://sdk.pagseguro.com'
  : 'https://sandbox.sdk.pagseguro.com';

export class PagBankError extends Error {
  status: number;
  detalhes: unknown;
  constructor(message: string, status: number, detalhes: unknown) {
    super(message);
    this.status = status;
    this.detalhes = detalhes;
  }
}

const TIMEOUT_MS = 15_000;
const MAX_TENTATIVAS_GET = 3;

function dormir(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function metodoSeguro(init: RequestInit): boolean {
  const metodo = (init.method ?? 'GET').toUpperCase();
  return metodo === 'GET' || metodo === 'HEAD';
}

export async function pagbankFetch(
  path: string,
  init: RequestInit = {},
): Promise<Record<string, unknown>> {
  const tentativas = metodoSeguro(init) ? MAX_TENTATIVAS_GET : 1;
  let ultimoErro: unknown;

  for (let tentativa = 1; tentativa <= tentativas; tentativa++) {
    try {
      const resp = await fetch(`${API_BASE}${path}`, {
        ...init,
        signal: AbortSignal.timeout(TIMEOUT_MS),
        headers: {
          Authorization: `Bearer ${pagbankToken()}`,
          'Content-Type': 'application/json',
          Accept: 'application/json',
          ...(init.headers ?? {}),
        },
      });
      const texto = await resp.text();
      let corpo: unknown = null;
      try {
        corpo = texto ? JSON.parse(texto) : null;
      } catch {
        corpo = texto;
      }
      if (!resp.ok) {
        const detalhe = corpo as Record<string, unknown> | null;
        const mensagem = (detalhe?.['error_messages'] as Array<Record<string, unknown>> | undefined)
          ?.map((e) => `${e['description'] ?? e['code']}`)
          .join(' • ') ?? `PagBank retornou HTTP ${resp.status}`;

        // 429/5xx em GET são transitórios: tenta novamente com backoff.
        if (tentativa < tentativas && (resp.status === 429 || resp.status >= 500)) {
          ultimoErro = new PagBankError(mensagem, resp.status, corpo);
          await dormir(400 * Math.pow(2, tentativa - 1) + Math.random() * 250);
          continue;
        }
        throw new PagBankError(mensagem, resp.status, corpo);
      }
      return (corpo as Record<string, unknown>) ?? {};
    } catch (erro) {
      ultimoErro = erro;
      const abortado = erro instanceof DOMException &&
        (erro.name === 'TimeoutError' || erro.name === 'AbortError');
      const transitorio = abortado ||
        erro instanceof TypeError ||
        (erro instanceof PagBankError && (erro.status === 429 || erro.status >= 500));
      if (tentativa < tentativas && transitorio) {
        await dormir(400 * Math.pow(2, tentativa - 1) + Math.random() * 250);
        continue;
      }
      if (abortado) {
        throw new PagBankError(
          'O PagBank demorou para responder. Tente novamente em instantes.',
          504,
          { timeout: true },
        );
      }
      throw erro;
    }
  }

  throw ultimoErro instanceof Error
    ? ultimoErro
    : new Error('Falha ao consultar o PagBank.');
}

// ─── Chave pública (criptografia de cartão no navegador) ───────

let chavePublicaCache: string | null = null;

export async function obterChavePublica(): Promise<string> {
  if (chavePublicaCache) return chavePublicaCache;
  try {
    const lista = await pagbankFetch('/public-keys?type=card');
    const chaves = (lista['public_keys'] as Array<Record<string, unknown>> | undefined) ?? [];
    const existente = chaves[0]?.['public_key'] as string | undefined;
    if (existente) {
      chavePublicaCache = existente;
      return existente;
    }
  } catch (_) {
    // Sem chave listável — cria uma abaixo.
  }
  const criada = await pagbankFetch('/public-keys', {
    method: 'POST',
    body: JSON.stringify({ type: 'card' }),
  });
  const publicKey = criada['public_key'] as string | undefined;
  if (!publicKey) {
    throw new PagBankError('Não foi possível obter a chave pública do PagBank', 500, criada);
  }
  chavePublicaCache = publicKey;
  return publicKey;
}

// ─── Sessão 3DS (obrigatória para cartão de débito) ────────────

let sessao3dsCache: { session: string; expiresAt: number } | null = null;

export async function obterSessao3ds(): Promise<string> {
  const agora = Date.now();
  if (sessao3dsCache && sessao3dsCache.expiresAt - 60_000 > agora) {
    return sessao3dsCache.session;
  }
  const resp = await fetch(`${SDK_BASE}/checkout-sdk/sessions`, {
    method: 'POST',
    signal: AbortSignal.timeout(TIMEOUT_MS),
    headers: {
      Authorization: `Bearer ${pagbankToken()}`,
      'Content-Type': 'application/json',
    },
  });
  const texto = await resp.text();
  let corpo: Record<string, unknown> = {};
  try {
    corpo = texto ? JSON.parse(texto) : {};
  } catch {
    corpo = {};
  }
  if (!resp.ok || !corpo['session']) {
    throw new PagBankError('Não foi possível criar a sessão 3DS', resp.status, corpo);
  }
  sessao3dsCache = {
    session: corpo['session'] as string,
    expiresAt: (corpo['expires_at'] as number | undefined) ?? agora + 25 * 60_000,
  };
  return sessao3dsCache.session;
}

// ─── Status do gateway → status interno ────────────────────────

export function mapearStatus(chargeStatus: string): string {
  switch ((chargeStatus ?? '').toUpperCase()) {
    case 'PAID':
      return 'pago';
    case 'IN_ANALYSIS':
      return 'em_analise';
    case 'DECLINED':
      return 'recusado';
    case 'CANCELED':
      return 'cancelado';
    case 'REFUNDED':
    case 'CHARGEBACK':
      return 'estornado';
    case 'AUTHORIZED':
      return 'em_analise';
    case 'WAITING':
      return 'pendente';
    default:
      // Status novo/desconhecido não pode regredir um pagamento já aprovado.
      // Mantém em análise para a conciliação resolver com segurança.
      return 'em_analise';
  }
}

// ─── Extrai o comprovante da resposta do PagBank ───────────────

export function extrairComprovante(order: Record<string, unknown>) {
  const charges = (order['charges'] as Array<Record<string, unknown>> | undefined) ?? [];
  const charge = charges[0] ?? {};
  const metodo = (charge['payment_method'] as Record<string, unknown> | undefined) ?? {};
  const tipo = (metodo['type'] as string | undefined) ?? '';
  const links = (charge['links'] as Array<Record<string, unknown>> | undefined) ?? [];
  const acharLink = (rel: string, media?: string) =>
    links.find((l) => l['rel'] === rel && (!media || l['media'] === media))?.['href'] as
      | string
      | undefined;

  const amount =
    (charge['amount'] as Record<string, unknown> | undefined) ??
    (order['amount'] as Record<string, unknown> | undefined) ??
    {};
  const valorCentavos = Number(amount['value'] ?? 0);

  const comprovante: Record<string, unknown> = {
    gateway_order_id: order['id'] as string | undefined,
    gateway_charge_id: charge['id'] as string | undefined,
    status: mapearStatus((charge['status'] as string | undefined) ?? ''),
    gateway_status: charge['status'],
    payment_response: charge['payment_response'],
    paid_at: charge['paid_at'],
  };
  if (Number.isFinite(valorCentavos) && valorCentavos > 0) {
    comprovante['valor_centavos'] = valorCentavos;
  }

  if (tipo === 'PIX') {
    const qr = (charge['qr_code'] as Record<string, unknown> | undefined) ?? {};
    const pix = (metodo['pix'] as Record<string, unknown> | undefined) ?? {};
    comprovante['pix_copia_cola'] = qr['text'];
    comprovante['pix_qr_image_url'] =
      acharLink('QRCODE.PNG', 'image/png') ??
      acharLink('QRCODE.BASE64')?.replace('/base64', '/png');
    comprovante['pix_e2e_id'] = pix['end_to_end_id'];
    const expiracao = pix['expiration_date'];
    if (expiracao) comprovante['expira_em'] = expiracao;
  }

  if (tipo === 'BOLETO') {
    const boleto = (metodo['boleto'] as Record<string, unknown> | undefined) ?? {};
    comprovante['boleto_linha_digitavel'] =
      (boleto['formatted_barcode'] as string | undefined) ?? boleto['barcode'];
    comprovante['boleto_codigo_barras'] = boleto['barcode'];
    comprovante['boleto_vencimento'] = boleto['due_date'];
    const pdf = links.find((l) => l['media'] === 'application/pdf')?.['href'];
    if (pdf) comprovante['boleto_pdf_url'] = pdf;
  }

  if (tipo === 'CREDIT_CARD' || tipo === 'DEBIT_CARD') {
    const card = (metodo['card'] as Record<string, unknown> | undefined) ?? {};
    comprovante['cartao_bandeira'] = card['brand'];
    comprovante['cartao_last4'] = card['last_digits'];
    const resposta = (charge['payment_response'] as Record<string, unknown> | undefined) ?? {};
    comprovante['cartao_autorizacao'] = resposta['reference'];
    comprovante['cartao_nsu'] = resposta['reference'];
  }

  return { comprovante, charge, metodo, tipo };
}
