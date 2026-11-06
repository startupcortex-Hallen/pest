/// Endereço real do cliente para o 3DS do PagBank.
///
/// O 3DS não aceita endereço fictício: bancos e antifraude comparam os dados
/// do portador com o endereço informado. Usamos o endereço de entrega do
/// pedido e, para retirada, o endereço salvo do cliente.
class EnderecoPagbank {
  final String street;
  final String number;
  final String complement;
  final String locality;
  final String city;
  final String region;
  final String postalCode;

  const EnderecoPagbank({
    required this.street,
    required this.number,
    required this.complement,
    required this.locality,
    required this.city,
    required this.region,
    required this.postalCode,
  });

  bool get completo =>
      street.trim().isNotEmpty &&
      number.trim().isNotEmpty &&
      city.trim().isNotEmpty &&
      region.trim().length == 2 &&
      postalCode.trim().length == 8;

  Map<String, dynamic> toJson3ds() => {
        'street': street,
        'number': number,
        'complement': complement,
        'regionCode': region,
        'country': 'BRA',
        'city': city,
        'postalCode': postalCode,
      };

  static String _digitos(dynamic valor) =>
      (valor ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');

  /// Monta a partir do pedido (entrega) ou de um endereço salvo (retirada).
  static EnderecoPagbank? dePedido(
    Map<String, dynamic> pedido, {
    Map<String, dynamic>? enderecoSalvo,
  }) {
    final tipo = pedido['tipo_entrega'] as String? ?? 'retirada';
    final entrega = (pedido['endereco_entrega'] as String? ?? '').trim();
    final cep = (pedido['cep_entrega'] as String? ?? '').trim();

    if (tipo == 'entrega' && entrega.isNotEmpty) {
      final doTexto = deTexto(entrega, cep);
      if (doTexto != null) return doTexto;
    }

    if (enderecoSalvo != null) return deSalvo(enderecoSalvo);
    return null;
  }

  static EnderecoPagbank? deSalvo(Map<String, dynamic> e) {
    final rua = (e['rua'] as String? ?? '').trim();
    final cidade = (e['cidade'] as String? ?? '').trim();
    final uf = (e['uf'] as String? ?? '').trim().toUpperCase();
    final cep = _digitos(e['cep']);
    if (rua.isEmpty || cidade.isEmpty || uf.length != 2 || cep.length != 8) {
      return null;
    }
    return EnderecoPagbank(
      street: rua,
      number: (e['numero'] as String? ?? '').trim().isEmpty
          ? 'S/N'
          : (e['numero'] as String? ?? '').trim(),
      complement: (e['complemento'] as String? ?? '').trim(),
      locality: (e['bairro'] as String? ?? '').trim(),
      city: cidade,
      region: uf,
      postalCode: cep,
    );
  }

  /// Formato usado pelo checkout:
  /// "Rua, 123, Complemento, Bairro, Cidade - UF, CEP 00000000".
  static EnderecoPagbank? deTexto(String endereco, String? cepPedido) {
    final texto = endereco.trim();
    if (texto.isEmpty) return null;

    final cepTexto = _digitos(
      RegExp(r'CEP\s*([0-9.-]+)', caseSensitive: false)
              .firstMatch(texto)
              ?.group(1) ??
          cepPedido,
    );

    final semCep = texto.replaceAll(
      RegExp(r',?\s*CEP\s*[0-9.-]+\s*$', caseSensitive: false),
      '',
    );
    final partes = semCep
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (partes.isEmpty) return null;

    final rua = partes.first;
    var numero = 'S/N';
    if (partes.length > 1 && RegExp(r'\d').hasMatch(partes[1])) {
      numero = partes[1];
    }

    var idxCidade = -1;
    var cidade = '';
    var uf = '';
    for (var i = 0; i < partes.length; i++) {
      final m = RegExp(r'^(.+?)\s*-\s*([A-Za-z]{2})$').firstMatch(partes[i]);
      if (m != null) {
        idxCidade = i;
        cidade = m.group(1)!.trim();
        uf = m.group(2)!.trim().toUpperCase();
        break;
      }
    }

    if (idxCidade < 0) return null;

    final fimBairro = idxCidade;
    final bairro = fimBairro > 0 ? partes[fimBairro - 1] : '';
    final complemento = partes.length > 3 &&
            fimBairro > 2 &&
            partes[2] != bairro &&
            partes[2] != numero
        ? partes.sublist(2, fimBairro - 1).join(', ')
        : '';

    if (rua.isEmpty ||
        cidade.isEmpty ||
        uf.length != 2 ||
        cepTexto.length != 8) {
      return null;
    }

    return EnderecoPagbank(
      street: rua,
      number: numero,
      complement: complemento,
      locality: bairro == numero || bairro == rua ? '' : bairro,
      city: cidade,
      region: uf,
      postalCode: cepTexto,
    );
  }
}
