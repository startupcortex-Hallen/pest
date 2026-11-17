import { createClient } from 'npm:@supabase/supabase-js@2';
import { getCorsHeaders, json } from '../_shared/cors.ts';
import {
  adminClient,
  mapMpStatus,
  mpFetch,
  periodicidadeDoPlano,
  sincronizarPreapproval,
} from '../_shared/mercadopago.ts';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;

function erro(mensagem: string, status = 400, cors = {}) {
  return json({ erro: mensagem }, status, cors);
}

Deno.serve(async (req) => {
  const cors = getCorsHeaders(req);
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return erro('method not allowed', 405, cors);

  try {
    const anon = createClient(SUPABASE_URL, ANON_KEY, {
      global: {
        headers: { Authorization: req.headers.get('Authorization') ?? '' },
      },
      auth: { persistSession: false },
    });
    const { data: auth, error: authError } = await anon.auth.getUser();
    if (authError || !auth.user) {
      return erro('Faça login para gerenciar sua assinatura.', 401, cors);
    }

    const admin = adminClient();
    const body = await req.json().catch(() => ({}));
    const action = String(body.action ?? 'status');

    const { data: perfil } = await admin
      .from('perfis')
      .select('nome, email')
      .eq('id', auth.user.id)
      .maybeSingle();
    const email = auth.user.email ?? perfil?.email ?? '';

    if (action === 'assinar') {
      const planId = String(body.plan_id ?? '');
      if (!planId) return erro('Plano inválido.', 422, cors);

      const { data: plano, error: planoError } = await admin
        .from('streaming_plans')
        .select('*')
        .eq('id', planId)
        .eq('ativo', true)
        .maybeSingle();
      if (planoError) throw new Error(planoError.message);
      if (!plano) return erro('Plano não encontrado ou inativo.', 404, cors);
      if (Number(plano.preco_centavos) <= 0) {
        return erro(
          'Este plano ainda não tem preço configurado. Avise o administrador.',
          422,
          cors,
        );
      }
      if (!email) {
        return erro(
          'Sua conta precisa ter um e-mail válido para assinar.',
          422,
          cors,
        );
      }

      const { data: atuais, error: atualError } = await admin
        .from('streaming_subscriptions')
        .select('*')
        .eq('user_id', auth.user.id)
        .in('status', ['pendente', 'ativa', 'pausada', 'inadimplente'])
        .order('created_at', { ascending: false })
        .limit(1);
      if (atualError) throw new Error(atualError.message);

      const atual = atuais?.[0];
      if (atual?.status === 'ativa') {
        return json(
          {
            erro: 'Você já possui uma assinatura ativa.',
            assinatura: atual,
          },
          409,
          cors,
        );
      }
      if (atual?.status === 'pausada' || atual?.status === 'inadimplente') {
        return json(
          {
            erro: 'Sua assinatura precisa ser regularizada no Mercado Pago.',
            assinatura: atual,
          },
          409,
          cors,
        );
      }
      if (atual?.status === 'pendente') {
        if (atual.plan_id === plano.id && atual.init_point) {
          return json(
            {
              assinatura: atual,
              init_point: atual.init_point,
              reaproveitada: true,
            },
            200,
            cors,
          );
        }
        if (atual.preapproval_id) {
          try {
            await mpFetch(`/preapproval/${atual.preapproval_id}`, {
              method: 'PUT',
              body: JSON.stringify({ status: 'cancelled' }),
            });
          } catch (e) {
            console.warn('mp-subscription: falha ao cancelar pendente', e);
          }
        }
        await admin
          .from('streaming_subscriptions')
          .update({
            status: 'cancelada',
            updated_at: new Date().toISOString(),
            last_sync_at: new Date().toISOString(),
          })
          .eq('id', atual.id);
      }

      const recorrencia = periodicidadeDoPlano(plano.periodo);
      const autoRecurring: Record<string, unknown> = {
        ...recorrencia,
        transaction_amount: Number(plano.preco_centavos) / 100,
        currency_id: 'BRL',
      };
      if (Number(plano.trial_dias) > 0) {
        autoRecurring.free_trial = {
          frequency: Number(plano.trial_dias),
          frequency_type: 'days',
        };
      }

      const preapproval = await mpFetch('/preapproval', {
        method: 'POST',
        body: JSON.stringify({
          reason: `O Pest+ - ${plano.nome}`,
          external_reference: `${auth.user.id}|${plano.id}`,
          payer_email: email,
          back_url:
            Deno.env.get('MP_BACK_URL') ?? 'https://opest.com.br/assinatura',
          status: 'pending',
          auto_recurring: autoRecurring,
        }),
      });

      const preapprovalId = String(preapproval.id ?? '');
      const initPoint = String(preapproval.init_point ?? '');
      if (!preapprovalId || !initPoint) {
        throw new Error('Mercado Pago não retornou o link de pagamento.');
      }

      const agora = new Date().toISOString();
      const { data: criada, error: insertError } = await admin
        .from('streaming_subscriptions')
        .insert({
          user_id: auth.user.id,
          plan_id: plano.id,
          gateway: 'mercadopago',
          status: mapMpStatus(preapproval.status),
          plan_nome: plano.nome,
          plan_nivel: plano.nivel,
          preco_centavos: plano.preco_centavos,
          periodo: plano.periodo,
          preapproval_id: preapprovalId,
          init_point: initPoint,
          payer_email: email,
          started_at: null,
          current_period_end: null,
          last_sync_at: agora,
          updated_at: agora,
        })
        .select()
        .single();
      if (insertError) throw new Error(insertError.message);

      await admin.from('streaming_subscription_events').insert({
        subscription_id: criada.id,
        user_id: auth.user.id,
        tipo: 'criacao',
        status: criada.status,
        payload: preapproval,
      });

      return json(
        { assinatura: criada, init_point: initPoint },
        200,
        cors,
      );
    }

    if (action === 'status') {
      const { data: assinaturas, error } = await admin
        .from('streaming_subscriptions')
        .select('*')
        .eq('user_id', auth.user.id)
        .order('created_at', { ascending: false })
        .limit(1);
      if (error) throw new Error(error.message);
      const assinatura = assinaturas?.[0];
      if (!assinatura) return json({ assinatura: null }, 200, cors);

      if (assinatura.preapproval_id) {
        try {
          const preapproval = await mpFetch(
            `/preapproval/${assinatura.preapproval_id}`,
          );
          await sincronizarPreapproval(admin, assinatura, preapproval);
        } catch (e) {
          console.error('mp-subscription: falha ao sincronizar', e);
        }
      }

      const { data: atualizada } = await admin
        .from('streaming_subscriptions')
        .select('*')
        .eq('id', assinatura.id)
        .maybeSingle();
      return json({ assinatura: atualizada }, 200, cors);
    }

    if (action === 'cancelar') {
      const { data: assinaturas, error } = await admin
        .from('streaming_subscriptions')
        .select('*')
        .eq('user_id', auth.user.id)
        .in('status', ['pendente', 'ativa', 'pausada', 'inadimplente'])
        .order('created_at', { ascending: false })
        .limit(1);
      if (error) throw new Error(error.message);
      const assinatura = assinaturas?.[0];
      if (!assinatura) {
        return erro('Nenhuma assinatura ativa encontrada.', 404, cors);
      }

      if (assinatura.preapproval_id) {
        await mpFetch(`/preapproval/${assinatura.preapproval_id}`, {
          method: 'PUT',
          body: JSON.stringify({ status: 'cancelled' }),
        });
      }

      const agora = new Date().toISOString();
      const { data: atualizada, error: updateError } = await admin
        .from('streaming_subscriptions')
        .update({
          status: 'cancelada',
          cancel_at_period_end: true,
          last_sync_at: agora,
          updated_at: agora,
        })
        .eq('id', assinatura.id)
        .select()
        .single();
      if (updateError) throw new Error(updateError.message);

      await admin.from('streaming_subscription_events').insert({
        subscription_id: assinatura.id,
        user_id: auth.user.id,
        tipo: 'cancelamento',
        status: 'cancelada',
        payload: {},
      });

      return json({ ok: true, assinatura: atualizada }, 200, cors);
    }

    return erro('Ação inválida.', 422, cors);
  } catch (e) {
    console.error('mp-subscription:', e);
    return erro(
      e instanceof Error ? e.message : 'Erro inesperado na assinatura.',
      500,
      cors,
    );
  }
});
