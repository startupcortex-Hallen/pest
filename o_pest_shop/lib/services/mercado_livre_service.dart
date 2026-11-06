import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// Operações de Mercado Livre disponíveis para o painel.
///
/// O OAuth e a sincronização real rodam nas Edge Functions `ml-oauth-start`,
/// `ml-oauth-callback`, `ml-sync` e `ml-webhook`. Esta classe apenas orquestra
/// o painel e nunca guarda tokens no app.
class MercadoLivreService {
  final SupabaseClient _client = SupabaseService.instance.client;

  Future<Map<String, dynamic>?> fetchStatus(int unidadeId) async {
    final r = await _client
        .from('integracoes_loja')
        .select(
          'id, unidade_id, plataforma, ml_user_id, ml_nickname, status, erro, '
          'connected_at, last_sync_at, created_at, updated_at',
        )
        .eq('unidade_id', unidadeId)
        .maybeSingle();
    return r;
  }

  Future<String> iniciarConexao(int unidadeId) async {
    final resposta = await _client.functions.invoke(
      'ml-oauth-start',
      body: {'unidade_id': unidadeId},
    );
    final data = resposta.data;
    if (data is Map && data['url'] is String) return data['url'] as String;
    throw StateError('Não foi possível iniciar a conexão com o Mercado Livre.');
  }

  Future<void> desconectar(int unidadeId) async {
    await _client.functions.invoke(
      'ml-sync',
      body: {'action': 'desconectar', 'unidade_id': unidadeId},
    );
  }

  Future<Map<String, dynamic>> publicarOuSincronizar(
    int produtoId, {
    String action = 'publicar',
  }) async {
    final resposta = await _client.functions.invoke(
      'ml-sync',
      body: {'action': action, 'produto_id': produtoId},
    );
    final data = resposta.data;
    if (data is Map) return data.cast<String, dynamic>();
    return {'ok': true};
  }

  Future<Map<String, dynamic>> sincronizarLote(int unidadeId) async {
    final resposta = await _client.functions.invoke(
      'ml-sync',
      body: {'action': 'sincronizar_lote', 'unidade_id': unidadeId},
    );
    final data = resposta.data;
    if (data is Map) return data.cast<String, dynamic>();
    return {'ok': true};
  }

  Future<List<Map<String, dynamic>>> fetchAnuncios(int unidadeId) async {
    final r = await _client
        .from('ml_anuncios')
        .select(
          'id, produto_id, ml_item_id, ml_user_product_id, category_id, '
          'listing_type, status, permalink, erro, last_sync_at',
        )
        .eq('unidade_id', unidadeId)
        .order('updated_at', ascending: false);
    if (r is! List) return [];
    return r.cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> fetchEventos({int limite = 30}) async {
    final r = await _client
        .from('ml_eventos')
        .select('id, topic, resource, status, attempts, erro, created_at, processed_at')
        .order('created_at', ascending: false)
        .limit(limite);
    if (r is! List) return [];
    return r.cast<Map<String, dynamic>>();
  }
}
