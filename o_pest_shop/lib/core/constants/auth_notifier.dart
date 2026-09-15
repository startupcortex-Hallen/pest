import 'package:flutter/foundation.dart';

class AuthRefreshNotifier extends ChangeNotifier {
  AuthRefreshNotifier._();
  static final AuthRefreshNotifier _instance = AuthRefreshNotifier._();
  static AuthRefreshNotifier get instance => _instance;

  void trigger() => notifyListeners();
}
