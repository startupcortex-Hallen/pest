import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/streaming_models.dart';
import '../services/auth_service.dart';
import '../services/streaming/streaming_service.dart';
import '../services/streaming/streaming_subscription_service.dart';

class StreamingProvider extends ChangeNotifier {
  final StreamingService _service;
  final AuthService _authService;
  final StreamingSubscriptionService _subscriptionService;

  StreamingProvider(
    this._service,
    this._authService,
    this._subscriptionService,
  ) {
    _authSubscription = _authService.authStateChanges.listen((state) {
      final id = state.session?.user.id;
      if (id != _loadedUserId) {
        _continueWatching = const [];
        _favorites = <String>{};
        _subscription = null;
        _nivelAcesso = 0;
        _codigoExpiraEm = null;
        _isAdmin = false;
        _loadedUserId = id;
        _lastLoaded = null;
        notifyListeners();
        unawaited(load(force: true));
      }
    });
  }

  StreamSubscription<AuthState>? _authSubscription;
  bool _disposed = false;

  List<StreamingSeries> _series = [];
  List<StreamingSeries> _featured = [];
  List<StreamingEpisode> _latestEpisodes = [];
  List<ContinueWatchingItem> _continueWatching = [];
  Set<String> _favorites = {};
  List<StreamingPlan> _plans = [];
  StreamingSubscription? _subscription;
  int _nivelAcesso = 0;
  DateTime? _codigoExpiraEm;
  StreamingHomeConfig _homeConfig = StreamingHomeConfig.padrao();
  StreamingSeries? _hero;
  StreamingSeriesStats _heroStats = const StreamingSeriesStats();
  int? _heroSeasonNumber;
  bool _loading = false;
  bool _isAdmin = false;
  String? _error;
  DateTime? _lastLoaded;
  String? _loadedUserId;
  int _loadGeneration = 0;
  Completer<void>? _idleCompleter;
  static const Duration _staleAfter = Duration(seconds: 60);

  List<StreamingSeries> get series => _series;
  List<StreamingSeries> get featured => _featured;
  List<StreamingEpisode> get latestEpisodes => _latestEpisodes;
  List<ContinueWatchingItem> get continueWatching => _continueWatching;
  Set<String> get favorites => _favorites;
  List<StreamingPlan> get plans => _plans;
  StreamingSubscription? get subscription => _subscription;
  int get nivelAcesso => _nivelAcesso;
  DateTime? get codigoExpiraEm => _codigoExpiraEm;
  StreamingHomeConfig get homeConfig => _homeConfig;
  StreamingSeries? get hero => _hero;
  StreamingSeriesStats get heroStats => _heroStats;
  int? get heroSeasonNumber => _heroSeasonNumber;
  bool get loading => _loading;
  String? get error => _error;
  String? get userId => _authService.currentUser?.id;
  bool get isLoggedIn => userId != null;
  bool get isSubscriber => _nivelAcesso > 0;

  bool isFavorite(String seriesId) => _favorites.contains(seriesId);

  bool canAccess(int requiredPlanLevel) {
    if (requiredPlanLevel <= 0) return true;
    if (_isAdmin) return true;
    return _nivelAcesso >= requiredPlanLevel;
  }

  Future<void> loadIfStale() async {
    if (_lastLoaded == null ||
        DateTime.now().difference(_lastLoaded!) >= _staleAfter ||
        _loadedUserId != userId) {
      await load();
    }
  }

  Future<void> waitUntilLoaded() async {
    if (!_loading) return;
    final atual = _idleCompleter;
    if (atual != null) await atual.future;
  }

  Future<void> load({bool force = false}) async {
    if (!force && _loading) return;

    final usuarioAtual = userId;
    if (!force &&
        _lastLoaded != null &&
        _loadedUserId == usuarioAtual &&
        DateTime.now().difference(_lastLoaded!) < _staleAfter) {
      return;
    }

    final geracao = ++_loadGeneration;
    final concluido = Completer<void>();
    _idleCompleter = concluido;
    _loading = true;
    _error = null;
    _notify();

    try {
      final series = await _service.fetchSeries();
      final config = await _service.fetchHomeConfig();
      final hero = await _resolverHero(config.heroSeriesId, series);
      var latest = <StreamingEpisode>[];
      try {
        latest = await _service.fetchLatestEpisodes();
      } catch (e) {
        debugPrint('Erro ao carregar últimos episódios: $e');
      }

      var planos = <StreamingPlan>[];
      try {
        planos = await _subscriptionService.fetchPlanos();
      } catch (e) {
        debugPrint('Erro ao carregar planos: $e');
      }

      var continueAssistindo = <ContinueWatchingItem>[];
      var favoritos = <String>{};
      StreamingSubscription? assinatura;
      var nivelAcesso = 0;
      DateTime? codigoExpiraEm;
      var isAdmin = false;
      if (usuarioAtual != null) {
        continueAssistindo = await _service.fetchContinueWatching(usuarioAtual);
        favoritos = await _service.fetchFavoriteSeriesIds(usuarioAtual);
        try {
          assinatura = await _subscriptionService.fetchMinhaAssinatura();
        } catch (e) {
          debugPrint('Erro ao carregar assinatura: $e');
        }
        try {
          nivelAcesso = await _subscriptionService.fetchNivelAcesso();
          codigoExpiraEm = await _subscriptionService
              .fetchCodigoAtivoExpiraEm();
        } catch (e) {
          debugPrint('Erro ao carregar nível de acesso: $e');
        }
        try {
          final perfil = await _authService.getProfile(usuarioAtual);
          isAdmin = perfil?.funcao == 'admin';
        } catch (e) {
          debugPrint('Erro ao carregar função do perfil: $e');
        }
      }

      var heroStats = const StreamingSeriesStats();
      int? heroTemporada;
      if (hero != null) {
        heroStats = await _service.fetchStats(hero.id);
        try {
          final temporadas = await _service.fetchSeasons(hero.id);
          if (temporadas.isNotEmpty) {
            heroTemporada = temporadas.first.seasonNumber;
          }
        } catch (_) {}
      }

      if (geracao != _loadGeneration) return;

      _series = series;
      _homeConfig = config;
      _hero = hero;
      _heroStats = heroStats;
      _heroSeasonNumber = heroTemporada;
      _latestEpisodes = latest;
      _continueWatching = continueAssistindo;
      _favorites = favoritos;
      _plans = planos;
      _subscription = assinatura;
      _nivelAcesso = isAdmin ? 3 : nivelAcesso;
      _codigoExpiraEm = codigoExpiraEm;
      _isAdmin = isAdmin;

      var destaques = series.where((item) => item.isFeatured).toList();
      if (destaques.isEmpty) destaques = series.take(12).toList();
      _featured = destaques;

      _loadedUserId = usuarioAtual;
      _lastLoaded = DateTime.now();
    } catch (e) {
      if (geracao != _loadGeneration) return;
      debugPrint('Erro ao carregar streaming: $e');
      _error = 'Não foi possível carregar o catálogo agora.';
      _loadedUserId = usuarioAtual;
      _lastLoaded = DateTime.now();
    } finally {
      if (geracao == _loadGeneration) {
        _loading = false;
        _notify();
      }
      if (!concluido.isCompleted) concluido.complete();
      if (identical(_idleCompleter, concluido)) {
        _idleCompleter = null;
      }
    }
  }

  Future<StreamingSeries?> _resolverHero(
    String? heroId,
    List<StreamingSeries> catalogo,
  ) async {
    if (heroId != null) {
      for (final serie in catalogo) {
        if (serie.id == heroId) return serie;
      }
      final serie = await _service.fetchSeriesById(heroId);
      if (serie != null && serie.status == 'publicado') return serie;
    }
    for (final serie in catalogo) {
      if (serie.isFeatured) return serie;
    }
    return catalogo.isEmpty ? null : catalogo.first;
  }

  Future<void> refresh() => load(force: true);

  Future<void> refreshUserData() async {
    final usuarioId = userId;
    if (usuarioId == null) {
      _continueWatching = const [];
      _favorites = <String>{};
      _subscription = null;
      _nivelAcesso = 0;
      _codigoExpiraEm = null;
      _notify();
      return;
    }
    try {
      _continueWatching = await _service.fetchContinueWatching(usuarioId);
      _favorites = await _service.fetchFavoriteSeriesIds(usuarioId);
      _subscription = await _subscriptionService.fetchMinhaAssinatura();
      _nivelAcesso = _isAdmin
          ? 3
          : await _subscriptionService.fetchNivelAcesso();
      _codigoExpiraEm = await _subscriptionService.fetchCodigoAtivoExpiraEm();
    } catch (e) {
      debugPrint('Erro refreshUserData streaming: $e');
    }
    _notify();
  }

  Future<void> refreshSubscription() async {
    if (userId == null) {
      _subscription = null;
      _nivelAcesso = 0;
      _codigoExpiraEm = null;
      _notify();
      return;
    }
    _subscription = await _subscriptionService.fetchMinhaAssinatura();
    _nivelAcesso = _isAdmin ? 3 : await _subscriptionService.fetchNivelAcesso();
    _codigoExpiraEm = await _subscriptionService.fetchCodigoAtivoExpiraEm();
    _notify();
  }

  Future<Map<String, dynamic>> resgatarCodigo(String codigo) async {
    final resultado = await _subscriptionService.resgatarCodigo(codigo);
    _nivelAcesso = _isAdmin ? 3 : await _subscriptionService.fetchNivelAcesso();
    _codigoExpiraEm = await _subscriptionService.fetchCodigoAtivoExpiraEm();
    _notify();
    return resultado;
  }

  Future<bool> toggleFavorite(String seriesId) async {
    final usuarioId = userId;
    if (usuarioId == null) return false;

    if (_favorites.contains(seriesId)) {
      await _service.removeFavorite(usuarioId, seriesId);
      _favorites = {..._favorites}..remove(seriesId);
    } else {
      await _service.addFavorite(usuarioId, seriesId);
      _favorites = {..._favorites, seriesId};
    }
    _notify();
    return true;
  }

  Future<StreamingEpisode?> resolveStartEpisode(String seriesId) =>
      _service.resolveStartEpisode(seriesId);

  Future<String> assinar(String planId) async {
    final data = await _subscriptionService.criarAssinatura(planId);
    final erro = data['erro']?.toString();
    if (erro != null && erro.isNotEmpty) {
      throw StateError(erro);
    }
    final assinaturaData = data['assinatura'];
    if (assinaturaData is Map) {
      _subscription = StreamingSubscription.fromJson(
        Map<String, dynamic>.from(assinaturaData),
      );
      _notify();
    }
    final initPoint = data['init_point']?.toString();
    if (initPoint == null || initPoint.isEmpty) {
      throw StateError('O Mercado Pago não retornou o link de pagamento.');
    }
    return initPoint;
  }

  Future<StreamingSubscription?> sincronizarAssinatura() async {
    final data = await _subscriptionService.sincronizarAssinatura();
    final assinaturaData = data['assinatura'];
    if (assinaturaData is Map) {
      _subscription = StreamingSubscription.fromJson(
        Map<String, dynamic>.from(assinaturaData),
      );
    } else {
      _subscription = null;
    }
    _nivelAcesso = _isAdmin ? 3 : await _subscriptionService.fetchNivelAcesso();
    _codigoExpiraEm = await _subscriptionService.fetchCodigoAtivoExpiraEm();
    _notify();
    return _subscription;
  }

  Future<void> cancelarAssinatura() async {
    await _subscriptionService.cancelarAssinatura();
    _subscription = await _subscriptionService.fetchMinhaAssinatura();
    _nivelAcesso = _isAdmin ? 3 : await _subscriptionService.fetchNivelAcesso();
    _codigoExpiraEm = await _subscriptionService.fetchCodigoAtivoExpiraEm();
    _notify();
  }

  Future<void> clearHistory() async {
    final usuarioId = userId;
    if (usuarioId == null) return;
    await _service.clearHistory(usuarioId);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _authSubscription?.cancel();
    super.dispose();
  }
}
