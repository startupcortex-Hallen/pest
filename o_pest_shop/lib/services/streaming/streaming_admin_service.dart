import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/streaming_models.dart';
import '../supabase_service.dart';

class StreamingAdminService {
  final SupabaseClient _client = SupabaseService.instance.client;

  List<Map<String, dynamic>> _list(dynamic resposta) {
    if (resposta is! List) return const [];
    return resposta
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<List<Map<String, dynamic>>> fetchSeries() async {
    final resposta = await _client
        .from('streaming_series')
        .select()
        .order('display_order', ascending: true)
        .order('title', ascending: true);
    return _list(resposta);
  }

  Future<List<Map<String, dynamic>>> fetchSeriesContagens() async {
    final resposta = await _client.from('streaming_series_contagens').select();
    return _list(resposta);
  }

  Future<List<Map<String, dynamic>>> fetchSeasons({String? seriesId}) async {
    var query = _client.from('streaming_temporadas_contagens').select();
    if (seriesId != null && seriesId.isNotEmpty) {
      query = query.eq('series_id', seriesId);
    }
    final resposta = await query
        .order('series_id', ascending: true)
        .order('display_order', ascending: true)
        .order('season_number', ascending: true);
    return _list(resposta);
  }

  Future<List<Map<String, dynamic>>> fetchEpisodes({String? seasonId}) async {
    var query = _client.from('streaming_episodes').select();
    if (seasonId != null && seasonId.isNotEmpty) {
      query = query.eq('season_id', seasonId);
    }
    final resposta = await query
        .order('display_order', ascending: true)
        .order('episode_number', ascending: true);
    return _list(resposta);
  }

  Future<Map<String, dynamic>?> fetchHomeConfig() async {
    final resposta = await _client
        .from('streaming_home_config')
        .select()
        .eq('id', 1)
        .maybeSingle();
    if (resposta == null) return null;
    return Map<String, dynamic>.from(resposta);
  }

  Future<void> saveHomeConfig({
    required String? heroSeriesId,
    required List<StreamingHomeSection> sections,
  }) async {
    await _client.from('streaming_home_config').upsert({
      'id': 1,
      'hero_series_id': heroSeriesId,
      'sections': sections.map((item) => item.toJson()).toList(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'id');
  }

  Future<void> atualizarOrdemSerie(String id, int ordem) async {
    await _client
        .from('streaming_series')
        .update({'display_order': ordem})
        .eq('id', id);
  }

  Future<void> atualizarOrdemTemporada(String id, int ordem) async {
    await _client
        .from('streaming_seasons')
        .update({'display_order': ordem})
        .eq('id', id);
  }

  Future<void> atualizarOrdemEpisodio(String id, int ordem) async {
    await _client
        .from('streaming_episodes')
        .update({'display_order': ordem})
        .eq('id', id);
  }

  Future<void> atualizarStatusSerie(String id, String status) async {
    await _client
        .from('streaming_series')
        .update({
          'status': status,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id);
  }

  Future<void> destacarSerie(String id, bool destacada) async {
    await _client
        .from('streaming_series')
        .update({'is_featured': destacada})
        .eq('id', id);
  }

  Future<void> atualizarStatusTemporada(String id, String status) async {
    await _client
        .from('streaming_seasons')
        .update({'status': status})
        .eq('id', id);
  }

  Future<void> atualizarStatusEpisodio(String id, String status) async {
    final dados = <String, dynamic>{'status': status};
    if (status == 'publicado') {
      dados['published_at'] = DateTime.now().toUtc().toIso8601String();
    }
    await _client.from('streaming_episodes').update(dados).eq('id', id);
  }

  Future<void> excluirSerie(String id) async {
    await _client.from('streaming_series').delete().eq('id', id);
  }

  Future<void> excluirTemporada(String id) async {
    await _client.from('streaming_seasons').delete().eq('id', id);
  }

  Future<void> excluirEpisodio(String id) async {
    await _client.from('streaming_episodes').delete().eq('id', id);
  }

  Future<List<Map<String, dynamic>>> fetchPlanosAdmin() async {
    final resposta = await _client
        .from('streaming_plans')
        .select()
        .order('ordem', ascending: true)
        .order('nivel', ascending: true);
    return _list(resposta);
  }

  Future<void> salvarPlano(Map<String, dynamic> dados, {String? id}) async {
    if (id == null) {
      await _client.from('streaming_plans').insert(dados);
    } else {
      await _client.from('streaming_plans').update(dados).eq('id', id);
    }
  }

  Future<void> excluirPlano(String id) async {
    await _client.from('streaming_plans').delete().eq('id', id);
  }

  Future<List<Map<String, dynamic>>> fetchAssinaturasAdmin() async {
    final resposta = await _client
        .from('streaming_subscriptions')
        .select('*, perfis(nome,email)')
        .order('created_at', ascending: false)
        .limit(200);
    return _list(resposta);
  }

  Future<void> atualizarStatusAssinatura(
    String id,
    String status, {
    int dias = 30,
  }) async {
    final agora = DateTime.now().toUtc();
    final dados = <String, dynamic>{
      'status': status,
      'last_sync_at': agora.toIso8601String(),
      'updated_at': agora.toIso8601String(),
    };
    if (status == 'ativa') {
      dados['started_at'] = agora.toIso8601String();
      dados['current_period_end'] = agora
          .add(Duration(days: dias))
          .toIso8601String();
      dados['cancel_at_period_end'] = false;
    }
    await _client.from('streaming_subscriptions').update(dados).eq('id', id);
  }

  Future<void> debugLog(String mensagem) async {
    debugPrint(mensagem);
  }
}
