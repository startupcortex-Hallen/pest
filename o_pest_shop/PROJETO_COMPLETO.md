# O Pest — Documentação Completa do Projeto

> Snapshot gerado em 12/11/2026.
> Projeto: aplicativo Flutter **O Pest - Shop** + Supabase + Mercado Livre + Mercado Pago + streaming de séries.
> Este documento não contém tokens, senhas ou chaves privadas.

---

## 1. Visão geral

O projeto é um aplicativo Flutter com backend Supabase para:

- Loja virtual (produtos, categorias, marcas, estoque, carrinho e checkout).
- Pedidos, pagamentos, frete, cupons, cartões e entregas.
- Unidades/lojas parceiras e área do entregador.
- Feed/notícias administrativas.
- Painel administrativo completo.
- **Central de streaming de séries** com catálogo, temporadas, episódios, player YouTube, progresso, favoritos e histórico.
- **Assinatura O Pest+** com planos por nível, conteúdo exclusivo e cobrança recorrente pelo Mercado Pago.

O aplicativo usa tema escuro (preto + vermelho), com `ThemeColors`/`AppTheme` para respeitar a identidade visual existente.

---

## 2. Stack técnica

### Flutter
- Flutter 3.41.7 / Dart 3.11.5.
- Gerenciamento de estado: **Provider / ChangeNotifier**.
- Navegação: **go_router**.
- Backend: **supabase_flutter**.
- Imagens: **cached_network_image**.
- Player: **youtube_player_flutter 10.0.1** (YouTube IFrame API).
- Upload de imagens: **image_picker**.
- Preferências locais: **shared_preferences**.
- Links externos: **url_launcher**.
- Mapas: **flutter_map / latlong2**.
- Animações: **lottie**.
- Compartilhamento: **share_plus**.

### Supabase
- Postgres com RLS.
- Storage buckets.
- Edge Functions em TypeScript/Deno.
- Auth e perfis (`perfis`).
- Edge Functions existentes: catálogo, frete, pagamentos, Mercado Livre etc.
- Novas Edge Functions: `mp-subscription` e `mp-webhook`.

### Pagamentos
- PagBank já integrado para pedidos da loja.
- **Mercado Pago** integrado para assinaturas recorrentes via API de `preapproval`.

---

## 3. Estrutura principal de pastas

```text
o_pest_shop/
├─ lib/
│  ├─ app.dart
│  ├─ main.dart
│  ├─ core/
│  │  ├─ helpers/          # tema, formatação, YouTube, entregas etc.
│  │  └─ theme/            # cores, tema, espaçamentos
│  ├─ models/
│  │  ├─ produto.dart
│  │  ├─ pedido/pagamento...
│  │  └─ streaming_models.dart
│  ├─ providers/
│  │  ├─ auth_provider.dart
│  │  ├─ cart_provider.dart
│  │  ├─ home_provider.dart
│  │  └─ streaming_provider.dart
│  ├─ router/app_router.dart
│  ├─ services/
│  │  ├─ auth_service.dart
│  │  ├─ admin_service.dart
│  │  ├─ pagamento_service.dart
│  │  └─ streaming/
│  │     ├─ streaming_service.dart
│  │     ├─ streaming_admin_service.dart
│  │     ├─ streaming_subscription_service.dart
│  │     └─ streaming_storage.dart
│  └─ ui/
│     ├─ navigation/main_shell.dart
│     ├─ screens/
│     │  ├─ admin/         # painel administrativo
│     │  ├─ streaming/     # aba Séries, detalhe, player, assinatura
│     │  ├─ home/
│     │  ├─ cart/
│     │  ├─ auth/
│     │  ├─ profile/
│     │  └─ ...
│     └─ widgets/
├─ supabase/
│  ├─ migrations/
│  ├─ functions/
│  │  ├─ mp-subscription/
│  │  ├─ mp-webhook/
│  │  └─ _shared/mercadopago.ts
│  └─ tests/
├─ android/
├─ ios/
├─ web/
├─ test/
└─ pubspec.yaml
```

---

## 4. Navegação principal

A navegação inferior possui:

1. **Início** — home da loja.
2. **Séries** — central de streaming (antiga aba Feed).
3. **Lojas** — unidades.
4. **Carrinho** — exige login.
5. **Perfil** — exige login.

Rotas principais de streaming:

- `/serie/:id` — página da série.
- `/serie/:id/episodio/:episodeId` — player.
- `/minha-lista` — favoritos.
- `/historico` — histórico.
- `/assinatura` — planos O Pest+.

A aba **Séries** e a página da série/player são públicas. Minha lista, histórico e assinatura exigem login para dados pessoais.

---

## 5. Central de streaming

### 5.1 Tela inicial (`streaming_home_screen.dart`)

- Top bar com menu, logo, O Pest+, Minha lista e Histórico.
- Banner principal cinematográfico com:
  - imagem horizontal;
  - título;
  - descrição;
  - temporada em destaque;
  - quantidade de episódios/temporadas;
  - botão Assistir/Assinar;
  - botão Ver série.
- Continue assistindo.
- Séries em destaque.
- Todas as séries.
- Últimos episódios.
- Estado vazio, erro e pull-to-refresh.
- Seções controladas por `streaming_home_config`.

### 5.2 Detalhe da série (`series_detail_screen.dart`)

- Banner/capa, título, categoria, classificação, ano, status.
- Contagem de temporadas e episódios.
- Descrição/sinopse, elenco.
- Trailer via player YouTube em diálogo.
- Seletor dinâmico de temporadas.
- Lista de episódios da temporada selecionada.
- Progresso individual por episódio.
- Favoritar/remover favorito.
- Paywall para conteúdo exclusivo.

### 5.3 Player (`episode_player_screen.dart`)

- YouTube IFrame API.
- Play/pause, volume quando suportado, barra de progresso e tela cheia.
- Tela cheia com orientação horizontal.
- Próximo/anterior episódio.
- Tela de encerramento com próximo episódio.
- Autoplay configurável e persistido.
- Tratamento de erros:
  - vídeo removido/privado;
  - vídeo sem incorporação;
  - restrição de idade/região;
  - falha do YouTube.
- Salvamento de progresso:
  - a cada ~10 s;
  - ao pausar;
  - ao encerrar;
  - ao sair da tela;
  - ao pausar o app.
- Conclusão automática em 90%.
- Progresso individual por usuário no Supabase.

### 5.4 Minha lista e histórico

- Favoritos de séries.
- Histórico de episódios assistidos.
- Limpeza de histórico.
- Percentual e status de conclusão.
- Acesso rápido ao player.

### 5.5 Modelos

`lib/models/streaming_models.dart`:

- `StreamingSeries`
- `StreamingSeason`
- `StreamingEpisode`
- `StreamingWatchProgress`
- `StreamingSeriesStats`
- `ContinueWatchingItem`
- `StreamingHistoryItem`
- `StreamingHomeConfig`
- `StreamingPlan`
- `StreamingSubscription`

### 5.6 Serviços

- `StreamingService` — catálogo, temporadas, episódios, progresso, favoritos, histórico, estatísticas.
- `StreamingAdminService` — CRUD administrativo, contagens, planos e assinaturas.
- `StreamingSubscriptionService` — planos, assinatura do usuário e Edge Functions do Mercado Pago.
- `StreamingStorage` — upload/remoção de imagens com validação de MIME e limite de 10 MB.

### 5.7 Provider

`StreamingProvider` mantém:

- catálogo;
- destaque/banner;
- seções da home;
- continue assistindo;
- últimos episódios;
- favoritos;
- planos;
- assinatura do usuário;
- controle `canAccess(requiredPlanLevel)`.

---

## 6. Assinatura O Pest+

### 6.1 Conceito

A “versão alternativa” é tratada como **catálogo exclusivo dentro da aba Séries**:

- Séries e episódios podem exigir um nível de plano.
- Nível `0` = grátis.
- Nível `1` = O Pest+ Básico ou superior.
- Nível `2` = O Pest+ Padrão ou superior.
- Nível `3` = O Pest+ Premium.

A assinatura é **recorrente** via Mercado Pago (`preapproval`).

### 6.2 Planos

Tabela `streaming_plans`:

- nome, slug, descrição;
- nível (1–3);
- preço em centavos;
- período (`mensal`/`anual`);
- dias de teste;
- telas simultâneas;
- qualidade;
- benefícios (`jsonb`);
- ativo/inativo;
- ordem.

Foram criados 3 planos-modelo **inativos e com preço 0**:
- O Pest+ Básico;
- O Pest+ Padrão;
- O Pest+ Premium.

O administrador deve definir preço e ativar antes de vender.

### 6.3 Assinaturas

Tabela `streaming_subscriptions`:

- usuário;
- plano;
- status (`pendente`, `ativa`, `pausada`, `cancelada`, `expirada`, `inadimplente`);
- gateway (`mercadopago`);
- `preapproval_id`;
- `init_point`;
- snapshot do plano (nome, nível, preço, período);
- início, fim do período atual;
- último pagamento;
- última sincronização.

Regra: um usuário só pode ter uma assinatura pendente/ativa/pausada/inadimplente por vez.

### 6.4 Fluxo do usuário

1. Abre **O Pest+**.
2. Escolhe um plano.
3. Toca em **Assinar com Mercado Pago**.
4. É redirecionado ao checkout do Mercado Pago.
5. O Mercado Pago envia webhook para atualizar o status.
6. O app sincroniza ao voltar para o foreground.
7. O conteúdo exclusivo é liberado conforme o nível do plano.
8. O usuário pode cancelar; o acesso permanece até o fim do período pago.

### 6.5 Fluxo administrativo

No painel: **Séries → Assinaturas**.

- Criar/editar/excluir planos.
- Definir preço, período, nível, teste, telas, qualidade e benefícios.
- Ativar/desativar plano.
- Ver assinaturas e status.
- Ativar ou cancelar manualmente para testes.
- O cancelamento manual **não** altera a cobrança no Mercado Pago; para isso use o painel do MP.

Para marcar conteúdo exclusivo:

- **Séries → editar série → Acesso ao conteúdo**.
- Ou **Episódios → editar episódio → Acesso ao episódio**.
- O nível efetivo é o maior entre série e episódio.

---

## 7. Banco de dados — streaming

### 7.1 Tabelas

- `streaming_series`
- `streaming_seasons`
- `streaming_episodes`
- `streaming_watch_progress`
- `streaming_favorites`
- `streaming_watch_history`
- `streaming_home_config`
- `streaming_plans`
- `streaming_subscriptions`
- `streaming_subscription_events`

### 7.2 Views

- `streaming_series_catalogo` — catálogo com contadores.
- `streaming_series_contagens` — contagens para o admin.
- `streaming_temporadas_contagens` — temporadas + contagem de episódios para o admin.

### 7.3 Funções

- `streaming_set_updated_at()` — atualiza `updated_at`.
- `streaming_preserva_conclusao()` — mantém episódio concluído.
- `streaming_nivel_assinatura()` — nível máximo ativo do usuário (admin = 3).
- `streaming_has_plan_level(nivel)` — verifica acesso ao nível.
- `streaming_has_active_subscription()` — verifica assinatura ativa.
- `streaming_contar_episodios(series_id)` — contagem pública de episódios.

### 7.4 RLS

- Conteúdo publicado: leitura pública.
- Conteúdo não publicado: somente admin.
- Episódios exclusivos: somente assinantes com nível suficiente (e admin).
- Progresso/favoritos/histórico: somente o próprio usuário.
- Planos: leitura pública dos ativos; admin gerencia.
- Assinaturas: usuário lê a própria; admin gerencia.
- Eventos de assinatura: somente admin.
- Storage `streaming`: leitura pública; escrita somente admin.

---

## 8. Migrations

### Aplicadas no projeto remoto

1. `supabase/migrations/20261112120000_streaming_catalogo.sql`
   - catálogo, temporadas, episódios, progresso, favoritos, histórico, home config;
   - RLS, bucket, seed inicial.

### Nova migration (pendente de aplicação no remoto)

2. `supabase/migrations/20261113120000_streaming_assinaturas.sql`
   - planos;
   - assinaturas;
   - eventos;
   - níveis de acesso;
   - RLS de assinaturas/planos;
   - funções de entitlement;
   - atualização da policy de episódios;
   - view de catálogo atualizada;
   - planos-modelo.

Para aplicar:

```bash
cd o_pest_shop
npx supabase db push
```

Ou colar o SQL no SQL Editor do Supabase.

### Teste de estrutura/RLS

`supabase/tests/streaming_rls.sql` — executar no SQL Editor após a migration.

---

## 9. Seed inicial de conteúdo

Série criada:

- **De Dentro da Favela**
- Canal: O Pest
- Status: publicado
- Destaque: sim
- Categoria: Websérie
- Temporadas:
  - 1ª temporada — Episódio 1 — `PHVQ17ifaWo`
  - 5ª temporada — Episódio 1 — `VYVevDrfSeg`

Capas iniciais usam thumbnails do YouTube derivadas dos próprios vídeos.
O administrador pode substituir por artes oficiais.

> Observação importante: durante os testes no emulador Android, os dois vídeos fornecidos retornaram restrição de incorporação/disponibilidade do YouTube. O player trata o erro corretamente, mas esses vídeos específicos não tocam dentro do app. Para reprodução interna, use vídeos que permitam incorporação ou habilite a opção no YouTube Studio.

---

## 10. Edge Functions de assinatura

### `mp-subscription`
Ações:

- `assinar` — cria/prepara a assinatura no Mercado Pago e retorna `init_point`.
- `status` — consulta o `preapproval` e sincroniza o banco.
- `cancelar` — cancela o `preapproval` no Mercado Pago.

### `mp-webhook`
- Recebe notificações do Mercado Pago.
- Valida assinatura HMAC quando `MP_WEBHOOK_SECRET` está configurado.
- Sincroniza `preapproval` e pagamentos.
- Registra eventos em `streaming_subscription_events`.

### Secrets necessários

Configurar no Supabase:

```bash
npx supabase secrets set \
  MP_ACCESS_TOKEN=SEU_TOKEN_DE_PRODUCAO_OU_TESTE \
  MP_WEBHOOK_SECRET=SEU_SEGREDO_DO_WEBHOOK \
  MP_BACK_URL=https://opest.com.br/assinatura
```

Nunca colocar esses valores no Flutter ou no GitHub.

### Deploy

```bash
npx supabase functions deploy mp-subscription
npx supabase functions deploy mp-webhook
```

### Webhook no painel do Mercado Pago

URL:

```text
https://rudmeztnxsxipmfytuem.supabase.co/functions/v1/mp-webhook
```

Tópicos recomendados:
- `preapproval`
- `payment`

O `mp-webhook` está configurado com `verify_jwt = false` em `supabase/config.toml`.

---

## 11. Painel administrativo

Acesso: menu lateral → **Área do Admin** (somente `funcao = admin`).

Abas relevantes:

- Dashboard
- Produtos
- Categorias
- Marcas
- Posts
- Lojas
- Integrações
- Banners
- **Séries**
  - Séries
  - Temporadas
  - Episódios
  - Home
  - **Assinaturas**
- Cupons
- Usuários
- Verificação
- Pedidos

### Cadastrar série
1. Séries → Nova série.
2. Preencher título, capa 2:3, banner 16:9, descrição, sinopse, categoria, classificação, ano, elenco, trailer.
3. Definir acesso (grátis ou nível 1/2/3).
4. Salvar rascunho ou publicar.

### Cadastrar temporada
1. Temporadas → selecionar série → Nova temporada.
2. Informar número, título, descrição, capa, data de lançamento, status e ordem.

### Cadastrar episódio
1. Episódios → selecionar série/temporada → Novo episódio.
2. Colar URL do YouTube; o ID é validado.
3. Pré-visualizar vídeo.
4. Informar número, título, descrição, duração, data de publicação, status e nível de acesso.
5. Salvar ou publicar.
6. Se a data for futura, fica agendado e é liberado automaticamente ao chegar a data.

### Importar vários episódios por links
1. Episódios → selecionar série/temporada → **Importar links**.
2. Colar um link do YouTube por linha.
3. Opcionalmente, usar `URL | Título do episódio`.
4. Tocar em **Validar links**.
5. O sistema mostra prévia, numeração automática, links inválidos e duplicados.
6. Tocar em **Importar N episódios como rascunho**.
7. Revisar, definir nível de acesso e publicar cada episódio.

A importação em lote foi criada especialmente para receber a lista completa de links das temporadas quando ela estiver disponível.

### Imagens
- Upload com validação real de JPG/PNG/WebP.
- Limite de 10 MB.
- Redimensionamento/qualidade no upload.
- Substituir/remover.
- Bucket `streaming`.

### Home do streaming
- Definir série do banner principal.
- Ativar/desativar seções.
- Reordenar seções.

### Planos O Pest+
1. Séries → Assinaturas → Novo plano.
2. Nome, slug, preço, período, nível, teste, telas, qualidade, benefícios.
3. Ativar o plano.
4. Só planos ativos com preço > 0 aparecem para assinatura.

---

## 12. Testes e comandos

### Análise
```bash
cd o_pest_shop
flutter analyze lib test
```
Resultado atual: **sem erros**; avisos/infos antigos do projeto permanecem.

### Testes
```bash
flutter test
```
Resultado atual: **60 testes passando**.

Inclui testes de:
- parsing de URL do YouTube;
- modelos de streaming;
- planos e assinaturas;
- catálogo/configuração da home;
- carrinho, catálogo, frete, cupom, banner etc.

### Build Android
```bash
flutter build apk --debug
```
Resultado atual: **sucesso**.

### Testes remotos
- Migration `20261112120000` aplicada no Supabase.
- Dados iniciais verificados via REST.
- Leitura pública confirmada.
- Escrita anônima bloqueada.
- Migration de assinaturas ainda pendente.
- Teste real do Mercado Pago depende de credenciais e webhook configurados.

---

## 13. Pendências e próximos passos

1. Aplicar `20261113120000_streaming_assinaturas.sql`.
2. Configurar secrets do Mercado Pago.
3. Deploy de `mp-subscription` e `mp-webhook`.
4. Cadastrar o webhook no painel do Mercado Pago.
5. Editar os 3 planos-modelo: definir preço, revisar benefícios e ativar.
6. Marcar a série/versão alternativa com nível de acesso > 0.
7. Testar o ciclo completo em sandbox do Mercado Pago.
8. Substituir os vídeos de teste por vídeos que permitam incorporação.
9. Quando a lista oficial de links chegar, usar **Séries → Episódios → Importar links** por temporada.
10. Opcional: perfis por conta, downloads offline, notificações, recomendação e Top 10.
10. Opcional: limpeza automática de imagens no Storage ao excluir registros.

---

## 14. Segurança

- Nenhuma `service_role` no Flutter.
- Tokens do Mercado Pago somente em secrets do Supabase.
- RLS ativa em todas as tabelas de streaming/assinatura.
- Usuário só lê o próprio progresso, favoritos, histórico e assinatura.
- Admin garantido por `funcao_usuario() = 'admin'` no banco.
- Storage de streaming com escrita apenas para admin.
- Webhook com validação HMAC quando o segredo está configurado.
- Upload de imagens com validação de tipo real e limite de tamanho.

---

## 15. Repositório

- Repositório: `https://github.com/startupcortex-Hallen/pest.git`
- Branch principal: `main`
- App Flutter: `o_pest_shop/`
- Supabase: `o_pest_shop/supabase/`
- Documentação local: `o_pest_shop/PROJETO_COMPLETO.md`

---

## 16. Observações finais

- A aba antiga **Feed** foi substituída por **Séries** na navegação inferior.
- As telas antigas de feed/posts continuam no código para não quebrar detalhes de posts e o módulo administrativo.
- O catálogo e a assinatura são totalmente dinâmicos, vindos do Supabase.
- O sistema foi preparado para novas séries, temporadas, episódios e planos sem alterar o Flutter.
