import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

class NutritionService {
  final SupabaseClient _client = SupabaseService.instance.client;

  Future<void> registrarAgua(String userId, int ml) async {
    final hoje = DateTime.now().toIso8601String().split('T')[0];
    final existente = await _client.from('agua_registro')
      .select('id, ml').eq('user_id', userId).eq('data', hoje).maybeSingle();
    if (existente != null) {
      final total = ((existente['ml'] as num?)?.toInt() ?? 0) + ml;
      await _client.from('agua_registro').update({'ml': total}).eq('id', existente['id'] as int);
    } else {
      await _client.from('agua_registro').insert({'user_id': userId, 'data': hoje, 'ml': ml});
    }
  }

  Future<List<Map<String, dynamic>>> fetchAssinaturas(String userId) async {
    final r = await _client.from('assinaturas').select().eq('user_id', userId).order('id', ascending: false);
    return (r as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> fetchNutricionistas() async {
    final r = await _client.from('nutricionistas').select().eq('disponivel', true);
    return (r as List).cast<Map<String, dynamic>>();
  }

  Future<void> agendarConsulta(String userId, int nutricionistaId, String dataHora) async {
    await _client.from('consultas').insert({
      'user_id': userId, 'nutricionista_id': nutricionistaId, 'data_hora': dataHora,
    });
  }

  Future<List<Map<String, dynamic>>> fetchTreinos(String userId) async {
    final r = await _client.from('treinos').select('*, exercicios(*)').eq('user_id', userId).order('ordem');
    return (r as List).cast<Map<String, dynamic>>();
  }
}
