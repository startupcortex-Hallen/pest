# Cloudflare Pages + catálogo estático

Este documento cobre a publicação do Flutter Web no Cloudflare Pages Free e a
geração do catálogo/imagens estáticas para tirar a navegação do Supabase.

## 1. O que já está pronto no repositório

- `.github/workflows/deploy.yml` mantém o GitHub Pages em `/pest/` como rollback
  e adiciona o job `deploy-cloudflare`.
- O job do Cloudflare gera `web/data/catalogo.json` e `web/data/produtos.json`,
  compila com `--base-href /` e publica em `o-pest-shop.pages.dev` (o domínio
  final é `opest.com.br`, configurado em Custom domains).
- `web/_headers` cacheia `/assets/*`, `/data/*` e `/img/*`.
- `web/_redirects` faz o fallback de SPA.
- O app lê o catálogo estático primeiro e usa a Edge Function `catalogo-publico`
  ou o PostgREST como fallback.
- Busca, categoria, página de produto e recomendados filtram o JSON local
  quando ele está disponível. O checkout continua revalidando preço/estoque no
  banco.

## 2. Criar o projeto no Cloudflare Pages

1. Acesse **Workers & Pages > Create > Pages > Direct Upload**.
2. Crie o projeto com o nome `o-pest-shop`.
3. Gere um API Token com permissão **Cloudflare Pages: Edit**.
4. Copie o **Account ID**.
5. No GitHub, cadastre os secrets do repositório:
   - `CLOUDFLARE_API_TOKEN`
   - `CLOUDFLARE_ACCOUNT_ID`

Sem esses secrets o job do Cloudflare é ignorado com um aviso; o GitHub Pages
continua funcionando.

## 3. Configurar o Supabase

No painel do Supabase:

1. **Authentication > URL Configuration**:
   - Site URL: `https://opest.com.br`
   - Redirect URLs: inclua `https://opest.com.br/**`,
     `https://www.opest.com.br/**`, `https://o-pest-shop.pages.dev/**` e mantenha
     `https://startupcortex-hallen.github.io/pest/**` durante a transição.
2. Secrets das Edge Functions:
   - `ALLOWED_ORIGINS=https://opest.com.br,https://www.opest.com.br,https://o-pest-shop.pages.dev,https://startupcortex-hallen.github.io`
   - Reimplante `catalogo-publico`, `pagamentos` e demais funções que usam CORS.
3. Se o login com Google/Apple for usado, atualize também os redirects do
   provedor.

## 4. Catálogo estático

Gerar manualmente:

```bash
npm run catalogo
```

O script usa `SUPABASE_URL` e `SUPABASE_ANON_KEY` quando existirem. Sem eles,
lê a URL e a chave pública de `lib/core/constants/supabase_constants.dart`
(a chave `anon` é pública e já vai no bundle do app).

Saída:

- `o_pest_shop/web/data/catalogo.json`: snapshot da home (até 50 produtos,
  promoções, categorias, banners vigentes e lojas).
- `o_pest_shop/web/data/produtos.json`: catálogo completo de produtos ativos
  para busca/categoria/página de produto.

O arquivo completo é gerado a partir da view `produtos_publicos` com a chave
`anon`; nunca use `service_role` no cliente ou no script de build.

Em produção, o próprio workflow gera os JSONs antes do build. Se a Edge
Function estiver fora do ar, o script tenta o PostgREST público e, se não
conseguir, mantém o build sem os arquivos (o app cai no fallback).

## 5. Imagens (opcional)

```bash
npm install
npm run imagens
```

O script baixa as imagens públicas, converte para WebP em 300/800/1600 px e
reescreve as URLs em `catalogo.json` e `produtos.json` para
`https://opest.com.br/img/...`. Defina `PUBLIC_BASE_URL` se o domínio mudar.
O Pages Free aceita até 20.000 arquivos e 25 MiB por arquivo; se passar disso,
migre as imagens para R2 (10 GB grátis, sem egress).

## 6. Limites e capacidade

| Cenário | Free + este plano |
|---|---|
| 10 mil visitantes na home/catálogo | viável, servido pelo CDN |
| 10 mil buscas/páginas de produto | viável com catálogo estático |
| 10 mil logins/cadastros | risco: Auth limita por IP |
| 10 mil comprando ao mesmo tempo | não garantido; use a feature flag `checkout` |
| 10 mil no Realtime/chat | não: limite de 200 conexões simultâneas |
| Imagens no Storage do Supabase | não suporta 5 GB de egress |

O catálogo estático é informativo. Preço, estoque, cupom e frete são sempre
recalculados no checkout.

## 7. Rollback

- O GitHub Pages continua publicado em `/pest/` a cada push na `main`.
- Para voltar o link divulgado, aponte o domínio/QR code para
  `https://startupcortex-hallen.github.io/pest/`.
- O kill switch de compra é a feature flag `checkout` em `app_config`; ela
  desliga o checkout sem novo deploy.
- Se o Pages estiver com problema, remova o job `deploy-cloudflare` ou apague
  os secrets; o workflow continua publicando apenas no GitHub Pages.

## 8. Domínio próprio `opest.com.br`

1. Na Cloudflare: **Add a site** > `opest.com.br` > plano Free.
2. Troque os nameservers no Registro.br pelos dois que a Cloudflare mostrar.
3. Aguarde o status **Active**.
4. No projeto Pages: **Custom domains** > adicione `opest.com.br` e
   `www.opest.com.br`.
5. Em **SSL/TLS**, use **Full (strict)**.
6. Se quiser, crie uma Redirect Rule de `www` para `opest.com.br`.
7. Atualize Site URL/redirects no Supabase e o secret `ALLOWED_ORIGINS`.
8. Confirme `https://opest.com.br/data/catalogo.json` e as rotas de produto
   abrindo no domínio novo.
