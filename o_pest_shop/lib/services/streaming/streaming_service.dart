import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/helpers/youtube_url.dart';
import '../../models/streaming_models.dart';
import '../supabase_service.dart';

class StreamingService {
  final SupabaseClient _client = SupabaseService.instance.client;

  static const double metaConcluido = 0.90;

  String? get _uid => _client.auth.currentUser?.id;

  List<Map<String, dynamic>> _list(dynamic resposta) {
    if (resposta is! List) return const [];
    return resposta
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  bool _visivel(StreamingEpisode episodio, DateTime agora) {
    final publicadoEm = episodio.publishedAt?.toUtc();
    if (episodio.status == 'publicado') {
      return publicadoEm == null || !publicadoEm.isAfter(agora);
    }
    if (episodio.status == 'agendado') {
      return publicadoEm != null && !publicadoEm.isAfter(agora);
    }
    return false;
  }

  Future<List<StreamingSeries>> fetchSeries({int limit = 100}) async {
    try {
      final resposta = await _client
          .from('streaming_series_catalogo')
          .select()
          .eq('status', 'publicado')
          .order('display_order', ascending: true)
          .order('title', ascending: true)
          .limit(limit);
      return _list(resposta)
          .map(StreamingSeries.fromJson)
          .where((serie) => serie.id.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('Erro fetchSeries streaming: $e');
      rethrow;
    }
  }

  Future<StreamingSeries?> fetchSeriesById(String id) async {
    try {
      final resposta = await _client
          .from('streaming_series_catalogo')
          .select()
          .eq('id', id)
          .maybeSingle();
      if (resposta == null) return null;
      return StreamingSeries.fromJson(Map<String, dynamic>.from(resposta));
    } catch (e) {
      debugPrint('Erro fetchSeriesById streaming: $e');
      return null;
    }
  }

  Future<List<StreamingSeason>> fetchSeasons(String seriesId) async {
    final resposta = await _client
        .from('streaming_seasons')
        .select()
        .eq('series_id', seriesId)
        .eq('status', 'publicado')
        .order('display_order', ascending: true)
        .order('season_number', ascending: true);
    return _list(resposta)
        .map(StreamingSeason.fromJson)
        .where((temporada) => temporada.id.isNotEmpty)
        .toList();
  }

  Future<StreamingSeason?> fetchSeasonById(String id) async {
    try {
      final resposta = await _client
          .from('streaming_seasons')
          .select()
          .eq('id', id)
          .maybeSingle();
      if (resposta == null) return null;
      return StreamingSeason.fromJson(Map<String, dynamic>.from(resposta));
    } catch (e) {
      debugPrint('Erro fetchSeasonById streaming: $e');
      return null;
    }
  }

  Future<List<StreamingEpisode>> fetchEpisodes(String seasonId) async {
    final resposta = await _client
        .from('streaming_episodes')
        .select()
        .eq('season_id', seasonId)
        .inFilter('status', ['publicado', 'agendado'])
        .order('display_order', ascending: true)
        .order('episode_number', ascending: true);

    final agora = DateTime.now().toUtc();
    return _list(resposta)
        .map(StreamingEpisode.fromJson)
        .where(
          (episodio) => episodio.id.isNotEmpty && _visivel(episodio, agora),
        )
        .toList();
  }

  Future<StreamingEpisode?> fetchEpisodeById(String id) async {
    try {
      final resposta = await _client
          .from('streaming_episodes')
          .select()
          .eq('id', id)
          .maybeSingle();
      if (resposta == null) return null;
      return StreamingEpisode.fromJson(Map<String, dynamic>.from(resposta));
    } catch (e) {
      debugPrint('Erro fetchEpisodeById streaming: $e');
      return null;
    }
  }

  Future<StreamingSeriesStats> fetchStats(String seriesId) async {
    try {
      final temporadasResposta = await _client
          .from('streaming_seasons')
          .select('id')
          .eq('series_id', seriesId)
          .eq('status', 'publicado');
      final temporadas = _list(temporadasResposta);
      if (temporadas.isEmpty) {
        return const StreamingSeriesStats();
      }

      final ids = temporadas
          .map((item) => item['id']?.toString())
          .whereType<String>()
          .toList();

      final episodiosResposta = await _client
          .from('streaming_episodes')
          .select('id,status,published_at')
          .inFilter('season_id', ids)
          .inFilter('status', ['publicado', 'agendado']);

      final agora = DateTime.now().toUtc();
      final episodios = _list(episodiosResposta).where((item) {
        final status = item['status']?.toString() ?? '';
        final publicado = DateTime.tryParse(
          item['published_at']?.toString() ?? '',
        );
        if (status == 'publicado') {
          return publicado == null || !publicado.toUtc().isAfter(agora);
        }
        return publicado != null && !publicado.toUtc().isAfter(agora);
      }).length;

      return StreamingSeriesStats(
        seasons: temporadas.length,
        episodes: episodios,
      );
    } catch (e) {
      debugPrint('Erro fetchStats streaming: $e');
      return const StreamingSeriesStats();
    }
  }

  Future<StreamingHomeConfig> fetchHomeConfig() async {
    try {
      final resposta = await _client
          .from('streaming_home_config')
          .select()
          .eq('id', 1)
          .maybeSingle();
      if (resposta == null) return StreamingHomeConfig.padrao();
      return StreamingHomeConfig.fromJson(Map<String, dynamic>.from(resposta));
    } catch (e) {
      debugPrint('Erro fetchHomeConfig streaming: $e');
      return StreamingHomeConfig.padrao();
    }
  }

  Future<List<StreamingEpisode>> fetchLatestEpisodes({int limit = 20}) async {
    final resposta = await _client
        .from('streaming_episodes')
        .select()
        .inFilter('status', ['publicado', 'agendado'])
        .order('published_at', ascending: false, nullsFirst: false)
        .order('created_at', ascending: false)
        .limit(limit * 3);

    final agora = DateTime.now().toUtc();
    final episodios = _list(resposta)
        .map(StreamingEpisode.fromJson)
        .where(
          (episodio) => episodio.id.isNotEmpty && _visivel(episodio, agora),
        )
        .take(limit)
        .toList();

    return _enriquecerEpisodios(episodios);
  }

  Future<List<StreamingEpisode>> _enriquecerEpisodios(
    List<StreamingEpisode> episodios,
  ) async {
    if (episodios.isEmpty) return const [];

    try {
      final temporadaIds = episodios
          .map((episodio) => episodio.seasonId)
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final temporadasResposta = await _client
          .from('streaming_seasons')
          .select('id,series_id,season_number,title')
          .inFilter('id', temporadaIds);
      final temporadas = <String, Map<String, dynamic>>{};
      for (final item in _list(temporadasResposta)) {
        final id = item['id']?.toString();
        if (id != null) temporadas[id] = item;
      }

      final serieIds = temporadas.values
          .map((item) => item['series_id']?.toString())
          .whereType<String>()
          .toSet()
          .toList();
      final seriesResposta = serieIds.isEmpty
          ? const []
          : await _client
                .from('streaming_series')
                .select('id,title,cover_url')
                .inFilter('id', serieIds);
      final series = <String, Map<String, dynamic>>{};
      for (final item in _list(seriesResposta)) {
        final id = item['id']?.toString();
        if (id != null) series[id] = item;
      }

      return episodios.map((episodio) {
        final temporada = temporadas[episodio.seasonId];
        final serie = temporada == null
            ? null
            : series[temporada['series_id']?.toString()];
        return episodio.copyWith(
          seriesId: serie?['id']?.toString(),
          seriesTitle: serie?['title']?.toString(),
          seasonTitle: temporada?['title']?.toString(),
          seasonNumber: (temporada?['season_number'] as num?)?.toInt(),
        );
      }).toList();
    } catch (e) {
      debugPrint('Erro ao enriquecer episÃ³dios streaming: $e');
      return episodios;
    }
  }

  Future<StreamingEpisode?> resolveStartEpisode(String seriesId) async {
    final usuarioId = _uid;
    if (usuarioId != null) {
      try {
        final resposta = await _client
            .from('streaming_watch_progress')
            .select()
            .eq('user_id', usuarioId)
            .eq('series_id', seriesId)
            .eq('completed', false)
            .gt('progress_seconds', 5)
            .order('last_watched_at', ascending: false)
            .limit(1);
        final linhas = _list(resposta);
        if (linhas.isNotEmpty) {
          final episodioId = linhas.first['episode_id']?.toString();
          if (episodioId != null) {
            final episodio = await fetchEpisodeById(episodioId);
            if (episodio != null) return episodio;
          }
        }
      } catch (e) {
        debugPrint('Erro resolveStartEpisode progresso: $e');
      }
    }

    final temporadas = await fetchSeasons(seriesId);
    for (final temporada in temporadas) {
      final episodios = await fetchEpisodes(temporada.id);
      if (episodios.isNotEmpty) return episodios.first;
    }
    return null;
  }

  Future<List<ContinueWatchingItem>> fetchContinueWatching(
    String userId, {
    int limit = 12,
  }) async {
    try {
      final resposta = await _client
          .from('streaming_watch_progress')
          .select()
          .eq('user_id', userId)
          .eq('completed', false)
          .gt('progress_seconds', 1)
          .order('last_watched_at', ascending: false)
          .limit(limit);
      final progressos = _list(
        resposta,
      ).map(StreamingWatchProgress.fromJson).toList();
      if (progressos.isEmpty) return const [];

      final episodioIds = progressos
          .map((item) => item.episodeId)
          .toSet()
          .toList();
      final episodiosResposta = await _client
          .from('streaming_episodes')
          .select()
          .inFilter('id', episodioIds)
          .inFilter('status', ['publicado', 'agendado']);
      final episodios = <String, StreamingEpisode>{};
      for (final item in _list(episodiosResposta)) {
        final episodio = StreamingEpisode.fromJson(item);
        episodios[episodio.id] = episodio;
      }

      final temporadaIds = episodios.values
          .map((item) => item.seasonId)
          .toSet()
          .toList();
      final temporadasResposta = temporadaIds.isEmpty
          ? const []
          : await _client
                .from('streaming_seasons')
                .select()
                .inFilter('id', temporadaIds);
      final temporadas = <String, StreamingSeason>{};
      for (final item in _list(temporadasResposta)) {
        final temporada = StreamingSeason.fromJson(item);
        temporadas[temporada.id] = temporada;
      }

      final serieIds = temporadas.values
          .map((item) => item.seriesId)
          .toSet()
          .toList();
      final seriesResposta = serieIds.isEmpty
          ? const []
          : await _client
                .from('streaming_series')
                .select()
                .inFilter('id', serieIds);
      final series = <String, StreamingSeries>{};
      for (final item in _list(seriesResposta)) {
        final serie = StreamingSeries.fromJson(item);
        series[serie.id] = serie;
      }

      final itens = <ContinueWatchingItem>[];
      for (final progresso in progressos) {
        final episodio = episodios[progresso.episodeId];
        if (episodio == null) continue;
        final temporada = temporadas[episodio.seasonId];
        if (temporada == null) continue;
        final serie = series[temporada.seriesId];
        if (serie == null) continue;
        itens.add(
          ContinueWatchingItem(
            series: serie,
            season: temporada,
            episode: episodio,
            progress: progresso,
          ),
        );
      }
      return itens;
    } catch (e) {
      debugPrint('Erro fetchContinueWatching streaming: $e');
      return const [];
    }
  }

  Future<List<StreamingHistoryItem>> fetchHistory(
    String userId, {
    int limit = 50,
  }) async {
    try {
      final resposta = await _client
          .from('streaming_watch_history')
          .select()
          .eq('user_id', userId)
          .order('watched_at', ascending: false)
          .limit(limit);
      final linhas = _list(resposta);
      if (linhas.isEmpty) return const [];

      final episodioIds = linhas
          .map((item) => item['episode_id']?.toString())
          .whereType<String>()
          .toSet()
          .toList();

      final episodiosResposta = await _client
          .from('streaming_episodes')
          .select()
          .inFilter('id', episodioIds)
          .inFilter('status', ['publicado', 'agendado']);
      final episodios = <String, StreamingEpisode>{};
      for (final item in _list(episodiosResposta)) {
        final episodio = StreamingEpisode.fromJson(item);
        episodios[episodio.id] = episodio;
      }

      final temporadaIds = episodios.values
          .map((item) => item.seasonId)
          .toSet()
          .toList();
      final temporadasResposta = temporadaIds.isEmpty
          ? const []
          : await _client
                .from('streaming_seasons')
                .select()
                .inFilter('id', temporadaIds);
      final temporadas = <String, StreamingSeason>{};
      for (final item in _list(temporadasResposta)) {
        final temporada = StreamingSeason.fromJson(item);
        temporadas[temporada.id] = temporada;
      }

      final serieIds = temporadas.values
          .map((item) => item.seriesId)
          .toSet()
          .toList();
      final seriesResposta = serieIds.isEmpty
          ? const []
          : await _client
                .from('streaming_series')
                .select()
                .inFilter('id', serieIds);
      final series = <String, StreamingSeries>{};
      for (final item in _list(seriesResposta)) {
        final serie = StreamingSeries.fromJson(item);
        series[serie.id] = serie;
      }

      final progressosResposta = await _client
          .from('streaming_watch_progress')
          .select()
          .eq('user_id', userId)
          .inFilter('episode_id', episodioIds);
      final progressos = <String, StreamingWatchProgress>{};
      for (final item in _list(progressosResposta)) {
        final progresso = StreamingWatchProgress.fromJson(item);
        progressos[progresso.episodeId] = progresso;
      }

      final itens = <StreamingHistoryItem>[];
      for (final linha in linhas) {
        final episodioId = linha['episode_id']?.toString();
        if (episodioId == null) continue;
        final episodio = episodios[episodioId];
        if (episodio == null) continue;
        final temporada = temporadas[episodio.seasonId];
        if (temporada == null) continue;
        final serie = series[temporada.seriesId];
        if (serie == null) continue;
        itens.add(
          StreamingHistoryItem(
            series: serie,
            season: temporada,
            episode: episodio,
            watchedAt: DateTime.tryParse(linha['watched_at']?.toString() ?? ''),
            progress: progressos[episodioId],
          ),
        );
      }
      return itens;
    } catch (e) {
      debugPrint('Erro fetchHistory streaming: $e');
      return const [];
    }
  }

  Future<Set<String>> fetchFavoriteSeriesIds(String userId) async {
    try {
      final resposta = await _client
          .from('streaming_favorites')
          .select('series_id')
          .eq('user_id', userId);
      return _list(resposta)
          .map((item) => item['series_id']?.toString())
          .whereType<String>()
          .toSet();
    } catch (e) {
      debugPrint('Erro fetchFavoriteSeriesIds streaming: $e');
      return <String>{};
    }
  }

  Future<void> addFavorite(String userId, String seriesId) async {
    await _client.from('streaming_favorites').upsert({
      'user_id': userId,
      'series_id': seriesId,
    }, onConflict: 'user_id,series_id');
  }

  Future<void> removeFavorite(String userId, String seriesId) async {
    await _client
        .from('streaming_favorites')
        .delete()
        .eq('user_id', userId)
        .eq('series_id', seriesId);
  }

  Future<void> clearHistory(String userId) async {
    await _client
        .from('streaming_watch_history')
        .delete()
        .eq('user_id', userId);
  }

  Future<StreamingWatchProgress?> fetchProgress(
    String userId,
    String episodeId,
  ) async {
    try {
      final resposta = await _client
          .from('streaming_watch_progress')
          .select()
          .eq('user_id', userId)
          .eq('episode_id', episodeId)
          .maybeSingle();
      if (resposta == null) return null;
      return StreamingWatchProgress.fromJson(
        Map<String, dynamic>.from(resposta),
      );
    } catch (e) {
      debugPrint('Erro fetchProgress streaming: $e');
      return null;
    }
  }

  Future<Map<String, StreamingWatchProgress>> fetchProgressForSeries(
    String userId,
    String seriesId,
  ) async {
    try {
      final resposta = await _client
          .from('streaming_watch_progress')
          .select()
          .eq('user_id', userId)
          .eq('series_id', seriesId);
      final mapa = <String, StreamingWatchProgress>{};
      for (final item in _list(resposta)) {
        final progresso = StreamingWatchProgress.fromJson(item);
        mapa[progresso.episodeId] = progresso;
      }
      return mapa;
    } catch (e) {
      debugPrint('Erro fetchProgressForSeries streaming: $e');
      return <String, StreamingWatchProgress>{};
    }
  }

  Future<void> saveProgress({
    required String userId,
    required String seriesId,
    required String seasonId,
    required String episodeId,
    required double positionSeconds,
    double durationSeconds = 0,
    bool forceCompleted = false,
  }) async {
    if (positionSeconds <= 0 && !forceCompleted) return;

    final seguro = positionSeconds.isFinite && positionSeconds > 0
        ? positionSeconds
        : 0.0;
    final duracao = durationSeconds.isFinite && durationSeconds > 0
        ? durationSeconds
        : null;
    final concluido =
        forceCompleted ||
        (duracao != null && seguro >= duracao * metaConcluido);

    final agora = DateTime.now().toUtc().toIso8601String();

    await _client.from('streaming_watch_progress').upsert({
      'user_id': userId,
      'series_id': seriesId,
      'season_id': seasonId,
      'episode_id': episodeId,
      'progress_seconds': seguro,
      'duration_seconds': duracao,
      'completed': concluido,
      'last_watched_at': agora,
      'updated_at': agora,
    }, onConflict: 'user_id,episode_id');

    await _client.from('streaming_watch_history').upsert({
      'user_id': userId,
      'episode_id': episodeId,
      'watched_at': agora,
    }, onConflict: 'user_id,episode_id');
  }

  Future<AdjacentEpisodes> fetchAdjacent(
    String seriesId,
    StreamingEpisode atual,
  ) async {
    try {
      final temporadas = await fetchSeasons(seriesId);
      final indiceTemporada = temporadas.indexWhere(
        (item) => item.id == atual.seasonId,
      );
      if (indiceTemporada == -1) return const AdjacentEpisodes();

      final episodiosAtuais = await fetchEpisodes(atual.seasonId);
      final indiceEpisodio = episodiosAtuais.indexWhere(
        (item) => item.id == atual.id,
      );
      if (indiceEpisodio == -1) return const AdjacentEpisodes();

      StreamingEpisode? anterior;
      StreamingEpisode? proximo;

      if (indiceEpisodio > 0) {
        anterior = episodiosAtuais[indiceEpisodio - 1];
      }
      if (indiceEpisodio < episodiosAtuais.length - 1) {
        proximo = episodiosAtuais[indiceEpisodio + 1];
      }

      if (anterior == null) {
        for (final temporada
            in temporadas.take(indiceTemporada).toList().reversed) {
          final episodios = await fetchEpisodes(temporada.id);
          if (episodios.isNotEmpty) {
            anterior = episodios.last;
            break;
          }
        }
      }

      if (proximo == null) {
        for (final temporada in temporadas.skip(indiceTemporada + 1)) {
          final episodios = await fetchEpisodes(temporada.id);
          if (episodios.isNotEmpty) {
            proximo = episodios.first;
            break;
          }
        }
      }

      return AdjacentEpisodes(previous: anterior, next: proximo);
    } catch (e) {
      debugPrint('Erro fetchAdjacent streaming: $e');
      return const AdjacentEpisodes();
    }
  }

  Future<List<StreamingSeries>> fetchSeriesByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final resposta = await _client
        .from('streaming_series_catalogo')
        .select()
        .inFilter('id', ids)
        .eq('status', 'publicado');
    final mapa = {
      for (final item in _list(resposta))
        item['id']?.toString() ?? '': StreamingSeries.fromJson(item),
    };
    return ids.map((id) => mapa[id]).whereType<StreamingSeries>().toList();
  }

  Future<List<StreamingSeason>> fetchSeasonsByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final resposta = await _client
        .from('streaming_seasons')
        .select()
        .inFilter('id', ids);
    return _list(resposta).map(StreamingSeason.fromJson).toList();
  }

  Future<List<StreamingEpisode>> fetchEpisodesByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final resposta = await _client
        .from('streaming_episodes')
        .select()
        .inFilter('id', ids);
    return _list(resposta).map(StreamingEpisode.fromJson).toList();
  }

  Future<StreamingEpisode?> fetchFirstEpisodeOfSeries(String seriesId) async {
    final temporadas = await fetchSeasons(seriesId);
    for (final temporada in temporadas) {
      final episodios = await fetchEpisodes(temporada.id);
      if (episodios.isNotEmpty) return episodios.first;
    }
    return null;
  }

  Future<Map<String, dynamic>?> fetchRawSeriesById(String id) async {
    final resposta = await _client
        .from('streaming_series')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (resposta == null) return null;
    return Map<String, dynamic>.from(resposta);
  }

  Future<Map<String, dynamic>?> fetchRawSeasonById(String id) async {
    final resposta = await _client
        .from('streaming_seasons')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (resposta == null) return null;
    return Map<String, dynamic>.from(resposta);
  }

  Future<Map<String, dynamic>?> fetchRawEpisodeById(String id) async {
    final resposta = await _client
        .from('streaming_episodes')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (resposta == null) return null;
    return Map<String, dynamic>.from(resposta);
  }

  /// Usado apenas pelo admin para validar rapidamente se a URL existe no
  /// catÃ¡logo local. A validaÃ§Ã£o de incorporaÃ§Ã£o Ã© feita pelo player do YouTube.
  bool youtubeIdValido(String? id) => YoutubeUrl.isValidId(id);
}
