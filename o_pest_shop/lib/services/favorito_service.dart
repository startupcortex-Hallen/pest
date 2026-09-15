import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/favorito.dart';
import 'supabase_service.dart';

class FavoritoService {
  final SupabaseClient _client = SupabaseService.instance.client;

  Future<List<Favorito>> fetchFavoritos(String userId) async {
    final response = await _client
        .from('favoritos')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    if (response is! List) return [];
    return response
        .map((json) => Favorito.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<List<int>> fetchFavoritosIds(String userId) async {
    final response = await _client
        .from('favoritos')
        .select('produto_id')
        .eq('user_id', userId);

    if (response is! List) return [];
    return response
        .map((json) => (json as Map<String, dynamic>)['produto_id'] as int)
        .toList();
  }

  Future<bool> isFavorito(String userId, int produtoId) async {
    final response = await _client
        .from('favoritos')
        .select('id')
        .eq('user_id', userId)
        .eq('produto_id', produtoId)
        .maybeSingle();
    return response != null;
  }

  Future<void> adicionar(String userId, int produtoId) async {
    await _client.from('favoritos').insert({
      'user_id': userId,
      'produto_id': produtoId,
    });
  }

  Future<void> remover(String userId, int produtoId) async {
    await _client
        .from('favoritos')
        .delete()
        .eq('user_id', userId)
        .eq('produto_id', produtoId);
  }

  Future<void> toggle(String userId, int produtoId) async {
    final exists = await isFavorito(userId, produtoId);
    if (exists) {
      await remover(userId, produtoId);
    } else {
      await adicionar(userId, produtoId);
    }
  }
}
