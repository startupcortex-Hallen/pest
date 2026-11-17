import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/helpers/categoria_icons.dart';
import '../../../core/helpers/scale_helper.dart';
import '../../../core/helpers/theme_colors.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/categoria.dart';
import '../../../models/produto.dart';
import '../../../providers/home_provider.dart';
import '../../widgets/animated_card_entry.dart';
import '../../widgets/app_states.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/banner_carousel.dart';
import '../../widgets/custom_drawer.dart';
import '../../widgets/featured_card.dart';
import '../product/product_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _categoryScrollController = ScrollController();
  final _productScrollController = ScrollController();
  static const _kCategoryScrollDuration = Duration(milliseconds: 500);
  int? _selectedCategoriaId;
  int? _loadedCategoriaId;
  int _lastRefreshCount = -1;
  bool _primeiroResume = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _productScrollController.addListener(_onProductScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HomeProvider>().loadHomeData();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _categoryScrollController.dispose();
    _productScrollController.dispose();
    super.dispose();
  }

  /// Ao voltar para o app, recarrega a home — dados e fotos ficam
  /// atualizados (ex.: depois de uma alteração feita no Supabase).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    if (_primeiroResume) {
      _primeiroResume = false;
      return;
    }
    context.read<HomeProvider>().loadIfStale();
  }

  void _onProductScroll() {
    final home = context.read<HomeProvider>();
    if (_selectedCategoriaId != null || !home.hasMore || home.isLoadingMore) return;
    final maxScroll = _productScrollController.position.maxScrollExtent;
    final current = _productScrollController.position.pixels;
    if (maxScroll - current <= 400) {
      home.loadMore();
    }
  }

  void _scrollToCategory(int index) {
    if (!_categoryScrollController.hasClients) return;
    final screenWidth = MediaQuery.of(context).size.width;
    const itemWidth = 68.0;
    final targetOffset =
        (index * itemWidth) - (screenWidth / 2 - itemWidth / 2);
    final clamped = targetOffset.clamp(
      0.0,
      _categoryScrollController.position.maxScrollExtent,
    );
    _categoryScrollController.animateTo(
      clamped,
      duration: _kCategoryScrollDuration,
      curve: Curves.easeInOutCubic,
    );
  }

  void _scrollToTopSmoothly() {
    if (!_productScrollController.hasClients) return;
    if (_productScrollController.offset <= 0) return;
    _productScrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  void _selecionarCategoria(int? categoriaId, int index) {
    setState(() {
      _selectedCategoriaId = categoriaId;
      _loadedCategoriaId = null;
      _lastRefreshCount = -1;
    });
    _scrollToCategory(index);
    _scrollToTopSmoothly();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: ThemeColors.background(context),
      drawer: const CustomDrawer(),
      body: Column(
        children: [
          AppTopBar.withSearch(
            onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
            onSearchTap: () => context.push('/busca'),
          ),
          Expanded(
            child: Consumer<HomeProvider>(
              builder: (context, home, _) {
                if (_selectedCategoriaId != null) {
                  if (_loadedCategoriaId != _selectedCategoriaId ||
                      _lastRefreshCount != home.refreshCount) {
                    if (!home.loading) {
                      _loadedCategoriaId = _selectedCategoriaId;
                      _lastRefreshCount = home.refreshCount;
                      // Carrega após o build para evitar "setState during build"
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          home.loadProdutosPorMarca(_selectedCategoriaId!);
                        }
                      });
                    }
                  }
                } else {
                  _loadedCategoriaId = null;
                }

                return _buildScrollableBody(context, home);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(HomeProvider home) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, color: AppColors.hint, size: 48),
            const SizedBox(height: AppSpacing.md),
            Text(
              home.error!,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.secondaryText),
            ),
            const SizedBox(height: AppSpacing.md),
            ElevatedButton(
              onPressed: home.loadHomeData,
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }

  // ─── CORPO COM CUSTOMSCROLLVIEW + SLIVERS ───────────

  Widget _buildScrollableBody(BuildContext context, HomeProvider home) {
    final showFeedLoading = home.loading &&
        (_selectedCategoriaId == null
            ? home.produtos.isEmpty
            : home.produtosPorMarca.isEmpty);
    final showBannerSkeleton =
        home.loading && home.banners.isEmpty && home.produtos.isEmpty;
    final showFeedError = home.error != null &&
        home.produtos.isEmpty &&
        home.produtosPorMarca.isEmpty;

    final cardHeight = context.h(104).clamp(88.0, 120.0);
    final verticalPad = context.w(AppSpacing.sm).clamp(6.0, 12.0);
    final headerExtent = cardHeight + (verticalPad * 2);
    final bottomSafePadding =
        context.h(96).clamp(88.0, 116.0) + MediaQuery.of(context).padding.bottom;

    return RefreshIndicator(
      onRefresh: () async {
        await context.read<HomeProvider>().refresh();
      },
      color: ThemeColors.primary(context),
      child: CustomScrollView(
        controller: _productScrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // 1. Carrossel de banners (ou skeleton / respiro quando vazio)
          if (showBannerSkeleton)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: AppSkeleton(
                      height: context.h(184).clamp(156.0, 220.0),
                      radius: 24,
                    ),
                  ),
                ),
              ),
            )
          else if (home.banners.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 20, bottom: 24),
                child: BannerCarousel(
                  key: ValueKey('banners_${home.refreshCount}'),
                  banners: home.banners,
                  onTap: _abrirBanner,
                ),
              ),
            )
          else
            const SliverToBoxAdapter(
              child: SizedBox(height: 12),
            ),

          // 2. Menu de categorias fixo (sticky) ao rolar
          SliverPersistentHeader(
            pinned: true,
            delegate: _CategoriesStickyHeaderDelegate(
              extent: headerExtent,
              backgroundColor: ThemeColors.background(context),
              child: _buildCategoriesCard(
                context,
                categorias: home.categorias,
                cardHeight: cardHeight,
                verticalPadding: verticalPad,
              ),
            ),
          ),

          // 3. Conteúdo do feed (loading, erro ou seções de produtos)
          if (showFeedLoading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (showFeedError)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildErrorState(home),
            )
          else
            ..._buildFeedSlivers(context, home, bottomSafePadding),
        ],
      ),
    );
  }

  List<Widget> _buildFeedSlivers(
    BuildContext context,
    HomeProvider home,
    double bottomSafePadding,
  ) {
    final secoes = _montarSecoes(home);
    return [
      SliverPadding(
        padding: EdgeInsets.only(
          top: context.h(18).clamp(14.0, 26.0),
          bottom: bottomSafePadding,
        ),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final s = secoes[index];
              if (s.builder != null) return s.builder!(context);
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                child: _buildSectionWithScroll(
                  context,
                  titulo: s.titulo!,
                  subtitle: s.subtitulo,
                  produtos: s.produtos!,
                ),
              );
            },
            childCount: secoes.length,
          ),
        ),
      ),
    ];
  }

  /// Monta as seções do feed sob demanda (só as visíveis são construídas).
  List<_Secao> _montarSecoes(HomeProvider home) {
    if (_selectedCategoriaId != null) {
      final porMarca = home.produtosPorMarca;
      if (porMarca.isEmpty) {
        return [
          _Secao.custom(
            (context) => _buildEmptyMessage(context, 'Nenhum produto encontrado'),
          ),
        ];
      }
      return porMarca.entries
          .map(
            (entry) => _Secao.produtos(
              titulo: entry.key,
              subtitulo:
                  '${entry.value.length} ${entry.value.length == 1 ? 'item' : 'itens'}',
              produtos: entry.value,
            ),
          )
          .toList();
    }

    final secoes = <_Secao>[];
    if (home.promocoes.isNotEmpty) {
      secoes.add(
        _Secao.custom(
          (context) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            child: _buildFlashOffersSection(home),
          ),
        ),
      );
    }

    // Deduplica produtos entre as seções (Ofertas + blocos por categoria):
    // garante 1 aparição por produto na tela → 1 Hero por tag → voo de volta
    // sempre aterrissa no card certo, mesmo com catálogo grande.
    final jaExibidos = home.promocoes.map((p) => p.id).toSet();
    final Map<int, List<Produto>> porCategoria = {};
    for (final p in home.produtos) {
      if (jaExibidos.contains(p.id)) continue;
      jaExibidos.add(p.id);
      porCategoria.putIfAbsent(p.categoriaId, () => []);
      porCategoria[p.categoriaId]!.add(p);
    }

    final sortedEntries = porCategoria.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    for (final entry in sortedEntries) {
      final catNome = entry.value.first.categoriaNome ?? 'Categoria';
      secoes.add(
        _Secao.produtos(
          titulo: catNome,
          subtitulo:
              '${entry.value.length} ${entry.value.length == 1 ? 'item' : 'itens'}',
          produtos: entry.value,
        ),
      );
    }

    if (home.isLoadingMore) {
      secoes.add(
        _Secao.custom(
          (context) => const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ),
      );
    }

    if (secoes.isEmpty) {
      secoes.add(
        _Secao.custom(
          (context) => _buildEmptyMessage(context, 'Nenhum produto encontrado'),
        ),
      );
    }
    return secoes;
  }

  Widget _buildEmptyMessage(BuildContext context, String msg) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.branding_watermark_outlined, color: AppColors.hint, size: 48),
          const SizedBox(height: AppSpacing.md),
          Text(msg, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.secondaryText)),
        ],
      ),
    );
  }

  // ─── SEÇÃO GENÉRICA (TÍTULO + LISTA HORIZONTAL) ────

  Widget _buildSectionWithScroll(
    BuildContext context, {
    required String titulo,
    String? subtitle,
    required List<Produto> produtos,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: context.w(AppSpacing.md)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  titulo,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (subtitle != null)
                Padding(
                  padding: EdgeInsets.only(left: context.w(AppSpacing.sm)),
                  child: Text(
                    subtitle,
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: ThemeColors.secondaryText(context)),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: context.h(AppSpacing.md)),
        SizedBox(
          height: context.h(220).clamp(200.0, 280.0),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: EdgeInsets.only(left: context.w(AppSpacing.md)),
            itemCount: produtos.length,
            separatorBuilder: (_, _) =>
                SizedBox(width: context.w(AppSpacing.md)),
            itemBuilder: (context, index) {
              return AnimatedCardEntry(
                index: index,
                animate: index < 6,
                child: FeaturedCard(
                  produto: produtos[index],
                  onTap: () => ProductDetailScreen.push(
                    context,
                    produtos[index].id,
                    imageUrl: produtos[index].urlImagem.isNotEmpty ? produtos[index].urlImagem.first : null,
                  ),
                  onLongPress: () => _mostrarQuickView(produtos[index]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ─── OFERTAS RELÂMPAGO ──────────────────────────────

  Future<void> _abrirBanner(Map<String, dynamic> banner) async {
    final link = (banner['link_url'] as String?)?.trim() ?? '';
    if (link.isEmpty) return;
    if (link.startsWith('/')) {
      context.push(link);
      return;
    }
    final uri = Uri.tryParse(link);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildFlashOffersSection(HomeProvider home) {
    final produtos = home.promocoes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: context.w(AppSpacing.md)),
          child: Row(
            children: [
              Text(
                'Ofertas Relâmpago',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              SizedBox(width: context.w(AppSpacing.md)),
              Lottie.asset(
                'assets/clock_animation.json',
                width: 20,
                height: 20,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'Ofertas por tempo limitado',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: const Color(0xFFFF6B00),
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
        ),
        SizedBox(height: context.h(AppSpacing.md)),
        SizedBox(
          height: context.h(220).clamp(200.0, 280.0),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: EdgeInsets.only(left: context.w(AppSpacing.md)),
            itemCount: produtos.length,
            separatorBuilder: (_, _) =>
                SizedBox(width: context.w(AppSpacing.md)),
            itemBuilder: (context, index) {
              return AnimatedCardEntry(
                index: index,
                animate: index < 6,
                child: FeaturedCard(
                  produto: produtos[index],
                  onTap: () => ProductDetailScreen.push(
                    context,
                    produtos[index].id,
                    imageUrl: produtos[index].urlImagem.isNotEmpty
                        ? produtos[index].urlImagem.first
                        : null,
                  ),
                  onLongPress: () => _mostrarQuickView(produtos[index]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ─── CATEGORIAS (header sticky dentro do CustomScrollView) ───

  Widget _buildCategoriesCard(
    BuildContext context, {
    required List<Categoria> categorias,
    required double cardHeight,
    required double verticalPadding,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: context.w(AppSpacing.md),
        vertical: verticalPadding,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ThemeColors.surface(context),
          borderRadius: BorderRadius.circular(16),
        ),
        child: SizedBox(
          height: cardHeight,
          child: ListView.separated(
            controller: _categoryScrollController,
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(
              horizontal: context.w(AppSpacing.sm),
              vertical: context.h(AppSpacing.sm),
            ),
            itemCount: categorias.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
            itemBuilder: (context, index) {
              if (index == 0) {
                return _buildCategoryItem(
                  'Todos',
                  Icons.grid_view_rounded,
                  isSelected: _selectedCategoriaId == null,
                  onTap: () => _selecionarCategoria(null, index),
                );
              }
              if (categorias.isNotEmpty) {
                final cat = categorias[index - 1];
                return _buildCategoryItem(
                  cat.nome,
                  _getIconForCategory(cat.nome, cat.icone),
                  isSelected: _selectedCategoriaId == cat.id,
                  onTap: () => _selecionarCategoria(cat.id, index),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryItem(
    String nome,
    IconData icon, {
    bool isSelected = false,
    VoidCallback? onTap,
  }) {
    final bgColor = isSelected
        ? AppColors.primary.withValues(alpha: 0.15)
        : AppColors.surfaceVariant;
    final iconColor =
        isSelected ? AppColors.primary : AppColors.secondaryText;
    final textColor =
        isSelected ? AppColors.primary : AppColors.secondaryText;
    final iconSize = context.w(48).clamp(40.0, 56.0);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: iconSize,
            height: iconSize,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(context.w(12).clamp(10.0, 16.0)),
            ),
            child: Icon(icon, color: iconColor, size: context.sp(20)),
          ),
          SizedBox(height: context.h(AppSpacing.xs)),
          SizedBox(
            width: context.w(56),
            child: Text(
              nome,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textColor,
                fontSize: context.sp(11).clamp(10.0, 12.0),
                fontWeight:
                    isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getIconForCategory(String nome, String? icone) {
    return resolverIconeCategoria(icone, nome);
  }

  void _mostrarQuickView(Produto p) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                height: 200,
                color: Colors.white,
                child: p.urlImagem.isNotEmpty
                    ? PageView.builder(
                        itemCount: p.urlImagem.length,
                        itemBuilder: (context, i) {
                          Widget img = Container(
                            color: Colors.white,
                            child: CachedNetworkImage(
                              imageUrl: p.urlImagem[i],
                              fit: BoxFit.contain,
                              useOldImageOnUrlChange: true,
                              fadeInDuration: Duration.zero,
                              fadeOutDuration: Duration.zero,
                              placeholder: (_, _) => const SizedBox.shrink(),
                              errorWidget: (_, _, _) => const Icon(Icons.image_outlined, size: 48, color: Color(0xFF9C9C9C)),
                            ),
                          );
                          if (i == 0) {
                            img = Hero(tag: 'produto_${p.id}', child: img);
                          }
                          return img;
                        },
                      )
                    : const Icon(Icons.image_outlined, size: 48, color: Color(0xFF9C9C9C)),
              ),
            ),
            if (p.urlImagem.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(p.urlImagem.length, (i) => Container(
                    width: 6, height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == 0 ? const Color(0xFFE50914) : const Color(0xFF9C9C9C),
                    ),
                  )),
                ),
              ),
            const SizedBox(height: 16),
            Text(p.nome, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            if (p.temDesconto)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('R\$ ${p.preco.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 14, color: Color(0xFF9C9C9C), decoration: TextDecoration.lineThrough)),
                  const SizedBox(width: 8),
                  Text('R\$ ${p.precoAtual.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFFF23D4F))),
                ],
              )
            else
              Text('R\$ ${p.precoAtual.toStringAsFixed(2)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  ProductDetailScreen.push(
                    context,
                    p.id,
                    imageUrl: p.urlImagem.isNotEmpty ? p.urlImagem.first : null,
                  );
                  Future.delayed(const Duration(milliseconds: 1000), () {
                    if (ctx.mounted) Navigator.pop(ctx);
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE50914),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Ver detalhes'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Seção do feed da home: linha horizontal de produtos ou widget customizado.
/// Guarda apenas os dados — o build acontece no itemBuilder do ListView,
/// que constrói somente as seções visíveis (escala com catálogos grandes).
class _Secao {
  final String? titulo;
  final String? subtitulo;
  final List<Produto>? produtos;
  final WidgetBuilder? builder;

  const _Secao.produtos({
    required this.titulo,
    this.subtitulo,
    required this.produtos,
  }) : builder = null;

  const _Secao.custom(this.builder)
      : titulo = null,
        subtitulo = null,
        produtos = null;
}

class _CategoriesStickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double extent;
  final Color backgroundColor;
  final Widget child;

  const _CategoriesStickyHeaderDelegate({
    required this.extent,
    required this.backgroundColor,
    required this.child,
  });

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final isPinned = shrinkOffset > 0 || overlapsContent;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        boxShadow: isPinned
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ]
            : const [],
      ),
      child: SizedBox.expand(child: child),
    );
  }

  @override
  bool shouldRebuild(covariant _CategoriesStickyHeaderDelegate oldDelegate) {
    return oldDelegate.extent != extent ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.child != child;
  }
}
