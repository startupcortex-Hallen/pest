import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

import '../../../core/helpers/streaming_format.dart';
import '../../../core/helpers/theme_colors.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/streaming_models.dart';
import '../../../providers/streaming_provider.dart';
import '../../../services/streaming/streaming_service.dart';
import 'streaming_widgets.dart';

class EpisodePlayerScreen extends StatefulWidget {
  final String seriesId;
  final String episodeId;

  const EpisodePlayerScreen({
    super.key,
    required this.seriesId,
    required this.episodeId,
  });

  @override
  State<EpisodePlayerScreen> createState() => _EpisodePlayerScreenState();
}

class _EpisodePlayerScreenState extends State<EpisodePlayerScreen>
    with WidgetsBindingObserver {
  final _service = StreamingService();
  static const _chaveAutoplay = 'streaming_autoplay_v1';

  StreamingSeries? _serie;
  StreamingSeason? _temporada;
  StreamingEpisode? _episodio;
  StreamingEpisode? _anterior;
  StreamingEpisode? _proximo;
  String? _seriesIdEfetivo;

  YoutubePlayerController? _controller;
  StreamSubscription<YoutubePlayerValue>? _valueSub;
  StreamSubscription<YoutubeVideoState>? _posicaoSub;

  Timer? _contador;
  int _segundosRestantes = 0;

  bool _loading = true;
  bool _bloqueado = false;
  bool _playerError = false;
  bool _terminou = false;
  bool _autoplay = true;
  bool _fullscreen = false;
  bool _salvando = false;
  String? _erro;
  String? _erroPlayer;
  Duration _posicao = Duration.zero;
  Duration _duracao = Duration.zero;
  DateTime _ultimoSalvamento = DateTime.fromMillisecondsSinceEpoch(0);

  String? get _uid => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _carregarPreferencias();
    _carregar();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(_salvarProgresso());
    }
  }

  Future<void> _carregarPreferencias() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final valor = prefs.getBool(_chaveAutoplay);
      if (mounted && valor != null) {
        setState(() => _autoplay = valor);
      }
    } catch (_) {}
  }

  Future<void> _carregar() async {
    setState(() {
      _loading = true;
      _erro = null;
      _playerError = false;
      _terminou = false;
      _erroPlayer = null;
      _bloqueado = false;
    });

    try {
      final provider = context.read<StreamingProvider>();
      await provider.loadIfStale();
      await provider.waitUntilLoaded();

      final serieRota = await _service.fetchSeriesById(widget.seriesId);
      if (serieRota != null &&
          !provider.canAccess(serieRota.requiredPlanLevel)) {
        if (!mounted) return;
        setState(() {
          _serie = serieRota;
          _loading = false;
          _bloqueado = true;
        });
        return;
      }

      final episodio = await _service.fetchEpisodeById(widget.episodeId);
      if (episodio == null) {
        throw Exception('Episódio não encontrado.');
      }
      final temporada = await _service.fetchSeasonById(episodio.seasonId);
      final seriesIdEfetivo = (temporada?.seriesId?.isNotEmpty == true)
          ? temporada!.seriesId
          : (widget.seriesId != 'null' && widget.seriesId.isNotEmpty
                ? widget.seriesId
                : '');
      final serie =
          serieRota ?? await _service.fetchSeriesById(seriesIdEfetivo);
      final vizinhos = await _service.fetchAdjacent(seriesIdEfetivo, episodio);

      StreamingWatchProgress? progresso;
      final usuarioId = _uid;
      if (usuarioId != null) {
        progresso = await _service.fetchProgress(usuarioId, episodio.id);
      }

      if (!mounted) return;
      setState(() {
        _episodio = episodio;
        _temporada = temporada;
        _serie = serie;
        _seriesIdEfetivo = seriesIdEfetivo.isEmpty
            ? temporada?.seriesId
            : seriesIdEfetivo;
        _anterior = vizinhos.previous;
        _proximo = vizinhos.next;
        _loading = false;
      });

      if (_deveOferecerRetomada(progresso)) {
        final segundos = await _mostrarRetomada(progresso!);
        if (!mounted) return;
        _criarPlayer(segundos ?? 0);
      } else {
        _criarPlayer(0);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não foi possível abrir este episódio agora.';
        _loading = false;
      });
    }
  }

  bool _deveOferecerRetomada(StreamingWatchProgress? progresso) {
    if (progresso == null || progresso.completed) return false;
    if (progresso.progressSeconds <= 5) return false;
    if (progresso.durationSeconds > 0 &&
        progresso.progressSeconds >= progresso.durationSeconds - 10) {
      return false;
    }
    return true;
  }

  Future<double?> _mostrarRetomada(StreamingWatchProgress progresso) async {
    final episodio = _episodio;
    final temporada = _temporada;
    final continuar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Continuar de onde parou?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (episodio != null)
              Text(
                '${episodio.title} • '
                'T${temporada?.seasonNumber ?? 1} EP ${episodio.episodeNumber}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            const SizedBox(height: 10),
            Text(
              'Você parou em '
              '${formatarTempoReproducao(progresso.progressSeconds)}'
              '${progresso.durationSeconds > 0 ? ' de ${formatarTempoReproducao(progresso.durationSeconds)} (${formatarPercentual(progresso.percentual)} do episódio)' : ''}.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Começar do início'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('Continuar'),
          ),
        ],
      ),
    );
    if (continuar == true) return progresso.progressSeconds;
    return 0;
  }

  void _criarPlayer(double inicioSegundos) {
    final episodio = _episodio;
    if (episodio == null) return;

    _destruirPlayer();
    final controller = YoutubePlayerController.fromVideoId(
      videoId: episodio.youtubeVideoId,
      autoPlay: true,
      startSeconds: inicioSegundos > 0 ? inicioSegundos : null,
      params: const YoutubePlayerParams(
        enableCaption: false,
        strictRelatedVideos: true,
        privacyEnhancedMode: false,
        videoStateUpdateInterval: 1000,
      ),
    );

    setState(() {
      _controller = controller;
      _playerError = false;
      _erroPlayer = null;
      _posicao = Duration(seconds: inicioSegundos.round());
    });

    _valueSub = controller.stream.listen(_onPlayerValue);
    _posicaoSub = controller.videoStateStream.listen(_onPosicao);
  }

  void _onPlayerValue(YoutubePlayerValue value) {
    if (!mounted) return;

    if (value.hasError) {
      debugPrint('Erro do player YouTube: ${value.error}');
      setState(() {
        _playerError = true;
        _erroPlayer = _mensagemErro(value.error);
      });
    }

    final duracao = value.metaData.duration;
    if (duracao > Duration.zero) {
      _duracao = duracao;
    }

    if (value.playerState == PlayerState.paused && _uid != null) {
      unawaited(_salvarProgresso());
    }

    if (value.playerState == PlayerState.ended && !_terminou) {
      _aoTerminar();
    }

    if (value.fullScreenOption.enabled != _fullscreen) {
      setState(() => _fullscreen = value.fullScreenOption.enabled);
      _aplicarOrientacao();
    }
  }

  void _onPosicao(YoutubeVideoState state) {
    _posicao = state.position;
    if (_uid == null) return;
    if (DateTime.now().difference(_ultimoSalvamento) >=
        const Duration(seconds: 10)) {
      unawaited(_salvarProgresso());
    }
  }

  void _aoTerminar() {
    setState(() => _terminou = true);
    unawaited(_salvarProgresso(forcarConclusao: true));
    if (_autoplay && _proximo != null) {
      _iniciarContagem();
    }
  }

  void _iniciarContagem() {
    _cancelarContagem();
    if (!mounted || _proximo == null) return;
    setState(() => _segundosRestantes = 5);
    _contador = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_segundosRestantes <= 1) {
        timer.cancel();
        setState(() => _segundosRestantes = 0);
        _abrirProximo();
      } else {
        setState(() => _segundosRestantes--);
      }
    });
  }

  void _cancelarContagem() {
    _contador?.cancel();
    _contador = null;
    if (mounted && _segundosRestantes != 0) {
      setState(() => _segundosRestantes = 0);
    }
  }

  Future<void> _salvarProgresso({
    bool forcarConclusao = false,
    bool forcar = false,
  }) async {
    final usuarioId = _uid;
    final episodio = _episodio;
    if (usuarioId == null || episodio == null || _salvando) return;

    final posicao = _posicao.inMilliseconds / 1000;
    if (posicao <= 0 && !forcarConclusao && !forcar) return;

    final duracao = _duracao.inMilliseconds > 0
        ? _duracao.inMilliseconds / 1000
        : (episodio.durationSeconds?.toDouble() ?? 0);

    _salvando = true;
    final seriesId = _seriesIdEfetivo;
    if (seriesId == null || seriesId.isEmpty) return;

    try {
      await _service.saveProgress(
        userId: usuarioId,
        seriesId: seriesId,
        seasonId: episodio.seasonId,
        episodeId: episodio.id,
        positionSeconds: posicao,
        durationSeconds: duracao,
        forceCompleted: forcarConclusao,
      );
      _ultimoSalvamento = DateTime.now();
    } catch (e) {
      debugPrint('Erro ao salvar progresso streaming: $e');
    } finally {
      _salvando = false;
    }
  }

  void _aplicarOrientacao() {
    if (_fullscreen) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  Future<void> _restaurarOrientacao() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void _destruirPlayer() {
    _valueSub?.cancel();
    _posicaoSub?.cancel();
    _valueSub = null;
    _posicaoSub = null;
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      unawaited(controller.close());
    }
  }

  void _abrirProximo() {
    final episodio = _proximo;
    if (episodio == null) return;
    _irParaEpisodio(episodio);
  }

  void _abrirAnterior() {
    final episodio = _anterior;
    if (episodio == null) return;
    _irParaEpisodio(episodio);
  }

  void _irParaEpisodio(StreamingEpisode episodio) async {
    await _salvarProgresso();
    if (!mounted) return;
    final seriesId = _seriesIdEfetivo ?? widget.seriesId;
    context.pushReplacement('/serie/$seriesId/episodio/${episodio.id}');
  }

  void _reverEpisodio() {
    _cancelarContagem();
    setState(() => _terminou = false);
    final controller = _controller;
    if (controller == null) {
      _criarPlayer(0);
      return;
    }
    controller.seekTo(seconds: 0);
    controller.playVideo();
  }

  Future<void> _alternarAutoplay(bool valor) async {
    setState(() => _autoplay = valor);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_chaveAutoplay, valor);
    } catch (_) {}
    if (!valor) {
      _cancelarContagem();
    } else if (_terminou && _proximo != null) {
      _iniciarContagem();
    }
  }

  Future<void> _assinarAgora() async {
    await context.push('/assinatura');
    if (!mounted) return;
    await context.read<StreamingProvider>().refreshSubscription();
    if (mounted) await _carregar();
  }

  Future<void> _abrirNoYoutube() async {
    final episodio = _episodio;
    if (episodio == null) return;
    final uri = Uri.tryParse(episodio.urlYoutubeEfetiva);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _tentarNovamentePlayer() {
    final posicao = _posicao.inSeconds.toDouble();
    _criarPlayer(posicao);
  }

  String _mensagemErro(YoutubeError erro) {
    switch (erro) {
      case YoutubeError.videoNotFound:
      case YoutubeError.cannotFindVideo:
      case YoutubeError.invalidParam:
        return 'Este vídeo não está mais disponível ou foi removido do YouTube.';
      case YoutubeError.notEmbeddable:
      case YoutubeError.sameAsNotEmbeddable:
      case YoutubeError.sameAsNotEmbeddable2:
        return 'Este vídeo não está disponível para reprodução incorporada. '
            'Pode ser restrito por idade, região ou pelas configurações do '
            'canal. Você pode assistir diretamente no YouTube.';
      case YoutubeError.html5Error:
        return 'O player do YouTube não conseguiu reproduzir este vídeo.';
      default:
        return 'Não foi possível reproduzir este vídeo agora.';
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _contador?.cancel();
    unawaited(_salvarProgresso());
    _destruirPlayer();
    unawaited(_restaurarOrientacao());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _episodio == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_bloqueado) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_rounded,
                  size: 52,
                  color: ThemeColors.primary(context),
                ),
                const SizedBox(height: 12),
                Text(
                  'Conteúdo exclusivo O Pest+',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_serie?.title ?? 'Esta produção'} faz parte da versão '
                  'alternativa. Assine para liberar o episódio.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    height: 1.45,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _assinarAgora,
                    icon: const Icon(Icons.workspace_premium_rounded, size: 18),
                    label: const Text('Conhecer planos do O Pest+'),
                  ),
                ),
                TextButton(
                  onPressed: () => context.pop(),
                  child: const Text('Voltar'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_erro != null || _episodio == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        body: StreamingErrorState(
          message: _erro ?? 'Episódio não encontrado.',
          onRetry: _carregar,
        ),
      );
    }

    final episodio = _episodio!;
    final temporada = _temporada;
    final serie = _serie;
    final descricao = episodio.sinopseCurta;

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) unawaited(_salvarProgresso());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              _cabecalho(context, serie, episodio, temporada),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_terminou)
                        _telaEncerramento(context)
                      else
                        AspectRatio(
                          aspectRatio: 16 / 9,
                          child: _areaPlayer(context),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          AppSpacing.md,
                          AppSpacing.md,
                          0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                StreamingBadge(
                                  label:
                                      'T${temporada?.seasonNumber ?? 1} • EP ${episodio.episodeNumber}',
                                ),
                                const SizedBox(width: 8),
                                if (_duracao.inSeconds > 0)
                                  Text(
                                    formatarTempoReproducao(
                                      _duracao.inSeconds.toDouble(),
                                    ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(color: Colors.white54),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              episodio.title,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            if (serie != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                serie.title,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: Colors.white60),
                              ),
                            ],
                            if (descricao.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(
                                descricao,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Colors.white70,
                                      height: 1.5,
                                    ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            _botoesEpisodio(context),
                            const SizedBox(height: 8),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _autoplay,
                              onChanged: _alternarAutoplay,
                              title: const Text(
                                'Reprodução automática',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              subtitle: const Text(
                                'Inicia o próximo episódio ao terminar este.',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            const SizedBox(height: 30),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cabecalho(
    BuildContext context,
    StreamingSeries? serie,
    StreamingEpisode episodio,
    StreamingSeason? temporada,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 4),
      color: Colors.black,
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  serie?.title ?? episodio.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'T${temporada?.seasonNumber ?? 1} • EP ${episodio.episodeNumber} • ${episodio.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Abrir no YouTube',
            onPressed: _abrirNoYoutube,
            icon: const Icon(
              Icons.open_in_new_rounded,
              color: Colors.white70,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _areaPlayer(BuildContext context) {
    if (_playerError) {
      return Container(
        color: AppColors.surface,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: AppColors.error,
              size: 34,
            ),
            const SizedBox(height: 8),
            Text(
              _erroPlayer ?? 'Não foi possível reproduzir este vídeo.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _tentarNovamentePlayer,
                  child: const Text('Tentar novamente'),
                ),
                TextButton(
                  onPressed: _abrirNoYoutube,
                  child: const Text('Abrir no YouTube'),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final controller = _controller;
    if (controller == null) {
      return Container(
        color: Colors.black,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return YoutubePlayer(
      key: ValueKey(_episodio?.id),
      controller: controller,
      backgroundColor: Colors.black,
      autoFullScreen: true,
      enableFullScreenOnVerticalDrag: true,
    );
  }

  Widget _telaEncerramento(BuildContext context) {
    final proximo = _proximo;
    final duracao = formatarDuracaoSegundos(proximo?.durationSeconds);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            ThemeColors.primary(context).withValues(alpha: 0.25),
            Colors.black,
          ],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 18),
      child: Column(
        children: [
          const Icon(
            Icons.check_circle_outline_rounded,
            color: Colors.white,
            size: 34,
          ),
          const SizedBox(height: 8),
          Text(
            'Você terminou este episódio',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          if (proximo != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    StreamingNetworkImage(
                      url: proximo.thumbnailEfetiva,
                      memCacheWidth: 800,
                      fallbackIcon: Icons.play_circle_outline_rounded,
                    ),
                    Container(color: Colors.black.withValues(alpha: 0.25)),
                    Center(
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'A seguir: ${proximo.title}',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'T${proximo.seasonNumber ?? _temporada?.seasonNumber ?? 1} • '
              'EP ${proximo.episodeNumber}'
              '${duracao.isNotEmpty ? ' • $duracao' : ''}',
              style: const TextStyle(color: Colors.white54, fontSize: 10),
            ),
            if (_autoplay && _segundosRestantes > 0) ...[
              const SizedBox(height: 4),
              Text(
                'Iniciando em $_segundosRestantes...',
                style: TextStyle(
                  color: ThemeColors.primary(context),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _abrirProximo,
                icon: const Icon(Icons.skip_next_rounded, size: 20),
                label: const Text('Próximo episódio'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: ThemeColors.primary(context),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ] else ...[
            Text(
              'Este é o último episódio disponível desta série.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => context.pop(),
              child: const Text('Voltar para a série'),
            ),
          ],
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: _reverEpisodio,
            icon: const Icon(Icons.replay_rounded, size: 18),
            label: const Text('Rever este episódio'),
          ),
        ],
      ),
    );
  }

  Widget _botoesEpisodio(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _anterior == null ? null : _abrirAnterior,
            icon: const Icon(Icons.skip_previous_rounded, size: 18),
            label: const Text('Anterior'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white24,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
              padding: const EdgeInsets.symmetric(vertical: 11),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _proximo == null ? null : _abrirProximo,
            icon: const Icon(Icons.skip_next_rounded, size: 18),
            label: const Text('Próximo'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white24,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
              padding: const EdgeInsets.symmetric(vertical: 11),
            ),
          ),
        ),
      ],
    );
  }
}
