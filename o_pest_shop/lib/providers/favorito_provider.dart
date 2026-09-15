import 'package:flutter/foundation.dart';
import '../services/auth_service.dart';
import '../services/favorito_service.dart';

class FavoritoProvider extends ChangeNotifier {
  final FavoritoService _favoritoService;
  final AuthService _authService;

  FavoritoProvider(this._favoritoService, this._authService);

  Set<int> _favoritosIds = {};
  bool _loading = false;

  Set<int> get favoritosIds => _favoritosIds;
  bool get loading => _loading;

  Future<void> loadFavoritos() async {
    final user = _authService.currentUser;
    if (user == null) return;

    _loading = true;
    notifyListeners();

    try {
      final ids = await _favoritoService.fetchFavoritosIds(user.id);
      _favoritosIds = ids.toSet();
    } catch (e) {
      debugPrint('Erro favorito: $e');
      _favoritosIds = {};
    }

    _loading = false;
    notifyListeners();
  }

  Future<void> toggle(int produtoId) async {
    final user = _authService.currentUser;
    if (user == null) return;

    await _favoritoService.toggle(user.id, produtoId);

    if (_favoritosIds.contains(produtoId)) {
      _favoritosIds.remove(produtoId);
    } else {
      _favoritosIds.add(produtoId);
    }
    notifyListeners();
  }

  bool isFavorito(int produtoId) => _favoritosIds.contains(produtoId);
}
