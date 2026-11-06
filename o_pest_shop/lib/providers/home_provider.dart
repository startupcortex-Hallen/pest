import 'package:flutter/foundation.dart';
import '../models/categoria.dart';
import '../models/produto.dart';
import '../services/catalogo_service.dart';
import '../services/produto_service.dart';

class HomeProvider extends ChangeNotifier {
  final ProdutoService _produtoService;
  final CatalogoService _catalogoService;

  HomeProvider(this._produtoService, this._catalogoService);

  static const Duration _staleAfter = Duration(seconds: 60);

  List<Categoria> _categorias = [];
  List<Produto> _produtos = [];
  List<Produto> _promocoes = [];
  List<Map<String, dynamic>> _banners = [];
  Map<String, List<Produto>> _produtosPorMarca = {};
  bool _loading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int? _lastProductId;
  String? _error;
  int _refreshCount = 0;
  DateTime? _lastLoaded;

  List<Categoria> get categorias => _categorias;
  List<Produto> get produtos => _produtos;
  List<Produto> get promocoes => _promocoes;
  List<Map<String, dynamic>> get banners => _banners;
  Map<String, List<Produto>> get produtosPorMarca => _produtosPorMarca;
  bool get loading => _loading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMore => _hasMore;
  String? get error => _error;
  int get refreshCount => _refreshCount;

  /// Carrega a home com cache local e revalidação em segundo plano.
  Future<void> loadHomeData({bool force = false}) async {
    if (!force &&
        _lastLoaded != null &&
        DateTime.now().difference(_lastLoaded!) < _staleAfter) {
      return;
    }

    _error = null;
    final cache = await _catalogoService.lerCache();
    if (cache != null) {
      _aplicarSnapshot(cache.toJson());
      _loading = false;
      notifyListeners();
    } else {
      _loading = true;
      notifyListeners();
    }

    final remoto = await _catalogoService.buscarRemoto();
    if (remoto != null) {
      _aplicarSnapshot(remoto);
      _lastLoaded = DateTime.now();
      _loading = false;
      notifyListeners();
      return;
    }

    await _carregarFallback();
  }

  Future<void> loadIfStale() async {
    if (_lastLoaded == null ||
        DateTime.now().difference(_lastLoaded!) >= _staleAfter) {
      await loadHomeData();
    }
  }

  Future<T> _seguro<T>(Future<T> Function() fn, T fallback) async {
    try {
      return await fn();
    } catch (_) {
      return fallback;
    }
  }

  Future<void> _carregarFallback() async {
    try {
      // Cada consulta falha de forma independente: se promoções falharem,
      // o catálogo ainda aparece.
      final resultados = await Future.wait<dynamic>([
        _seguro(
          () => _produtoService.fetchCategorias(force: true),
          <Categoria>[],
        ),
        _seguro(
          () => _produtoService.fetchProdutos(lastId: null),
          <Produto>[],
        ),
        _seguro(
          () => _produtoService.fetchProdutosEmPromocao(),
          <Produto>[],
        ),
      ]);
      _categorias = (resultados[0] as List).cast<Categoria>();
      final primeiraPagina = (resultados[1] as List).cast<Produto>();
      _produtos = primeiraPagina;
      _ordenarPorEstoque();
      _lastProductId =
          primeiraPagina.isNotEmpty ? primeiraPagina.last.id : null;
      _hasMore = primeiraPagina.length == ProdutoService.pageSize;
      _promocoes = (resultados[2] as List).cast<Produto>();
      _banners = await _catalogoService.buscarBannersFallback();
    } catch (e) {
      debugPrint('Erro ao carregar home (fallback): $e');
      if (_categorias.isEmpty && _produtos.isEmpty && _promocoes.isEmpty) {
        _error = 'Erro ao carregar dados. Verifique sua conexão.';
      }
    }

    _lastLoaded = DateTime.now();
    _loading = false;
    notifyListeners();
  }

  void _aplicarSnapshot(Map<String, dynamic> json) {
    List<Map<String, dynamic>> mapas(String chave) {
      final raw = json[chave];
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList(growable: false);
    }

    try {
      _categorias = mapas('categorias')
          .map((e) => Categoria.fromJson(e))
          .toList(growable: false);

      final produtos = mapas('produtos')
          .map((e) => Produto.fromJson(e))
          .toList(growable: false);
      // O cursor usa o último id da ordem do servidor (asc), antes de
      // reordenar a lista para exibição por estoque.
      _lastProductId = produtos.isNotEmpty ? produtos.last.id : null;
      _hasMore = produtos.length == ProdutoService.pageSize;
      _produtos = [...produtos];
      _ordenarPorEstoque();

      _promocoes = mapas('promocoes')
          .map((e) => Produto.fromJson(e))
          .toList(growable: false);
      _banners = mapas('banners');
      _error = null;
    } catch (e) {
      debugPrint('Erro ao aplicar snapshot do catálogo: $e');
    }
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
        final idsExistentes = _produtos.map((p) => p.id).toSet();
        final filtrados =
            novos.where((p) => !idsExistentes.contains(p.id)).toList();
        if (filtrados.isEmpty) {
          _hasMore = false;
        } else {
          _produtos = [..._produtos, ...filtrados];
          _ordenarPorEstoque();
          _lastProductId = novos.last.id;
          if (filtrados.length < ProdutoService.pageSize) _hasMore = false;
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar mais produtos: $e');
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
    await loadHomeData(force: true);
  }
}
