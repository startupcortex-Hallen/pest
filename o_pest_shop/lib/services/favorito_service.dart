import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/favorito.dart';
import '../models/produto.dart';
import 'produto_service.dart';
import 'supabase_service.dart';

class FavoritoService {
  final SupabaseClient _client = SupabaseService.instance.client;

  /// Busca os IDs e depois os produtos na view pública. Evita o embed em
  /// `produtos(*)` (que expunha custo e carregava colunas desnecessárias).
  Future<List<Produto>> fetchProdutosFavoritos(String userId) async {
    final ids = await fetchFavoritosIds(userId);
    if (ids.isEmpty) return const [];

    final response = await _client
        .from('produtos_publicos')
        .select(ProdutoService.publicColumns)
        .inFilter('id', ids);

    if (response is! List) return const [];
    final porId = <int, Produto>{};
    for (final row in response) {
      final produto = Produto.fromJson(row as Map<String, dynamic>);
      porId[produto.id] = produto;
    }
    return ids
        .map((id) => porId[id])
        .whereType<Produto>()
        .toList(growable: false);
  }

  Future<List<Favorito>> fetchFavoritos(String userId) async {
    final response = await _client
        .from('favoritos')
        .select()
        .eq('user_id', userId)
        .order('id', ascending: false);

    return response.map((json) => Favorito.fromJson(json)).toList();
  }

  Future<List<int>> fetchFavoritosIds(String userId) async {
    final response = await _client
        .from('favoritos')
        .select('produto_id')
        .eq('user_id', userId);

    return response
        .map((json) => json['produto_id'])
        .whereType<num>()
        .map((id) => id.toInt())
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
