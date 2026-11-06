# Testes de carga — O Pest Shop

> **Nunca rode estes testes contra produção.**
> Use um projeto Supabase de staging, PagBank em simulação e dados sintéticos.
> Não faça compras reais em massa.

## Pré-requisitos

- k6 instalado (`https://k6.io`).
- Staging com a migration `20261105120000_hardening_escalabilidade.sql`.
- `catalogo-publico` publicada (`--no-verify-jwt`).
- `SIMULACAO_PAGAMENTO=true` no staging.
- Produto de teste com estoque alto e retirada habilitada.
- Arquivo `tokens.txt` no formato `user_id,token` (um por linha), gerado com
  usuários reais de teste (RLS).

## Ordem obrigatória

| Etapa | VUs | Comando |
|---|---:|---|
| 1 | 50 | `k6 run -e VUS=50 -e DURATION=10m ... catalogo.js` |
| 2 | 100 | `VUS=100` |
| 3 | 300 | `VUS=300` |
| 4 | 500 | `VUS=500` |
| 5 | 2.000 | somente com k6 distribuído/externo |
| 6 | 10.000 | somente com geradores distribuídos |
| 7 | 50.000 | somente com infraestrutura paga e aval de capacidade |

Só avance se a etapa anterior cumprir os critérios do
`docs/RELATORIO_TESTES_CARGA.md`.

## Catálogo

```bash
k6 run \
  -e BASE_URL=https://SEU_STAGING.supabase.co \
  -e ANON_KEY=SUA_ANON_KEY \
  -e VUS=100 \
  -e DURATION=10m \
  loadtest/catalogo.js
```

## Checkout (simulado)

```bash
k6 run \
  -e BASE_URL=https://SEU_STAGING.supabase.co \
  -e ANON_KEY=SUA_ANON_KEY \
  -e USER_TOKENS_FILE=tokens.txt \
  -e PRODUTO_ID=123 \
  -e UNIDADE_ID=1 \
  -e PEDIDOS_POR_MINUTO=50 \
  -e DURATION=10m \
  loadtest/checkout.js
```

O checkout cria pedidos e simula PIX. Zere o staging depois do teste.

## Webhook

O webhook exige payload real/assinatura e um pagamento local existente. Use
`loadtest/webhook.js` apenas com um arquivo de eventos preparado; não invente
charge IDs. Este teste é o último da fila e deve ser feito com o gateway em
sandbox/mock.

## Coleta

- k6: p50/p95/p99, RPS, erros, 429.
- Supabase: CPU/RAM, pooler wait, slow queries, Edge 5xx.
- Cloudflare: cache hit, egress, origem.
- Banco: zero oversell, zero cobrança duplicada, estoque/cupom consistentes.

Preencha a tabela em `docs/RELATORIO_TESTES_CARGA.md` **somente com resultados
reais**.
