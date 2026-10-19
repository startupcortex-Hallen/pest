/// Validação e mascaramento de CPF (mesma regra da Edge Function).
library;

String somenteDigitosCpf(String valor) => valor.replaceAll(RegExp(r'[^0-9]'), '');

/// Valida os dígitos verificadores do CPF.
bool cpfValido(String cpf) {
  final d = somenteDigitosCpf(cpf);
  if (d.length != 11) return false;
  if (RegExp(r'^(\d)\1{10}$').hasMatch(d)) return false;

  int digito(int ate) {
    var soma = 0;
    for (var i = 0; i < ate; i++) {
      soma += int.parse(d[i]) * (ate + 1 - i);
    }
    final resto = (soma * 10) % 11;
    return resto == 10 ? 0 : resto;
  }

  return digito(9) == int.parse(d[9]) && digito(10) == int.parse(d[10]);
}

/// Mascara o CPF para exibição: ***.456.789-**
String mascararCpf(String cpf) {
  final d = somenteDigitosCpf(cpf);
  if (d.length != 11) return '***.***.***-**';
  return '***.${d.substring(3, 6)}.${d.substring(6, 9)}-**';
}
