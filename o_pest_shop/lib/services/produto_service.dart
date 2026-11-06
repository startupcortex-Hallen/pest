import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/produto.dart';
import '../models/categoria.dart';
import 'catalogo_local.dart';
import 'catalogo_service.dart';
import 'supabase_service.dart';

class ProdutoService {
  final CatalogoService _catalogo;

  ProdutoService({CatalogoService? catalogo})
      : _catalogo = catalogo ?? CatalogoService();

  SupabaseClient get _client => SupabaseService.instance.client;

  static const int pageSize = 50;

  /// Colunas públicas (a view já exclui custo/ML/loja privada).
  static const String publicColumns =
      'id,nome,descricao,preco,preco_promocional,em_promocao,url_imagem,'
      'categoria_id,marca_id,estoque,unidade_id,vendas,frete_gratis,'
      'percentual_desconto,garantia,parcelas,cores,sku,gtin,peso_kg,'
      'comprimento_cm,largura_cm,altura_cm,condicao,ativo,created_at,'
      'categoria_nome,marca_nome,unidade_nome';

  static List<Categoria>? _categoriasCache;
  static DateTime? _categoriasCacheEm;
  static const Duration _categoriasTtl = Duration(minutes: 10);

  Future<List<Categoria>> fetchCategorias({bool force = false}) async {
    final agora = DateTime.now();
    final cache = _categoriasCache;
    if (!force &&
        cache != null &&
        _categoriasCacheEm != null &&
        agora.difference(_categoriasCacheEm!) < _categoriasTtl) {
      return cache;
    }

    final snapshot = await _catalogo.lerCache();
    if (snapshot != null && snapshot.categorias.isNotEmpty) {
      final lista = snapshot.categorias
          .map((json) => Categoria.fromJson(json))
          .toList(growable: false);
      _categoriasCache = lista;
      _categoriasCacheEm = agora;
      return lista;
    }

    final response = await _client
        .from('categorias')
        .select('id,nome,icone')
        .order('nome', ascending: true);
    if (response is! List) return cache ?? [];

    final lista = response
        .map((json) => Categoria.fromJson(json as Map<String, dynamic>))
        .toList(growable: false);
    _categoriasCache = lista;
    _categoriasCacheEm = agora;
    return lista;
  }

  /// Busca produtos com filtro textual (ilike), paginação por cursor.
  Future<List<Produto>> fetchProdutos({
    int? categoriaId,
    int? lastId,
    String? search,
    int? marcaId,
    int? unidadeId,
  }) async {
    final locais = await _catalogo.carregarProdutosLocais();
    if (locais.isNotEmpty) {
      return CatalogoLocal.paraProdutos(
        CatalogoLocal.filtrar(
          locais,
          categoriaId: categoriaId,
          lastId: lastId,
          search: search,
          marcaId: marcaId,
          unidadeId: unidadeId,
          limite: pageSize,
        ),
      );
    }

    var query = _client
        .from('produtos_publicos')
        .select(publicColumns)
        .eq('ativo', true) as dynamic;

    if (categoriaId != null) query = query.eq('categoria_id', categoriaId);
    if (marcaId != null) query = query.eq('marca_id', marcaId);
    if (unidadeId != null) query = query.eq('unidade_id', unidadeId);
    if (search != null && search.isNotEmpty) {
      query = query.ilike('nome', '%$search%');
    }
    if (lastId != null) query = query.gt('id', lastId);

    final response = await query.order('id', ascending: true).limit(pageSize);
    if (response is! List) return [];
    return response
        .map((json) => Produto.fromJson(json as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<Produto?> fetchProdutoById(int id) async {
    final locais = await _catalogo.carregarProdutosLocais();
    if (locais.isNotEmpty) {
      for (final item in locais) {
        if (item['id'] == id && item['ativo'] != false) {
          return Produto.fromJson(item);
        }
      }
    }

    final response = await _client
        .from('produtos_publicos')
        .select(publicColumns)
        .eq('id', id)
        .eq('ativo', true)
        .maybeSingle();
    if (response == null) return null;
    return Produto.fromJson(response as Map<String, dynamic>);
  }

  Future<List<Produto>> fetchProdutosEmPromocao() async {
    final locais = await _catalogo.carregarProdutosLocais();
    if (locais.isNotEmpty) {
      return CatalogoLocal.paraProdutos(
        CatalogoLocal.filtrar(
          locais,
          emPromocao: true,
          limite: 20,
        ),
      );
    }

    final response = await _client
        .from('produtos_publicos')
        .select(publicColumns)
        .eq('em_promocao', true)
        .eq('ativo', true)
        .order('id', ascending: true)
        .limit(20);
    if (response is! List) return [];
    return response
        .map((json) => Produto.fromJson(json as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<Map<String, List<Produto>>> fetchProdutosPorMarca(
    int categoriaId,
  ) async {
    final locais = await _catalogo.carregarProdutosLocais();
    if (locais.isNotEmpty) {
      final produtos = CatalogoLocal.paraProdutos(
        CatalogoLocal.filtrar(
          locais,
          categoriaId: categoriaId,
          limite: 50,
        ),
      );
      return _agruparPorMarca(produtos);
    }

    final response = await _client
        .from('produtos_publicos')
        .select(publicColumns)
        .eq('categoria_id', categoriaId)
        .eq('ativo', true)
        .order('id', ascending: true)
        .limit(50);
    if (response is! List) return {};

    final produtos = response
        .map((json) => Produto.fromJson(json as Map<String, dynamic>))
        .toList(growable: false);
    return _agruparPorMarca(produtos);
  }

  Map<String, List<Produto>> _agruparPorMarca(List<Produto> produtos) {
    final Map<String, List<Produto>> grouped = {};
    for (final p in produtos) {
      final marca = p.marcaNome ?? 'Sem marca';
      grouped.putIfAbsent(marca, () => []);
      grouped[marca]!.add(p);
    }
    final sorted = grouped.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    return {for (final e in sorted) e.key: e.value};
  }

  /// Recomendados da página do produto (mesma categoria; fallback geral).
  Future<List<Produto>> fetchRecomendados(
    int produtoId, {
    int? categoriaId,
    int limite = 10,
  }) async {
    final locais = await _catalogo.carregarProdutosLocais();
    if (locais.isNotEmpty) {
      final categoria = categoriaId != null && categoriaId > 0
          ? categoriaId
          : null;
      var filtrados = CatalogoLocal.filtrar(
        locais,
        categoriaId: categoria,
        excluirId: produtoId,
        limite: limite,
      );
      if (filtrados.isEmpty) {
        filtrados = CatalogoLocal.filtrar(
          locais,
          excluirId: produtoId,
          limite: limite,
        );
      }
      return CatalogoLocal.paraProdutos(filtrados);
    }

    var query = _client
        .from('produtos_publicos')
        .select(publicColumns)
        .eq('ativo', true)
        .neq('id', produtoId) as dynamic;
    if (categoriaId != null && categoriaId > 0) {
      query = query.eq('categoria_id', categoriaId);
    }
    var response = await query.order('id').limit(limite);
    if (response is! List || response.isEmpty) {
      response = await _client
          .from('produtos_publicos')
          .select(publicColumns)
          .eq('ativo', true)
          .neq('id', produtoId)
          .order('id')
          .limit(limite);
    }
    if (response is! List) return [];
    return response
        .map((json) => Produto.fromJson(json as Map<String, dynamic>))
        .toList(growable: false);
  }
}
