import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/cupom.dart';
import 'supabase_service.dart';

class CupomService {
  final SupabaseClient _client = SupabaseService.instance.client;

  Future<List<Cupom>> fetchCupons() async {
    final response = await _client
        .from('cupons')
        .select()
        .eq('ativo', true)
        .order('data_validade');

    if (response is! List) return [];
    return response
        .map((json) => Cupom.fromJson(json as Map<String, dynamic>))
        .where((c) => c.valido)
        .toList();
  }

  Future<Cupom?> validarCupom(String codigo) async {
    final code = codigo.trim().toUpperCase();
    if (code.isEmpty) return null;
    final response = await _client
        .from('cupons')
        .select()
        .ilike('codigo', code)
        .maybeSingle();

    if (response == null) return null;

    final cupom = Cupom.fromJson(response as Map<String, dynamic>);
    if (!cupom.valido) return null;
    return cupom;
  }

  Future<void> usarCupom(int cupomId) async {
    await _client
        .from('cupons')
        .update({
          'usos_atuais': _client.rpc('increment', params: {'row_id': cupomId}),
        })
        .eq('id', cupomId);
  }
}
