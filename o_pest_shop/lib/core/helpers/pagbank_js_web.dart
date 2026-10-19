import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// SDK JavaScript do PagBank (criptografia RSA do cartão no navegador e
/// autenticação 3DS). O PAN nunca sai em texto puro para o nosso servidor.
@JS('PagSeguro.setUp')
external void _setUp(JSAny options);

@JS('PagSeguro.encryptCard')
external JSObject _encryptCard(JSObject options);

@JS('PagSeguro.authenticate3DS')
external JSPromise<JSObject> _authenticate3DS(JSObject request);

class PagBankJs {
  static bool get disponivel => true;

  static bool _carregado = false;
  static Completer<void>? _carregando;

  static const _sdkUrl =
      'https://assets.pagseguro.com.br/checkout-sdk-js/rc/dist/browser/pagseguro.min.js';

  static Future<void> carregarSdk() {
    if (_carregado) return Future.value();
    if (_carregando != null) return _carregando!.future;
    final completer = Completer<void>();
    _carregando = completer;

    final existente = web.document.querySelector('script[data-pagbank-sdk]');
    if (existente != null) {
      _carregado = true;
      completer.complete();
      return completer.future;
    }

    final script = web.document.createElement('script') as web.HTMLScriptElement;
    script.src = _sdkUrl;
    script.setAttribute('data-pagbank-sdk', 'true');
    script.onload = ((web.Event _) {
      _carregado = true;
      if (!completer.isCompleted) completer.complete();
    }).toJS;
    script.onerror = ((web.Event _) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('Não foi possível carregar o SDK de pagamento. Verifique a conexão.'),
        );
      }
    }).toJS;
    web.document.head!.appendChild(script);
    return completer.future;
  }

  /// Criptografa os dados do cartão com a chave pública do PagBank.
  /// Retorna o campo `encrypted` usado na criação da cobrança.
  static Future<String> criptografarCartao({
    required String publicKey,
    required String holder,
    required String number,
    required String expMonth,
    required String expYear,
    required String securityCode,
  }) async {
    await carregarSdk();
    final payload = <String, dynamic>{
      'publicKey': publicKey,
      'holder': holder,
      'number': number,
      'expMonth': expMonth,
      'expYear': expYear,
      'securityCode': securityCode,
    }.jsify()! as JSObject;

    final resultado = _encryptCard(payload);
    final hasErrors =
        (resultado.getProperty<JSBoolean?>('hasErrors'.toJS) ?? false.toJS).toDart;
    if (hasErrors) {
      final erros = resultado.getProperty<JSAny?>('errors'.toJS)?.dartify();
      throw StateError(_mensagemErroCartao(erros));
    }
    final encrypted = resultado.getProperty<JSString?>('encryptedCard'.toJS)?.toDart;
    if (encrypted == null || encrypted.isEmpty) {
      throw StateError('Não foi possível criptografar o cartão. Confira os dados.');
    }
    return encrypted;
  }

  /// Executa a autenticação 3DS do PagBank (abre o desafio do banco quando
  /// necessário). Retorna `{status, authenticationStatus, id}`.
  static Future<Map<String, String>> autenticar3ds({
    required String session,
    required String env,
    required Map<String, dynamic> request,
  }) async {
    await carregarSdk();
    final setParams = <String, dynamic>{'session': session, 'env': env}.jsify()! as JSObject;
    _setUp(setParams);

    final payload = <String, dynamic>{'data': request}.jsify()! as JSObject;
    final resultado = await _authenticate3DS(payload).toDart;
    final mapa = Map<String, dynamic>.from(resultado.dartify() as Map);
    return {
      'status': mapa['status']?.toString() ?? '',
      'authenticationStatus': mapa['authenticationStatus']?.toString() ?? '',
      'id': mapa['id']?.toString() ?? '',
    };
  }

  static String _mensagemErroCartao(dynamic erros) {
    if (erros is List && erros.isNotEmpty) {
      final primeiro = erros.first;
      if (primeiro is Map) {
        final mensagem = primeiro['message'];
        if (mensagem != null) return 'Cartão inválido: $mensagem';
      }
    }
    return 'Dados do cartão inválidos. Confira número, validade e CVV.';
  }
}
