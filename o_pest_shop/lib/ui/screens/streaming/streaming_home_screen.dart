import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/helpers/theme_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/streaming_models.dart';
import '../../../providers/streaming_provider.dart';
import '../../widgets/custom_drawer.dart';
import 'streaming_widgets.dart';

class StreamingHomeScreen extends StatefulWidget {
  const StreamingHomeScreen({super.key});

  @override
  State<StreamingHomeScreen> createState() => _StreamingHomeScreenState();
}

class _StreamingHomeScreenState extends State<StreamingHomeScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _abrindoHero = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StreamingProvider>().loadIfStale();
    });
  }

  Future<void> _assistirHero(StreamingProvider provider) async {
    final hero = provider.hero;
    if (hero == null || _abrindoHero) return;

    if (!provider.canAccess(hero.requiredPlanLevel)) {
      _snack('Conteúdo exclusivo. Conheça os planos do O Pest+.');
      await context.push('/assinatura');
      return;
    }

    setState(() => _abrindoHero = true);
    try {
      final episodio = await provider.resolveStartEpisode(hero.id);
      if (!mounted) return;
      setState(() => _abrindoHero = false);
      if (episodio == null) {
        _snack('Esta série ainda não tem episódios disponíveis.');
        return;
      }
      await context.push('/serie/${hero.id}/episodio/${episodio.id}');
      if (mounted) await provider.refreshUserData();
    } catch (e) {
      if (!mounted) return;
      setState(() => _abrindoHero = false);
      _snack('Não foi possível abrir o episódio agora. Tente novamente.');
    }
  }

  Future<void> _abrirSerie(String serieId) async {
    await context.push('/serie/$serieId');
    if (mounted) {
      await context.read<StreamingProvider>().refreshUserData();
    }
  }

  Future<void> _abrirEpisodio(StreamingEpisode episodio) async {
    final serieId = episodio.seriesId;
    if (serieId == null || serieId.isEmpty) {
      _snack('Não foi possível identificar a série deste episódio.');
      return;
    }
    await context.push('/serie/$serieId/episodio/${episodio.id}');
    if (mounted) {
      await context.read<StreamingProvider>().refreshUserData();
    }
  }

  void _snack(String mensagem) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(mensagem)));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StreamingProvider>();

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: ThemeColors.background(context),
      drawer: const CustomDrawer(),
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              onMenu: () => _scaffoldKey.currentState?.openDrawer(),
              onSubscription: () => context.push('/assinatura'),
              onFavorites: () => context.push('/minha-lista'),
              onHistory: () => context.push('/historico'),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: provider.refresh,
                child: _corpo(provider),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _corpo(StreamingProvider provider) {
    if (provider.loading && provider.series.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.series.isEmpty) {
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: provider.error != null
                ? StreamingErrorState(
                    message: provider.error!,
                    onRetry: provider.refresh,
                  )
                : StreamingEmptyState(
                    title: 'Nenhuma série disponível',
                    message:
                        'Quando o administrador publicar uma produção, ela aparecerá aqui.',
                    icon: Icons.movie_filter_outlined,
                    actionLabel: 'Atualizar catálogo',
                    onAction: provider.refresh,
                  ),
          ),
        ],
      );
    }

    final slivers = <Widget>[];

    final hero = provider.hero;
    if (hero != null) {
      slivers.add(
        SliverToBoxAdapter(
          child: _HeroBanner(
            serie: hero,
            stats: provider.heroStats,
            temporada: provider.heroSeasonNumber,
            carregando: _abrindoHero,
            bloqueado: !provider.canAccess(hero.requiredPlanLevel),
            onAssistir: () => _assistirHero(provider),
            onVerSerie: () => _abrirSerie(hero.id),
          ),
        ),
      );
    }

    if (!provider.isLoggedIn) {
      slivers.add(
        SliverToBoxAdapter(
          child: _GuestSavePrompt(onEntrar: () => context.push('/login')),
        ),
      );
    }

    for (final secao in provider.homeConfig.sections) {
      if (!secao.enabled) continue;
      switch (secao.key) {
        case 'continue_watching':
          if (provider.continueWatching.isNotEmpty) {
            slivers.add(
              SliverToBoxAdapter(
                child: StreamingSectionHeader(
                  title: 'Continue assistindo',
                  actionLabel: 'Histórico',
                  onAction: () => context.push('/historico'),
                ),
              ),
            );
            slivers.add(
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 194,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                    itemCount: provider.continueWatching.length,
                    itemBuilder: (context, index) {
                      final item = provider.continueWatching[index];
                      return StreamingContinueCard(
                        item: item,
                        onTap: () => _abrirEpisodio(item.episode),
                      );
                    },
                  ),
                ),
              ),
            );
          }
          break;
        case 'featured':
          if (provider.featured.isNotEmpty) {
            slivers.add(
              const SliverToBoxAdapter(
                child: StreamingSectionHeader(title: 'Séries em destaque'),
              ),
            );
            slivers.add(
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 292,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                    itemCount: provider.featured.length,
                    itemBuilder: (context, index) {
                      final serie = provider.featured[index];
                      return Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: SizedBox(
                          width: 148,
                          child: StreamingPosterCard(
                            series: serie,
                            onTap: () => _abrirSerie(serie.id),
                            bloqueado: !provider.canAccess(
                              serie.requiredPlanLevel,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          }
          break;
        case 'all_series':
          if (provider.series.isNotEmpty) {
            slivers.add(
              const SliverToBoxAdapter(
                child: StreamingSectionHeader(title: 'Todas as séries'),
              ),
            );
            slivers.add(
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  0,
                ),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final largura = constraints.crossAxisExtent;
                    final colunas = largura >= 720
                        ? 5
                        : largura >= 520
                        ? 4
                        : 3;
                    return SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: colunas,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 10,
                        childAspectRatio: 0.54,
                      ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final serie = provider.series[index];
                        return StreamingPosterCard(
                          series: serie,
                          onTap: () => _abrirSerie(serie.id),
                          showDescription: false,
                          bloqueado: !provider.canAccess(
                            serie.requiredPlanLevel,
                          ),
                        );
                      }, childCount: provider.series.length),
                    );
                  },
                ),
              ),
            );
          }
          break;
        case 'latest_episodes':
          if (provider.latestEpisodes.isNotEmpty) {
            slivers.add(
              const SliverToBoxAdapter(
                child: StreamingSectionHeader(title: 'Últimos episódios'),
              ),
            );
            slivers.add(
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 222,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                    itemCount: provider.latestEpisodes.length,
                    itemBuilder: (context, index) {
                      final episodio = provider.latestEpisodes[index];
                      return StreamingLatestEpisodeCard(
                        episode: episodio,
                        onTap: () => _abrirEpisodio(episodio),
                      );
                    },
                  ),
                ),
              ),
            );
          }
          break;
      }
    }

    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 110)));

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: slivers,
    );
  }
}

class _TopBar extends StatelessWidget {
  final VoidCallback onMenu;
  final VoidCallback onSubscription;
  final VoidCallback onFavorites;
  final VoidCallback onHistory;

  const _TopBar({
    required this.onMenu,
    required this.onSubscription,
    required this.onFavorites,
    required this.onHistory,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      decoration: BoxDecoration(
        color: ThemeColors.background(context),
        border: Border(
          bottom: BorderSide(
            color: ThemeColors.outline(context).withValues(alpha: 0.45),
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onMenu,
            icon: const Icon(Icons.menu_rounded, color: Colors.white, size: 22),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              'assets/logo.jpg',
              width: 34,
              height: 34,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.play_circle_fill_rounded,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'SÉRIES',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                    color: ThemeColors.primaryText(context),
                  ),
                ),
                Text(
                  'O Pest • histórias em episódios',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: ThemeColors.secondaryText(context),
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'O Pest+',
            onPressed: onSubscription,
            icon: const Icon(
              Icons.workspace_premium_rounded,
              color: Colors.white,
              size: 21,
            ),
          ),
          IconButton(
            tooltip: 'Minha lista',
            onPressed: onFavorites,
            icon: const Icon(
              Icons.favorite_border_rounded,
              color: Colors.white,
              size: 21,
            ),
          ),
          IconButton(
            tooltip: 'Histórico',
            onPressed: onHistory,
            icon: const Icon(
              Icons.history_rounded,
              color: Colors.white,
              size: 21,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroBanner extends StatelessWidget {
  final StreamingSeries serie;
  final StreamingSeriesStats stats;
  final int? temporada;
  final bool carregando;
  final bool bloqueado;
  final VoidCallback onAssistir;
  final VoidCallback onVerSerie;

  const _HeroBanner({
    required this.serie,
    required this.stats,
    required this.temporada,
    required this.carregando,
    required this.bloqueado,
    required this.onAssistir,
    required this.onVerSerie,
  });

  @override
  Widget build(BuildContext context) {
    final largura = MediaQuery.sizeOf(context).width;
    final altura = (largura * 0.74).clamp(310.0, 470.0);
    final descricao = serie.descricaoCurta;
    final imagem = serie.bannerUrl ?? serie.coverUrl;

    return SizedBox(
      height: altura,
      child: Stack(
        fit: StackFit.expand,
        children: [
          StreamingNetworkImage(
            url: imagem,
            alignment: Alignment.topCenter,
            memCacheWidth: 1200,
            fallbackIcon: Icons.movie_filter_outlined,
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.15),
                  Colors.black.withValues(alpha: 0.25),
                  ThemeColors.background(context).withValues(alpha: 0.96),
                ],
                stops: const [0, 0.45, 1],
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  ThemeColors.background(context).withValues(alpha: 0.78),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          Positioned(
            left: AppSpacing.md,
            right: AppSpacing.md,
            bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    StreamingBadge(
                      label: bloqueado ? 'EXCLUSIVO' : 'EM DESTAQUE',
                      color: ThemeColors.primary(context),
                    ),
                    if (serie.category != null &&
                        serie.category!.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      StreamingInfoChip(label: serie.category!),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  serie.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.8),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                ),
                if (descricao.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Text(
                    descricao,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.82),
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: 9),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (temporada != null)
                      StreamingInfoChip(
                        label: 'T$temporada em destaque',
                        icon: Icons.video_library_rounded,
                      ),
                    if (stats.episodes > 0)
                      StreamingInfoChip(
                        label: '${stats.episodes} episódios',
                        icon: Icons.playlist_play_rounded,
                      ),
                    if (stats.seasons > 0)
                      StreamingInfoChip(
                        label: '${stats.seasons} temporadas',
                        icon: Icons.layers_rounded,
                      ),
                    if (serie.releaseYear != null)
                      StreamingInfoChip(label: '${serie.releaseYear}'),
                    if (serie.ageRating != null)
                      StreamingInfoChip(label: serie.ageRating!),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: carregando ? null : onAssistir,
                        icon: carregando
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                bloqueado
                                    ? Icons.lock_rounded
                                    : Icons.play_arrow_rounded,
                                size: 22,
                              ),
                        label: Text(
                          carregando
                              ? 'ABRINDO...'
                              : bloqueado
                              ? 'ASSINAR'
                              : 'ASSISTIR',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ThemeColors.primary(context),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onVerSerie,
                        icon: const Icon(Icons.info_outline_rounded, size: 18),
                        label: const Text('VER SÉRIE'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.55),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GuestSavePrompt extends StatelessWidget {
  final VoidCallback onEntrar;

  const _GuestSavePrompt({required this.onEntrar});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        0,
      ),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            ThemeColors.primary(context).withValues(alpha: 0.18),
            ThemeColors.surface(context),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ThemeColors.primary(context).withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.bookmark_add_outlined,
            color: ThemeColors.primary(context),
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Entre para salvar seu progresso, favoritos e continuar de onde parou.',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: ThemeColors.primaryText(context),
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: onEntrar, child: const Text('Entrar')),
        ],
      ),
    );
  }
}
