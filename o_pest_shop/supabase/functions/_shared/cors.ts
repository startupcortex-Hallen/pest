// CORS restrito aos domínios da loja.
//
// Configure outros domínios com o secret ALLOWED_ORIGINS (separados por vírgula).
// Em desenvolvimento, localhost continua liberado.

const DEFAULT_ORIGINS = [
  'https://startupcortex-hallen.github.io',
  'http://localhost:8080',
  'http://localhost:3000',
  'http://localhost:5000',
  'http://127.0.0.1:8080',
];

export function getCorsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get('Origin') ?? '';
  const permitidos = (Deno.env.get('ALLOWED_ORIGINS') ?? DEFAULT_ORIGINS.join(','))
    .split(',')
    .map((o) => o.trim())
    .filter((o) => o.length > 0);

  const permitido = permitidos.includes(origin) ? origin : permitidos[0] ?? '';
  return {
    'Access-Control-Allow-Origin': permitido,
    'Vary': 'Origin',
    'Access-Control-Allow-Headers':
      'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
  };
}

export function json(
  body: unknown,
  status = 200,
  cors: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}
