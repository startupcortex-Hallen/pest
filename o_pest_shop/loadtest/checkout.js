import http from 'k6/http';
import { check } from 'k6';
import { SharedArray } from 'k6/data';

const BASE_URL = __ENV.BASE_URL;
const ANON_KEY = __ENV.ANON_KEY;
const PRODUTO_ID = Number(__ENV.PRODUTO_ID || 1);
const UNIDADE_ID = Number(__ENV.UNIDADE_ID || 1);
const RATE = Number(__ENV.PEDIDOS_POR_MINUTO || 50);
const DURATION = __ENV.DURATION || '10m';

// Formato: user_id,token
const usuarios = new SharedArray('usuarios', () => {
  const texto = open(__ENV.USER_TOKENS_FILE).trim();
  return texto.split(/\r?\n/).filter(Boolean).map((linha) => {
    const [id, token] = linha.split(',');
    return { id: id.trim(), token: token.trim() };
  });
});

export const options = {
  scenarios: {
    checkout: {
      executor: 'constant-arrival-rate',
      rate: RATE,
      timeUnit: '1m',
      duration: DURATION,
      preAllocatedVUs: 200,
      maxVUs: 1000,
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<2000'],
    checks: ['rate>0.99'],
  },
};

function uuid() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === 'x' ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

export default function () {
  const u = usuarios[Math.floor(Math.random() * usuarios.length)];
  const headers = {
    apikey: ANON_KEY,
    Authorization: `Bearer ${u.token}`,
    'Content-Type': 'application/json',
  };

  const body = {
    p_user_id: u.id,
    p_itens: [{ produto_id: PRODUTO_ID, quantidade: 1, unidade_id: UNIDADE_ID }],
    p_tipo_entrega: 'retirada',
    p_idempotency_key: uuid(),
  };

  const r = http.post(`${BASE_URL}/rest/v1/rpc/finalizar_checkout_v6`, JSON.stringify(body), {
    headers,
  });

  let pedidos = [];
  if (r.status === 200) {
    try {
      pedidos = JSON.parse(r.body) || [];
    } catch (_) {
      pedidos = [];
    }
  }

  check(r, {
    'checkout 200': (x) => x.status === 200,
    'criou pedido': () => Array.isArray(pedidos) && pedidos.length > 0,
  });

  const ids = Array.isArray(pedidos) ? pedidos.map((p) => p.id) : [];
  if (ids.length > 0) {
    const pagamento = http.post(
      `${BASE_URL}/functions/v1/pagamentos`,
      JSON.stringify({ acao: 'simular', pedido_ids: ids, metodo: 'pix' }),
      { headers },
    );
    check(pagamento, {
      'pagamento simulado 200': (x) => x.status === 200,
    });
  }
}
