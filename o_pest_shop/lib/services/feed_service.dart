import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/feed_comment.dart';
import '../models/feed_post.dart';
import 'supabase_service.dart';

class FeedService {
  final SupabaseClient _client = SupabaseService.instance.client;

  Future<List<FeedPost>> fetchPosts({String? currentUserId}) async {
    final response = await _client
        .from('posts_feed')
        .select('*, post_likes(user_id), post_comentarios(*), unidades(id, nome, foto_url)')
        .order('created_at', ascending: false)
        .limit(20);

    if (response is! List) {
      debugPrint('████ fetchPosts response nao é List: $response');
      return [];
    }
    debugPrint('████ fetchPosts raw rows: ${response.length}');
    if (response.isNotEmpty) {
      debugPrint('████ primeiro post raw: ${response.first}');
    }
    final posts = <FeedPost>[];
    for (final json in response) {
      try {
        posts.add(FeedPost.fromJson(json as Map<String, dynamic>, currentUserId: currentUserId));
      } catch (e) {
        debugPrint('████ ERRO ao parsear post: $e');
        debugPrint('████ JSON do post com erro: $json');
      }
    }
    debugPrint('████ fetchPosts parsed: ${posts.length} posts');
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
      final response = await _client
          .from('posts_feed')
          .select('categoria')
          .order('created_at', ascending: false);

      if (response is! List) return [];
      final categorias = response
          .map((json) => (json as Map<String, dynamic>)['categoria'] as String?)
          .where((c) => c != null && c.isNotEmpty)
          .map((c) => c!)
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
    final response = await _client
        .from('post_comentarios')
        .select()
        .eq('post_id', postId)
        .order('created_at', ascending: true);

    if (response is! List) return [];
    final comments = <FeedComment>[];
    for (final json in response) {
      try {
        final c = json as Map<String, dynamic>;
        // Busca perfil do autor separadamente (FK pode não existir)
        try {
          final perfil = await _client
              .from('perfis')
              .select('nome, avatar_url')
              .eq('id', c['user_id'])
              .maybeSingle();
          if (perfil != null) {
            c['perfis'] = perfil;
          } else {
            debugPrint('████ Perfil não encontrado para user_id=${c['user_id']}');
          }
        } catch (e) {
          debugPrint('████ ERRO ao buscar perfil do comentário: $e');
        }
        comments.add(FeedComment.fromJson(c));
      } catch (e) {
        debugPrint('████ ERRO ao parsear comentário: $e');
      }
    }
    return comments;
  }

  Future<bool> checkCandidatura(String vagaId, String userId) async {
    final response = await _client
        .from('candidaturas')
        .select('id')
        .eq('vaga_id', vagaId)
        .eq('user_id', userId)
        .maybeSingle();
    return response != null;
  }

  Future<void> submitCandidatura(Map<String, dynamic> data) async {
    await _client.from('candidaturas').insert(data);
  }
}
