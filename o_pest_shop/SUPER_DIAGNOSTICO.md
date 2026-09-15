# SUPER DIAGNÓSTICO — AIRES HEALTH STORE

## 1. ARQUITETURA GERAL

**Framework:** Flutter (SDK ^3.11.5)  
**Backend:** Supabase (PostgreSQL + Realtime + Auth + Storage)  
**Estado:** Provider (ChangeNotifier)  
**Roteamento:** GoRouter (33 rotas)  
**Autenticação:** Supabase Auth (email/senha)  
**Tema:** Light/Dark com Google Fonts (Inter)

---

## 2. ESTRUTURA DE PASTAS

```
lib/
├── app.dart                          # App root (MultiProvider + MaterialApp.router)
├── main.dart                         # Entry point (Supabase init + orientação)
├── core/
│   ├── constants/supabase_constants.dart
│   ├── helpers/
│   │   ├── categoria_icons.dart
│   │   ├── scale_helper.dart          # Responsividade (base 390x844)
│   │   ├── theme_colors.dart          # Context-aware ThemeColors
│   │   └── time_ago.dart
│   └── theme/
│       ├── app_colors.dart            # Light + Dark palettes
│       ├── app_spacing.dart           # Spacing + Radius constants
│       └── app_theme.dart             # ThemeData (light + dark)
├── models/                           # 16 classes de modelo
├── providers/                        # 8 ChangeNotifiers
├── services/                         # 12 classes de serviço
├── router/app_router.dart            # 33 rotas
└── ui/
    ├── widgets/                      # 8 widgets reutilizáveis
    ├── screens/
    │   ├── admin/                    # CRUD completo (10 abas)
    │   ├── auth/                     # Login + Register
    │   ├── cart/                     # Carrinho + Checkout
    │   ├── chat/                     # Chat + Central de Atendimento
    │   ├── feed/                     # Feed + Detalhes (post, vaga, evento, etc)
    │   ├── gym/                      # Aulas, Personal, Avaliação, Progresso, Desafios
    │   ├── home/                     # Home + Busca
    │   ├── navigation/               # MainShell (BottomNavigation)
    │   ├── pedidos/                  # Meus Pedidos
    │   ├── product/                  # Detalhe do Produto
    │   ├── profile/                  # Perfil + Nutrição + Treinos
    │   └── unidades/                 # Lista de Unidades
    └── navigation/                   # Bottom Navigation Shell
```

---

## 3. TABELAS DO BANCO DE DADOS (33 tabelas)

### 3.1 Tabelas de Identidade e Autenticação

| Tabela | Colunas | FK |
|--------|---------|----|
| `perfis` | `id` (uuid PK), `nome`, `email`, `perfil` (text), `funcao` (text), `telefone`, `avatar_url`, `nome_completo`, `cpf`, `unidade_id` (int?), `objetivo`, `codigo`, `pontos` (int) | `unidade_id → unidades.id` |

**Funções (roles):** `admin`, `atendente`, `entregador`, `nutricionista`, `personal`, `cliente` (default)

### 3.2 Tabelas de Produto e E-commerce

| Tabela | Colunas | FK |
|--------|---------|----|
| `categorias` | `id` (int PK), `nome`, `icone` | — |
| `marcas` | `id` (int PK), `nome` | — |
| `produtos` | `id` (int PK), `nome`, `descricao`, `preco`, `em_promocao`, `categoria_id` (int), `marca_id` (int?), `estoque`, `unidade_id` (int?), `vendas`, `frete_gratis`, `percentual_desconto`, `garantia`, `parcelas`, `url_imagem` (jsonb) | `categoria_id → categorias.id`, `marca_id → marcas.id`, `unidade_id → unidades.id` |
| `galeria_produtos` | `url_imagem` | Link com `produtos.id` |
| `carrinho` | `id` (int PK), `user_id` (uuid), `produto_id` (int), `quantidade`, `created_at` | `user_id → perfis.id`, `produto_id → produtos.id` |
| `favoritos` | `id` (int PK), `user_id` (uuid), `produto_id` (int), `created_at` | `user_id → perfis.id`, `produto_id → produtos.id` |
| `cupons` | `id` (int PK), `codigo`, `tipo`, `valor`, `valor_minimo`, `data_validade`, `uso_maximo`, `usos_atuais`, `ativo` | — |
| `pedidos` | `id` (int PK), `user_id` (uuid), `unidade_id` (int), `status`, `total`, `created_at` | `user_id → perfis.id`, `unidade_id → unidades.id` |
| `pedido_itens` | `id` (int PK), `pedido_id` (int), `produto_id` (int), `quantidade`, `preco_unitario` | `pedido_id → pedidos.id`, `produto_id → produtos.id` |
| `cartoes_usuario` | `id` (int PK), `user_id` (uuid), `apelido`, `numero_mascarado`, `bandeira`, `titular`, `mes_validade`, `ano_validade`, `padrao` | `user_id → perfis.id` |

### 3.3 Tabelas de Feed e Conteúdo

| Tabela | Colunas | FK |
|--------|---------|----|
| `posts_feed` | `id` (uuid PK), `user_id` (uuid), `titulo`, `descricao`, `url_imagem`, `url_youtube`, `categoria`, `created_at`, `unidade_id` (int?) | `unidade_id → unidades.id` ⚠️ **FK para `perfis.id` NÃO EXISTE** |
| `post_likes` | `id` (int PK), `post_id` (uuid), `user_id` (uuid) | `post_id → posts_feed.id`, `user_id → perfis.id` |
| `post_comentarios` | `id` (int PK), `post_id` (uuid), `user_id` (uuid), `texto`, `created_at` | `post_id → posts_feed.id`, `user_id → perfis.id` |
| `candidaturas` | `id` (int PK), `vaga_id` (uuid), `user_id` (uuid), `nome`, `email`, `telefone`, `url_curriculo`, `created_at` | `vaga_id → posts_feed.id`, `user_id → perfis.id` |

### 3.4 Tabelas de Unidades/Franquias

| Tabela | Colunas | FK |
|--------|---------|----|
| `unidades` | `id` (int PK), `nome`, `slug` (NOT NULL), `endereco`, `bairro`, `cidade`, `logo_url`, `foto_url`, `horario_seg` a `horario_dom`, `ordem`, `ativa`, `distancia`, `latitude`, `longitude`, `created_at` | — |
| `aulas` | `id` (int PK), `unidade_id` (int), `nome`, `instrutor`, `dia_semana`, `horario`, `duracao`, `vagas`, `vagas_ocupadas`, `descricao` | `unidade_id → unidades.id` |
| `aulas_inscricao` | `id` (int PK), `aula_id` (int), `user_id` (uuid), `data_aula` | `aula_id → aulas.id`, `user_id → perfis.id` |
| `personal_sessoes` | `id` (int PK), `unidade_id` (int), `personal_id` (uuid), `aluno_id` (uuid), `data_hora`, `duracao`, `status`, `valor`, `observacao`, `concluido` | `unidade_id → unidades.id`, `personal_id → perfis.id`, `aluno_id → perfis.id` |
| `avaliacoes` | `id` (int PK), `user_id` (uuid), `unidade_id` (int), `data_avaliacao`, `peso`, `altura`, `percentual_gordura`, `massa_muscular`, `imc`, `braco_esquerdo`, `braco_direito`, `cintura`, `quadril`, `coxa_esquerda`, `coxa_direita` | `user_id → perfis.id`, `unidade_id → unidades.id` |
| `progresso_fotos` | `id` (int PK), `user_id` (uuid), `foto_url`, `data` | `user_id → perfis.id` |
| `desafios` | `id` (int PK), `unidade_id` (int), `nome`, `ativo` | `unidade_id → unidades.id` |
| `desafios_participantes` | `id` (int PK), `desafio_id` (int), `user_id` (uuid), `progresso` | `desafio_id → desafios.id`, `user_id → perfis.id` |
| `indicacoes` | `id` (int PK), `usuario_id` (uuid), `indicado_id` (uuid), `codigo_indicacao`, `pontos_ganhos` | `usuario_id → perfis.id`, `indicado_id → perfis.id` |

### 3.5 Tabelas de Nutrição e Treinos

| Tabela | Colunas | FK |
|--------|---------|----|
| `plano_refeicoes` | `id` (int PK), `user_id` (uuid), `dia_semana`, `tipo`, `horario`, `calorias`, `descricao`, `icone`, `concluido` | `user_id → perfis.id` |
| `assinaturas` | `id` (int PK), `user_id` (uuid), `plano`, `status`, `valor`, `data_inicio`, `data_fim`, `bonus`, `created_at` | `user_id → perfis.id` |
| `nutricionistas` | `id` (int PK), `nome`, `email`, `telefone`, `crn`, `bio`, `avatar_url`, `preco_consulta`, `disponivel` | — |
| `consultas` | `id` (int PK), `user_id` (uuid), `nutricionista_id` (int), `data_hora`, `status` | `user_id → perfis.id`, `nutricionista_id → nutricionistas.id` |
| `treinos` | `id` (int PK), `user_id` (uuid), `nome`, `dia_semana`, `ordem` | `user_id → perfis.id` |
| `exercicios` | `id` (int PK), `treino_id` (int), `nome`, `aparelho`, `grupo_muscular`, `series`, `repeticoes`, `carga_sugerida`, `observacao`, `ordem`, `concluido` | `treino_id → treinos.id` |
| `agua_registro` | `id` (int PK), `user_id` (uuid), `data`, `ml` | `user_id → perfis.id` |

### 3.6 Tabelas de Chat

| Tabela | Colunas | FK |
|--------|---------|----|
| `conversas` | `id` (int PK), `usuario_id` (uuid), `unidade_id` (int?), `profissional_id` (uuid?), `ultima_mensagem`, `updated_at`, `created_at` | `usuario_id → perfis.id`, `profissional_id → perfis.id`, `unidade_id → unidades.id` |
| `mensagens` | `id` (int PK), `conversa_id` (int), `remetente_id` (uuid), `texto`, `created_at` | `conversa_id → conversas.id`, `remetente_id → perfis.id` ⚠️ **FK podem não existir** |

---

## 4. RELACIONAMENTOS E FKs — DIAGNÓSTICO DE FALHAS

### ✅ FKs que EXISTEM (confirmadas pelo uso no código):
- `produtos.unidade_id → unidades.id`
- `pedidos.user_id → perfis.id`, `pedidos.unidade_id → unidades.id`
- `carrinho.user_id → perfis.id`, `carrinho.produto_id → produtos.id`
- `post_likes.post_id → posts_feed.id`, `post_likes.user_id → perfis.id`
- `conversas.usuario_id → perfis.id`, `conversas.unidade_id → unidades.id`
- `treinos.user_id → perfis.id`
- `exercicios.treino_id → treinos.id`
- `aulas.unidade_id → unidades.id`
- `personal_sessoes.unidade_id → unidades.id`, `personal_sessoes.personal_id → perfis.id`, `personal_sessoes.aluno_id → perfis.id`
- `avaliacoes.user_id → perfis.id`, `avaliacoes.unidade_id → unidades.id`

### ❌ FKs AUSENTES (causam PGRST200 ao tentar JOIN):
- **`posts_feed.user_id → perfis.id`** — NÃO EXISTE. Causa erro PGRST200 ao tentar `posts_feed.select('*, perfis(nome, avatar_url)')`. O feed funciona SEM o join de perfis, usando `unidades(id, nome, foto_url)` como fallback.

### ⚠️ FKs PROVAVELMENTE AUSENTES (não confirmadas):
- **`mensagens.remetente_id → perfis.id`** — O `ChatService` não usa join justamente para evitar erro. Busca perfil separadamente.
- **`conversas.usuario_id → perfis.id`** — O `ChatService` busca perfil separadamente.
- **`pedido_itens.produto_id → produtos.id`** — O `fetchPedidos` tenta join mas pode falhar.

---

## 5. RLS — POLICIES DE SEGURANÇA

### Policies para `conversas`:
```sql
-- Cliente vê apenas suas próprias conversas
CREATE POLICY "Cliente - ver conversas" ON conversas FOR SELECT
TO authenticated USING (usuario_id = auth.uid());

-- Atendente/Admin vê conversas da sua unidade
CREATE POLICY "Atendente - ver conversas da unidade" ON conversas FOR SELECT
TO authenticated USING (
  unidade_id IS NOT NULL AND (
    (SELECT funcao FROM perfis WHERE id = auth.uid()) = 'admin'
    OR ((SELECT funcao FROM perfis WHERE id = auth.uid()) IN ('admin', 'atendente')
        AND unidade_id = (SELECT unidade_id FROM perfis WHERE id = auth.uid()))
  )
);

-- Criar conversa
CREATE POLICY "Criar conversa" ON conversas FOR INSERT
TO authenticated WITH CHECK (true);
```

### Policies para `mensagens`:
```sql
CREATE POLICY "Cliente - ver mensagens" ON mensagens FOR SELECT
TO authenticated USING (
  conversa_id IN (SELECT id FROM conversas WHERE usuario_id = auth.uid())
  OR conversa_id IN (SELECT id FROM conversas WHERE unidade_id IS NOT NULL
    AND (SELECT funcao FROM perfis WHERE id = auth.uid()) IN ('admin', 'atendente')
    AND unidade_id = (SELECT unidade_id FROM perfis WHERE id = auth.uid()))
);

CREATE POLICY "Enviar mensagem" ON mensagens FOR INSERT
TO authenticated WITH CHECK (remetente_id = auth.uid());
```

### ⚠️ Problemas de RLS identificados:
1. **Recursão**: A policy de `mensagens` faz subquery em `conversas` que depende de `perfis`. A árvore de dependências pode causar recursão no PostgreSQL em casos complexos.
2. **Subquery aninhada**: `(SELECT funcao FROM perfis WHERE id = auth.uid())` é executada para cada linha — ineficiente em grande escala.
3. **Unidades sem policy explícita**: As tabelas `unidades`, `produtos`, `posts_feed` e outras precisam de policies de SELECT para `anon` e `authenticated` para exibição pública.
4. **Storage sem policy**: Buckets `Produtos`, `fotos_perfil`, `Curriculos` precisam de policies para leitura pública e upload condicional.

---

## 6. ROTAS (33 rotas no GoRouter)

| Path | Screen | Parâmetros | Autenticação |
|------|--------|------------|--------------|
| `/login` | LoginScreen | — | Redirect se logado |
| `/register` | RegisterScreen | — | Redirect se logado |
| `/` | MainShell (Home) | — | Redirect se não logado |
| `/busca` | SearchResultsScreen | `?q=` | — |
| `/categoria/:id` | MainShell | `id` int | — |
| `/produto/:id` | ProductDetailScreen | `id` int | — |
| `/favoritos` | FavoritesScreen | — | — |
| `/perfil` | ProfileScreen | — | — |
| `/carrinho` | CartScreen | — | — |
| `/cupons` | CuponsScreen | — | — |
| `/cartoes` | CartoesScreen | — | — |
| `/editar-dados` | EditPersonalDataScreen | — | — |
| `/plano-nutricional` | PlanoNutricionalScreen | — | — |
| `/post/:id` | PostDetailScreen | `id` String | — |
| `/aviso/:id` | AvisoDetailScreen | `id` String | — |
| `/novidade/:id` | NovidadeDetailScreen | `id` String | — |
| `/evento/:id` | EventoDetailScreen | `id` String | — |
| `/vaga/:id` | VagaDetailScreen | `id` String | — |
| `/unidade/:id` | UnidadeScreen | `id` int | — |
| `/pedidos` | PedidosScreen | — | — |
| `/assinaturas` | AssinaturasScreen | — | — |
| `/nutricionistas` | NutricionistasScreen | — | — |
| `/treinos` | TreinosScreen | — | — |
| `/aulas` | AulasScreen | — | — |
| `/personal` | PersonalScreen | — | — |
| `/avaliacao` | AvaliacaoScreen | — | — |
| `/progresso` | ProgressoScreen | — | — |
| `/desafios` | DesafiosScreen | — | — |
| `/indicacao` | IndicacaoScreen | — | — |
| `/dashboard` | DashboardScreen | — | — |
| `/chat/:id/:nome` | ChatScreen | `id` int, `nome` String | — |
| `/central-atendimento` | CentralAtendimentoScreen | — | — |
| `/admin` | AdminScreen | — | Só admin |

---

## 7. PROVIDERS (ChangeNotifiers)

| Provider | Responsabilidade |
|----------|------------------|
| `ThemeProvider` | Alternância light/dark |
| `AuthProvider` | Login, signOut, getProfile, refresh |
| `HomeProvider` | Dados da Home (categorias, produtos, promoções, refresh) |
| `FeedProvider` | Posts do feed, categorias, toggleLike |
| `CartProvider` | Carrinho (CRUD + clear) |
| `FavoritoProvider` | Favoritos (toggle, check) |
| `CupomProvider` | Cupons (fetch, validate, use) |
| `CartaoProvider` | Cartões de crédito |

---

## 8. SERVIÇOS (12 classes, ~107 métodos)

| Serviço | Total Métodos | Tabelas Usadas |
|---------|---------------|----------------|
| `AuthService` | 8 | `perfis` |
| `ProdutoService` | 5 | `produtos`, `categorias`, `marcas`, `galeria_produtos` |
| `FeedService` | 9 | `posts_feed`, `post_likes`, `post_comentarios`, `candidaturas` |
| `FavoritoService` | 6 | `favoritos` |
| `CupomService` | 3 | `cupons` |
| `CartService` | 6 | `carrinho` |
| `CartaoService` | 3 | `cartoes_usuario` |
| `GymService` | 17 | `aulas`, `aulas_inscricao`, `perfis`, `personal_sessoes`, `avaliacoes`, `progresso_fotos`, `conversas`, `mensagens`, `desafios`, `desafios_participantes`, `indicacoes`, `pedidos` |
| `NutritionService` | 5 | `agua_registro`, `assinaturas`, `nutricionistas`, `consultas`, `treinos`, `exercicios` |
| `ChatService` | 9 | `conversas`, `mensagens`, `perfis`, `unidades`, `pedidos`, `pedido_itens` |
| `AdminService` | 33 | `produtos`, `categorias`, `marcas`, `posts_feed`, `candidaturas`, `perfis`, `plano_refeicoes`, `assinaturas`, `nutricionistas`, `consultas`, `treinos`, `exercicios` |
| `SupabaseService` | 3 | Singleton (initialize) |

---

## 9. MODELS (16 classes)

| Model | Uso |
|-------|-----|
| `UserProfile` | Perfil do usuário + unidade vinculada |
| `Produto` | Produto com preço, imagem, categoria, marca, unidade |
| `Categoria` | Categoria de produto |
| `Marca` | Marca de produto |
| `Cupom` | Cupom de desconto |
| `CartItem` | Item do carrinho com produto info |
| `CartaoCredito` | Cartão salvo do usuário |
| `FeedPost` | Post do feed com likes, unidade, autor |
| `FeedComment` | Comentário de post |
| `Favorito` | Item favoritado |
| `Assinatura` | Assinatura de plano nutricional |
| `Aula` / `PersonalSession` / `Avaliacao` | Modelos de academia (3 em 1 arquivo) |
| `Exercicio` | Exercício de treino |
| `Treino` | Treino (ficha de dia) |
| `Nutricionista` | Profissional de nutrição |
| `PlanoRefeicao` | Refeição do plano nutricional |

---

## 10. WIDGETS REUTILIZÁVEIS (8)

| Widget | Uso |
|--------|-----|
| `AppTopBar` | Top bar padrão (search/title + bottom widget) |
| `CustomDrawer` | Drawer lateral com menu por role |
| `BottomNav` | Via MainShell (5 abas) |
| `FeedCard` | Card de post do feed (imagem, vídeo, like, comentários) |
| `FeaturedCard` | Card de produto horizontal (home) |
| `UnitCard` | Card de unidade (imagem, nome, bairro, endereço) |
| `AnimatedCardEntry` | Animação de entrada com fade + slide |
| `VideoCard` | Card específico para vídeos |

---

## 11. STORAGE BUCKETS

| Bucket | Uso | RLS |
|--------|-----|-----|
| `Produtos` | Imagens de produtos | ✅ Pública |
| `fotos_perfil` | Avatares de usuários | ⚠️ Verificar |
| `Curriculos` | PDFs de candidatura a vagas | ⚠️ Verificar |

---

## 12. SUPABASE REALTIME

| Canal | Tabela | Filtro | Uso |
|-------|--------|--------|-----|
| `mensagens_$conversaId` | `mensagens` | `conversa_id = $id` | Chat em tempo real |
| `novas_mensagens` | `mensagens` | — | Central de Atendimento |

---

## 13. FALHAS DE SEGURANÇA IDENTIFICADAS

### 🔴 Críticas:
1. **FK ausente `posts_feed.user_id → perfis.id`** — Impede join. Posts aparecem sem autor quando `unidade_id` é null.
2. **RLS ausente em tabelas públicas** — `unidades`, `produtos`, `aulas`, `desafios` podem não ter policies para anon/authenticated, fazendo consultas retornarem vazio.
3. **Storage sem policies** — Upload de fotos e currículos pode ser bloqueado ou permitido sem controle.

### 🟡 Médias:
4. **Recursão potencial em policies de mensagens** — Subquery em `conversas` → `perfis` pode causar loop.
5. **Remetente_id enviado pelo cliente** — A policy `remetente_id = auth.uid()` protege, mas o Flutter ainda envia o ID. Ideal seria usar `auth.uid()` direto na query.
6. **`perfis.funcao` como string** — Sem `CHECK` constraint, qualquer string pode ser inserida como função.

### 🟢 Leves:
7. **Senha reset sem confirmação** — `resetPasswordForEmail` sem verificação de token expirado.
8. **Carrinho sem limite de quantidade** — Sem validação de estoque no backend.

---

## 14. PROBLEMAS CONHECIDOS (Bugs)

1. **Feed não mostra posts sem `unidade_id`** — Nome do autor fica como "Aires Health" genérico.
2. **`DiagnosticsProperty<void>` no feed** — Erro de renderização causado por `FlexParentData` em `Expanded` fora de `Row/Column` (já corrigido).
3. **Cart error** — `Erro cart: type 'List<dynamic>' is not a subtype of type 'String?'` — Incompatibilidade de tipo no cart service.
4. **Unidades sem `slug` não podem ser inseridas** — NOT NULL sem default. Admin form não envia `slug`.
5. **`pedido_itens.produto_id` FK possivelmente ausente** — Join `produtos!produto_id` pode falhar.
6. **Vídeos no feed** — thumbnails do YouTube substituíram o player real para evitar overflow do platform view.

---

## 15. FLUXOS PRINCIPAIS

### Cliente:
```
Login → Home (produtos, promoções) → Feed (posts, vagas, eventos) → 
Unidades (lista por bairro) → Detalhe da Unidade (mapa + produtos + chat) →
Carrinho → Checkout → Pedidos
```

### Admin:
```
Drawer → Admin Screen (10 abas):
Produtos | Categorias | Marcas | Candidaturas | Posts | Unidades | Cupons | Usuários | Nutrição | Treinos
```

### Atendente:
```
Drawer → Central de Atendimento → Lista de Conversas → Chat → Responder Cliente
```
