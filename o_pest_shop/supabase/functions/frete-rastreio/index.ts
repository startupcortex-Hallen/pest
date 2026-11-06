// Edge Function `frete-rastreio` — sincroniza o rastreio dos Correios.
//
// Deploy com --no-verify-jwt e agende no Cron (Supabase > Integrations > Cron)
// a cada 15/30 minutos:
//   POST https://SEU_PROJECT.supabase.co/functions/v1/frete-rastreio
//   Header: x-conciliacao-secret: CONCILIACAO_SECRET
//
// Sem agendamento, o admin ainda pode sincronizar manualmente pelo botão
// "Sincronizar rastreio" no detalhe do pedido.

import { createClient } from 'npm:@supabase/supabase-js@2';
import { json } from '../_shared/cors.ts';
import {
  rastrearCorreios,
  statusEnvioPorEventos,
} from '../_shared/correios.ts';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const SECRET = Deno.env.get('CONCILIACAO_SECRET') ?? '';

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('method not allowed', { status: 405 });
  }
  if (!SECRET) {
    console.error('CONCILIACAO_SECRET não configurado — rastreio recusado.');
    return new Response('configuração ausente', { status: 500 });
  }
  if (req.headers.get('x-conciliacao-secret') !== SECRET) {
    return new Response('não autorizado', { status: 401 });
  }

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
    auth: { persistSession: false },
  });

  const { data: envios, error } = await admin
    .from('envios')
    .select('*')
    .not('codigo_objeto', 'is', null)
    .in('status', [
      'pendente',
      'prepostado',
      'gerada',
      'aguardando_postagem',
      'postado',
      'em_transito',
    ])
    .order('ultima_sincronizacao', { ascending: true, nullsFirst: true })
    .limit(50);

  if (error) {
    return json({ erro: error.message }, 500);
  }

  let atualizados = 0;
  const falhas: Array<{ envio_id: string; erro: string }> = [];

  for (const envio of (envios ?? []) as Array<Record<string, unknown>>) {
    const envioId = String(envio['id']);
    const codigo = String(envio['codigo_objeto'] ?? '');
    if (!codigo) continue;
    const payload = envio['payload'];
    if (
      payload &&
      typeof payload === 'object' &&
      (payload as Record<string, unknown>)['simulacao'] === true
    ) {
      continue;
    }

    try {
      const eventos = await rastrearCorreios(codigo);
      for (const evento of eventos) {
        await admin.from('envio_eventos').upsert(
          {
            envio_id: envioId,
            codigo: evento.codigo,
            tipo: evento.tipo,
            descricao: evento.descricao,
            detalhe: evento.detalhe,
            ocorrido_em: evento.ocorrido_em ?? new Date().toISOString(),
            payload: evento.payload,
          },
          {
            onConflict: 'envio_id,codigo,ocorrido_em',
            ignoreDuplicates: true,
          },
        );
      }

      const status = statusEnvioPorEventos(eventos);
      const agora = new Date().toISOString();
      const atualizacao: Record<string, unknown> = {
        ultima_sincronizacao: agora,
        updated_at: agora,
      };
      if (status) {
        atualizacao['status'] = status;
        atualizacao['status_correios'] = status;
        if (status === 'postado') atualizacao['postado_em'] = agora;
        if (status === 'entregue') atualizacao['entregue_em'] = agora;
      }

      await admin.from('envios').update(atualizacao).eq('id', envioId);

      if (status) {
        const pedidoId = Number(envio['pedido_id']);
        const { data: pedido } = await admin
          .from('pedidos')
          .select('id, status, tipo_entrega')
          .eq('id', pedidoId)
          .maybeSingle();

        if (String(pedido?.['status'] ?? '') === 'cancelado') {
          continue;
        }

        const dadosPedido: Record<string, unknown> = {
          etiqueta_status: status,
          updated_at: agora,
        };
        if (status === 'postado') {
          dadosPedido['status'] = 'postado';
          dadosPedido['postado_em'] = agora;
        } else if (
          status === 'em_transito' &&
          ['pago', 'em_preparo', 'postado'].includes(
            String(pedido?.['status'] ?? ''),
          )
        ) {
          dadosPedido['status'] = 'em_transito';
        } else if (status === 'entregue') {
          dadosPedido['status'] = 'entregue';
          dadosPedido['entregue_em'] = agora;
        }

        await admin.from('pedidos').update(dadosPedido).eq('id', pedidoId);
      }

      atualizados++;
    } catch (e) {
      const mensagem = e instanceof Error
        ? e.message
        : 'Falha ao consultar o rastreio.';
      falhas.push({ envio_id: envioId, erro: mensagem });
      await admin
        .from('envios')
        .update({
          erro: mensagem,
          ultima_sincronizacao: new Date().toISOString(),
        })
        .eq('id', envioId);
    }
  }

  return json({
    ok: true,
    processados: (envios ?? []).length,
    atualizados,
    falhas,
  });
});
