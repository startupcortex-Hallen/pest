// =====================================================================
// O Pest - Shop | Edge Function: mp-create-payment
//
// Cria o pagamento no Mercado Pago (PIX ou cartao tokenizado).
// O ACCESS TOKEN fica SOMENTE aqui (Supabase Secrets) — nunca no app,
// que e um site estatico e inspecionavel.
//
// Secrets necessarios:
//   supabase secrets set MP_ACCESS_TOKEN=TEST-...   (ou APP_USR-... em producao)
//   (SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY ja existem)
//
// Deploy:
//   supabase functions deploy mp-create-payment --no-verify-jwt
//   (o app envia o JWT do usuario; validamos dentro da funcao)
// =====================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
    const mpToken = Deno.env.get('MP_ACCESS_TOKEN');
    if (!mpToken) return json({ error: 'MP_ACCESS_TOKEN nao configurado' }, 500);

    // Cliente no contexto do usuario (RLS aplica): garante que ele so ve o proprio pedido.
    const supabase = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
    });

    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return json({ error: 'Nao autenticado' }, 401);

    const body = await req.json().catch(() => ({}));
    const pedidoId: number | undefined = body.pedido_id;
    const metodo: 'pix' | 'cartao' = body.metodo === 'cartao' ? 'cartao' : 'pix';
    const cardTokenId: string | undefined = body.card_token_id;
    const parcelas: number = Number(body.parcelas ?? 1);
    const payerEmail: string | undefined = body.payer_email ?? user.email ?? undefined;
    const cpf: string | undefined = body.cpf;

    if (!pedidoId) return json({ error: 'pedido_id obrigatorio' }, 400);
    if (metodo === 'cartao' && !cardTokenId) return json({ error: 'card_token_id obrigatorio' }, 400);

    // Total REAL: vem do banco, nunca do app.
    const { data: pedido, error: errPedido } = await supabase
      .from('pedidos')
      .select('id, total, status, user_id, tipo_entrega, endereco_entrega')
      .eq('id', pedidoId)
      .maybeSingle();

    if (errPedido || !pedido) return json({ error: 'Pedido nao encontrado' }, 404);
    if (pedido.user_id !== user.id) return json({ error: 'Pedido de outro usuario' }, 403);
    if (pedido.status !== 'pendente') return json({ error: 'Pedido ja processado' }, 409);

    const valor = Number(pedido.total);
    if (!(valor > 0)) return json({ error: 'Valor do pedido invalido' }, 400);

    const notaFiscal = {
      transaction_amount: Number(valor.toFixed(2)),
      external_reference: String(pedido.id),
      notification_url: `${supabaseUrl}/functions/v1/mp-webhook`,
      description: `Pedido #${pedido.id} - O Pest Shop`,
      payer: {
        email: payerEmail,
        ...(cpf ? { identification: { type: 'CPF', number: cpf.replace(/\D/g, '') } } : {}),
      },
    };

    const payload = metodo === 'pix'
      ? { ...notaFiscal, payment_method_id: 'pix' }
      : {
          ...notaFiscal,
          token: cardTokenId,
          installments: parcelas > 0 ? parcelas : 1,
          payment_method_id: 'credit_card',
        };

    const mpRes = await fetch('https://api.mercadopago.com/v1/payments', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${mpToken}`,
        // Evita cobranca duplicada se o app reenviar a mesma requisicao.
        'X-Idempotency-Key': `pedido-${pedido.id}-${metodo}`,
      },
      body: JSON.stringify(payload),
    });

    const mp = await mpRes.json();

    if (!mpRes.ok) {
      return json({ error: mp?.message ?? 'Falha ao criar pagamento', detalhe: mp }, 400);
    }

    const dados = mp?.point_of_interaction?.transaction_data ?? {};

    // Registra a tentativa no pedido (sem mudar status: quem muda e o webhook).
    await supabase.from('pedidos').update({
      transacao_id: String(mp.id),
      pagamento: metodo === 'pix' ? 'pix' : 'cartao',
      pagamento_detalhes: mp.status,
    }).eq('id', pedido.id);

    return json({
      payment_id: mp.id,
      status: mp.status,
      status_detail: mp.status_detail,
      metodo,
      pix_qr_code: dados.qr_code ?? null,
      pix_qr_code_base64: dados.qr_code_base64 ?? null,
      ticket_url: dados.ticket_url ?? null,
    });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
