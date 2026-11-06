import { adminClient } from '../_shared/mercadolivre.ts';

// O Mercado Livre exige resposta 200 em menos de 500 ms. Aqui apenas
// registramos o evento; o processamento pesado fica em ml-process-events.
Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('ok');
  try {
    const raw = await req.text();
    const evento = raw ? JSON.parse(raw) : {};
    const topic = String(evento.topic ?? '');
    const resource = String(evento.resource ?? '');
    if (!topic || !resource) {
      return new Response(JSON.stringify({ ok: false }), {
        status: 200,
        headers: { 'content-type': 'application/json' },
      });
    }

    if (Deno.env.get('ML_APP_ID')) {
      const appId = String(evento.application_id ?? '');
      if (appId && appId !== Deno.env.get('ML_APP_ID')) {
        console.warn('ml-webhook: application_id inesperado', appId);
        return new Response(JSON.stringify({ ok: true, ignorado: true }), {
          status: 200,
          headers: { 'content-type': 'application/json' },
        });
      }
    }

    const admin = adminClient();
    const { error } = await admin.from('ml_eventos').insert({
      topic,
      resource,
      ml_user_id: evento.user_id ? Number(evento.user_id) : null,
      application_id: evento.application_id ? Number(evento.application_id) : null,
      payload: evento,
      status: 'pendente',
    });
    if (error) throw error;

    return new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { 'content-type': 'application/json' },
    });
  } catch (e) {
    console.error('ml-webhook:', e);
    // Mesmo em erro de parse devolvemos 200 para o ML não desativar o tópico.
    return new Response(JSON.stringify({ ok: false }), {
      status: 200,
      headers: { 'content-type': 'application/json' },
    });
  }
});
