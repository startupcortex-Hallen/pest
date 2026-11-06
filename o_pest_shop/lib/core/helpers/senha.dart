/// Regra única de senha forte usada no cadastro, recuperação e troca.
String? validarSenhaForte(String? value) {
  if (value == null || value.isEmpty) return 'Informe sua senha';
  if (value.length < 8) {
    return 'A senha deve ter no mínimo 8 caracteres';
  }
  if (!RegExp(r'[A-Za-z]').hasMatch(value) ||
      !RegExp(r'[0-9]').hasMatch(value)) {
    return 'Use letras e números na senha';
  }
  return null;
}
