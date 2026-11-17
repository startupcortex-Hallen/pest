import {
  adminClient,
  dataIso,
  mpFetch,
  sincronizarPreapproval,
} from '../_shared/mercadopago.ts';

async function assinaturaValida(
  req: Request,
  dataId: string,
): Promise<boolean> {
  const secret = Deno.env.get('MP_WEBHOOK_SECRET');
  if (!secret) {
    console.warn('mp-webhook: MP_WEBHOOK_SECRET não configurado; assinatura não validada.');
    return true;
  }

  const assinatura = req.headers.get('x-signature') ?? '';
  const requestId = req.headers.get('x-request-id') ?? '';
  const partes = assinatura.split(',').reduce<Record<string, string>>(
    (acc, item) => {
      const [chave, valor] = item.split('=');
      if (chave && valor) acc[chave.trim()] = valor.trim();
      return acc;
    },
    {},
  );

  const ts = partes.ts;
  const v1 = partes.v1;
  if (!ts || !v1) return false;

  const manifest = `id:${dataId};request-id:${requestId};ts:${ts};`;
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const assinaturaBytes = await crypto.subtle.sign(
    'HMAC',
    key,
    encoder.encode(manifest),
  );
  const esperado = [...new Uint8Array(assinaturaBytes)]
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');

  return esperado.toLowerCase() === v1.toLowerCase();
}

Deno.serve(async (req) => {
  if (req.method !== 'POST' && req.method !== 'GET') {
    return new Response('ok');
  }

  try {
    const url = new URL(req.url);
    const raw = req.method === 'POST' ? await req.text() : '';
    const body = raw ? JSON.parse(raw) : {};
    const topic = String(
      body.type ?? body.topic ?? url.searchParams.get('topic') ?? '',
    );
    const dataId = String(
      body?.data?.id ?? body.resource ?? url.searchParams.get('id') ?? '',
    );

    if (!topic) {
      return new Response(JSON.stringify({ ok: true, ignorado: true }), {
        status: 200,
        headers: { 'content-type': 'application/json' },
      });
    }

    if (dataId && !(await assinaturaValida(req, dataId))) {
      return new Response(JSON.stringify({ ok: false, erro: 'assinatura inválida' }), {
        status: 401,
        headers: { 'content-type': 'application/json' },
      });
    }

    const admin = adminClient();

    if (
      dataId &&
      (topic === 'preapproval' ||
        topic === 'subscription_preapproval' ||
        topic === 'preapproval.created' ||
        topic === 'preapproval.updated')
    ) {
      const preapproval = await mpFetch(`/preapproval/${dataId}`);
      const { data: assinaturas, error } = await admin
        .from('streaming_subscriptions')
        .select('*')
        .eq('preapproval_id', dataId)
        .limit(1);
      if (error) throw new Error(error.message);
      const assinatura = assinaturas?.[0];
      if (!assinatura) {
        console.warn('mp-webhook: assinatura não encontrada', dataId);
        return new Response(JSON.stringify({ ok: true, ignorado: true }), {
          status: 200,
          headers: { 'content-type': 'application/json' },
        });
      }

      await sincronizarPreapproval(admin, assinatura, preapproval);
      return new Response(JSON.stringify({ ok: true }), {
        status: 200,
        headers: { 'content-type': 'application/json' },
      });
    }

    if (dataId && topic === 'payment') {
      const pagamento = await mpFetch(`/v1/payments/${dataId}`);
      const referencia = String(pagamento.external_reference ?? '');
      const userId = referencia.split('|')[0];
      if (userId) {
        const { data: assinaturas } = await admin
          .from('streaming_subscriptions')
          .select('*')
          .eq('user_id', userId)
          .order('created_at', { ascending: false })
          .limit(1);
        const assinatura = assinaturas?.[0];
        if (assinatura) {
          const agora = new Date().toISOString();
          const statusPagamento = String(pagamento.status ?? '');
          const status =
            statusPagamento === 'approved'
              ? 'ativa'
              : statusPagamento === 'rejected' ||
                  statusPagamento === 'cancelled'
                ? 'inadimplente'
                : assinatura.status;
          await admin
            .from('streaming_subscriptions')
            .update({
              status,
              last_payment_at:
                dataIso(pagamento.date_approved) ??
                dataIso(pagamento.date_created) ??
                agora,
              started_at:
                status === 'ativa'
                  ? (assinatura.started_at ?? agora)
                  : assinatura.started_at,
              last_sync_at: agora,
              updated_at: agora,
            })
            .eq('id', assinatura.id);
          await admin.from('streaming_subscription_events').insert({
            subscription_id: assinatura.id,
            user_id: userId,
            tipo: 'pagamento',
            status,
            payload: pagamento,
          });
        }
      }
      return new Response(JSON.stringify({ ok: true }), {
        status: 200,
        headers: { 'content-type': 'application/json' },
      });
    }

    return new Response(JSON.stringify({ ok: true, ignorado: true }), {
      status: 200,
      headers: { 'content-type': 'application/json' },
    });
  } catch (e) {
    console.error('mp-webhook:', e);
    return new Response(
      JSON.stringify({ ok: false, erro: e instanceof Error ? e.message : 'erro' }),
      { status: 500, headers: { 'content-type': 'application/json' } },
    );
  }
});
