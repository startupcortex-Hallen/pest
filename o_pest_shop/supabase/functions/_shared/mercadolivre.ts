import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2';

export const ML_API = 'https://api.mercadolibre.com';
export const ML_AUTH = 'https://auth.mercadolivre.com.br/authorization';

export type Integracao = {
  id: string;
  unidade_id: number;
  plataforma: string;
  ml_user_id: number | null;
  ml_nickname: string | null;
  access_token: string | null;
  refresh_token: string | null;
  token_expira_em: string | null;
  refresh_expira_em: string | null;
  scopes: string | null;
  status: string;
  erro: string | null;
};

export function adminClient(): SupabaseClient {
  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) throw new Error('Supabase service role não configurado');
  return createClient(url, key, { auth: { persistSession: false } });
}

export function mlCredenciais() {
  const clientId = Deno.env.get('ML_CLIENT_ID');
  const clientSecret = Deno.env.get('ML_CLIENT_SECRET');
  const redirectUri = Deno.env.get('ML_REDIRECT_URI');
  if (!clientId || !clientSecret || !redirectUri) {
    throw new Error('Configure ML_CLIENT_ID, ML_CLIENT_SECRET e ML_REDIRECT_URI');
  }
  return { clientId, clientSecret, redirectUri };
}

export async function buscarIntegracao(
  admin: SupabaseClient,
  unidadeId: number,
): Promise<Integracao | null> {
  const { data, error } = await admin
    .from('integracoes_loja')
    .select('*')
    .eq('unidade_id', unidadeId)
    .eq('plataforma', 'mercadolivre')
    .maybeSingle();
  if (error) throw new Error(`Erro ao buscar integração: ${error.message}`);
  return data as Integracao | null;
}

export async function renovarToken(
  admin: SupabaseClient,
  integracao: Integracao,
): Promise<string> {
  if (!integracao.refresh_token) {
    throw new Error('Conta Mercado Livre sem refresh token. Reconecte a loja.');
  }
  const { clientId, clientSecret } = mlCredenciais();
  const body = new URLSearchParams({
    grant_type: 'refresh_token',
    client_id: clientId,
    client_secret: clientSecret,
    refresh_token: integracao.refresh_token,
  });
  const resp = await fetch(`${ML_API}/oauth/token`, {
    method: 'POST',
    headers: {
      accept: 'application/json',
      'content-type': 'application/x-www-form-urlencoded',
    },
    body,
  });
  const json = await resp.json().catch(() => ({}));
  if (!resp.ok || !json.access_token) {
    const msg = json.error_description ?? json.error ?? `HTTP ${resp.status}`;
    await admin
      .from('integracoes_loja')
      .update({ status: 'erro', erro: `Refresh token: ${msg}`, updated_at: new Date().toISOString() })
      .eq('id', integracao.id);
    throw new Error(`Falha ao renovar token do Mercado Livre: ${msg}`);
  }

  const agora = Date.now();
  const expira = new Date(agora + Number(json.expires_in ?? 21600) * 1000).toISOString();
  const refreshExpira = json.refresh_token
    ? new Date(agora + 180 * 24 * 60 * 60 * 1000).toISOString()
    : integracao.refresh_expira_em;

  await admin
    .from('integracoes_loja')
    .update({
      access_token: json.access_token,
      refresh_token: json.refresh_token ?? integracao.refresh_token,
      token_expira_em: expira,
      refresh_expira_em: refreshExpira,
      scopes: json.scope ?? integracao.scopes,
      status: 'conectado',
      erro: null,
      updated_at: new Date().toISOString(),
    })
    .eq('id', integracao.id);

  integracao.access_token = json.access_token;
  integracao.refresh_token = json.refresh_token ?? integracao.refresh_token;
  integracao.token_expira_em = expira;
  return json.access_token;
}

export async function tokenValido(
  admin: SupabaseClient,
  integracao: Integracao,
): Promise<string> {
  if (!integracao.access_token) return renovarToken(admin, integracao);
  const expira = integracao.token_expira_em
    ? new Date(integracao.token_expira_em).getTime()
    : 0;
  if (expira > Date.now() + 5 * 60 * 1000) return integracao.access_token;
  return renovarToken(admin, integracao);
}

export async function mlFetch(
  admin: SupabaseClient,
  integracao: Integracao,
  path: string,
  init: RequestInit = {},
  tentativa = 0,
): Promise<any> {
  const token = await tokenValido(admin, integracao);
  const headers = new Headers(init.headers);
  headers.set('Authorization', `Bearer ${token}`);
  if (!headers.has('accept')) headers.set('accept', 'application/json');
  const resp = await fetch(`${ML_API}${path}`, { ...init, headers });
  if (resp.status === 401 && tentativa === 0) {
    await renovarToken(admin, integracao);
    return mlFetch(admin, integracao, path, init, tentativa + 1);
  }
  const texto = await resp.text();
  const json = texto ? JSON.parse(texto) : {};
  if (!resp.ok) {
    const msg =
      json?.message ??
      json?.error_description ??
      json?.error ??
      `HTTP ${resp.status}`;
    throw new Error(`Mercado Livre ${resp.status}: ${msg}`);
  }
  return json;
}

export function statusPedidoMl(order: any): string {
  const status = String(order?.status ?? '');
  if (status === 'cancelled') return 'cancelado';
  if (status === 'delivered') return 'entregue';
  if (status === 'shipped') return 'saiu_para_entrega';
  if (status === 'paid' || status === 'confirmed') return 'pago';
  return 'pendente';
}
