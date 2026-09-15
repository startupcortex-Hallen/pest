import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/produto.dart';
import '../models/categoria.dart';
import 'supabase_service.dart';

class ProdutoService {
  final SupabaseClient _client = SupabaseService.instance.client;

  static const int pageSize = 50;

  Future<List<Categoria>> fetchCategorias() async {
    final response = await _client
        .from('categorias')
        .select()
        .order('nome', ascending: true);
    if (response is! List) return [];
    return response.map((json) => Categoria.fromJson(json as Map<String, dynamic>)).toList();
  }

  /// Busca produtos com filtro textual (ilike), paginação por cursor e joins.
  Future<List<Produto>> fetchProdutos({
    int? categoriaId,
    int? lastId,
    String? search,
    int? marcaId,
    int? unidadeId,
  }) async {
    var query = _client.from('produtos').select('*, categorias(nome), marcas(nome), unidades(nome)') as dynamic;
    if (categoriaId != null) query = query.eq('categoria_id', categoriaId);
    if (marcaId != null) query = query.eq('marca_id', marcaId);
    if (unidadeId != null) query = query.eq('unidade_id', unidadeId);
    if (search != null && search.isNotEmpty) {
      query = query.ilike('nome', '%$search%');
    }
    if (lastId != null) query = query.gt('id', lastId);
    // ascending: true é EXPLÍCITO — o default do postgrest é DESCENDENTE
    final response = await query.order('id', ascending: true).limit(pageSize);
    if (response is! List) return [];
    return response.map((json) => Produto.fromJson(json as Map<String, dynamic>)).toList();
  }

  Future<Produto?> fetchProdutoById(int id) async {
    final response = await _client
        .from('produtos')
        .select('*, categorias(nome), marcas(nome), galeria_produtos(url_imagem), unidades(nome)')
        .eq('id', id)
        .maybeSingle();
    if (response == null) return null;
    return Produto.fromJson(response as Map<String, dynamic>);
  }

  Future<List<Produto>> fetchProdutosEmPromocao() async {
    final response = await _client
        .from('produtos')
        .select('*, categorias(nome), marcas(nome), galeria_produtos(url_imagem), unidades(nome)')
        .eq('em_promocao', true)
        .order('id', ascending: true)
        .limit(20);
    if (response is! List) return [];
    return response.map((json) => Produto.fromJson(json as Map<String, dynamic>)).toList();
  }

  Future<Map<String, List<Produto>>> fetchProdutosPorMarca(int categoriaId) async {
    final response = await _client
        .from('produtos')
        .select('*, categorias(nome), marcas(nome), galeria_produtos(url_imagem), unidades(nome)')
        .eq('categoria_id', categoriaId)
        .order('id', ascending: true)
        .limit(50);
    if (response is! List) return {};
    final produtos = response.map((json) => Produto.fromJson(json as Map<String, dynamic>)).toList();
    final Map<String, List<Produto>> grouped = {};
    for (final p in produtos) {
      final marca = p.marcaNome ?? 'Sem marca';
      grouped.putIfAbsent(marca, () => []);
      grouped[marca]!.add(p);
    }
    final sorted = grouped.entries.toList()..sort((a, b) => b.value.length.compareTo(a.value.length));
    return {for (final e in sorted) e.key: e.value};
  }
}
