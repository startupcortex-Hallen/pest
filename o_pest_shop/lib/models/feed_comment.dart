class FeedComment {
  final String id;
  final String userId;
  final String autorNome;
  final String? autorImagem;
  final String texto;
  final String? createdAt;

  FeedComment({
    required this.id,
    required this.userId,
    this.autorNome = '',
    this.autorImagem,
    required this.texto,
    this.createdAt,
  });

  factory FeedComment.fromJson(Map<String, dynamic> json) {
    final perfis = json['perfis'] as Map<String, dynamic>?;
    return FeedComment(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      autorNome: perfis?['nome'] as String? ?? 'Usuário',
      autorImagem: perfis?['avatar_url'] as String?,
      texto: json['texto'] as String? ?? '',
      createdAt: json['created_at'] as String?,
    );
  }
}
