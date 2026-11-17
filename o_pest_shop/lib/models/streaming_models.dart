import '../core/helpers/youtube_url.dart';

DateTime? _data(dynamic valor) {
  if (valor == null) return null;
  return DateTime.tryParse(valor.toString());
}

int? _inteiro(dynamic valor) => (valor as num?)?.toInt();

double _decimal(dynamic valor) => (valor as num?)?.toDouble() ?? 0;

String? _texto(dynamic valor) {
  final texto = valor?.toString().trim();
  if (texto == null || texto.isEmpty) return null;
  return texto;
}

class StreamingSeries {
  final String id;
  final String title;
  final String slug;
  final String? description;
  final String? synopsis;
  final String? coverUrl;
  final String? bannerUrl;
  final String? category;
  final String? ageRating;
  final int? releaseYear;
  final String status;
  final bool isFeatured;
  final int displayOrder;
  final int requiredPlanLevel;
  final String? trailerYoutubeId;
  final String? trailerUrl;
  final String? castMembers;
  final int seasonsCount;
  final int episodesCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const StreamingSeries({
    required this.id,
    required this.title,
    required this.slug,
    this.description,
    this.synopsis,
    this.coverUrl,
    this.bannerUrl,
    this.category,
    this.ageRating,
    this.releaseYear,
    this.status = 'rascunho',
    this.isFeatured = false,
    this.displayOrder = 0,
    this.requiredPlanLevel = 0,
    this.trailerYoutubeId,
    this.trailerUrl,
    this.castMembers,
    this.seasonsCount = 0,
    this.episodesCount = 0,
    this.createdAt,
    this.updatedAt,
  });

  String get descricaoCurta {
    final texto = description ?? synopsis;
    if (texto == null || texto.trim().isEmpty) return '';
    return texto.trim();
  }

  String? get trailerIdValido => YoutubeUrl.isValidId(trailerYoutubeId)
      ? trailerYoutubeId
      : YoutubeUrl.extractId(trailerUrl);

  factory StreamingSeries.fromJson(Map<String, dynamic> json) {
    return StreamingSeries(
      id: json['id']?.toString() ?? '',
      title: _texto(json['title']) ?? 'Série',
      slug: _texto(json['slug']) ?? '',
      description: _texto(json['description']),
      synopsis: _texto(json['synopsis']),
      coverUrl: _texto(json['cover_url']),
      bannerUrl: _texto(json['banner_url']),
      category: _texto(json['category']),
      ageRating: _texto(json['age_rating']),
      releaseYear: _inteiro(json['release_year']),
      status: _texto(json['status']) ?? 'rascunho',
      isFeatured: json['is_featured'] == true,
      displayOrder: _inteiro(json['display_order']) ?? 0,
      requiredPlanLevel: _inteiro(json['required_plan_level']) ?? 0,
      trailerYoutubeId: _texto(json['trailer_youtube_id']),
      trailerUrl: _texto(json['trailer_url']),
      castMembers: _texto(json['cast_members']),
      seasonsCount: _inteiro(json['seasons_count']) ?? 0,
      episodesCount: _inteiro(json['episodes_count']) ?? 0,
      createdAt: _data(json['created_at']),
      updatedAt: _data(json['updated_at']),
    );
  }
}

class StreamingSeason {
  final String id;
  final String seriesId;
  final int seasonNumber;
  final String? title;
  final String? description;
  final String? coverUrl;
  final DateTime? releaseDate;
  final String status;
  final int displayOrder;
  final int requiredPlanLevel;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const StreamingSeason({
    required this.id,
    required this.seriesId,
    required this.seasonNumber,
    this.title,
    this.description,
    this.coverUrl,
    this.releaseDate,
    this.status = 'rascunho',
    this.displayOrder = 0,
    this.requiredPlanLevel = 0,
    this.createdAt,
    this.updatedAt,
  });

  String get nomeExibicao {
    final nome = title?.trim();
    if (nome != null && nome.isNotEmpty) return nome;
    return '$seasonNumberª temporada';
  }

  factory StreamingSeason.fromJson(Map<String, dynamic> json) {
    return StreamingSeason(
      id: json['id']?.toString() ?? '',
      seriesId: json['series_id']?.toString() ?? '',
      seasonNumber: _inteiro(json['season_number']) ?? 1,
      title: _texto(json['title']),
      description: _texto(json['description']),
      coverUrl: _texto(json['cover_url']),
      releaseDate: _data(json['release_date']),
      status: _texto(json['status']) ?? 'rascunho',
      displayOrder: _inteiro(json['display_order']) ?? 0,
      requiredPlanLevel: _inteiro(json['required_plan_level']) ?? 0,
      createdAt: _data(json['created_at']),
      updatedAt: _data(json['updated_at']),
    );
  }
}

class StreamingEpisode {
  final String id;
  final String seasonId;
  final int episodeNumber;
  final String title;
  final String? description;
  final String? synopsis;
  final String youtubeVideoId;
  final String? youtubeUrl;
  final String? coverUrl;
  final String? thumbnailUrl;
  final int? durationSeconds;
  final DateTime? publishedAt;
  final String status;
  final int displayOrder;
  final bool isFeatured;
  final int requiredPlanLevel;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  final String? seriesId;
  final String? seriesTitle;
  final String? seasonTitle;
  final int? seasonNumber;

  const StreamingEpisode({
    required this.id,
    required this.seasonId,
    required this.episodeNumber,
    required this.title,
    this.description,
    this.synopsis,
    required this.youtubeVideoId,
    this.youtubeUrl,
    this.coverUrl,
    this.thumbnailUrl,
    this.durationSeconds,
    this.publishedAt,
    this.status = 'rascunho',
    this.displayOrder = 0,
    this.isFeatured = false,
    this.requiredPlanLevel = 0,
    this.createdAt,
    this.updatedAt,
    this.seriesId,
    this.seriesTitle,
    this.seasonTitle,
    this.seasonNumber,
  });

  String get thumbnailEfetiva {
    final thumb = thumbnailUrl?.trim();
    if (thumb != null && thumb.isNotEmpty) return thumb;
    final capa = coverUrl?.trim();
    if (capa != null && capa.isNotEmpty) return capa;
    return YoutubeUrl.thumbnailUrl(youtubeVideoId);
  }

  String get capaEfetiva {
    final capa = coverUrl?.trim();
    if (capa != null && capa.isNotEmpty) return capa;
    return thumbnailEfetiva;
  }

  String get urlYoutubeEfetiva => youtubeUrl?.trim().isNotEmpty == true
      ? youtubeUrl!.trim()
      : YoutubeUrl.watchUrl(youtubeVideoId);

  String get sinopseCurta {
    final texto = synopsis ?? description;
    if (texto == null || texto.trim().isEmpty) return '';
    return texto.trim();
  }

  StreamingEpisode copyWith({
    String? seriesId,
    String? seriesTitle,
    String? seasonTitle,
    int? seasonNumber,
  }) {
    return StreamingEpisode(
      id: id,
      seasonId: seasonId,
      episodeNumber: episodeNumber,
      title: title,
      description: description,
      synopsis: synopsis,
      youtubeVideoId: youtubeVideoId,
      youtubeUrl: youtubeUrl,
      coverUrl: coverUrl,
      thumbnailUrl: thumbnailUrl,
      durationSeconds: durationSeconds,
      publishedAt: publishedAt,
      status: status,
      displayOrder: displayOrder,
      isFeatured: isFeatured,
      requiredPlanLevel: requiredPlanLevel,
      createdAt: createdAt,
      updatedAt: updatedAt,
      seriesId: seriesId ?? this.seriesId,
      seriesTitle: seriesTitle ?? this.seriesTitle,
      seasonTitle: seasonTitle ?? this.seasonTitle,
      seasonNumber: seasonNumber ?? this.seasonNumber,
    );
  }

  factory StreamingEpisode.fromJson(Map<String, dynamic> json) {
    return StreamingEpisode(
      id: json['id']?.toString() ?? '',
      seasonId: json['season_id']?.toString() ?? '',
      episodeNumber: _inteiro(json['episode_number']) ?? 1,
      title: _texto(json['title']) ?? 'Episódio',
      description: _texto(json['description']),
      synopsis: _texto(json['synopsis']),
      youtubeVideoId: _texto(json['youtube_video_id']) ?? '',
      youtubeUrl: _texto(json['youtube_url']),
      coverUrl: _texto(json['cover_url']),
      thumbnailUrl: _texto(json['thumbnail_url']),
      durationSeconds: _inteiro(json['duration_seconds']),
      publishedAt: _data(json['published_at']),
      status: _texto(json['status']) ?? 'rascunho',
      displayOrder: _inteiro(json['display_order']) ?? 0,
      isFeatured: json['is_featured'] == true,
      requiredPlanLevel: _inteiro(json['required_plan_level']) ?? 0,
      createdAt: _data(json['created_at']),
      updatedAt: _data(json['updated_at']),
    );
  }
}

class StreamingPlan {
  final String id;
  final String nome;
  final String slug;
  final String? descricao;
  final int nivel;
  final int precoCentavos;
  final String periodo;
  final int trialDias;
  final int maxTelas;
  final String? qualidade;
  final List<String> beneficios;
  final bool ativo;
  final int ordem;

  const StreamingPlan({
    required this.id,
    required this.nome,
    required this.slug,
    this.descricao,
    this.nivel = 1,
    this.precoCentavos = 0,
    this.periodo = 'mensal',
    this.trialDias = 0,
    this.maxTelas = 1,
    this.qualidade,
    this.beneficios = const [],
    this.ativo = false,
    this.ordem = 0,
  });

  String get precoFormatado =>
      'R\$ ${(precoCentavos / 100).toStringAsFixed(2).replaceAll('.', ',')}';

  String get periodoLabel => periodo == 'anual' ? 'por ano' : 'por mês';

  factory StreamingPlan.fromJson(Map<String, dynamic> json) {
    final lista = json['beneficios'];
    return StreamingPlan(
      id: json['id']?.toString() ?? '',
      nome: _texto(json['nome']) ?? 'Plano',
      slug: _texto(json['slug']) ?? '',
      descricao: _texto(json['descricao']),
      nivel: _inteiro(json['nivel']) ?? 1,
      precoCentavos: _inteiro(json['preco_centavos']) ?? 0,
      periodo: _texto(json['periodo']) ?? 'mensal',
      trialDias: _inteiro(json['trial_dias']) ?? 0,
      maxTelas: _inteiro(json['max_telas']) ?? 1,
      qualidade: _texto(json['qualidade']),
      beneficios: lista is List
          ? lista.map((item) => item.toString()).toList()
          : const [],
      ativo: json['ativo'] == true,
      ordem: _inteiro(json['ordem']) ?? 0,
    );
  }
}

class StreamingSubscription {
  final String id;
  final String userId;
  final String planId;
  final String status;
  final String? planNome;
  final int planNivel;
  final int? precoCentavos;
  final String? periodo;
  final String? preapprovalId;
  final String? initPoint;
  final DateTime? startedAt;
  final DateTime? currentPeriodEnd;
  final DateTime? lastPaymentAt;
  final bool cancelAtPeriodEnd;

  const StreamingSubscription({
    required this.id,
    required this.userId,
    required this.planId,
    required this.status,
    this.planNome,
    this.planNivel = 0,
    this.precoCentavos,
    this.periodo,
    this.preapprovalId,
    this.initPoint,
    this.startedAt,
    this.currentPeriodEnd,
    this.lastPaymentAt,
    this.cancelAtPeriodEnd = false,
  });

  bool get ativa {
    if (status != 'ativa') return false;
    final fim = currentPeriodEnd;
    return fim == null || fim.isAfter(DateTime.now());
  }

  bool get pendente => status == 'pendente';

  factory StreamingSubscription.fromJson(Map<String, dynamic> json) {
    return StreamingSubscription(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      planId: json['plan_id']?.toString() ?? '',
      status: _texto(json['status']) ?? 'pendente',
      planNome: _texto(json['plan_nome']),
      planNivel: _inteiro(json['plan_nivel']) ?? 0,
      precoCentavos: _inteiro(json['preco_centavos']),
      periodo: _texto(json['periodo']),
      preapprovalId: _texto(json['preapproval_id']),
      initPoint: _texto(json['init_point']),
      startedAt: _data(json['started_at']),
      currentPeriodEnd: _data(json['current_period_end']),
      lastPaymentAt: _data(json['last_payment_at']),
      cancelAtPeriodEnd: json['cancel_at_period_end'] == true,
    );
  }
}

class StreamingWatchProgress {
  final String id;
  final String userId;
  final String seriesId;
  final String seasonId;
  final String episodeId;
  final double progressSeconds;
  final double durationSeconds;
  final bool completed;
  final DateTime? lastWatchedAt;

  const StreamingWatchProgress({
    required this.id,
    required this.userId,
    required this.seriesId,
    required this.seasonId,
    required this.episodeId,
    required this.progressSeconds,
    required this.durationSeconds,
    required this.completed,
    this.lastWatchedAt,
  });

  double get percentual {
    if (durationSeconds <= 0) return 0;
    return (progressSeconds / durationSeconds).clamp(0, 1);
  }

  factory StreamingWatchProgress.fromJson(Map<String, dynamic> json) {
    return StreamingWatchProgress(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      seriesId: json['series_id']?.toString() ?? '',
      seasonId: json['season_id']?.toString() ?? '',
      episodeId: json['episode_id']?.toString() ?? '',
      progressSeconds: _decimal(json['progress_seconds']),
      durationSeconds: _decimal(json['duration_seconds']),
      completed: json['completed'] == true,
      lastWatchedAt: _data(json['last_watched_at']),
    );
  }
}

class StreamingSeriesStats {
  final int seasons;
  final int episodes;

  const StreamingSeriesStats({this.seasons = 0, this.episodes = 0});
}

class ContinueWatchingItem {
  final StreamingSeries series;
  final StreamingSeason season;
  final StreamingEpisode episode;
  final StreamingWatchProgress progress;

  const ContinueWatchingItem({
    required this.series,
    required this.season,
    required this.episode,
    required this.progress,
  });
}

class StreamingHistoryItem {
  final StreamingSeries series;
  final StreamingSeason season;
  final StreamingEpisode episode;
  final DateTime? watchedAt;
  final StreamingWatchProgress? progress;

  const StreamingHistoryItem({
    required this.series,
    required this.season,
    required this.episode,
    this.watchedAt,
    this.progress,
  });
}

class AdjacentEpisodes {
  final StreamingEpisode? previous;
  final StreamingEpisode? next;

  const AdjacentEpisodes({this.previous, this.next});
}

class StreamingHomeSection {
  final String key;
  final bool enabled;

  const StreamingHomeSection({required this.key, this.enabled = true});

  static const labels = {
    'continue_watching': 'Continue assistindo',
    'featured': 'Séries em destaque',
    'all_series': 'Todas as séries',
    'latest_episodes': 'Últimos episódios',
  };

  String get label => labels[key] ?? key;

  factory StreamingHomeSection.fromJson(Map<String, dynamic> json) {
    return StreamingHomeSection(
      key: json['key']?.toString() ?? '',
      enabled: json['enabled'] != false,
    );
  }

  Map<String, dynamic> toJson() => {'key': key, 'enabled': enabled};

  StreamingHomeSection copyWith({bool? enabled}) =>
      StreamingHomeSection(key: key, enabled: enabled ?? this.enabled);
}

class StreamingHomeConfig {
  final String? heroSeriesId;
  final List<StreamingHomeSection> sections;

  const StreamingHomeConfig({this.heroSeriesId, required this.sections});

  static const List<StreamingHomeSection> secoesPadrao = [
    StreamingHomeSection(key: 'continue_watching'),
    StreamingHomeSection(key: 'featured'),
    StreamingHomeSection(key: 'all_series'),
    StreamingHomeSection(key: 'latest_episodes'),
  ];

  factory StreamingHomeConfig.padrao() =>
      const StreamingHomeConfig(sections: secoesPadrao);

  bool secaoAtiva(String key) =>
      sections.any((secao) => secao.key == key && secao.enabled);

  factory StreamingHomeConfig.fromJson(Map<String, dynamic> json) {
    final lidas = <StreamingHomeSection>[];
    final bruto = json['sections'];
    if (bruto is List) {
      for (final item in bruto) {
        if (item is Map) {
          final secao = StreamingHomeSection.fromJson(
            Map<String, dynamic>.from(item),
          );
          if (secao.key.isNotEmpty) lidas.add(secao);
        }
      }
    }

    for (final padrao in secoesPadrao) {
      if (!lidas.any((secao) => secao.key == padrao.key)) {
        lidas.add(padrao);
      }
    }

    return StreamingHomeConfig(
      heroSeriesId: _texto(json['hero_series_id']),
      sections: lidas,
    );
  }
}
