import 'package:flutter/foundation.dart';

class AuthRefreshNotifier extends ChangeNotifier {
  AuthRefreshNotifier._();
  static final AuthRefreshNotifier _instance = AuthRefreshNotifier._();
  static AuthRefreshNotifier get instance => _instance;

  void trigger() => notifyListeners();
}

/// Marcador global: o app foi aberto por um link de recuperação de senha.
/// O roteador usa isso para levar o usuário à tela de "Nova senha".
class PasswordRecoveryFlag {
  PasswordRecoveryFlag._();
  static bool pending = false;
}
