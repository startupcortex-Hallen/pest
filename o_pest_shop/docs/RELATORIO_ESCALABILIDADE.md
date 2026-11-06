# Relatório de Escalabilidade — O Pest Shop

> Estado real após o hardening de 05/11/2026.
> **Nada foi aplicado em produção.** As migrations e functions precisam ser
> validadas em staging e publicadas com autorização.

## 1. Resumo executivo

O projeto **não deve ser vendido como “50 mil usuários simultâneos no Supabase
Free”**. O Free é adequado para o banco inicial, autenticação e checkout de
baixo/médio volume. A campanha de grande audiência só é segura se o tráfego
público (catálogo, imagens, estáticos) for absorvido por CDN/cache e se o
checkout for controlado por fila/limite de admissão.

O que foi feito nesta rodada:

- Fechado o furo de **preço adulterado** no checkout (P0 financeiro).
- Substituído o advisory lock de sessão por **lock atômico em tabela**.
- Serializado o processamento de comprovantes por pagamento.
- Criado catálogo público cacheável (`catalogo-publico` + cache local no app).
- Criadas views públicas que não expõem custo/PIX/repasse.
- Criadas feature flags (`checkout`, `pagamentos`, `frete`, `manutenção`).
- Reduzido polling de pagamento de 5s para 20s, com leitura local e sync a
   cada 60s; pausa em segundo plano.
- Índices, limpeza de temporários, navegação pública do catálogo e compressão
  de upload de imagens.

## 2. Limites oficiais do Supabase Free (referência)

| Recurso | Free |
|---|---|
| PostgreSQL | 500 MB |
| RAM/compute | compartilhada, 500 MB |
| Egress não cacheado | 5 GB/mês |
| Egress cacheado | 5 GB/mês |
| Storage | 1 GB |
| MAU | 50.000 |
| Edge Functions | 500.000 invocações/mês |
| Realtime | 200 conexões simultâneas |
| Backups | não disponíveis para download |
| Pausa | após 7 dias de inatividade |

O MAU de 50.000 **não** significa 50.000 conexões simultâneas. O gargalo real
do Free é a instância compartilhada de banco, o egress e o limite de conexões.

## 3. Capacidade real (estimativa honesta)

| Cenário | Free sem CDN | Free com CDN + este hardening |
|---|---|---|
| 100–300 visitantes navegando | viável | viável |
| 500 visitantes navegando | risco de fila no PostgREST | viável se cache hit alto |
| 2.000 visitantes navegando | não recomendado | possível com CDN e catálogo cacheado |
| 10.000–50.000 visitantes | não recomendado | somente com CDN/Cloudflare e origem dimensionada; **não comprovado** |
| Checkout dinâmico | centenas de pedidos/dia | depende de teste; não presumir 5.000/min |
| 50.000 checkouts simultâneos | inviável no Free | exige Pro/Team + fila + teste de carga |

**Regra prática:** o catálogo pode ser servido em escala por CDN; autenticação,
estoque, checkout e pagamentos são operações dinâmicas e precisam de capacidade
própria comprovada. Não há teste de 50k executado neste relatório.

## 4. O que foi implementado

### 4.1 Migration

`supabase/migrations/20261105120000_hardening_escalabilidade.sql`

- Trigger `trg_forcar_preco_produto`: `pedido_itens.preco_unitario` sempre vem
  de `produtos`, nunca do cliente.
- Tabela `cobranca_locks` + RPCs atômicas com TTL.
- Coluna `pagamentos.processando_em` + RPCs de aquisição/liberação.
- Tabela `app_config` + view pública `app_config_publica` + RPC admin.
- Views `produtos_publicos` e `unidades_publicas`.
- Revogação de SELECT de colunas sensíveis em `produtos`/`unidades` para
  clientes; RPCs `admin_listar_produtos` e `admin_listar_unidades`.
- Leitura anônima controlada de catálogo/feed.
- Índices para produtos, pedidos, pagamentos, perfis, mensagens, fretes.
- `limpar_registros_temporarios()` + agendamento no pg_cron quando existir.
- Checkout v6 com guard de feature flag.

### 4.2 Edge Functions

- `pagamentos`: timeout de 15s, retry com backoff em GET, feature flags
  (`pagamentos.ativo`, `pix_only`), throttle de 30s na consulta ao PagBank.
- `pagamentos-webhook` / `_shared/pagamentos_db.ts`: lock de processamento por
  pagamento (evita webhook + conciliação + consulta simultâneos).
- `catalogo-publico`: snapshot público com `ETag` e `Cache-Control`
  (`s-maxage=60`, `stale-while-revalidate=300`).
- Correios/PagBank: timeout no SDK 3DS.

### 4.3 Flutter

- `CatalogoService`: cache local (`shared_preferences`) + Edge snapshot.
- `HomeProvider`: stale-while-revalidate, carregamento paralelo no fallback,
  throttle de 60s.
- Navegação pública: home, busca, produto, categoria, unidade e feed.
- Carrinho/perfil continuam exigindo login; ações de compra/favorito pedem login.
- Polling de pagamento: 20s local + sync Edge a cada 60s + pausa em background.
- Feed/chat: joins que eliminam N+1; categorias via RPC.
- Produtos/lojas: consultas nas views públicas com colunas explícitas.
- Upload de produto: `maxWidth/maxHeight` 1600 + qualidade 75.
- Cache de imagens com `memCacheWidth` em cards, busca, feed e vídeos.
- Feature flags lidas do banco e aplicadas no checkout.
- Deep link do GitHub Pages via `404.html` + `?redirect=` seguro.
- Headers/redirects de CDN e metatags Open Graph.

## 5. Testes executados (resultados reais)

| Teste | Resultado |
|---|---|
| `flutter analyze --no-fatal-infos --no-fatal-warnings` | **0 erros**; 340 warnings/infos (a maioria legado) |
| `flutter test` | **41 testes passando** |
| `flutter build web --release --base-href /pest/` | **sucesso** (main.dart.js ~4,35 MB) |
| Teste de carga 50/100/500/2k/10k/50k | **não executado** |
| Aplicação da migration em staging | **não executada** (sem Supabase CLI/DB local) |
| Teste de preço adulterado em banco | **pendente de staging** |
| Teste de concorrência de estoque | **pendente de staging** |

Não inventamos resultados de carga. O `RELATORIO_TESTES_CARGA.md` traz o plano
e os scripts; os números só devem ser preenchidos após execução em staging.

## 6. Riscos residuais

1. **Free não tem backup baixável.** Exportar o banco antes da campanha.
2. **Egress de imagens** continua sendo o maior risco. Sem CDN/Storage
   otimizado, 5 GB acabam rápido.
3. **Auth** tem limite por IP (30 sign-ins/5 min). Evento com Wi-Fi/NAT pode
   bloquear; configurar rate limits + CAPTCHA e preferir browse anônimo.
4. **Checkout dinâmico** no Free não tem capacidade comprovada. Se a campanha
   prometer venda em massa, planejar Pro/Team antes do link.
5. **Webhook** ainda é processado inline (com lock). Em volume muito alto, a
   evolução é fila + worker; o lock reduz a corrida, não a fila.
6. **PagBank/Correios/OSM** têm limites externos; validar volume com os
   fornecedores.
7. **R2/Cloudflare não foi provisionado** — o código está pronto para cache,
   mas a conta/configuração é uma etapa de infraestrutura.

## 7. Migração Free → Pro (sem reconstruir)

1. Criar projeto Pro de staging com o mesmo schema.
2. Rodar migrations em ordem; validar views/grants/RPCs.
3. Publicar Edge Functions e configurar secrets.
4. Configurar `ALLOWED_ORIGINS`, SMTP, PagBank sandbox.
5. Executar carga 100/500/2.000; ajustar compute.
6. Ativar PITR/backup e log drain.
7. Repetir em produção com janela e rollback.

Gatilhos para sair do Free:

- CPU/RAM do banco > 60–70% de forma persistente.
- Egress projetado > 70% da franquia.
- Aumento de 429/5xx ou latência p95.
- Fila de checkout maior que a capacidade.
- Necessidade de backup/PITR e suporte com SLA.

## 8. Como aplicar (staging primeiro)

```bash
cd o_pest_shop
# 1. aplicar a migration no staging (painel SQL ou CLI)
# 2. publicar functions
supabase functions deploy pagamentos
supabase functions deploy pagamentos-webhook --no-verify-jwt
supabase functions deploy pagamentos-conciliacao --no-verify-jwt
supabase functions deploy catalogo-publico --no-verify-jwt
supabase functions deploy frete-cotacao
supabase functions deploy frete-etiqueta
supabase functions deploy frete-rastreio --no-verify-jwt

# 3. conferir feature flags
select chave, valor from public.app_config;
# 4. rodar testes de segurança
#    supabase/tests/seguranca_checkout.sql
# 5. rodar app/testes
flutter analyze
flutter test
```

**Não aplicar em produção sem autorização expressa.**
