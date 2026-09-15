import 'package:flutter/foundation.dart';
import '../models/cupom.dart';
import '../services/cupom_service.dart';

class CupomProvider extends ChangeNotifier {
  final CupomService _cupomService;

  CupomProvider(this._cupomService);

  List<Cupom> _cuponsDisponiveis = [];
  Cupom? _cupomAplicado;
  bool _loading = false;

  List<Cupom> get cuponsDisponiveis => _cuponsDisponiveis;
  Cupom? get cupomAplicado => _cupomAplicado;
  bool get loading => _loading;
  bool get temCupomAplicado => _cupomAplicado != null;

  Future<void> loadCupons() async {
    _loading = true;
    notifyListeners();
    try {
      _cuponsDisponiveis = await _cupomService.fetchCupons();
    } catch (e) {
      debugPrint('Erro cupom: $e');
      _cuponsDisponiveis = [];
    }
    _loading = false;
    notifyListeners();
  }

  Future<String?> aplicarCupom(String codigo) async {
    try {
      final cupom = await _cupomService.validarCupom(codigo);
      if (cupom == null) return 'Cupom inválido ou expirado';
      _cupomAplicado = cupom;
      notifyListeners();
      return null;
    } catch (e) {
      return 'Erro ao validar cupom';
    }
  }

  void removerCupom() {
    _cupomAplicado = null;
    notifyListeners();
  }

  double calcularDesconto(double total) {
    if (_cupomAplicado == null) return total;
    return _cupomAplicado!.aplicarDesconto(total);
  }
}
