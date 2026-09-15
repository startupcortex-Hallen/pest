import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/cart_item.dart';
import 'supabase_service.dart';

class CartService {
  final SupabaseClient _client = SupabaseService.instance.client;

  Future<List<CartItem>> fetchCart(String userId) async {
    final response = await _client
        .from('carrinho')
        .select('*, produtos(nome, preco, preco_promocional, url_imagem, estoque, unidade_id, em_promocao, frete_gratis)')
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    if (response is! List) return [];
    return response
        .map((json) => CartItem.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<int> fetchCartCount(String userId) async {
    final response = await _client
        .from('carrinho')
        .select('id')
        .eq('user_id', userId);
    if (response is! List) return 0;
    return response.length;
  }

  Future<void> adicionar(String userId, int produtoId, {int quantidade = 1, String? cor}) async {
    var query = _client
        .from('carrinho')
        .select('id, quantidade')
        .eq('user_id', userId)
        .eq('produto_id', produtoId);
    if (cor != null && cor.isNotEmpty) {
      query = query.eq('cor', cor);
    } else {
      query = query.isFilter('cor', null);
    }
    final existing = await query.maybeSingle();

    if (existing != null) {
      final qtd = (existing['quantidade'] as int? ?? 0) + quantidade;
      await _client
          .from('carrinho')
          .update({'quantidade': qtd})
          .eq('id', existing['id']);
    } else {
      await _client.from('carrinho').insert({
        'user_id': userId,
        'produto_id': produtoId,
        'quantidade': quantidade,
        if (cor != null && cor.isNotEmpty) 'cor': cor,
      });
    }
  }

  Future<void> atualizarQuantidade(int cartItemId, int quantidade) async {
    if (quantidade <= 0) {
      await _client.from('carrinho').delete().eq('id', cartItemId);
    } else {
      await _client
          .from('carrinho')
          .update({'quantidade': quantidade})
          .eq('id', cartItemId);
    }
  }

  Future<void> remover(int cartItemId) async {
    await _client.from('carrinho').delete().eq('id', cartItemId);
  }

  Future<void> limpar(String userId) async {
    await _client.from('carrinho').delete().eq('user_id', userId);
  }
}
