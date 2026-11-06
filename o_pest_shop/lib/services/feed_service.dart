import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/feed_comment.dart';
import '../models/feed_post.dart';
import 'supabase_service.dart';

class FeedService {
  final SupabaseClient _client = SupabaseService.instance.client;

  Future<List<FeedPost>> fetchPosts({String? currentUserId}) async {
    // Traz apenas contadores (IDs) de comentários/likes. O texto completo dos
    // comentários é carregado só no detalhe, evitando payload gigante no feed.
    final response = await _client
        .from('posts_feed')
        .select(
          'id,user_id,titulo,descricao,url_imagem,url_youtube,categoria,'
          'created_at,unidade_id,'
          'post_likes(user_id),post_comentarios(id),'
          'unidades(id,nome,foto_url)',
        )
        .order('created_at', ascending: false)
        .limit(20);

    if (response is! List) return const [];

    final posts = <FeedPost>[];
    for (final json in response) {
      try {
        final mapa = json as Map<String, dynamic>;
        final categoria = (mapa['categoria'] as String? ?? '').toLowerCase();
        if (categoria.startsWith('vaga') || categoria == 'emprego') continue;
        posts.add(FeedPost.fromJson(mapa, currentUserId: currentUserId));
      } catch (e) {
        debugPrint('Erro ao parsear post: $e');
      }
    }
    return posts;
  }

  Future<void> likePost(String postId, String userId) async {
    await _client.from('post_likes').insert({
      'post_id': postId,
      'user_id': userId,
    });
  }

  Future<void> unlikePost(String postId, String userId) async {
    await _client
        .from('post_likes')
        .delete()
        .eq('post_id', postId)
        .eq('user_id', userId);
  }

  Future<void> addComment(String postId, String userId, String texto) async {
    await _client.from('post_comentarios').insert({
      'post_id': postId,
      'user_id': userId,
      'texto': texto,
    });
  }

  /// Verifica se o usuário já comentou nesta publicação
  Future<bool> checkJaComentou(String postId, String userId) async {
    try {
      final r = await _client
          .from('post_comentarios')
          .select('id')
          .eq('post_id', postId)
          .eq('user_id', userId)
          .maybeSingle();
      return r != null;
    } catch (_) {
      return false;
    }
  }

  Future<void> deleteComment(String commentId) async {
    await _client.from('post_comentarios').delete().eq('id', commentId);
  }

  Future<List<String>> fetchCategorias() async {
    try {
      final response = await _client.rpc('feed_categorias');
      if (response is! List) return [];
      final categorias = response
          .map((json) {
            if (json is Map) return json['categoria'] as String?;
            return json as String?;
          })
          .whereType<String>()
          .where((c) =>
              c.isNotEmpty &&
              !c.toLowerCase().startsWith('vaga') &&
              c.toLowerCase() != 'emprego')
          .toSet()
          .toList();
      categorias.sort();
      return categorias;
    } catch (e) {
      debugPrint('Erro fetchCategorias: $e');
      return [];
    }
  }

  Future<List<FeedComment>> fetchComments(String postId) async {
    // Join com o perfil elimina uma consulta por comentário (N+1). Se o join
    // não estiver disponível para anônimos, cai no select simples.
    dynamic response;
    try {
      response = await _client
          .from('post_comentarios')
          .select('*, perfis(nome, avatar_url)')
          .eq('post_id', postId)
          .order('created_at', ascending: true);
    } catch (_) {
      response = await _client
          .from('post_comentarios')
          .select()
          .eq('post_id', postId)
          .order('created_at', ascending: true);
    }

    if (response is! List) return [];
    final comments = <FeedComment>[];
    for (final json in response) {
      try {
        comments.add(FeedComment.fromJson(json as Map<String, dynamic>));
      } catch (e) {
        debugPrint('Erro ao parsear comentário: $e');
      }
    }
    return comments;
  }
}
