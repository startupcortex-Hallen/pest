import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/favorito.dart';
import '../models/produto.dart';
import 'supabase_service.dart';

class FavoritoService {
  final SupabaseClient _client = SupabaseService.instance.client;

  /// Produtos favoritados COM os dados completos (join com produtos).
  /// É o que a tela de Favoritos usa — independe da Home.
  Future<List<Produto>> fetchProdutosFavoritos(String userId) async {
    final response = await _client
        .from('favoritos')
        .select(
            'produto_id, produtos(*, marcas(nome), unidades(id, nome), categorias(nome))')
        .eq('user_id', userId)
        .order('id', ascending: false);

    return response
        .where((row) => row['produtos'] != null)
        .map((row) => Produto.fromJson(
            (row['produtos'] as Map).cast<String, dynamic>()))
        .toList();
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
