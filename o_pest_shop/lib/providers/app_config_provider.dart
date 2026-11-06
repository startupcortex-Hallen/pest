import 'package:flutter/foundation.dart';

import '../services/app_config_service.dart';

class AppConfigProvider extends ChangeNotifier {
  final AppConfigService _service;

  AppConfigProvider(this._service);

  AppConfig _config = const AppConfig();
  bool _carregado = false;

  AppConfig get config => _config;
  bool get carregado => _carregado;
  bool get checkoutAtivo => _config.checkoutAtivo;
  bool get pagamentosAtivo => _config.pagamentosAtivo;
  bool get freteAtivo => _config.freteAtivo;
  bool get pixOnly => _config.pixOnly;
  bool get manutencao => _config.manutencao;
  String? get mensagemManutencao => _config.mensagemManutencao;

  Future<void> load() async {
    _config = await _service.load();
    _carregado = true;
    notifyListeners();
  }
}
