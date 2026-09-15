import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/helpers/scale_helper.dart';
import '../../../core/helpers/theme_colors.dart';
import '../../../models/feed_post.dart';
import '../../../providers/feed_provider.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/custom_drawer.dart';
import '../../widgets/feed_card.dart';
import '../../widgets/animated_card_entry.dart';
import 'post_navigation.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _categoryScrollController = ScrollController();
  static const _kCategoryScrollDuration = Duration(milliseconds: 500);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FeedProvider>().loadFeed();
    });
  }

  @override
  void dispose() {
    _categoryScrollController.dispose();
    super.dispose();
  }

  void _scrollToCategory(int index) {
    if (!_categoryScrollController.hasClients) return;
    final screenWidth = MediaQuery.of(context).size.width;
    const itemWidth = 68.0;
    final targetOffset = (index * itemWidth) - (screenWidth / 2 - itemWidth / 2);
    final clamped = targetOffset.clamp(0.0, _categoryScrollController.position.maxScrollExtent);
    _categoryScrollController.animateTo(clamped, duration: _kCategoryScrollDuration, curve: Curves.easeInOutCubic);
  }

  IconData _iconForCategoria(String cat) {
    switch (cat.toLowerCase()) {
      case 'avisos': return Icons.campaign_rounded;
      case 'eventos': return Icons.event_rounded;
      case 'vagas': return Icons.work_rounded;
      case 'novidades': return Icons.new_releases_rounded;
      default: return Icons.circle_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: ThemeColors.background(context),
      drawer: const CustomDrawer(),
      body: SafeArea(
        child: Column(
          children: [
            AppTopBar.withSearch(
              onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
              onSearchTap: () => context.push('/busca'),
              bottomWidget: _buildCategories(context),
            ),
            Expanded(
              child: Consumer<FeedProvider>(
                builder: (context, feed, _) {
                  if (feed.loading && feed.feed.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (feed.feed.isEmpty) {
                    return _buildEmptyState();
                  }
                  return RefreshIndicator(
                    onRefresh: () => feed.loadFeed(),
                    child: _buildFeed(context, feed),
                  );
                },
              ),
            ),
            ],
        ),
      ),
    );
  }

  Widget _buildCategories(BuildContext context) {
    final feed = context.watch<FeedProvider>();
    final categorias = feed.categorias;
    return Container(
      margin: EdgeInsets.only(bottom: context.w(AppSpacing.md), left: context.w(AppSpacing.md), right: context.w(AppSpacing.md)),
      decoration: BoxDecoration(color: ThemeColors.surface(context), borderRadius: BorderRadius.circular(AppRadius.rLg(context))),
      child: SizedBox(
        height: context.h(104).clamp(88.0, 120.0),
        child: ListView.separated(
          controller: _categoryScrollController,
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: context.w(AppSpacing.sm), vertical: context.h(AppSpacing.sm)),
          itemCount: categorias.length + 1,
          separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xs),
          itemBuilder: (context, index) {
            if (index == 0) {
              return _buildCatItem('Todas', Icons.grid_view_rounded,
                isSelected: feed.selectedCategoria == null,
                onTap: () { feed.selectCategoria(null); _scrollToCategory(index); },
              );
            }
            final cat = categorias[index - 1];
            return _buildCatItem(cat, _iconForCategoria(cat),
              isSelected: feed.selectedCategoria?.toLowerCase() == cat.toLowerCase(),
              onTap: () { feed.selectCategoria(cat); _scrollToCategory(index); },
            );
          },
        ),
      ),
    );
  }

  Widget _buildCatItem(String nome, IconData icon, {bool isSelected = false, VoidCallback? onTap}) {
    final bgColor = isSelected ? ThemeColors.primary(context).withValues(alpha: 0.15) : ThemeColors.surfaceVariant(context);
    final iconColor = isSelected ? ThemeColors.primary(context) : ThemeColors.secondaryText(context);
    final textColor = isSelected ? ThemeColors.primary(context) : ThemeColors.secondaryText(context);
    final iconSize = context.w(48).clamp(40.0, 56.0);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: iconSize, height: iconSize, decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(context.w(12).clamp(10.0, 16.0))),
            child: Icon(icon, color: iconColor, size: context.sp(20))),
          SizedBox(height: context.h(AppSpacing.xs)),
          SizedBox(width: context.w(56), child: Text(nome, textAlign: TextAlign.center,
            style: TextStyle(color: textColor, fontSize: context.sp(11).clamp(10.0, 12.0), fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500),
            maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false)),
        ],
      ),
    );
  }

  Widget _buildFeed(BuildContext context, FeedProvider feed) {
    final posts = feed.feed;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: posts.length,
      itemBuilder: (context, index) {
        final p = posts[index];
        try {
          return AnimatedCardEntry(
            index: index,
            child: FeedCard(
              postId: p.id,
              autor: p.autorNome, categoria: p.categoria,
              autorImagem: p.autorImagem,
              imagemUrl: p.urlImagem, youtubeUrl: p.urlYoutube,
              titulo: p.titulo, descricao: p.descricao,
              likeCount: p.likeCount, commentCount: p.commentCount,
              likedByMe: p.likedByMe,
              onTap: _rota(p),
              onLike: () => feed.toggleLike(p.id),
              onComment: () => pushPostDetail(context, p.id, p.categoria),
              onAutorTap: p.unidadeId != null
                  ? () => context.push('/unidade/${p.unidadeId}')
                  : null,
            ),
          );
        } catch (e) {
          debugPrint('Erro ao renderizar card do feed: $e');
          return const SizedBox.shrink();
        }
      },
    );
  }

  void Function() _rota(FeedPost p) => () => pushPostDetail(context, p.id, p.categoria);

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.article_outlined, color: ThemeColors.hint(context), size: 64),
          const SizedBox(height: 16),
          Text('Nenhuma publicação no feed', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Novidades aparecerão aqui', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: ThemeColors.secondaryText(context))),
        ],
      ),
    );
  }
}
