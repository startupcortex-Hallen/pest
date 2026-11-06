import { createClient } from 'npm:@supabase/supabase-js@2';
import { getCorsHeaders, json } from '../_shared/cors.ts';
import { adminClient, ML_AUTH, mlCredenciais } from '../_shared/mercadolivre.ts';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;

Deno.serve(async (req) => {
  const cors = getCorsHeaders(req);
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ erro: 'method not allowed' }, 405, cors);

  try {
    const anon = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
      auth: { persistSession: false },
    });
    const { data: auth, error: authError } = await anon.auth.getUser();
    if (authError || !auth.user) {
      return json({ erro: 'Faça login para conectar o Mercado Livre.' }, 401, cors);
    }

    const body = await req.json().catch(() => ({}));
    const unidadeId = Number(body.unidade_id);
    if (!Number.isFinite(unidadeId) || unidadeId <= 0) {
      return json({ erro: 'unidade_id inválido' }, 422, cors);
    }

    const admin = adminClient();
    const { data: perfil } = await admin
      .from('perfis')
      .select('funcao, unidade_id')
      .eq('id', auth.user.id)
      .maybeSingle();

    const pode =
      perfil?.funcao === 'admin' ||
      ((perfil?.funcao === 'gestor' || perfil?.funcao === 'atendente') &&
        Number(perfil?.unidade_id) === unidadeId);
    if (!pode) {
      return json({ erro: 'Sem permissão para esta loja.' }, 403, cors);
    }

    const { data: unidade } = await admin
      .from('unidades')
      .select('id, nome')
      .eq('id', unidadeId)
      .maybeSingle();
    if (!unidade) return json({ erro: 'Loja não encontrada.' }, 404, cors);

    const { clientId, redirectUri } = mlCredenciais();
    const state = crypto.randomUUID();
    const codeVerifier = crypto.randomUUID() + crypto.randomUUID();
    const expira = new Date(Date.now() + 15 * 60 * 1000).toISOString();

    const { error: stateError } = await admin.from('ml_oauth_states').insert({
      state,
      user_id: auth.user.id,
      unidade_id: unidadeId,
      code_verifier: codeVerifier,
      expires_at: expira,
    });
    if (stateError) throw new Error(stateError.message);

    const params = new URLSearchParams({
      response_type: 'code',
      client_id: clientId,
      redirect_uri: redirectUri,
      state,
    });
    if (Deno.env.get('ML_PKCE') === 'true') {
      const hash = await crypto.subtle.digest(
        'SHA-256',
        new TextEncoder().encode(codeVerifier),
      );
      const challenge = btoa(String.fromCharCode(...new Uint8Array(hash)))
        .replace(/\+/g, '-')
        .replace(/\//g, '_')
        .replace(/=+$/, '');
      params.set('code_challenge', challenge);
      params.set('code_challenge_method', 'S256');
    }

    return json(
      {
        url: `${ML_AUTH}?${params.toString()}`,
        unidade_id: unidadeId,
        unidade_nome: unidade.nome,
      },
      200,
      cors,
    );
  } catch (e) {
    return json(
      { erro: e instanceof Error ? e.message : String(e) },
      500,
      cors,
    );
  }
});
