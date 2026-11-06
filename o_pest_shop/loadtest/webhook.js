import http from 'k6/http';
import { check } from 'k6';
import { SharedArray } from 'k6/data';

// Formato: um JSON por linha: {"body":"...","signature":"..."}
// Gere os eventos a partir de pagamentos reais de staging. Nunca invente
// charge IDs: o webhook precisa encontrar o pagamento local.
const eventos = new SharedArray('eventos', () => {
  const texto = open(__ENV.WEBHOOK_EVENTS_FILE).trim();
  return texto
    .split(/\r?\n/)
    .filter(Boolean)
    .map((linha) => JSON.parse(linha));
});

const BASE_URL = __ENV.BASE_URL;
const RATE = Number(__ENV.EVENTOS_POR_SEGUNDO || 10);
const DURATION = __ENV.DURATION || '5m';

export const options = {
  scenarios: {
    webhook: {
      executor: 'constant-arrival-rate',
      rate: RATE,
      timeUnit: '1s',
      duration: DURATION,
      preAllocatedVUs: 50,
      maxVUs: 200,
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.05'],
    http_req_duration: ['p(95)<2000'],
  },
};

export default function () {
  const e = eventos[Math.floor(Math.random() * eventos.length)];
  const r = http.post(`${BASE_URL}/functions/v1/pagamentos-webhook`, e.body, {
    headers: {
      'Content-Type': 'application/json',
      'x-authenticity-token': e.signature,
    },
  });
  check(r, {
    'webhook 2xx': (x) => x.status >= 200 && x.status < 300,
  });
}
