class CartaoCredito {
  final int id;
  final String userId;
  final String apelido;
  final String numeroMascarado;
  final String bandeira;
  final String titular;
  final int mesValidade;
  final int anoValidade;
  final bool padrao;

  CartaoCredito({
    required this.id,
    required this.userId,
    required this.apelido,
    required this.numeroMascarado,
    required this.bandeira,
    required this.titular,
    required this.mesValidade,
    required this.anoValidade,
    this.padrao = false,
  });

  String get bandeiraIcon {
    switch (bandeira.toLowerCase()) {
      case 'visa':
        return 'Visa';
      case 'mastercard':
      case 'master':
        return 'Master';
      case 'elo':
        return 'Elo';
      case 'amex':
      case 'american express':
        return 'Amex';
      default:
        return bandeira;
    }
  }

  factory CartaoCredito.fromJson(Map<String, dynamic> json) {
    return CartaoCredito(
      id: json['id'] as int,
      userId: json['user_id'] as String,
      apelido: json['apelido'] as String? ?? '',
      numeroMascarado: json['numero_mascarado'] as String? ?? '',
      bandeira: json['bandeira'] as String? ?? '',
      titular: json['titular'] as String? ?? '',
      mesValidade: json['mes_validade'] as int? ?? 1,
      anoValidade: json['ano_validade'] as int? ?? 2030,
      padrao: json['padrao'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'apelido': apelido,
        'numero_mascarado': numeroMascarado,
        'bandeira': bandeira,
        'titular': titular,
        'mes_validade': mesValidade,
        'ano_validade': anoValidade,
        'padrao': padrao,
      };
}
