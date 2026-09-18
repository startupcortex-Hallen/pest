import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import '../../../core/helpers/categoria_icons.dart';
import '../../../core/helpers/scale_helper.dart';
import '../../../core/helpers/theme_colors.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/produto.dart';
import '../../../providers/home_provider.dart';
import '../../widgets/animated_card_entry.dart';
import '../../widgets/app_top_bar.dart';
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
    context.read<HomeProvider>().refresh();
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
            bottomWidget: _buildCategories(context),
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
                        if (mounted) home.loadProdutosPorMarca(_selectedCategoriaId!);
                      });
                    }
                  }
                } else {
                  _loadedCategoriaId = null;
                }

                final showLoading = home.loading &&
                    (_selectedCategoriaId == null
                        ? home.produtos.isEmpty
                        : home.produtosPorMarca.isEmpty);

                if (showLoading) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }
                if (home.error != null &&
                    home.produtos.isEmpty &&
                    home.produtosPorMarca.isEmpty) {
                  return _buildErrorState(home);
                }
                return _buildLazyFeed(home);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(HomeProvider home) {
    return Center(
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
    );
  }

  // ─── FEED LAZY (ListView.builder por seção) ─────────

  Widget _buildLazyFeed(HomeProvider home) {
    final secoes = _montarSecoes(home);
    return RefreshIndicator(
      onRefresh: () async {
        await context.read<HomeProvider>().refresh();
      },
      color: ThemeColors.primary(context),
      child: ListView.builder(
        controller: _productScrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(0, context.h(22).clamp(16.0, 32.0), 0, context.w(AppSpacing.lg)),
        itemCount: secoes.length,
        itemBuilder: (context, index) {
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
      ),
    );
  }

  /// Monta as seções do feed sob demanda (só as visíveis são construídas).
  List<_Secao> _montarSecoes(HomeProvider home) {
    if (_selectedCategoriaId != null) {
      final porMarca = home.produtosPorMarca;
      if (porMarca.isEmpty) {
        return [_Secao.custom((context) => _buildEmptyMessage(context, 'Nenhum produto encontrado'))];
      }
      return porMarca.entries.map((entry) => _Secao.produtos(
            titulo: entry.key,
            subtitulo: '${entry.value.length} ${entry.value.length == 1 ? 'item' : 'itens'}',
            produtos: entry.value,
          )).toList();
    }

    final secoes = <_Secao>[];
    if (home.promocoes.isNotEmpty) {
      secoes.add(_Secao.custom((context) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            child: _buildFlashOffersSection(home),
          )));
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
      secoes.add(_Secao.produtos(
        titulo: catNome,
        subtitulo: '${entry.value.length} ${entry.value.length == 1 ? 'item' : 'itens'}',
        produtos: entry.value,
      ));
    }

    if (home.isLoadingMore) {
      secoes.add(_Secao.custom((context) => const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )));
    }

    if (secoes.isEmpty) {
      secoes.add(_Secao.custom((context) => _buildEmptyMessage(context, 'Nenhum produto encontrado')));
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
            separatorBuilder: (_, __) =>
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
            separatorBuilder: (_, __) =>
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

  // ─── CATEGORIAS (usado como bottomWidget do AppTopBar) ───

  Widget _buildCategories(BuildContext context) {
    final home = context.watch<HomeProvider>();
    final categorias = home.categorias;
    return Container(
      margin: EdgeInsets.only(
          bottom: context.w(AppSpacing.md),
          left: context.w(AppSpacing.md),
          right: context.w(AppSpacing.md)),
      decoration: BoxDecoration(
        color: ThemeColors.surface(context),
        borderRadius: BorderRadius.circular(AppRadius.rLg(context)),
      ),
      child: SizedBox(
        height: context.h(104).clamp(88.0, 120.0),
        child: ListView.separated(
          controller: _categoryScrollController,
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(
              horizontal: context.w(AppSpacing.sm), vertical: context.h(AppSpacing.sm)),
          itemCount: categorias.length + 1,
          separatorBuilder: (_, __) =>
              const SizedBox(width: AppSpacing.xs),
          itemBuilder: (context, index) {
            if (index == 0) {
              return _buildCategoryItem(
                'Todos',
                Icons.grid_view_rounded,
                isSelected: _selectedCategoriaId == null,
                onTap: () {
                  setState(() {
                    _selectedCategoriaId = null;
                    _loadedCategoriaId = null;
                    _lastRefreshCount = -1;
                  });
                  _scrollToCategory(index);
                },
              );
            }
            if (categorias.isNotEmpty) {
              final cat = categorias[index - 1];
              return _buildCategoryItem(
                cat.nome,
                _getIconForCategory(cat.nome, cat.icone),
                isSelected: _selectedCategoriaId == cat.id,
                onTap: () {
                  setState(() {
                    _selectedCategoriaId = cat.id;
                    _loadedCategoriaId = null;
                    _lastRefreshCount = -1;
                  });
                  _scrollToCategory(index);
                },
              );
            }
            return const SizedBox.shrink();
          },
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
                              placeholder: (_, __) => const SizedBox.shrink(),
                              errorWidget: (_, __, ___) => const Icon(Icons.image_outlined, size: 48, color: Color(0xFF9C9C9C)),
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
