bool luhnValido(String numero) {
  final digitos = numero.replaceAll(RegExp(r'[^0-9]'), '');
  if (digitos.length < 13 || digitos.length > 19) return false;

  var soma = 0;
  var dobrar = false;
  for (var i = digitos.length - 1; i >= 0; i--) {
    var valor = int.parse(digitos[i]);
    if (dobrar) {
      valor *= 2;
      if (valor > 9) valor -= 9;
    }
    soma += valor;
    dobrar = !dobrar;
  }
  return soma % 10 == 0;
}

String bandeiraCartao(String numero) {
  final digitos = numero.replaceAll(RegExp(r'[^0-9]'), '');
  if (digitos.isEmpty) return 'Cartão';

  final prefixo4 = digitos.length >= 4 ? digitos.substring(0, 4) : digitos;
  final prefixo6 = digitos.length >= 6 ? digitos.substring(0, 6) : digitos;
  final prefixo2 = digitos.length >= 2 ? digitos.substring(0, 2) : digitos;

  if (RegExp(r'^4').hasMatch(digitos)) return 'Visa';
  if (RegExp(r'^(5[1-5]|2[2-7])').hasMatch(digitos)) return 'Mastercard';
  if (RegExp(r'^3[47]').hasMatch(digitos)) return 'Amex';
  if (const {'4011', '4312', '4389', '4514', '4573', '4576', '5067', '5090', '6277', '6362', '6363', '6500', '6516', '6550'}.contains(prefixo4)) {
    return 'Elo';
  }
  if (prefixo6 == '606282' || prefixo4 == '3841') return 'Hipercard';
  if (RegExp(r'^(36|38|30[0-5])').hasMatch(digitos)) return 'Diners';
  if (prefixo4 == '6011' || prefixo2 == '65') return 'Discover';

  return 'Cartão';
}
