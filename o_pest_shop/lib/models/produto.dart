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
  final String? sku;
  final String? gtin;
  final double? pesoKg;
  final double? comprimentoCm;
  final double? larguraCm;
  final double? alturaCm;
  final String condicao;
  final double? custo;
  final String? mlCategoryId;
  final String? mlDomainId;
  final String? mlListingType;
  final String? mlStatus;
  final String? mlItemId;
  final String? mlPermalink;
  final bool mlSyncEnabled;

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
    this.sku,
    this.gtin,
    this.pesoKg,
    this.comprimentoCm,
    this.larguraCm,
    this.alturaCm,
    this.condicao = 'new',
    this.custo,
    this.mlCategoryId,
    this.mlDomainId,
    this.mlListingType,
    this.mlStatus,
    this.mlItemId,
    this.mlPermalink,
    this.mlSyncEnabled = false,
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

    String? marcaNome = json['marca_nome'] as String?;
    final marcas = json['marcas'];
    if (marcas is Map) {
      marcaNome = marcas['nome'] as String? ?? marcaNome;
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

    int? unidadeId = json['unidade_id'] as int?;
    String? unidadeNome = json['unidade_nome'] as String?;
    final unidades = json['unidades'];
    if (unidades is Map) {
      unidadeId = unidades['id'] as int? ?? unidadeId;
      unidadeNome = unidades['nome'] as String? ?? unidadeNome;
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
          : json['categoria_nome'] as String?,
      marcaId: json['marca_id'] as int?,
      marcaNome: marcaNome,
      estoque: json['estoque'] as int? ?? 0,
      unidadeId: unidadeId,
      unidadeNome: unidadeNome,
      vendas: json['vendas'] as int? ?? 0,
      freteGratis: json['frete_gratis'] as bool? ?? false,
      percentualDesconto: json['percentual_desconto'] as int? ?? (json['em_promocao'] == true ? 10 : 0),
      garantia: json['garantia'] as String?,
      parcelas: json['parcelas'] as int? ?? 12,
      precoPromocional: (json['preco_promocional'] as num?)?.toDouble(),
      cores: cores,
      sku: json['sku'] as String?,
      gtin: json['gtin'] as String?,
      pesoKg: (json['peso_kg'] as num?)?.toDouble(),
      comprimentoCm: (json['comprimento_cm'] as num?)?.toDouble(),
      larguraCm: (json['largura_cm'] as num?)?.toDouble(),
      alturaCm: (json['altura_cm'] as num?)?.toDouble(),
      condicao: json['condicao'] as String? ?? 'new',
      custo: (json['custo'] as num?)?.toDouble(),
      mlCategoryId: json['ml_category_id'] as String?,
      mlDomainId: json['ml_domain_id'] as String?,
      mlListingType: json['ml_listing_type'] as String?,
      mlStatus: json['ml_status'] as String?,
      mlItemId: json['ml_item_id'] as String?,
      mlPermalink: json['ml_permalink'] as String?,
      mlSyncEnabled: json['ml_sync_enabled'] == true,
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
        if (sku != null) 'sku': sku,
        if (gtin != null) 'gtin': gtin,
        if (pesoKg != null) 'peso_kg': pesoKg,
        if (comprimentoCm != null) 'comprimento_cm': comprimentoCm,
        if (larguraCm != null) 'largura_cm': larguraCm,
        if (alturaCm != null) 'altura_cm': alturaCm,
        'condicao': condicao,
        if (custo != null) 'custo': custo,
        if (mlCategoryId != null) 'ml_category_id': mlCategoryId,
        if (mlDomainId != null) 'ml_domain_id': mlDomainId,
        if (mlListingType != null) 'ml_listing_type': mlListingType,
        'ml_sync_enabled': mlSyncEnabled,
      };
}
