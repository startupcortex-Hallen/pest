import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = __ENV.BASE_URL;
const ANON_KEY = __ENV.ANON_KEY;
const VUS = Number(__ENV.VUS || 50);
const DURATION = __ENV.DURATION || '10m';

export const options = {
  scenarios: {
    catalogo: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: VUS },
        { duration: DURATION, target: VUS },
        { duration: '2m', target: 0 },
      ],
      gracefulRampDown: '30s',
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<800'],
    checks: ['rate>0.99'],
  },
};

const headers = {
  apikey: ANON_KEY,
  Authorization: `Bearer ${ANON_KEY}`,
};

export default function () {
  const requests = [
    http.get(`${BASE_URL}/functions/v1/catalogo-publico`, { headers }),
    http.get(
      `${BASE_URL}/rest/v1/produtos_publicos?select=id,nome,preco,preco_promocional,em_promocao,url_imagem,estoque,unidade_nome&limit=50`,
      { headers },
    ),
    http.get(`${BASE_URL}/rest/v1/categorias?select=id,nome,icone`, { headers }),
    http.get(
      `${BASE_URL}/rest/v1/banners?select=id,titulo,imagem_url,link_url,ordem&ativo=eq.true`,
      { headers },
    ),
  ];

  for (const r of requests) {
    check(r, {
      'status 2xx/304': (x) => x.status === 200 || x.status === 304,
    });
  }

  sleep(5 + Math.random() * 10);
}
