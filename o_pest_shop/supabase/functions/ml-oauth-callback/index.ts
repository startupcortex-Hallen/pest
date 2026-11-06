import { adminClient, ML_API, mlCredenciais } from '../_shared/mercadolivre.ts';

function html(mensagem: string, ok: boolean): Response {
  const cor = ok ? '#00A650' : '#F23D4F';
  return new Response(
    `<!doctype html><html lang="pt-BR"><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title>O Pest × Mercado Livre</title></head>
    <body style="font-family:system-ui;background:#0A0A0A;color:#EDEDED;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0">
      <div style="max-width:420px;padding:32px;text-align:center">
        <div style="font-size:48px">${ok ? '✅' : '⚠️'}</div>
        <h1 style="color:${cor}">${ok ? 'Mercado Livre conectado' : 'Não foi possível conectar'}</h1>
        <p style="color:#C6C6C6">${mensagem}</p>
        <p style="color:#9C9C9C;font-size:13px">Você já pode fechar esta aba e voltar para o painel do O Pest.</p>
      </div>
    </body></html>`,
    {
      status: ok ? 200 : 400,
      headers: { 'Content-Type': 'text/html; charset=utf-8' },
    },
  );
}

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const code = url.searchParams.get('code');
  const state = url.searchParams.get('state');
  const erro = url.searchParams.get('error');

  if (erro) return html(`O Mercado Livre retornou: ${erro}`, false);
  if (!code || !state) return html('Código de autorização ausente.', false);

  try {
    const admin = adminClient();
    const { data: pendente, error } = await admin
      .from('ml_oauth_states')
      .select('*')
      .eq('state', state)
      .maybeSingle();
    if (error) throw new Error(error.message);
    if (!pendente) return html('Estado de autorização inválido ou já utilizado.', false);
    if (new Date(pendente.expires_at).getTime() < Date.now()) {
      await admin.from('ml_oauth_states').delete().eq('id', pendente.id);
      return html('A autorização expirou. Tente conectar novamente.', false);
    }

    const { clientId, clientSecret, redirectUri } = mlCredenciais();
    const body = new URLSearchParams({
      grant_type: 'authorization_code',
      client_id: clientId,
      client_secret: clientSecret,
      code,
      redirect_uri: redirectUri,
    });
    if (pendente.code_verifier && Deno.env.get('ML_PKCE') === 'true') {
      body.set('code_verifier', pendente.code_verifier);
    }

    const tokenResp = await fetch(`${ML_API}/oauth/token`, {
      method: 'POST',
      headers: {
        accept: 'application/json',
        'content-type': 'application/x-www-form-urlencoded',
      },
      body,
    });
    const token = await tokenResp.json().catch(() => ({}));
    if (!tokenResp.ok || !token.access_token) {
      throw new Error(
        token.error_description ?? token.error ?? `HTTP ${tokenResp.status}`,
      );
    }

    const userResp = await fetch(`${ML_API}/users/me`, {
      headers: { Authorization: `Bearer ${token.access_token}` },
    });
    const mlUser = await userResp.json().catch(() => ({}));
    if (!userResp.ok) {
      throw new Error(mlUser.message ?? `HTTP ${userResp.status}`);
    }

    const agora = Date.now();
    const tokenExpira = new Date(
      agora + Number(token.expires_in ?? 21600) * 1000,
    ).toISOString();
    const refreshExpira = new Date(
      agora + 180 * 24 * 60 * 60 * 1000,
    ).toISOString();

    const { error: upsertError } = await admin.from('integracoes_loja').upsert(
      {
        unidade_id: pendente.unidade_id,
        plataforma: 'mercadolivre',
        ml_user_id: mlUser.id ?? token.user_id ?? null,
        ml_nickname: mlUser.nickname ?? mlUser.email ?? null,
        access_token: token.access_token,
        refresh_token: token.refresh_token ?? null,
        token_expira_em: tokenExpira,
        refresh_expira_em: refreshExpira,
        scopes: token.scope ?? null,
        status: 'conectado',
        erro: null,
        connected_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      },
      { onConflict: 'unidade_id' },
    );
    if (upsertError) throw new Error(upsertError.message);

    await admin.from('ml_oauth_states').delete().eq('id', pendente.id);

    return html(
      `Loja conectada como <strong>${mlUser.nickname ?? mlUser.email ?? mlUser.id}</strong>.`,
      true,
    );
  } catch (e) {
    console.error('ml-oauth-callback:', e);
    return html(e instanceof Error ? e.message : String(e), false);
  }
});
