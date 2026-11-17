import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/streaming_models.dart';
import '../supabase_service.dart';

class StreamingSubscriptionService {
  final SupabaseClient _client = SupabaseService.instance.client;

  List<Map<String, dynamic>> _list(dynamic resposta) {
    if (resposta is! List) return const [];
    return resposta
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<List<StreamingPlan>> fetchPlanos() async {
    try {
      final resposta = await _client
          .from('streaming_plans')
          .select()
          .eq('ativo', true)
          .order('ordem', ascending: true)
          .order('nivel', ascending: true);
      return _list(resposta)
          .map(StreamingPlan.fromJson)
          .where((plano) => plano.id.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('Erro fetchPlanos streaming: $e');
      return const [];
    }
  }

  Future<StreamingSubscription?> fetchMinhaAssinatura() async {
    final usuarioId = _client.auth.currentUser?.id;
    if (usuarioId == null) return null;
    try {
      final resposta = await _client
          .from('streaming_subscriptions')
          .select()
          .eq('user_id', usuarioId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (resposta == null) return null;
      return StreamingSubscription.fromJson(
        Map<String, dynamic>.from(resposta),
      );
    } catch (e) {
      debugPrint('Erro fetchMinhaAssinatura: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>> criarAssinatura(String planId) async {
    final resposta = await _client.functions.invoke(
      'mp-subscription',
      body: {'action': 'assinar', 'plan_id': planId},
    );
    final data = resposta.data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw StateError('Resposta inválida do servidor de assinaturas.');
  }

  Future<Map<String, dynamic>> sincronizarAssinatura() async {
    final resposta = await _client.functions.invoke(
      'mp-subscription',
      body: {'action': 'status'},
    );
    final data = resposta.data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw StateError('Resposta inválida do servidor de assinaturas.');
  }

  Future<Map<String, dynamic>> cancelarAssinatura() async {
    final resposta = await _client.functions.invoke(
      'mp-subscription',
      body: {'action': 'cancelar'},
    );
    final data = resposta.data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw StateError('Resposta inválida do servidor de assinaturas.');
  }

  Future<int> fetchNivelAcesso() async {
    if (_client.auth.currentUser == null) return 0;
    try {
      final resposta = await _client.rpc('streaming_nivel_assinatura');
      if (resposta is num) return resposta.toInt();
      return int.tryParse(resposta?.toString() ?? '') ?? 0;
    } catch (e) {
      debugPrint('Erro fetchNivelAcesso: $e');
      return 0;
    }
  }

  Future<DateTime?> fetchCodigoAtivoExpiraEm() async {
    final usuarioId = _client.auth.currentUser?.id;
    if (usuarioId == null) return null;
    try {
      final resposta = await _client
          .from('streaming_access_code_redemptions')
          .select('expires_at')
          .eq('user_id', usuarioId)
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
          .order('expires_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (resposta == null) return null;
      return DateTime.tryParse(resposta['expires_at']?.toString() ?? '');
    } catch (e) {
      debugPrint('Erro fetchCodigoAtivoExpiraEm: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>> resgatarCodigo(String codigo) async {
    final resposta = await _client.rpc(
      'streaming_resgatar_codigo',
      params: {'p_codigo': codigo.trim()},
    );
    if (resposta is Map) return Map<String, dynamic>.from(resposta);
    throw StateError('Resposta inválida ao resgatar o código.');
  }
}
