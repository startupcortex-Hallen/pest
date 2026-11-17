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
import 'streaming_widgets.dart';
import 'widgets/youtube_preview_dialog.dart';

class SeriesDetailScreen extends StatefulWidget {
  final String seriesId;

  const SeriesDetailScreen({super.key, required this.seriesId});

  @override
  State<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends State<SeriesDetailScreen> {
  final _service = StreamingService();

  StreamingSeries? _serie;
  List<StreamingSeason> _temporadas = [];
  StreamingSeason? _temporadaSelecionada;
  List<StreamingEpisode> _episodios = [];
  Map<String, StreamingWatchProgress> _progressos = {};
  StreamingSeriesStats _stats = const StreamingSeriesStats();
  bool _loading = true;
  bool _carregandoEpisodios = false;
  bool _abrindoPlayer = false;
  bool _bloqueado = false;
  String? _erro;

  String? get _usuarioAtual => context.read<AuthProvider>().user?.id;

  @override
  void initState() {
    super.initState();
    _carregar();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<StreamingProvider>().loadIfStale();
      }
    });
  }

  Future<void> _carregar() async {
    final usuarioId = _usuarioAtual;
    final provider = context.read<StreamingProvider>();
    await provider.loadIfStale();
    await provider.waitUntilLoaded();

    setState(() {
      _loading = true;
      _erro = null;
    });

    try {
      final serie = await _service.fetchSeriesById(widget.seriesId);
      if (serie == null) {
        throw Exception('Série não encontrada.');
      }

      final bloqueado = !provider.canAccess(serie.requiredPlanLevel);
      final stats = await _service.fetchStats(serie.id);

      if (bloqueado) {
        if (!mounted) return;
        setState(() {
          _serie = serie;
          _temporadas = [];
          _temporadaSelecionada = null;
          _episodios = [];
          _progressos = {};
          _stats = stats;
          _bloqueado = true;
          _loading = false;
        });
        return;
      }

      final temporadas = await _service.fetchSeasons(serie.id);

      var progressos = <String, StreamingWatchProgress>{};
      if (usuarioId != null) {
        progressos = await _service.fetchProgressForSeries(usuarioId, serie.id);
      }

      final selecionada = temporadas.isEmpty ? null : temporadas.first;
      final episodios = selecionada == null
          ? <StreamingEpisode>[]
          : await _service.fetchEpisodes(selecionada.id);

      if (!mounted) return;
      setState(() {
        _serie = serie;
        _temporadas = temporadas;
        _temporadaSelecionada = selecionada;
        _episodios = episodios;
        _progressos = progressos;
        _stats = stats;
        _bloqueado = false;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não foi possível carregar esta série.';
        _loading = false;
      });
    }
  }

  Future<void> _abrirAssinatura() async {
    await context.push('/assinatura');
    if (!mounted) return;
    await context.read<StreamingProvider>().refreshSubscription();
    if (mounted) _carregar();
  }

  Future<void> _selecionarTemporada(StreamingSeason temporada) async {
    if (_temporadaSelecionada?.id == temporada.id || _carregandoEpisodios) {
      return;
    }
    setState(() {
      _temporadaSelecionada = temporada;
      _episodios = [];
      _carregandoEpisodios = true;
    });
    try {
      final episodios = await _service.fetchEpisodes(temporada.id);
      if (!mounted) return;
      setState(() {
        _episodios = episodios;
        _carregandoEpisodios = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregandoEpisodios = false);
      _snack('Não foi possível carregar os episódios desta temporada.');
    }
  }

  Future<void> _assistir() async {
    final serie = _serie;
    if (serie == null || _abrindoPlayer) return;
    if (_bloqueado) {
      await _abrirAssinatura();
      return;
    }

    setState(() => _abrindoPlayer = true);
    try {
      final episodio = await context
          .read<StreamingProvider>()
          .resolveStartEpisode(serie.id);
      if (!mounted) return;
      setState(() => _abrindoPlayer = false);
      if (episodio == null) {
        _snack('Esta série ainda não tem episódios disponíveis.');
        return;
      }
      await _abrirEpisodio(episodio);
    } catch (e) {
      if (!mounted) return;
      setState(() => _abrindoPlayer = false);
      _snack('Não foi possível abrir o episódio agora.');
    }
  }

  Future<void> _abrirEpisodio(StreamingEpisode episodio) async {
    final serie = _serie;
    if (serie == null) return;
    await context.push('/serie/${serie.id}/episodio/${episodio.id}');
    if (!mounted) return;
    final usuarioId = context.read<AuthProvider>().user?.id;
    if (usuarioId != null) {
      final progressos = await _service.fetchProgressForSeries(
        usuarioId,
        serie.id,
      );
      if (mounted) setState(() => _progressos = progressos);
    }
    if (mounted) {
      await context.read<StreamingProvider>().refreshUserData();
    }
  }

  Future<void> _favoritar() async {
    final serie = _serie;
    if (serie == null) return;

    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) {
      final entrar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Salvar na minha lista'),
          content: const Text(
            'Entre na sua conta para favoritar séries e manter sua lista '
            'sincronizada em todos os dispositivos.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Agora não'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Entrar'),
            ),
          ],
        ),
      );
      if (entrar == true && mounted) context.push('/login');
      return;
    }

    try {
      await context.read<StreamingProvider>().toggleFavorite(serie.id);
    } catch (e) {
      if (mounted) _snack('Não foi possível atualizar sua lista.');
    }
  }

  void _abrirTrailer() {
    final serie = _serie;
    final videoId = serie?.trailerIdValido;
    if (serie == null || videoId == null) return;
    showDialog<void>(
      context: context,
      builder: (_) => YoutubePreviewDialog(
        videoId: videoId,
        titulo: 'Trailer — ${serie.title}',
      ),
    );
  }

  void _snack(String mensagem) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(mensagem)));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StreamingProvider>();

    if (_loading) {
      return Scaffold(
        backgroundColor: ThemeColors.background(context),
        appBar: AppBar(
          backgroundColor: ThemeColors.background(context),
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_serie == null || _erro != null) {
      return Scaffold(
        backgroundColor: ThemeColors.background(context),
        appBar: AppBar(
          backgroundColor: ThemeColors.background(context),
          foregroundColor: Colors.white,
        ),
        body: StreamingErrorState(
          message: _erro ?? 'Série não encontrada.',
          onRetry: _carregar,
        ),
      );
    }

    final serie = _serie!;
    final favorita = provider.isFavorite(serie.id);
    final trailerId = serie.trailerIdValido;

    return Scaffold(
      backgroundColor: ThemeColors.background(context),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 310,
            pinned: true,
            backgroundColor: ThemeColors.background(context),
            surfaceTintColor: Colors.transparent,
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: _CircleButton(
                icon: Icons.arrow_back_rounded,
                onTap: () => context.pop(),
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _CircleButton(
                  icon: favorita
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: favorita ? ThemeColors.primary(context) : Colors.white,
                  onTap: _favoritar,
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  StreamingNetworkImage(
                    url: serie.bannerUrl ?? serie.coverUrl,
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
                          Colors.transparent,
                          ThemeColors.background(context),
                        ],
                        stops: const [0, 0.45, 1],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              _cabecalho(context, serie, favorita, trailerId),
              if (_bloqueado)
                _paywall(context)
              else if (_temporadas.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: StreamingEmptyState(
                    title: 'Temporadas em preparação',
                    message: 'Esta série ainda não tem temporadas publicadas.',
                    icon: Icons.video_library_outlined,
                  ),
                )
              else ...[
                StreamingSectionHeader(
                  title: 'Temporadas',
                  actionLabel: '${_temporadas.length} disponíveis',
                ),
                _seletorTemporadas(context),
                if (_temporadaSelecionada != null)
                  _cartaoTemporada(context, _temporadaSelecionada!),
                StreamingSectionHeader(
                  title: 'Episódios',
                  actionLabel: _temporadaSelecionada?.nomeExibicao,
                ),
                if (_carregandoEpisodios)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_episodios.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(AppSpacing.md),
                    child: StreamingEmptyState(
                      title: 'Nenhum episódio disponível',
                      message:
                          'Os episódios desta temporada aparecerão aqui quando forem publicados.',
                      icon: Icons.playlist_remove_rounded,
                    ),
                  )
                else
                  ..._episodios.map(
                    (episodio) => _EpisodioTile(
                      episodio: episodio,
                      temporada: _temporadaSelecionada!,
                      progresso: _progressos[episodio.id],
                      onTap: () => _abrirEpisodio(episodio),
                    ),
                  ),
              ],
              const SizedBox(height: 120),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _cabecalho(
    BuildContext context,
    StreamingSeries serie,
    bool favorita,
    String? trailerId,
  ) {
    final descricao = serie.descricaoCurta;
    final participantes = serie.castMembers?.trim();
    final continuar = _progressos.values.any(
      (progresso) => !progresso.completed && progresso.progressSeconds > 5,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 4, AppSpacing.md, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            serie.title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 5,
            children: [
              if (serie.category != null && serie.category!.isNotEmpty)
                StreamingInfoChip(
                  label: serie.category!,
                  icon: Icons.local_movies_rounded,
                ),
              if (serie.releaseYear != null)
                StreamingInfoChip(label: '${serie.releaseYear}'),
              if (serie.ageRating != null)
                StreamingInfoChip(
                  label: serie.ageRating!,
                  icon: Icons.family_restroom_rounded,
                ),
              if (_stats.seasons > 0)
                StreamingInfoChip(
                  label: '${_stats.seasons} temporadas',
                  icon: Icons.layers_rounded,
                ),
              if (_stats.episodes > 0)
                StreamingInfoChip(
                  label: '${_stats.episodes} episódios',
                  icon: Icons.playlist_play_rounded,
                ),
              if (serie.requiredPlanLevel > 0)
                StreamingBadge(
                  label: 'EXCLUSIVO',
                  color: ThemeColors.primary(context),
                ),
              if (serie.status != 'publicado')
                StreamingBadge(label: serie.status.toUpperCase()),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _bloqueado
                      ? _abrirAssinatura
                      : (_abrindoPlayer ? null : _assistir),
                  icon: _bloqueado
                      ? const Icon(Icons.lock_rounded, size: 20)
                      : _abrindoPlayer
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.play_arrow_rounded, size: 22),
                  label: Text(
                    _bloqueado
                        ? 'ASSINAR PARA ASSISTIR'
                        : _abrindoPlayer
                        ? 'ABRINDO...'
                        : continuar
                        ? 'CONTINUAR'
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
                    ),
                  ),
                ),
              ),
              if (trailerId != null) ...[
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: _abrirTrailer,
                  icon: const Icon(Icons.movie_creation_outlined, size: 18),
                  label: const Text('TRAILER'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 13,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 6),
              IconButton(
                tooltip: favorita ? 'Remover da minha lista' : 'Minha lista',
                onPressed: _favoritar,
                icon: Icon(
                  favorita
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: favorita
                      ? ThemeColors.primary(context)
                      : ThemeColors.secondaryText(context),
                ),
              ),
            ],
          ),
          if (descricao.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              descricao,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: ThemeColors.primaryText(context),
                height: 1.5,
              ),
            ),
          ],
          if (serie.synopsis != null &&
              serie.synopsis!.trim().isNotEmpty &&
              serie.synopsis!.trim() != descricao) ...[
            const SizedBox(height: 8),
            Text(
              serie.synopsis!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: ThemeColors.secondaryText(context),
                height: 1.5,
              ),
            ),
          ],
          if (participantes != null && participantes.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Elenco / participantes',
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              participantes,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: ThemeColors.secondaryText(context),
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _paywall(BuildContext context) {
    final planos = context.watch<StreamingProvider>().plans;
    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpacing.md, 16, AppSpacing.md, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ThemeColors.primary(context).withValues(alpha: 0.22),
            ThemeColors.surface(context),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: ThemeColors.primary(context).withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lock_rounded,
                color: ThemeColors.primary(context),
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Conteúdo exclusivo O Pest+',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Esta produção faz parte da versão alternativa do catálogo. '
            'Assine para liberar temporadas, episódios e novos lançamentos.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: ThemeColors.secondaryText(context),
              height: 1.45,
            ),
          ),
          if (planos.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'A partir de ${planos.first.precoFormatado} ${planos.first.periodoLabel}',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: ThemeColors.primary(context),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _abrirAssinatura,
              icon: const Icon(Icons.workspace_premium_rounded, size: 18),
              label: const Text('Conhecer planos do O Pest+'),
            ),
          ),
          TextButton(
            onPressed: () async {
              await context.read<StreamingProvider>().refreshSubscription();
              if (mounted) _carregar();
            },
            child: const Text('Já sou assinante — verificar acesso'),
          ),
        ],
      ),
    );
  }

  Widget _cartaoTemporada(BuildContext context, StreamingSeason temporada) {
    final temCapa = temporada.coverUrl?.trim().isNotEmpty == true;
    final descricao = temporada.description?.trim() ?? '';
    final data = formatarDataStreaming(temporada.releaseDate);
    if (!temCapa && descricao.isEmpty && data.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 12, AppSpacing.md, 0),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: ThemeColors.surface(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: ThemeColors.outline(context).withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (temCapa) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 66,
                  height: 99,
                  child: StreamingNetworkImage(
                    url: temporada.coverUrl,
                    memCacheWidth: 240,
                    fallbackIcon: Icons.video_library_outlined,
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    temporada.nomeExibicao,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (data.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      'Lançamento: $data',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: ThemeColors.secondaryText(context),
                        fontSize: 9,
                      ),
                    ),
                  ],
                  if (descricao.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      descricao,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: ThemeColors.secondaryText(context),
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _seletorTemporadas(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        itemCount: _temporadas.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final temporada = _temporadas[index];
          final selecionada = temporada.id == _temporadaSelecionada?.id;
          return GestureDetector(
            onTap: () => _selecionarTemporada(temporada),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: selecionada
                    ? ThemeColors.primary(context)
                    : ThemeColors.surfaceVariant(context),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selecionada
                      ? ThemeColors.primary(context)
                      : ThemeColors.outline(context),
                ),
              ),
              child: Text(
                temporada.nomeExibicao,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: selecionada
                      ? Colors.white
                      : ThemeColors.primaryText(context),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  const _CircleButton({
    required this.icon,
    required this.onTap,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }
}

class _EpisodioTile extends StatelessWidget {
  final StreamingEpisode episodio;
  final StreamingSeason temporada;
  final StreamingWatchProgress? progresso;
  final VoidCallback onTap;

  const _EpisodioTile({
    required this.episodio,
    required this.temporada,
    required this.progresso,
    required this.onTap,
  });

  String get _statusLabel {
    switch (episodio.status) {
      case 'publicado':
        return 'Disponível';
      case 'agendado':
        final publicadoEm = episodio.publishedAt;
        if (publicadoEm != null && !publicadoEm.isAfter(DateTime.now())) {
          return 'Disponível';
        }
        return 'Em breve';
      case 'arquivado':
        return 'Arquivado';
      default:
        return 'Rascunho';
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = formatarDataStreaming(
      episodio.publishedAt ?? episodio.createdAt,
    );
    final duracao = formatarDuracaoSegundos(episodio.durationSeconds);
    final sinopse = episodio.sinopseCurta;
    final concluido = progresso?.completed == true;
    final percentual = progresso?.percentual ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, 10),
      child: Material(
        color: ThemeColors.surface(context),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 126,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      StreamingNetworkImage(
                        url: episodio.thumbnailEfetiva,
                        memCacheWidth: 400,
                        fallbackIcon: Icons.play_circle_outline_rounded,
                      ),
                      Container(color: Colors.black.withValues(alpha: 0.18)),
                      Center(
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.58),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            concluido
                                ? Icons.check_rounded
                                : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 21,
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
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'T${temporada.seasonNumber} • EP ${episodio.episodeNumber}',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: ThemeColors.primary(context),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 9,
                                ),
                          ),
                          if (concluido) ...[
                            const SizedBox(width: 5),
                            Icon(
                              Icons.check_circle_rounded,
                              size: 12,
                              color: ThemeColors.success(context),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        episodio.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (sinopse.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          sinopse,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: ThemeColors.secondaryText(context),
                                fontSize: 10,
                                height: 1.3,
                              ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 2,
                        children: [
                          if (duracao.isNotEmpty)
                            Text(
                              duracao,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: ThemeColors.secondaryText(context),
                                    fontSize: 9,
                                  ),
                            ),
                          if (data.isNotEmpty)
                            Text(
                              data,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: ThemeColors.secondaryText(context),
                                    fontSize: 9,
                                  ),
                            ),
                          Text(
                            _statusLabel,
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
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8, right: 4),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: ThemeColors.hint(context),
                  size: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
