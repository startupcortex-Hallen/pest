class FeedPost {
  final String id;
  final String userId;
  final String autorNome;
  final String? autorImagem;
  final String titulo;
  final String? descricao;
  final String? urlImagem;
  final String? urlYoutube;
  final String categoria;
  final int likeCount;
  final int commentCount;
  final bool likedByMe;
  final String? createdAt;
  final int? unidadeId;
  final String? unidadeNome;
  final String? unidadeFotoUrl;

  FeedPost({
    required this.id,
    required this.userId,
    this.autorNome = '',
    this.autorImagem,
    required this.titulo,
    this.descricao,
    this.urlImagem,
    this.urlYoutube,
    this.categoria = 'noticia',
    this.likeCount = 0,
    this.commentCount = 0,
    this.likedByMe = false,
    this.createdAt,
    this.unidadeId,
    this.unidadeNome,
    this.unidadeFotoUrl,
  });

  factory FeedPost.fromJson(Map<String, dynamic> json, {String? currentUserId}) {
    int likeCount = 0;
    bool likedByMe = false;

    final likes = json['post_likes'] as List?;
    if (likes != null) {
      likeCount = likes.length;
      if (currentUserId != null) {
        likedByMe = likes.any((like) {
          if (like is Map) return like['user_id'] == currentUserId;
          return like == currentUserId;
        });
      }
    }

    int commentCount = 0;
    final comments = json['post_comentarios'] as List?;
    if (comments != null) commentCount = comments.length;

    int? unidadeId;
    String? unidadeNome;
    String? unidadeFotoUrl;
    final unidades = json['unidades'];
    if (unidades is Map) {
      unidadeId = unidades['id'] as int?;
      unidadeNome = unidades['nome'] as String?;
      unidadeFotoUrl = unidades['foto_url'] as String?;
    }

    return FeedPost(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      autorNome: unidadeNome ?? 'O Pest - Shop',
      autorImagem: unidadeFotoUrl,
      titulo: json['titulo'] as String? ?? '',
      descricao: json['descricao'] as String?,
      urlImagem: json['url_imagem'] as String?,
      urlYoutube: json['url_youtube'] as String?,
      categoria: json['categoria'] as String? ?? 'noticia',
      likeCount: likeCount,
      commentCount: commentCount,
      likedByMe: likedByMe,
      createdAt: json['created_at'] as String?,
      unidadeId: unidadeId ?? json['unidade_id'] as int?,
      unidadeNome: unidadeNome,
    );
  }
}
