import 'package:flutter_test/flutter_test.dart';
import 'package:o_pest_shop/core/helpers/youtube_url.dart';
import 'package:o_pest_shop/models/streaming_models.dart';

void main() {
  group('YoutubeUrl.extractId', () {
    test('aceita URL watch', () {
      expect(
        YoutubeUrl.extractId('https://www.youtube.com/watch?v=PHVQ17ifaWo'),
        'PHVQ17ifaWo',
      );
    });

    test('aceita URL curta', () {
      expect(
        YoutubeUrl.extractId('https://youtu.be/VYVevDrfSeg?t=30'),
        'VYVevDrfSeg',
      );
    });

    test('aceita embed, shorts e live', () {
      expect(
        YoutubeUrl.extractId('https://www.youtube.com/embed/PHVQ17ifaWo'),
        'PHVQ17ifaWo',
      );
      expect(
        YoutubeUrl.extractId('https://youtube.com/shorts/VYVevDrfSeg'),
        'VYVevDrfSeg',
      );
      expect(
        YoutubeUrl.extractId('https://www.youtube.com/live/PHVQ17ifaWo'),
        'PHVQ17ifaWo',
      );
    });

    test('aceita ID puro', () {
      expect(YoutubeUrl.extractId('PHVQ17ifaWo'), 'PHVQ17ifaWo');
    });

    test('rejeita domínio, texto e ID inválido', () {
      expect(
        YoutubeUrl.extractId('https://example.com/watch?v=PHVQ17ifaWo'),
        isNull,
      );
      expect(YoutubeUrl.extractId('apenas um texto'), isNull);
      expect(YoutubeUrl.extractId('https://youtu.be/curto'), isNull);
      expect(YoutubeUrl.extractId(''), isNull);
      expect(YoutubeUrl.extractId(null), isNull);
    });

    test('normaliza URL', () {
      expect(
        YoutubeUrl.normalizedUrl('https://youtu.be/PHVQ17ifaWo'),
        'https://www.youtube.com/watch?v=PHVQ17ifaWo',
      );
    });
  });

  group('StreamingModels', () {
    test('episódio sem miniatura usa miniatura do YouTube', () {
      final episodio = StreamingEpisode.fromJson({
        'id': 'ep-1',
        'season_id': 'season-1',
        'episode_number': 1,
        'title': 'Episódio 1',
        'youtube_video_id': 'PHVQ17ifaWo',
        'status': 'publicado',
      });

      expect(
        episodio.thumbnailEfetiva,
        'https://img.youtube.com/vi/PHVQ17ifaWo/hqdefault.jpg',
      );
      expect(
        episodio.urlYoutubeEfetiva,
        'https://www.youtube.com/watch?v=PHVQ17ifaWo',
      );
    });

    test('plano formata preço e benefícios', () {
      final plano = StreamingPlan.fromJson({
        'id': 'plano-1',
        'nome': 'O Pest+ Premium',
        'slug': 'opest-plus-premium',
        'nivel': 3,
        'preco_centavos': 2990,
        'periodo': 'mensal',
        'beneficios': ['4 telas', '4K'],
        'ativo': true,
      });

      expect(plano.precoFormatado, 'R\$ 29,90');
      expect(plano.periodoLabel, 'por mês');
      expect(plano.beneficios, ['4 telas', '4K']);
      expect(plano.nivel, 3);
    });

    test('assinatura só fica ativa dentro do período', () {
      final ativa = StreamingSubscription.fromJson({
        'id': 'sub-1',
        'user_id': 'user-1',
        'plan_id': 'plano-1',
        'status': 'ativa',
        'plan_nivel': 2,
        'current_period_end': DateTime.now()
            .add(const Duration(days: 2))
            .toIso8601String(),
      });
      final expirada = StreamingSubscription.fromJson({
        'id': 'sub-2',
        'user_id': 'user-1',
        'plan_id': 'plano-1',
        'status': 'ativa',
        'plan_nivel': 2,
        'current_period_end': DateTime.now()
            .subtract(const Duration(days: 1))
            .toIso8601String(),
      });

      expect(ativa.ativa, isTrue);
      expect(expirada.ativa, isFalse);
    });

    test('série lê o nível de plano exigido', () {
      final serie = StreamingSeries.fromJson({
        'id': 'serie-1',
        'title': 'Versão alternativa',
        'slug': 'versao-alternativa',
        'status': 'publicado',
        'required_plan_level': 2,
      });

      expect(serie.requiredPlanLevel, 2);
    });

    test('configuração da home mantém todas as seções conhecidas', () {
      final config = StreamingHomeConfig.fromJson({
        'hero_series_id': 'serie-1',
        'sections': [
          {'key': 'latest_episodes', 'enabled': false},
        ],
      });

      expect(config.heroSeriesId, 'serie-1');
      expect(
        config.sections.any((secao) => secao.key == 'latest_episodes'),
        isTrue,
      );
      expect(config.sections.any((secao) => secao.key == 'all_series'), isTrue);
      expect(config.secaoAtiva('latest_episodes'), isFalse);
    });
  });
}
