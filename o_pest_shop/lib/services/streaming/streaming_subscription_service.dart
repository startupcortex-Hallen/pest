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
}
