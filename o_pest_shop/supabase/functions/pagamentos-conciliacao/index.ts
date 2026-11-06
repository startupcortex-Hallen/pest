// Conciliação automática de pagamentos pendentes.
//
// Chamada por um agendador (Supabase Cron / pg_cron + pg_net) com o header
// x-conciliacao-secret. Consulta no PagBank as cobranças pendentes e aplica
// o comprovante usando a mesma trilha do webhook (idempotente).
//
// Deploy:
//   supabase functions deploy pagamentos-conciliacao --no-verify-jwt
//   supabase secrets set CONCILIACAO_SECRET=um-segredo-longo
//
// Agende, por exemplo, a cada 2 minutos:
//   POST https://SEU_PROJECT.supabase.co/functions/v1/pagamentos-conciliacao
//   Header: x-conciliacao-secret: <segredo>

import { createClient } from 'npm:@supabase/supabase-js@2';
import { extrairComprovante, pagbankFetch } from '../_shared/pagbank.ts';
import { aplicarComprovante } from '../_shared/pagamentos_db.ts';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const CONCILIACAO_SECRET = Deno.env.get('CONCILIACAO_SECRET') ?? '';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-conciliacao-secret',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}

type PagamentoPendente = {
  id: number;
  status: string;
  gateway: string | null;
  gateway_order_id: string | null;
  gateway_dados: Record<string, unknown> | null;
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ erro: 'Método não permitido.' }, 405);

  if (!CONCILIACAO_SECRET) {
    return json({ erro: 'CONCILIACAO_SECRET não configurado.' }, 500);
  }
  if (req.headers.get('x-conciliacao-secret') !== CONCILIACAO_SECRET) {
    return json({ erro: 'Não autorizado.' }, 401);
  }

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
    auth: { persistSession: false },
  });

  const umMinutoAtras = new Date(Date.now() - 60_000).toISOString();
  const { data, error } = await admin
    .from('pagamentos')
    .select('id, status, gateway, gateway_order_id, gateway_dados')
    .in('status', ['pendente', 'em_analise'])
    .not('gateway_order_id', 'is', null)
    .lt('created_at', umMinutoAtras)
    .order('created_at', { ascending: true })
    .limit(100);

  if (error) {
    console.error('conciliação: falha ao listar pagamentos', error);
    return json({ erro: 'Falha ao listar pagamentos pendentes.' }, 500);
  }

  let consultados = 0;
  let atualizados = 0;
  let ignorados = 0;
  let falhas = 0;

  for (const raw of (data ?? []) as PagamentoPendente[]) {
    if (raw.gateway === 'simulacao' || raw.gateway_dados?.['simulado'] === true) {
      ignorados++;
      continue;
    }
    if (!raw.gateway_order_id) {
      ignorados++;
      continue;
    }

    consultados++;
    try {
      const order = await pagbankFetch(`/orders/${raw.gateway_order_id}`);
      const { comprovante } = extrairComprovante(order);
      if (!comprovante['status'] || comprovante['status'] === raw.status) {
        continue;
      }
      await aplicarComprovante(admin, raw.id, comprovante);
      atualizados++;
    } catch (e) {
      falhas++;
      console.error(`conciliação: falha no pagamento #${raw.id}`, e);
    }
  }

  return json({
    ok: true,
    consultados,
    atualizados,
    ignorados,
    falhas,
    executado_em: new Date().toISOString(),
  });
});
