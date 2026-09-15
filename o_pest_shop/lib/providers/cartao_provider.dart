import 'package:flutter/foundation.dart';
import '../models/cartao_credito.dart';
import '../services/auth_service.dart';
import '../services/cartao_service.dart';

class CartaoProvider extends ChangeNotifier {
  final CartaoService _cartaoService;
  final AuthService _authService;

  CartaoProvider(this._cartaoService, this._authService);

  List<CartaoCredito> _cartoes = [];
  bool _loading = false;

  List<CartaoCredito> get cartoes => _cartoes;
  bool get loading => _loading;

  String? get userId => _authService.currentUser?.id;

  Future<void> loadCartoes() async {
    final uid = userId;
    if (uid == null) return;
    _loading = true;
    notifyListeners();
    try {
      _cartoes = await _cartaoService.fetchCartoes(uid);
    } catch (e) {
      debugPrint('Erro cartao: $e');
      _cartoes = [];
    }
    _loading = false;
    notifyListeners();
  }

  Future<String?> adicionarCartao(CartaoCredito cartao) async {
    try {
      await _cartaoService.adicionar(cartao);
      await loadCartoes();
      return null;
    } catch (e) {
      return 'Erro ao salvar cartão';
    }
  }

  Future<void> removerCartao(int cartaoId) async {
    await _cartaoService.remover(cartaoId);
    await loadCartoes();
  }
}
