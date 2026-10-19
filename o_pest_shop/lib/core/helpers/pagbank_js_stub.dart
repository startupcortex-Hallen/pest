/// Versão para plataformas sem navegador (Android/iOS/desktop).
/// A criptografia de cartão do PagBank roda no SDK JavaScript — no app
/// nativo o pagamento com cartão fica disponível na versão web.
class PagBankJs {
  static bool get disponivel => false;

  static Future<void> carregarSdk() async {
    throw UnsupportedError('Pagamento com cartão disponível na versão web.');
  }

  static Future<String> criptografarCartao({
    required String publicKey,
    required String holder,
    required String number,
    required String expMonth,
    required String expYear,
    required String securityCode,
  }) async {
    throw UnsupportedError('Pagamento com cartão disponível na versão web.');
  }

  static Future<Map<String, String>> autenticar3ds({
    required String session,
    required String env,
    required Map<String, dynamic> request,
  }) async {
    throw UnsupportedError('Pagamento com cartão disponível na versão web.');
  }
}
