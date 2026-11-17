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

Plano principal ativo:
- **O Pest+** - R$ 14,99 por mês, nível 1, mensal, 1 tela, HD.
- As 12 temporadas principais continuam gratuitas (conteúdo do YouTube).
- O plano libera as temporadas exclusivas de bastidores/conteúdo especial.
- Benefícios: bastidores de cada temporada principal, extras, novos conteúdos antes e acesso no celular.

O administrador pode criar outros planos, níveis e temporadas exclusivas pelo painel.

### 6.2.1 Códigos de acesso

Além da assinatura paga, o O Pest+ possui **códigos de acesso temporário**:
- o fã resgata um código no app;
- o acesso é liberado por 1 mês ou mais, sem cobrança;
- cada código tem duração, limite de usos, validade e nível de acesso;
- o administrador pode criar, editar, desativar e excluir códigos;
- os códigos são pensados para sorteios e liberações manuais para fãs.

Tabelas:
- `streaming_access_codes`
- `streaming_access_code_redemptions`

Função:
- `streaming_resgatar_codigo(text)`

Tela do usuário:
- **O Pest+ → Tenho um código de acesso → Resgatar**.

Tela do admin:
- **Séries → Assinaturas → Códigos de acesso**.

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
- Criar/editar/desativar/excluir códigos de acesso.
- Copiar código para enviar ao fã.
- Acompanhar usos, duração e validade dos códigos.
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
- `streaming_access_codes`
- `streaming_access_code_redemptions`

### 7.2 Views

- `streaming_series_catalogo` — catálogo com contadores.
- `streaming_series_contagens` — contagens para o admin.
- `streaming_temporadas_contagens` — temporadas + contagem de episódios para o admin.

### 7.3 Funções

- `streaming_set_updated_at()` — atualiza `updated_at`.
- `streaming_preserva_conclusao()` — mantém episódio concluído.
- `streaming_nivel_assinatura()` — nível máximo ativo do usuário (assinatura ou código; admin = 3).
- `streaming_has_plan_level(nivel)` — verifica acesso ao nível.
- `streaming_has_active_subscription()` — verifica assinatura ativa.
- `streaming_contar_episodios(series_id)` — contagem pública de episódios.
- `streaming_resgatar_codigo(text)` — resgata um código temporário com validações de uso, validade e duplicidade.

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

2. `supabase/migrations/20261113120000_streaming_assinaturas.sql`
   - planos;
   - assinaturas;
   - eventos;
   - níveis de acesso;
   - RLS de assinaturas/planos;
   - funções de entitlement;
   - atualização da policy de episódios;
   - view de catálogo atualizada;
   - plano O Pest+ de R$ 14,99/mês;
   - códigos de acesso temporário.

3. `supabase/migrations/20261114120000_streaming_bastidores.sql`
   - acesso por temporada;
   - as 12 temporadas principais ficam gratuitas;
   - 120 episódios principais;
   - série separada de bastidores;
   - 1 temporada de bastidores grátis (5 episódios);
   - 12 temporadas de bastidores exclusivas (5 episódios cada);
   - RLS de temporada/episódio atualizada.

4. `supabase/migrations/20261115120000_streaming_plan_bastidores.sql`
   - atualiza os benefícios do plano O Pest+ para o modelo de bastidores exclusivos.

Status: **aplicadas no projeto remoto**.

Para reaplicar em outro ambiente:

```bash
cd o_pest_shop
npx supabase db push
```

Ou colar o SQL no SQL Editor do Supabase.

### Teste de estrutura/RLS

`supabase/tests/streaming_rls.sql` — executar no SQL Editor após a migration.

---

## 9. Seed inicial de conteúdo

Séries criadas:

1. **De Dentro da Favela** — série principal
   - Canal: O Pest
   - Status: publicado
   - Destaque: sim
   - Categoria: Websérie
   - Acesso: **gratuito**
   - **12 temporadas**
   - **10 episódios por temporada = 120 episódios**
   - Watch no YouTube normalmente, também dentro do app.

2. **Bastidores - De Dentro da Favela** — série separada
   - Status: publicado
   - Destaque: sim
   - Categoria: Bastidores
   - Acesso: gratuito na série, com temporadas exclusivas
   - **13 temporadas**
   - **1 temporada grátis** (5 episódios)
   - **12 temporadas exclusivas O Pest+** (5 episódios cada, uma para cada temporada principal)
   - Total: **65 episódios**
   - As temporadas exclusivas liberam com assinatura ou código de acesso.

Os links dos episódios são **placeholders públicos do YouTube** para teste.
O administrador deve substituí-los pelos vídeos oficiais.

Capas iniciais usam thumbnails do YouTube derivadas dos próprios vídeos.
O administrador pode substituir por artes oficiais.

> Observação importante sobre vídeos: vídeos **privados** do YouTube normalmente
> não podem ser incorporados em aplicativos de terceiros. Para o player funcionar,
> use vídeos **não listados** (unlisted) ou públicos e confirme no YouTube Studio
> que a opção de incorporação está habilitada. Durante os testes no emulador, alguns
> links de teste retornaram restrição de incorporação; o player exibe o aviso,
> permite tentar novamente e oferece “Abrir no YouTube”.

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
3. Definir **Acesso à temporada**:
   - `0` = grátis;
   - `1` = exclusivo O Pest+;
   - `2`/`3` = níveis superiores.
4. A temporada pode ser grátis mesmo em uma série com temporadas pagas.
5. Episódios herdam o maior nível entre série, temporada e episódio.

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
5. Plano inicial configurado: **O Pest+ — R$ 14,99/mês**.

### Códigos de acesso O Pest+
1. Séries → Assinaturas → Códigos de acesso → Novo código.
2. O sistema gera um código no formato `PEST-XXXX-XXXX`.
3. Definir duração em dias, usos máximos, validade, nível e observação.
4. Ativar o código.
5. Copiar o código e enviar para o fã.
6. O fã resgata em **O Pest+ → Tenho um código de acesso**.
7. O acesso fica liberado até a data de expiração.
8. Códigos podem ser desativados ou excluídos a qualquer momento.

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
- Migrations `20261112120000` e `20261113120000` aplicadas no Supabase.
- Série principal: 12 temporadas e 120 episódios gratuitos confirmados.
- Bastidores: 13 temporadas e 65 episódios; 1 temporada grátis e 12 exclusivas.
- Plano O Pest+ ativo a R$ 14,99/mês.
- Código de acesso de teste criado e resgatado com sucesso no app.
- Validação RLS:
  - anônimo vê 5 episódios da temporada grátis de bastidores;
  - anônimo vê 0 episódios de uma temporada exclusiva;
  - usuário com código ativo vê os 5 episódios da temporada exclusiva.
- Paywall por temporada, desbloqueio por código, temporadas grátis/pagas e player testados no emulador Android.
- Leitura pública confirmada; escrita anônima bloqueada.
- Realtime de episódios incluído; atualização de link reflete no detalhe/player.
- Combinações de links do YouTube variam: alguns vídeos retornam restrição de incorporação (tratada pelo app).
- Teste real do Mercado Pago depende de credenciais e webhook configurados.

---

## 13. Pendências e próximos passos

1. Configurar secrets do Mercado Pago.
2. Deploy de `mp-subscription` e `mp-webhook`.
3. Cadastrar o webhook no painel do Mercado Pago.
4. Testar o ciclo completo de assinatura em sandbox do Mercado Pago.
5. Substituir os links de teste pelos vídeos oficiais.
6. Usar **Séries → Episódios → Importar links** quando a lista oficial de links chegar.
7. Confirmar que os vídeos são **não listados/públicos** e permitem incorporação; vídeos privados normalmente não tocam no iframe.
8. Opcional: perfis por conta, downloads offline, notificações, recomendação e Top 10.
9. Opcional: limpeza automática de imagens no Storage ao excluir registros.
10. Remover ou alterar a senha das contas de teste criadas no ambiente.

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
