# Relatório de Testes de Carga — O Pest Shop

> **Status: PLANO CRIADO, TESTES DE CARGA NÃO EXECUTADOS.**
> Nenhum número abaixo deve ser tratado como capacidade comprovada.

## 1. Regras

- Nunca executar carga pesada na produção.
- Nunca gerar compras reais em massa.
- Usar staging com o mesmo schema/plano e PagBank em simulação.
- Começar em 50 usuários e só avançar se os critérios passarem.
- 2.000+ somente com geradores externos (k6 distribuído/Grafana Cloud k6).
- 50.000 somente com infraestrutura paga dimensionada e aval de capacidade.

## 2. Ambiente

- Supabase staging (Free para 50–500; Pro/Team para 2k+).
- Seed: 1.000–5.000 produtos, 50.000 usuários de teste, endereços válidos.
- Tokens de teste reais (RLS), gerados previamente; não fazer login no meio do
  teste para não medir Auth.
- PagBank sandbox ou mock local; `SIMULACAO_PAGAMENTO=true` no staging.
- Cloudflare/CDN configurado como produção.
- Métricas abertas: Supabase (CPU/RAM/pooler/slow queries), Cloudflare
  (cache hit/egress), Edge logs, PagBank, Sentry.

## 3. Cenários e critérios

| Cenário | Carga | Duração | Critério de aceite |
|---|---:|---:|---|
| Catálogo | 50 VUs | 10 min | p95 < 800ms; erro < 1% |
| Catálogo | 100 VUs | 10 min | idem |
| Catálogo | 300 VUs | 10 min | idem |
| Catálogo | 500 VUs | 10 min | idem; cache hit > 90% |
| Catálogo | 2.000 VUs | 15 min | idem; origem estável |
| Catálogo | 10.000 VUs | 15 min | somente externo; erro < 1% |
| Catálogo | 50.000 VUs | 20 min | somente com infra paga; não presumir |
| Checkout | 50 pedidos/min | 10 min | p95 < 2s; zero oversell |
| Checkout | 300 pedidos/min | 10 min | idem |
| Checkout | 5.000 pedidos/min | 15 min | somente infra paga; zero duplicidade |
| Webhook | 100 eventos/s | 5 min | drenagem < 2 min; idempotente |
| Falhas | PagBank 500/timeout | 10 min | retry/backoff; sem perda |

## 4. Scripts

Os scripts estão em `loadtest/`:

- `loadtest/catalogo.js`: home/catálogo (Edge + PostgREST público).
- `loadtest/checkout.js`: RPC de checkout + função de pagamento em simulação.
- `loadtest/webhook.js`: reenvio de payloads sintéticos com assinatura.
- `loadtest/README.md`: como executar 50/100/300/500/2k/10k/50k.

Exemplo:

```bash
k6 run -e BASE_URL=https://SEU_STAGING.supabase.co \
       -e ANON_KEY=... \
       -e USER_TOKENS_FILE=tokens.txt \
       loadtest/catalogo.js
```

## 5. Resultados (preencher somente após execução)

| Teste | RPS | p50 | p95 | p99 | Erros | 429 | Cache hit | DB CPU | Observações |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| 50 VUs | — | — | — | — | — | — | — | — | não executado |
| 100 VUs | — | — | — | — | — | — | — | — | não executado |
| 300 VUs | — | — | — | — | — | — | — | — | não executado |
| 500 VUs | — | — | — | — | — | — | — | — | não executado |
| 2.000 VUs | — | — | — | — | — | — | — | — | não executado |
| 10.000 VUs | — | — | — | — | — | — | — | — | não executado |
| 50.000 VUs | — | — | — | — | — | — | — | — | não executado |

## 6. Go/No-Go

Aprovado somente se:

- [ ] Zero oversell e zero cobrança duplicada em todos os testes.
- [ ] p95 catálogo < 800ms e checkout < 2s nos volumes aprovados.
- [ ] Erro < 1%; sem 429/5xx em cascata.
- [ ] DB < 70% CPU/RAM; pooler wait < 50ms.
- [ ] Webhook < 2 min; conciliação sem perda.
- [ ] Backup externo restaurável.
- [ ] Capacidade declarada por escrito e compatível com o volume prometido.
