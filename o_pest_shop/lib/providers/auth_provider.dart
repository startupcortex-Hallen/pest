import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants/auth_notifier.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService;
  StreamSubscription<AuthState>? _authSubscription;

  AuthProvider(this._authService) {
    _authSubscription = _authService.authStateChanges.listen(_onAuthStateChange);
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  UserProfile? _user;
  bool _loading = false;
  String? _error;

  UserProfile? get user => _user;
  bool get loading => _loading;
  String? get error => _error;
  bool get isAuthenticated => _user != null;

  void _onAuthStateChange(AuthState state) {
    if (state.session != null && !_loading) {
      _loadProfile(state.session!.user.id);
    } else if (state.session == null) {
      _user = null;
      notifyListeners();
    }
  }

  Future<void> _loadProfile(String userId) async {
    try {
      final profile = await _authService.getProfile(userId);
      if (profile != null) {
        _user = profile;
        debugPrint('████ Perfil carregado do banco: ${profile.nome}');
      } else {
        _user = _createFallbackProfile();
        debugPrint('████ Perfil não encontrado no banco, criando fallback: ${_user!.nome}');
        try {
          await _authService.updateProfile(_user!);
          debugPrint('████ Fallback salvo no banco com sucesso');
          // Recarrega para pegar o registro completo
          final saved = await _authService.getProfile(userId);
          if (saved != null) _user = saved;
        } catch (e) {
          debugPrint('████ Erro ao salvar fallback: $e');
        }
      }
    } catch (e) {
      debugPrint('████ Erro _loadProfile: $e');
      _user = _createFallbackProfile();
    }
    if (_user != null) {
      AuthRefreshNotifier.instance.trigger();
    }
  }

  UserProfile _createFallbackProfile() {
    final user = _authService.currentUser;
    final nome = user?.userMetadata?['nome'] as String? ?? user?.email ?? 'Usuário';
    return UserProfile(
      id: user?.id ?? '',
      nome: nome,
      email: user?.email ?? '',
    );
  }

  Future<void> refreshProfile() async {
    if (_user == null) return;
    await _loadProfile(_user!.id);
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _authService.signIn(
        email: email,
        password: password,
      );
      if (response.user != null) {
        await _loadProfile(response.user!.id);
      }
    } on AuthException catch (e) {
      _error = _mapAuthError(e.message);
    } catch (e) {
      _error = 'Erro inesperado. Tente novamente.';
    }

    _loading = false;
    notifyListeners();
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String nome,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _authService.signUp(
        email: email,
        password: password,
        nome: nome,
      );
      if (response.user != null) {
        await _loadProfile(response.user!.id);
      }
    } on AuthException catch (e) {
      _error = _mapAuthError(e.message);
    } on FormatException catch (e) {
      _error = 'Erro de conexão. Verifique sua internet e tente novamente.';
      debugPrint('████ Erro formato signUp: $e');
    } catch (e) {
      _error = 'Não foi possível conectar ao servidor. Verifique sua internet e tente novamente.';
      debugPrint('████ Erro signUp: $e');
    }

    _loading = false;
    notifyListeners();
  }

  Future<void> signOut() async {
    await _authService.signOut();
    _user = null;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  String _mapAuthError(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('already registered') ||
        lower.contains('ja cadastrado')) {
      return 'Este email já está cadastrado.';
    }
    if (lower.contains('invalid login credentials') ||
        lower.contains('email or password') ||
        lower.contains('invalid credentials')) {
      return 'Email ou senha incorretos.';
    }
    if (lower.contains('password')) {
      return 'A senha deve ter no mínimo 6 caracteres.';
    }
    if (lower.contains('email')) {
      return 'Email inválido.';
    }
    if (lower.contains('rate limit')) {
      return 'Muitas tentativas. Aguarde alguns segundos.';
    }
    return message;
  }
}
