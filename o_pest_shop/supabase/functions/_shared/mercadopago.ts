import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2';

export const MP_API = 'https://api.mercadopago.com';

export function adminClient(): SupabaseClient {
  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) throw new Error('Supabase service role não configurado');
  return createClient(url, key, { auth: { persistSession: false } });
}

export function mpToken(): string {
  const token = Deno.env.get('MP_ACCESS_TOKEN');
  if (!token) {
    throw new Error('Configure o secret MP_ACCESS_TOKEN do Mercado Pago.');
  }
  return token;
}

export async function mpFetch(
  path: string,
  init: RequestInit = {},
): Promise<Record<string, unknown>> {
  const resp = await fetch(`${MP_API}${path}`, {
    ...init,
    headers: {
      accept: 'application/json',
      'content-type': 'application/json',
      Authorization: `Bearer ${mpToken()}`,
      ...(init.headers ?? {}),
    },
  });
  const data = await resp.json().catch(() => ({}));
  if (!resp.ok) {
    const mensagem =
      (data as Record<string, unknown>).message ??
      (data as Record<string, unknown>).error ??
      `HTTP ${resp.status}`;
    throw new Error(`Mercado Pago: ${String(mensagem)}`);
  }
  return data as Record<string, unknown>;
}

export function mapMpStatus(status: unknown): string {
  switch (String(status ?? '').toLowerCase()) {
    case 'authorized':
      return 'ativa';
    case 'paused':
      return 'pausada';
    case 'cancelled':
    case 'canceled':
      return 'cancelada';
    case 'expired':
      return 'expirada';
    case 'pending':
      return 'pendente';
    default:
      return 'pendente';
  }
}

export function periodoMeses(periodo: unknown): number {
  return String(periodo ?? 'mensal') === 'anual' ? 12 : 1;
}

export function dataIso(valor: unknown): string | null {
  if (valor == null || valor === '') return null;
  const data = new Date(String(valor));
  return Number.isNaN(data.getTime()) ? null : data.toISOString();
}

export type AssinaturaDb = {
  id: string;
  user_id: string;
  plan_id: string;
  status: string;
  preapproval_id: string | null;
  plan_nome: string | null;
  plan_nivel: number | null;
};

export async function sincronizarPreapproval(
  admin: SupabaseClient,
  assinatura: AssinaturaDb,
  preapproval: Record<string, unknown>,
): Promise<void> {
  const status = mapMpStatus(preapproval.status);
  const auto = (preapproval.auto_recurring ?? {}) as Record<string, unknown>;
  const proximoPagamento = dataIso(
    preapproval.next_payment_date ?? auto.end_date,
  );
  const inicio = dataIso(preapproval.date_created);
  const agora = new Date().toISOString();

  await admin
    .from('streaming_subscriptions')
    .update({
      status,
      started_at: status === 'ativa' ? (inicio ?? agora) : null,
      current_period_end: proximoPagamento,
      cancel_at_period_end: status === 'cancelada',
      last_sync_at: agora,
      updated_at: agora,
    })
    .eq('id', assinatura.id);

  await admin.from('streaming_subscription_events').insert({
    subscription_id: assinatura.id,
    user_id: assinatura.user_id,
    tipo: 'sincronizacao',
    status,
    payload: preapproval,
  });
}

export function periodicidadeDoPlano(periodo: unknown): {
  frequency: number;
  frequency_type: string;
} {
  return {
    frequency: periodoMeses(periodo),
    frequency_type: 'months',
  };
}
