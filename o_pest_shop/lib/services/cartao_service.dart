import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/cartao_credito.dart';
import 'supabase_service.dart';

class CartaoService {
  final SupabaseClient _client = SupabaseService.instance.client;

  Future<List<CartaoCredito>> fetchCartoes(String userId) async {
    final response = await _client
        .from('cartoes_usuario')
        .select()
        .eq('user_id', userId)
        .order('padrao', ascending: false);

    if (response is! List) return [];
    return response
        .map((json) => CartaoCredito.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<void> adicionar(CartaoCredito cartao) async {
    await _client.from('cartoes_usuario').insert(cartao.toJson());
  }

  Future<void> remover(int cartaoId) async {
    await _client.from('cartoes_usuario').delete().eq('id', cartaoId);
  }
}
