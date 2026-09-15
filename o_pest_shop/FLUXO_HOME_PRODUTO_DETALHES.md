# FLUXO HOME → PRODUTO → DETALHES

## Documentação Técnica da Arquitetura Atual

---

## PARTE 1 — ESTRUTURA DE ARQUIVOS

```
lib/
├── services/
│   └── produto_service.dart          # Serviço de busca de produtos (Supabase)
├── providers/
│   └── home_provider.dart            # Estado da Home (ChangeNotifier)
├── models/
│   └── produto.dart                  # Modelo de dados do Produto
├── router/
│   └── app_router.dart               # Rotas (GoRouter)
├── ui/
│   ├── screens/
│   │   ├── home/
│   │   │   └── home_screen.dart      # Tela inicial / Home
│   │   └── product/
│   │       └── product_detail_screen.dart  # Tela de detalhes do produto
│   └── widgets/
│       ├── featured_card.dart        # Card do produto na Home
│       └── animated_card_entry.dart  # Animação de entrada dos cards
```

---

## PARTE 2 — TELA INICIAL / HOME

**Arquivo:** `lib/ui/screens/home/home_screen.dart`
**Classe:** `HomeScreen` (StatefulWidget) / `_HomeScreenState` (State)
**Widget principal:** `Scaffold` > `Column` > `AppTopBar` + `Expanded(Consumer<HomeProvider>)`

### Fluxo de dados:

```
Supabase (tabela "produtos")
    ↓
ProdutoService.fetchProdutos({lastId})  ← paginação por cursor (20 itens)
    ↓
List<Produto> (model)
    ↓
HomeProvider._produtos
    ↓
Consumer<HomeProvider> na HomeScreen
    ↓
_buildAllCategoriesView() → _buildCategoriasBlocks() → _buildSectionWithScroll()
    ↓
FeaturedCard (card do produto)
```

### Provider/Estado:

- **Provider:** `HomeProvider` (ChangeNotifier em `lib/providers/home_provider.dart`)
- **Inicialização:** `WidgetsBinding.instance.addPostFrameCallback` → `context.read<HomeProvider>().loadHomeData()`
- **Refresh:** `HomeProvider.refresh()` chamado via `MainShell` ao trocar para aba Home
- **Paginação:** `HomeProvider.loadMore()` (cursor por `lastProductId`, pageSize=20)
- **Detecção scroll:** `_productScrollController` com listener a 400px do fim

### Queries Supabase (ProdutoService.fetchProdutos):

```dart
SELECT *, categorias(nome), marcas(nome), unidades(nome)
FROM produtos
[WHERE categoria_id = ?]       // opcional
[WHERE id > ?]                 // paginação por cursor
ORDER BY id
LIMIT 20
```

---

## PARTE 3 — CARD DO PRODUTO (FeaturedCard)

**Arquivo:** `lib/ui/widgets/featured_card.dart`
**Classe:** `FeaturedCard` (StatelessWidget)

### Parâmetros:
| Parâmetro | Tipo | Origem |
|-----------|------|--------|
| `produto` | `Produto` | Modelo completo |
| `onTap` | `VoidCallback?` | Navegação para `/produto/:id` |

### Estrutura do Card:

```
Container(width: 160, borderRadius, shadow)
  └── Column
      ├── Expanded
      │   └── Container
      │       └── CachedNetworkImage (fit: BoxFit.contain, url: produto.urlImagem.first)
      │            OU Icon (fallback se sem imagem)
      └── Padding
          └── Column
              ├── SizedBox(4)
              ├── Text(produto.nome, bodySmall, bold, maxLines:2)
              ├── SizedBox(4)
              ├── Text("R\$ ${preco}", titleSmall, bold)
              └── [Se unidadeNome != null]
                  ├── SizedBox(2)
                  └── Text(unidadeNome, fontSize:9, blue #0052FF, bold)
```

### Dados exibidos no Card:
- **Imagem:** `produto.urlImagem.first` (primeira URL da lista)
- **Nome:** `produto.nome`
- **Preço:** `R$ ${produto.precoAtual.toStringAsFixed(2)}`
- **Unidade:** `produto.unidadeNome` (azul, opcional)
- **Estoque:** NÃO exibido no FeaturedCard

---

## PARTE 4 — IMAGEM DO PRODUTO NA HOME

**Widget:** `CachedNetworkImage` (pacote `cached_network_image`)

```dart
CachedNetworkImage(
    imageUrl: produto.urlImagem.first,
    fit: BoxFit.contain,
    placeholder: (_, __) => Center(child: CircularProgressIndicator(strokeWidth: 2)),
    errorWidget: (_, __, ___) => Icon(Icons.image_outlined, color: AppColors.hint),
)
```

- **URL:** `produto.urlImagem.first` — campo `url_imagem` (JSON array de strings) na tabela `produtos`
- **Cache:** `CachedNetworkImage` gerencia cache automaticamente
- **Placeholder:** `CircularProgressIndicator`
- **Error:** `Icon(Icons.image_outlined)`
- **Fallback:** Se `urlImagem` vazio → `Icon(Icons.image_outlined)`

---

## PARTE 5 — CLIQUE NO PRODUTO

**Arquivo:** `lib/ui/widgets/featured_card.dart`
**Classe:** `FeaturedCard`
**Widget de toque:** `GestureDetector` (envolve todo o Container do card)
**Método:** `onTap` callback recebido como parâmetro

### Fluxo do clique:

```
Usuário toca no card
    ↓
GestureDetector.onTap dispara
    ↓
onTap() definido em home_screen.dart (Consumer builder)
    ↓
context.push('/produto/${produtos[index].id}')
```

No `_buildSectionWithScroll` da HomeScreen:
```dart
onTap: () => context.push('/produto/${produtos[index].id}'),
```

---

## PARTE 6 — NAVEGAÇÃO PARA DETALHES

**Pacote:** `go_router` (GoRouter)

**Arquivo de rotas:** `lib/router/app_router.dart`

**Definição da rota:**
```dart
GoRoute(
    path: '/produto/:id',
    builder: (_, s) => ProductDetailScreen(
        produtoId: int.parse(s.pathParameters['id']!),
    ),
)
```

**Parâmetros enviados:**
- Apenas `produtoId` (int) — extraído de `pathParameters['id']`
- O objeto `Produto` NÃO é enviado para a tela de detalhes

**Método de navegação:** `context.push('/produto/${produtos[index].id}')`

---

## PARTE 7 — TELA DE DETALHES

**Arquivo:** `lib/ui/screens/product/product_detail_screen.dart`
**Classe:** `ProductDetailScreen` (StatefulWidget)

### Parâmetros de entrada:
```dart
class ProductDetailScreen extends StatefulWidget {
    final int produtoId;
    const ProductDetailScreen({super.key, required this.produtoId});
}
```

### Fluxo de carregamento:
```
Recebe apenas produtoId (int)
    ↓
initState → _loadProduto()
    ↓
ProdutoService.fetchProdutoById(produtoId)
    ↓
Nova consulta ao Supabase (NÃO usa o objeto da Home)
    ↓
Produto? _produto
    ↓
_buildBody() ou "Produto não encontrado"
```

### Query Supabase (fetchProdutoById):
```dart
SELECT *, categorias(nome), marcas(nome), galeria_produtos(url_imagem), unidades(nome)
FROM produtos
WHERE id = :produtoId
```

### Estrutura da tela:
```
Scaffold
  ├── AppBar (custom PreferredSize, 56px)
  │   └── Row: back + share + cart buttons
  ├── Body: SingleChildScrollView
  │   └── Column
  │       ├── _buildImageSection (360px height, PageView de imagens)
  │       ├── _buildInfoSection (nome, preço, frete, descrição)
  │       └── SizedBox(height: lg)
  └── bottomNavigationBar: _buildBottomBar (add to cart + buy buttons)
```

### Dados exibidos nos detalhes:
- **Imagens:** `PageView` com `CachedNetworkImage`, `fit: BoxFit.contain`, dots indicators
- **Nome:** `produto.nome` — `titleLarge`, fontWeight w600
- **Preço:** `R$ ${precoAtual}` — `headlineLarge`
- **Desconto:** Badge `% OFF` se `temDesconto`
- **Parcelas:** `em Xx de R$ Y sem juros`
- **Frete grátis:** Ícone + texto "Frete grátis" se `freteGratis`
- **Garantia:** Texto da garantia
- **Descrição:** Texto do produto
- **Unidade:** `produto.unidadeNome` (no texto do frete: "Chega hoje em ${unidadeNome}")
- **Estoque:** NÃO exibido na tela de detalhes

---

## PARTE 8 — IMAGEM NA TELA DE DETALHES

**Widget:** `CachedNetworkImage` dentro de `PageView` com `PageController`

```dart
PageView.builder(
    controller: _pageController,
    itemCount: imagens.length,
    itemBuilder: (_, i) => CachedNetworkImage(
        imageUrl: imagens[i],
        fit: BoxFit.contain,
        placeholder: (_, __) => Center(child: CircularProgressIndicator(strokeWidth: 2)),
        errorWidget: (_, __, ___) => Container(
            color: ThemeColors.surfaceVariant(context),
            child: Icon(Icons.image_outlined, color: ThemeColors.hint(context), size: 64),
        ),
    ),
)
```

- **Container:** 360px height, `ThemeColors.surface` background
- **Page dots:** `AnimatedContainer` indicando página atual
- **Botão favoritar:** `Positioned` no canto superior direito
- **Fonte das imagens:** `produto.urlImagem` (mesmo campo da Home — `url_imagem`)

**Comparação Home vs Detalhes:**
| Aspecto | Home (FeaturedCard) | Detalhes (ProductDetailScreen) |
|---------|-------------------|-------------------------------|
| URL | `urlImagem.first` | `urlImagem[i]` (múltiplas) |
| Widget | `CachedNetworkImage` | `CachedNetworkImage` |
| Fit | `BoxFit.contain` | `BoxFit.contain` |
| Cache | `cached_network_image` | `cached_network_image` |
| Origem | Mesmo `Produto.urlImagem` | Mesmo `Produto.urlImagem` |

**Ambas usam a mesma ORIGEM de imagem** (campo `url_imagem` da tabela `produtos`), porém:
- Home exibe apenas a primeira imagem (`urlImagem.first`)
- Detalhes exibe todas as imagens em um `PageView`

---

## PARTE 9 — RELAÇÃO ENTRE CARD E DETALHES

**NÃO EXISTE ATUALMENTE UMA SHARED ELEMENT TRANSITION IMPLEMENTADA ENTRE A HOME E OS DETALHES.**

A navegação usa a transição padrão do GoRouter/MaterialPageRoute (slide da direita para esquerda no Android).

Não há:
- ❌ `Hero` widget
- ❌ `HeroController`
- ❌ `OpenContainer`
- ❌ `PageRouteBuilder` customizado
- ❌ `SharedElementTransition`
- ❌ Nenhum mecanismo de animação conectando o card da Home à tela de detalhes

---

## PARTE 10 — IDENTIDADE ÚNICA DO PRODUTO

| Propriedade | Valor |
|-------------|-------|
| **Campo** | `id` |
| **Tipo** | `int` |
| **Tabela Supabase** | `produtos` (PK, serial) |
| **Model Flutter** | `Produto.id` (int) |
| **Usado na Home** | `context.push('/produto/${p.id}')` |
| **Usado nos Detalhes** | `widget.produtoId` → `ProdutoService.fetchProdutoById(id)` |

Este `id` seria a `HeroTag` ideal para uma futura Shared Element Animation.

---

## PARTE 11 — SUPABASE (Fluxo Home → Detalhes)

### Tabela: `produtos`

**Colunas utilizadas no fluxo:**
| Coluna | Tipo | Uso |
|--------|------|-----|
| `id` | int (PK) | Identificador único |
| `nome` | text | Nome do produto |
| `descricao` | text | Descrição |
| `preco` | numeric | Preço |
| `url_imagem` | jsonb | Array de URLs de imagens |
| `categoria_id` | int (FK → categorias.id) | Categoria |
| `marca_id` | int? (FK → marcas.id) | Marca |
| `unidade_id` | int? (FK → unidades.id) | Unidade responsável |
| `em_promocao` | bool | Se está em promoção |
| `frete_gratis` | bool | Frete grátis |
| `garantia` | text? | Garantia |
| `parcelas` | int | Número de parcelas |
| `percentual_desconto` | int? | % de desconto |
| `estoque` | int | Quantidade em estoque |
| `vendas` | int | Contagem de vendas |

### Joins utilizados:

**Home (fetchProdutos):**
```dart
SELECT *, categorias(nome), marcas(nome), unidades(nome)
FROM produtos
ORDER BY id LIMIT 20
```

**Detalhes (fetchProdutoById):**
```dart
SELECT *, categorias(nome), marcas(nome), galeria_produtos(url_imagem), unidades(nome)
FROM produtos WHERE id = :id
```

### Tabelas relacionadas:
| Tabela | Join | Coluna usada |
|--------|------|-------------|
| `categorias` | `produtos.categoria_id → categorias.id` | `nome` |
| `marcas` | `produtos.marca_id → marcas.id` | `nome` |
| `unidades` | `produtos.unidade_id → unidades.id` | `nome` |
| `galeria_produtos` | `produtos.id = galeria_produtos.produto_id` | `url_imagem` |

---

## PARTE 12 — MAPA COMPLETO DO FLUXO

```
SUPABASE (tabela "produtos")
│
├── Home:  SELECT + joins categorias(nome), marcas(nome), unidades(nome)  ORDER BY id LIMIT/pageSize
│   └── ProdutoService.fetchProdutos({categoriaId?, lastId?})
│       └── lib/services/produto_service.dart
│
├── Detalhes:  SELECT + joins categorias(nome), marcas(nome), galeria_produtos, unidades(nome)  WHERE id = ?
│   └── ProdutoService.fetchProdutoById(id)
│       └── lib/services/produto_service.dart
│
└── Model Produto
    └── lib/models/produto.dart
    │
    ├── Home
    │   ├── HomeProvider._produtos (List<Produto>)
    │   │   └── lib/providers/home_provider.dart
    │   ├── Consumer<HomeProvider> na HomeScreen
    │   │   └── lib/ui/screens/home/home_screen.dart
    │   ├── _buildAllCategoriesView → _buildCategoriasBlocks → _buildSectionWithScroll
    │   │   └── lib/ui/screens/home/home_screen.dart
    │   ├── FeaturedCard(produto: produtos[index], onTap: ...)
    │   │   └── lib/ui/widgets/featured_card.dart
    │   │   ├── CachedNetworkImage (primeira imagem)
    │   │   ├── Text(nome)
    │   │   ├── Text(preço)
    │   │   └── Text(unidadeNome) [azul, opcional]
    │   └── GestureDetector.onTap → context.push('/produto/${p.id}')
    │
    └── Detalhes
        ├── GoRouter: /produto/:id
        │   └── lib/router/app_router.dart
        ├── ProductDetailScreen(produtoId: int)
        │   └── lib/ui/screens/product/product_detail_screen.dart
        ├── _loadProduto() → ProdutoService.fetchProdutoById(id)
        ├── _buildImageSection → PageView + CachedNetworkImage (múltiplas)
        ├── _buildInfoSection → nome, preço, frete, descrição
        └── _buildBottomBar → botões "Adicionar ao Carrinho" + "Comprar Agora"
```

---

## PARTE 13 — PONTOS EXATOS PARA IMPLEMENTAR SHARED ELEMENT

| Item | Local | Sugestão |
|------|-------|----------|
| **Hero na Home** | `featured_card.dart` — `CachedNetworkImage` (linha ~42) | Envolver imagem em `Hero(tag: 'produto_${produto.id}')` |
| **Hero tag** | Derivada de `produto.id` | `'produto_${produto.id}'` |
| **Hero nos Detalhes** | `product_detail_screen.dart` — `CachedNetworkImage` no `PageView` (linha ~132) | Envolver imagem em `Hero(tag: 'produto_${_produto!.id}')` |
| **Ponto de início** | `FeaturedCard.onTap` → `context.push('/produto/:id')` | Manter navegação GoRouter, o Hero lida com a animação |
| **Ponto de término** | `ProductDetailScreen.build` → `_buildImageSection` | O Hero no detalhe deve estar visível no primeiro frame |
| **Desafio** | Detalhes carrega produto via `fetchProdutoById` (requisição separada) | A Hero tag precisa ser conhecida antes do produto carregar. Solução: usar o `produtoId` do widget como tag, ou criar Hero com tag baseada no ID mesmo antes do carregamento |

---

## PARTE 14 — FLUXO VISUAL ATUAL

**Transição atual:** Transição padrão do GoRouter/MaterialPageRoute.

- **Tipo:** `PageRouteBuilder` padrão (slide horizontal)
- **Direção:** Da direita para a esquerda (nova tela desliza sobre a anterior)
- **Duração:** 300ms (padrão Material)
- **Hero:** ❌ NÃO existe
- **Fade:** ❌ NÃO existe (além do fade padrão do slide)
- **Slide:** ✅ Transição padrão de slide horizontal
- **Shared Element:** ❌ NÃO existe

Não há qualquer animação personalizada conectando o card do produto da Home à sua representação na tela de detalhes.

---

## PARTE 15 — TABELA DE REFERÊNCIA

| Elemento | Arquivo | Classe/Widget | Origem | Destino |
|----------|---------|---------------|--------|---------|
| **Produto** | `lib/models/produto.dart` | `Produto` | Supabase `produtos` | Home + Detalhes |
| **ID** | `lib/models/produto.dart:5` | `int id` | `produtos.id` (PK, serial) | Router `/produto/:id` |
| **Imagem** | `lib/models/produto.dart:9` | `List<String> urlImagem` | `produtos.url_imagem` (jsonb) | Home: `[0]` / Detalhes: `[i]` |
| **Imagem (Home)** | `lib/ui/widgets/featured_card.dart:42` | `CachedNetworkImage` | `urlImagem.first` | Card visual |
| **Imagem (Detalhes)** | `lib/ui/screens/product/product_detail_screen.dart:132` | `CachedNetworkImage` (PageView) | `urlImagem[i]` | Detalhes visual |
| **Nome** | `lib/models/produto.dart:6` | `String nome` | `produtos.nome` | Card + Detalhes |
| **Preço** | `lib/models/produto.dart:8` | `double preco` | `produtos.preco` | Card + Detalhes |
| **Unidade** | `lib/models/produto.dart:16` | `String? unidadeNome` | `unidades(nome)` join | Card (azul) + Detalhes (frete) |
| **Estoque** | `lib/models/produto.dart:12` | `int estoque` | `produtos.estoque` | Card (Admin) / ❌ Não no FeaturedCard |
| **Navegação** | `lib/router/app_router.dart` | `GoRouter.push('/produto/$id')` | `context.push()` | GoRouter → ProductDetailScreen |
| **Service** | `lib/services/produto_service.dart` | `ProdutoService` | Supabase | Providers |
| **Provider** | `lib/providers/home_provider.dart` | `HomeProvider` | ProdutoService | HomeScreen Consumer |
| **Card** | `lib/ui/widgets/featured_card.dart` | `FeaturedCard` | HomeProvider._produtos | ListView horizontal |
| **Detalhes** | `lib/ui/screens/product/product_detail_screen.dart` | `ProductDetailScreen` | GoRouter + fetchProdutoById | Tela cheia |
| **Cache imagem** | `cached_network_image: ^3.4.1` | `CachedNetworkImage` | Mesmo pacote | Home + Detalhes |
| **Hero atual** | ❌ NÃO EXISTE | — | — | — |
