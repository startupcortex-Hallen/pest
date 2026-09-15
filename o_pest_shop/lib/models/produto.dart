class Produto {
  final int id;
  final String nome;
  final String descricao;
  final double preco;
  final bool emPromocao;
  final List<String> urlImagem;
  final int categoriaId;
  final String? categoriaNome;
  final int? marcaId;
  final String? marcaNome;
  final int estoque;
  final int? unidadeId;
  final String? unidadeNome;
  final int vendas;
  final bool freteGratis;
  final int percentualDesconto;
  final String? garantia;
  final int parcelas;
  final double? precoPromocional;
  final List<String> cores;

  Produto({
    required this.id,
    required this.nome,
    required this.descricao,
    required this.preco,
    this.emPromocao = false,
    this.urlImagem = const [],
    required this.categoriaId,
    this.categoriaNome,
    this.marcaId,
    this.marcaNome,
    this.estoque = 0,
    this.unidadeId,
    this.unidadeNome,
    this.vendas = 0,
    this.freteGratis = false,
    this.percentualDesconto = 0,
    this.garantia,
    this.parcelas = 12,
    this.precoPromocional,
    this.cores = const [],
  });

  factory Produto.fromJson(Map<String, dynamic> json) {
    List<String> imagens;
    final raw = json['url_imagem'];
    if (raw is List) {
      imagens = [];
      for (final e in raw) {
        if (e is String && e.isNotEmpty) imagens.add(e);
      }
    } else if (raw is String && raw.isNotEmpty) {
      final clean = raw.replaceAll(RegExp(r'[{}]'), '');
      imagens = clean.isNotEmpty ? [clean] : [];
    } else {
      imagens = [];
    }

    String? marcaNome;
    final marcas = json['marcas'];
    if (marcas is Map) {
      marcaNome = marcas['nome'] as String?;
    }

    List<String> cores = [];
    final rawCores = json['cores'];
    if (rawCores is List) {
      for (final e in rawCores) {
        if (e is String && e.isNotEmpty) cores.add(e);
      }
    } else if (rawCores is String && rawCores.isNotEmpty) {
      cores = rawCores.replaceAll(RegExp(r'[{}]'), '').split(',');
    }

    int? unidadeId;
    String? unidadeNome;
    final unidades = json['unidades'];
    if (unidades is Map) {
      unidadeId = unidades['id'] as int?;
      unidadeNome = unidades['nome'] as String?;
    }

    return Produto(
      id: json['id'] as int,
      nome: json['nome'] as String? ?? '',
      descricao: json['descricao'] as String? ?? '',
      preco: (json['preco'] as num?)?.toDouble() ?? 0.0,
      emPromocao: json['em_promocao'] as bool? ?? false,
      urlImagem: imagens,
      categoriaId: json['categoria_id'] as int? ?? 0,
      categoriaNome: json['categorias'] is Map
          ? (json['categorias'] as Map)['nome'] as String?
          : null,
      marcaId: json['marca_id'] as int?,
      marcaNome: marcaNome,
      estoque: json['estoque'] as int? ?? 0,
      unidadeId: unidadeId ?? json['unidade_id'] as int?,
      unidadeNome: unidadeNome,
      vendas: json['vendas'] as int? ?? 0,
      freteGratis: json['frete_gratis'] as bool? ?? false,
      percentualDesconto: json['percentual_desconto'] as int? ?? (json['em_promocao'] == true ? 10 : 0),
      garantia: json['garantia'] as String?,
      parcelas: json['parcelas'] as int? ?? 12,
      precoPromocional: (json['preco_promocional'] as num?)?.toDouble(),
      cores: cores,
    );
  }

  double get precoAtual => (emPromocao && precoPromocional != null) ? precoPromocional! : preco;

  bool get temDesconto => emPromocao && precoPromocional != null && precoPromocional! < preco;

  Map<String, dynamic> toJson() => {
        'id': id,
        'nome': nome,
        'descricao': descricao,
        'preco': preco,
        'em_promocao': emPromocao,
        'categoria_id': categoriaId,
        'estoque': estoque,
        'cores': cores,
      };
}
