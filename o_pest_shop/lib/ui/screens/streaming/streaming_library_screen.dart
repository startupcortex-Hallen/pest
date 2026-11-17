import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/helpers/streaming_format.dart';
import '../../../core/helpers/theme_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/streaming_models.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/streaming_provider.dart';
import '../../../services/streaming/streaming_service.dart';
import '../../widgets/login_required.dart';
import 'streaming_widgets.dart';

class StreamingLibraryScreen extends StatefulWidget {
  final int initialTab;

  const StreamingLibraryScreen({super.key, this.initialTab = 0});

  @override
  State<StreamingLibraryScreen> createState() => _StreamingLibraryScreenState();
}

class _StreamingLibraryScreenState extends State<StreamingLibraryScreen>
    with SingleTickerProviderStateMixin {
  final _service = StreamingService();
  late final TabController _tabCtrl;
  List<StreamingHistoryItem> _historico = [];
  bool _carregandoHistorico = true;
  String? _erroHistorico;
  String? _usuarioHistorico;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(
      length: 2,
      initialIndex: widget.initialTab.clamp(0, 1),
      vsync: this,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StreamingProvider>().loadIfStale();
      final usuarioId = context.read<AuthProvider>().user?.id;
      if (usuarioId != null) {
        _usuarioHistorico = usuarioId;
        _carregarHistorico(usuarioId);
      } else {
        setState(() => _carregandoHistorico = false);
      }
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregarHistorico(String usuarioId) async {
    setState(() {
      _carregandoHistorico = true;
      _erroHistorico = null;
    });
    try {
      final itens = await _service.fetchHistory(usuarioId);
      if (!mounted) return;
      setState(() {
        _historico = itens;
        _carregandoHistorico = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erroHistorico = 'Não foi possível carregar seu histórico.';
        _carregandoHistorico = false;
      });
    }
  }

  Future<void> _abrirEpisodio(StreamingEpisode episodio) async {
    final serieId = episodio.seriesId;
    if (serieId == null) return;
    await context.push('/serie/$serieId/episodio/${episodio.id}');
    if (!mounted) return;
    final usuarioId = context.read<AuthProvider>().user?.id;
    if (usuarioId != null) {
      await _carregarHistorico(usuarioId);
    }
    if (mounted) {
      await context.read<StreamingProvider>().refreshUserData();
    }
  }

  Future<void> _limparHistorico() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limpar histórico'),
        content: const Text(
          'Isso remove o histórico de reprodução da sua conta. '
          'O progresso dos episódios é mantido para você continuar de onde parou.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Limpar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    try {
      await context.read<StreamingProvider>().clearHistory();
      if (mounted) {
        setState(() => _historico = []);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível limpar o histórico.')),
        );
      }
    }
  }

  Future<void> _removerFavorito(String serieId) async {
    try {
      await context.read<StreamingProvider>().toggleFavorite(serieId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível atualizar sua lista.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final provider = context.watch<StreamingProvider>();
    final logado = auth.user != null;

    return Scaffold(
      backgroundColor: ThemeColors.background(context),
      appBar: AppBar(
        backgroundColor: ThemeColors.background(context),
        foregroundColor: ThemeColors.primaryText(context),
        title: const Text(
          'Minha lista & histórico',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: ThemeColors.primary(context),
          labelColor: ThemeColors.primary(context),
          unselectedLabelColor: ThemeColors.secondaryText(context),
          tabs: const [
            Tab(text: 'Minha lista'),
            Tab(text: 'Histórico'),
          ],
        ),
      ),
      body: !logado
          ? const LoginRequired(
              title: 'Entre para continuar',
              message: 'Favoritos e histórico ficam vinculados à sua conta.',
              icon: Icons.favorite_border_rounded,
            )
          : TabBarView(
              controller: _tabCtrl,
              children: [_minhaLista(provider), _historicoTab(provider)],
            ),
    );
  }

  Widget _minhaLista(StreamingProvider provider) {
    if (provider.loading && provider.series.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.series.isEmpty && provider.error != null) {
      return StreamingErrorState(
        message: provider.error!,
        onRetry: provider.refresh,
      );
    }

    final favoritas = provider.series
        .where((serie) => provider.isFavorite(serie.id))
        .toList();

    if (favoritas.isEmpty) {
      return StreamingEmptyState(
        title: 'Sua lista está vazia',
        message:
            'Toque no coração de uma série para salvá-la e encontrá-la aqui.',
        icon: Icons.favorite_border_rounded,
        actionLabel: 'Explorar séries',
        onAction: () => context.pop(),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.md),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 14,
        crossAxisSpacing: 10,
        childAspectRatio: 0.54,
      ),
      itemCount: favoritas.length,
      itemBuilder: (context, index) {
        final serie = favoritas[index];
        return StreamingPosterCard(
          series: serie,
          isFavorite: true,
          onFavorite: () => _removerFavorito(serie.id),
          onTap: () => context.push('/serie/${serie.id}'),
          showDescription: false,
          bloqueado: !provider.canAccess(serie.requiredPlanLevel),
        );
      },
    );
  }

  Widget _historicoTab(StreamingProvider provider) {
    if (_carregandoHistorico) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_erroHistorico != null) {
      return StreamingErrorState(
        message: _erroHistorico!,
        onRetry: () {
          final usuarioId =
              _usuarioHistorico ?? context.read<AuthProvider>().user?.id;
          if (usuarioId != null) _carregarHistorico(usuarioId);
        },
      );
    }
    if (_historico.isEmpty) {
      return const StreamingEmptyState(
        title: 'Nenhum episódio assistido',
        message:
            'Os episódios que você assistir aparecerão aqui para retomar depois.',
        icon: Icons.history_rounded,
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            10,
            AppSpacing.md,
            4,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${_historico.length} episódios recentes',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: ThemeColors.secondaryText(context),
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _limparHistorico,
                icon: const Icon(Icons.delete_outline_rounded, size: 16),
                label: const Text('Limpar histórico'),
                style: TextButton.styleFrom(
                  foregroundColor: ThemeColors.error(context),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () {
              final usuarioId = context.read<AuthProvider>().user?.id;
              if (usuarioId == null) return Future.value();
              return _carregarHistorico(usuarioId);
            },
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                4,
                AppSpacing.md,
                100,
              ),
              itemCount: _historico.length,
              itemBuilder: (context, index) {
                final item = _historico[index];
                return _HistoricoCard(
                  item: item,
                  onTap: () => _abrirEpisodio(item.episode),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _HistoricoCard extends StatelessWidget {
  final StreamingHistoryItem item;
  final VoidCallback onTap;

  const _HistoricoCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final episodio = item.episode;
    final progresso = item.progress;
    final percentual = progresso?.percentual ?? 0;
    final concluido = progresso?.completed == true;
    final quando = tempoRelativoStreaming(item.watchedAt);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: ThemeColors.surface(context),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 116,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          StreamingNetworkImage(
                            url: episodio.thumbnailEfetiva,
                            memCacheWidth: 360,
                            fallbackIcon: Icons.play_circle_outline_rounded,
                          ),
                          Center(
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.58),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                concluido
                                    ? Icons.check_rounded
                                    : Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                          if (percentual > 0)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: StreamingProgressBar(
                                percentual: percentual,
                                height: 3,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.series.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'T${item.season.seasonNumber} • EP ${episodio.episodeNumber} • ${episodio.title}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: ThemeColors.secondaryText(context),
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          if (concluido)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: StreamingBadge(
                                label: 'CONCLUÍDO',
                                color: ThemeColors.success(context),
                              ),
                            )
                          else if (percentual > 0)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Text(
                                formatarPercentual(percentual),
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: ThemeColors.primary(context),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 9,
                                    ),
                              ),
                            ),
                          if (quando.isNotEmpty)
                            Text(
                              quando,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: ThemeColors.secondaryText(context),
                                    fontSize: 9,
                                  ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 14),
                  child: Icon(Icons.chevron_right_rounded, size: 18),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
