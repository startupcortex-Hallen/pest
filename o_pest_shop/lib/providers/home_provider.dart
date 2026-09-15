import 'package:flutter/foundation.dart';
import '../models/categoria.dart';
import '../models/produto.dart';
import '../services/produto_service.dart';

class HomeProvider extends ChangeNotifier {
  final ProdutoService _produtoService;

  HomeProvider(this._produtoService);

  List<Categoria> _categorias = [];
  List<Produto> _produtos = [];
  List<Produto> _promocoes = [];
  Map<String, List<Produto>> _produtosPorMarca = {};
  bool _loading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int? _lastProductId;
  String? _error;
  int _refreshCount = 0;

  List<Categoria> get categorias => _categorias;
  List<Produto> get produtos => _produtos;
  List<Produto> get promocoes => _promocoes;
  Map<String, List<Produto>> get produtosPorMarca => _produtosPorMarca;
  bool get loading => _loading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMore => _hasMore;
  String? get error => _error;
  int get refreshCount => _refreshCount;

  /// Carrega dados iniciais (primeira página).
  Future<void> loadHomeData() async {
    _loading = true;
    _error = null;
    _lastProductId = null;
    _hasMore = true;
    notifyListeners();

    try {
      _categorias = await _produtoService.fetchCategorias();
    } catch (e) {
      debugPrint('████████ ERRO CATEGORIAS: $e');
      _categorias = [];
    }

    try {
      final primeiraPagina = await _produtoService.fetchProdutos(lastId: null);
      _produtos = primeiraPagina;
      _ordenarPorEstoque();
      // Cursor usa o último id da ORDEM DO SERVIDOR (asc), não o da lista
      // reordenada por estoque — senão a paginação pula/repeti produtos.
      _lastProductId = primeiraPagina.isNotEmpty ? primeiraPagina.last.id : null;
      _hasMore = primeiraPagina.length == ProdutoService.pageSize;
    } catch (e) {
      debugPrint('████████ ERRO PRODUTOS: $e');
      _produtos = [];
      _hasMore = false;
    }

    try {
      _promocoes = await _produtoService.fetchProdutosEmPromocao();
    } catch (e) {
      debugPrint('████████ ERRO PROMOCOES: $e');
    }

    if (_categorias.isEmpty && _produtos.isEmpty && _promocoes.isEmpty) {
      _error = 'Erro ao carregar dados. Verifique sua conexão.';
    }

    _loading = false;
    notifyListeners();
  }

  /// Carrega próxima página de produtos (lazy loading).
  Future<void> loadMore() async {
    if (_isLoadingMore || !_hasMore || _lastProductId == null) return;

    _isLoadingMore = true;
    notifyListeners();

    try {
      final novos = await _produtoService.fetchProdutos(lastId: _lastProductId);
      if (novos.isEmpty) {
        _hasMore = false;
      } else {
        // Evita duplicação por ID
        final idsExistentes = _produtos.map((p) => p.id).toSet();
        final filtrados = novos.where((p) => !idsExistentes.contains(p.id)).toList();
        if (filtrados.isEmpty) {
          _hasMore = false;
        } else {
          _produtos = [..._produtos, ...filtrados];
          _ordenarPorEstoque();
          // Cursor: último id da resposta bruta do servidor (ordem asc)
          _lastProductId = novos.last.id;
          if (filtrados.length < ProdutoService.pageSize) _hasMore = false;
        }
      }
    } catch (e) {
      debugPrint('████████ ERRO LOAD MORE: $e');
    }

    _isLoadingMore = false;
    notifyListeners();
  }

  void _ordenarPorEstoque() {
    _produtos.sort((a, b) {
      int prio(Produto p) {
        if (p.estoque <= 0) return 2;
        if (p.estoque <= 3) return 1;
        return 0;
      }
      final cmp = prio(a).compareTo(prio(b));
      if (cmp != 0) return cmp;
      return a.id.compareTo(b.id);
    });
  }

  Future<void> loadProdutosPorMarca(int categoriaId) async {
    _loading = true;
    notifyListeners();

    try {
      _produtosPorMarca =
          await _produtoService.fetchProdutosPorMarca(categoriaId);
    } catch (e) {
      _produtosPorMarca = {};
    }

    _loading = false;
    notifyListeners();
  }

  Future<void> refresh() async {
    _produtosPorMarca = {};
    _refreshCount++;
    await loadHomeData();
  }
}
