# Arquitetura de Alto Tráfego — O Pest Shop

> Objetivo: absorver 10.000–50.000 visitantes de campanha **sem** mandar cada
> visitante ao PostgreSQL, mantendo o Supabase Free como motor de negócio.
> Isso é uma arquitetura de **mitigação**, não uma promessa de capacidade.

## 1. Camadas

```
Visitante (Web/Android)
        │
        ▼
Cloudflare (DNS, CDN, WAF, rate limit, cache)
        │
        ├── Flutter Web / assets ───────────────► Cloudflare Pages (cache global)
        ├── Catálogo JSON ─────────────────────► Cloudflare Cache
        │        └── origem: Edge Function catalogo-publico
        ├── Imagens públicas ──────────────────► Cloudflare Cache / R2 (avaliar)
        │        └── origem: Supabase Storage
        │
        ▼
Supabase Free
  PostgreSQL + RLS + Auth + RPCs transacionais
        │
        ▼
PagBank (cobrança, webhook, conciliação)
```

O checkout **nunca** usa o catálogo cacheado como verdade. Ele chama
`finalizar_checkout_v6`, que recalcula preço/estoque/frete no banco.

## 2. Cloudflare — configuração recomendada

### 2.1 Hospedagem

- Preferir **Cloudflare Pages** para o `build/web` (deploy do GitHub Actions pode
  publicar em Pages via `wrangler pages deploy build/web`). No Pages, build com
  `--base-href /` (raiz) ou ajuste `web/_redirects`/base para `/pest/*`.
- Alternativa: manter GitHub Pages e colocar Cloudflare na frente com proxy
  laranja. O GitHub Pages tem limite de 100 GB/mês; Cloudflare reduz o hitting
  no origin, mas não remove o limite do provedor.
- Domínio próprio + HTTPS + HSTS.

### 2.2 Cache Rules (ordem)

| Rota | Cache | Observação |
|---|---|---|
| `/assets/*`, `/canvaskit/*`, `/icons/*` | Cache Everything, 1 ano | assets versionados; usar `immutable` |
| `/main.dart.js`, `/flutter_bootstrap.js` | 5 min + revalidate | não cachear por 1 ano |
| `/functions/v1/catalogo-publico` | 60s edge, 30s browser, SWR 300s | catálogo público |
| imagens do Storage (`/storage/v1/object/public/Produtos/*`) | 7–30 dias | arquivos com nome versionado |
| `/rest/v1/*`, `/auth/v1/*`, `/functions/v1/pagamentos*` | **Bypass** | nunca cachear dados privados |
| `/pedidos`, `/carrinho`, `/admin` | **Bypass** | dados de usuário |

Regra de ouro: **não cachear** nada que responda com dados de sessão,
carrinho, pedido, pagamento, perfil ou painel.

### 2.3 WAF e rate limiting

Sugestão inicial (ajustar após teste):

- `/auth/v1/token`, `/auth/v1/signup`, `/auth/v1/recover`: 30 req/min por IP,
  desafio gerenciado em picos.
- `/functions/v1/pagamentos`: 20 req/min por usuário/IP.
- `/rest/v1/pedidos`, `/rest/v1/pagamentos`: 60 req/min por usuário.
- `/rest/v1/produtos_publicos`, `/functions/v1/catalogo-publico`: cache alto e
  limite generoso; o objetivo é servir cache, não origin.
- Bot Fight Mode / Turnstile no cadastro e recuperação de senha.
- Bloquear métodos não usados e paths de administração fora do esperado.

### 2.4 Compressão

- Brotli para HTML/JS/JSON.
- WASM já é comprimido no build; não recomprimir em excesso.
- Imagens: WebP/AVIF, tamanhos 300/800/1600 px; nunca servir original de 3 MB
  na listagem.

### 2.5 Workers e R2

- **Workers**: úteis para reescrever/proteger o catálogo e servir cache com
  cabeçalhos próprios. O plano Free tem 100k requisições/dia; não use Worker
  como proxy de **toda** requisição de imagem. Use cache na borda.
- **R2**: avaliar para imagens públicas (10 GB grátis, sem egress). Só migrar
  se o Storage/egress do Supabase for o gargalo; exige rotina de upload e
  atualização das URLs no banco.
- Não adicionar Workers/R2 “por moda”: primeiro medir cache hit e egress.

## 3. Catálogo distribuído

### Fluxo

1. Admin altera produto/loja/banner.
2. O banco registra a alteração.
3. `catalogo-publico` gera um snapshot com `ETag`.
4. Cloudflare cacheia por até 60s (`stale-while-revalidate=300`).
5. App lê o snapshot; se indisponível, cai no PostgREST público.
6. Checkout revalida tudo no banco.

### Contrato do snapshot

`GET /functions/v1/catalogo-publico`

```json
{
  "versao": "2026-11-05T12:00:00.000Z",
  "categorias": [],
  "produtos": [],
  "promocoes": [],
  "banners": [],
  "unidades": []
}
```

Não inclui custo, PIX, repasse, ML, estoque reservado ou dados de usuário.
Preço/estoque do snapshot são **informativos**; o checkout sempre recalcula.

### Cache local no app

- `shared_preferences` guarda o último snapshot (até 24h).
- A home abre com o cache e revalida em segundo plano (stale-while-revalidate).
- `loadIfStale` evita consultar ao trocar de aba/resume em menos de 60s.

## 4. Autenticação e navegação

- Catálogo, busca, produto, loja e feed são públicos.
- Carrinho, conta, pedidos, favoritos, endereços e painéis exigem login.
- Ações como comprar/favoritar abrem o login em vez de falhar silenciosamente.
- O cadastro/login continua no Supabase Auth; para campanha, configurar
  SMTP próprio, rate limits e CAPTCHA/Turnstile.
- Nunca colocar `service_role` no Flutter/Web. A chave pública (`anon`) pode
  ficar no cliente; as regras estão no RLS.

## 5. Checkout e pagamentos

- Preço e estoque são calculados/lockados no banco.
- `pedido_itens.preco_unitario` é forçado pelo trigger a partir de `produtos`.
- `cobranca_locks` substitui advisory lock de sessão.
- `pagamentos.processando_em` serializa webhook/conciliação/consulta.
- Webhook é a fonte principal; o app lê o banco a cada 20s e sincroniza com o
  PagBank no máximo a cada 60s.
- Feature flags podem desligar checkout/pagamentos ou forçar PIX sem deploy.
- Se o volume justificar, a próxima evolução é fila de webhook + sala de espera
  de checkout (controle de admissão), não aumentar polling.

## 6. Observabilidade mínima

- Sentry/Crashlytics no Flutter.
- Log drain do Supabase (quando disponível no plano).
- Alertas: 429/5xx, CPU/RAM, pooler wait, p95, pagamentos em revisão, fila de
  webhook, falhas de Auth.
- Dashboard de egress/cache hit da Cloudflare.
- Teste de restauração de backup externo antes da campanha.

## 7. Limites explícitos

- Este documento **não** afirma que o Free suporta 50k usuários simultâneos em
  operações dinâmicas.
- A camada CDN pode absorver muitos visitantes, mas o banco continua sendo o
  gargalo de checkout/estoque.
- Para 10k–50k simultâneos com venda, a recomendação é contratar Pro/Team (ou
  superior), dimensionar compute e executar teste de carga antes do link.
