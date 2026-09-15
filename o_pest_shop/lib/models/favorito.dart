class Favorito {
  final int id;
  final String userId;
  final int produtoId;
  final String? createdAt;

  Favorito({
    required this.id,
    required this.userId,
    required this.produtoId,
    this.createdAt,
  });

  factory Favorito.fromJson(Map<String, dynamic> json) {
    return Favorito(
      id: json['id'] as int,
      userId: json['user_id'] as String,
      produtoId: json['produto_id'] as int,
      createdAt: json['created_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'produto_id': produtoId,
      };
}
