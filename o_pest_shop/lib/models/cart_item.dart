class CartItem {
  final int id;
  final String userId;
  final int produtoId;
  int quantidade;
  final String? cor;
  final String? createdAt;
  final String? produtoNome;
  final double? produtoPreco;
  final double? produtoPrecoPromocional;
  final String? produtoImagem;
  final int? produtoEstoque;
  final int? produtoUnidadeId;
  final bool produtoEmPromocao;
  final bool produtoFreteGratis;

  CartItem({
    required this.id,
    required this.userId,
    required this.produtoId,
    this.quantidade = 1,
    this.cor,
    this.createdAt,
    this.produtoNome,
    this.produtoPreco,
    this.produtoPrecoPromocional,
    this.produtoImagem,
    this.produtoEstoque,
    this.produtoUnidadeId,
    this.produtoEmPromocao = false,
    this.produtoFreteGratis = false,
  });

  bool get temPromocao =>
      produtoEmPromocao &&
      produtoPrecoPromocional != null &&
      produtoPrecoPromocional! < (produtoPreco ?? 0);

  double get precoAtual =>
      temPromocao ? produtoPrecoPromocional! : (produtoPreco ?? 0);

  double get economiaPorItem => ((produtoPreco ?? 0) - precoAtual).clamp(0, double.infinity);

  double get economia => economiaPorItem * quantidade;

  double get total => precoAtual * quantidade;

  bool get esgotado => (produtoEstoque ?? 0) <= 0;

  factory CartItem.fromJson(Map<String, dynamic> json) {
    final produto = json['produtos'] as Map<String, dynamic>?;
    // url_imagem é TEXT[] no banco — extrai a primeira imagem com segurança
    String? imagem;
    final rawImagem = produto?['url_imagem'];
    if (rawImagem is List && rawImagem.isNotEmpty) {
      imagem = rawImagem.first.toString();
    } else if (rawImagem is String && rawImagem.isNotEmpty) {
      imagem = rawImagem;
    }
    return CartItem(
      id: json['id'] as int,
      userId: json['user_id'] as String,
      produtoId: json['produto_id'] as int,
      quantidade: json['quantidade'] as int? ?? 1,
      cor: json['cor'] as String?,
      createdAt: json['created_at'] as String?,
      produtoNome: produto?['nome'] as String?,
      produtoPreco: (produto?['preco'] as num?)?.toDouble(),
      produtoPrecoPromocional: (produto?['preco_promocional'] as num?)?.toDouble(),
      produtoImagem: imagem,
      produtoEstoque: produto?['estoque'] as int?,
      produtoUnidadeId: produto?['unidade_id'] as int?,
      produtoEmPromocao: produto?['em_promocao'] == true,
      produtoFreteGratis: produto?['frete_gratis'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'produto_id': produtoId,
        'quantidade': quantidade,
        'cor': cor,
      };
}
