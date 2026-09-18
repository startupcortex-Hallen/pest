import 'package:flutter/foundation.dart';
import '../models/cart_item.dart';
import '../services/auth_service.dart';
import '../services/cart_service.dart';

class CartProvider extends ChangeNotifier {
  final CartService _cartService;
  final AuthService _authService;

  CartProvider(this._cartService, this._authService);

  List<CartItem> _items = [];
  bool _loading = false;
  String? _error;

  List<CartItem> get items => _items;
  bool get loading => _loading;
  String? get error => _error;
  int get count => _items.length;

  /// Soma das quantidades (badge do carrinho, como nas grandes lojas).
  int get totalItens => _items.fold(0, (sum, item) => sum + item.quantidade);
  double get total =>
      _items.fold(0.0, (sum, item) => sum + item.total);

  /// Soma dos preços cheios (sem promoção) — para exibir a economia.
  double get subtotal =>
      _items.fold(0.0, (sum, item) => sum + (item.produtoPreco ?? 0) * item.quantidade);

  /// Economia total gerada pelos preços promocionais dos itens.
  double get economia => _items.fold(0.0, (sum, item) => sum + item.economia);

  List<CartItem> get itensEsgotados => _items.where((i) => i.esgotado).toList();

  String? get userId => _authService.currentUser?.id;

  Future<void> loadCart() async {
    final uid = userId;
    if (uid == null) return;

    // Refresh silencioso quando já há itens: atualiza preços/quantidades
    // sem o spinner de tela cheia (evita o "piscar" a cada add/remove).
    if (_items.isNotEmpty) {
      try {
        _items = await _cartService.fetchCart(uid);
        _error = null;
      } catch (e) {
        debugPrint('Erro cart: $e');
        _error = 'Não foi possível atualizar o carrinho.';
      }
      notifyListeners();
      return;
    }

    _loading = true;
    notifyListeners();

    try {
      _items = await _cartService.fetchCart(uid);
      _error = null;
    } catch (e) {
      debugPrint('Erro cart: $e');
      _error = 'Não foi possível carregar o carrinho. Tente novamente.';
      _items = [];
    }

    _loading = false;
    notifyListeners();
  }

  Future<bool> adicionar(int produtoId, {int quantidade = 1, String? cor}) async {
    final uid = userId;
    if (uid == null) return false;

    try {
      await _cartService.adicionar(uid, produtoId, quantidade: quantidade, cor: cor);
      await loadCart();
      // Só confirma sucesso se a releitura deu certo e o item está na lista
      // (antes retornava true mesmo com o fetch quebrado -> carrinho "vazio").
      if (_error != null) return false;
      return _items.any((i) => i.produtoId == produtoId);
    } catch (e) {
      debugPrint('Erro ao adicionar ao carrinho: $e');
      _error = 'Não foi possível adicionar ao carrinho.';
      notifyListeners();
      return false;
    }
  }

  Future<void> atualizarQuantidade(int cartItemId, int quantidade) async {
    await _cartService.atualizarQuantidade(cartItemId, quantidade);
    await loadCart();
  }

  Future<void> remover(int cartItemId) async {
    await _cartService.remover(cartItemId);
    await loadCart();
  }

  Future<void> limpar() async {
    final uid = userId;
    if (uid == null) return;
    await _cartService.limpar(uid);
    await loadCart();
  }
}
