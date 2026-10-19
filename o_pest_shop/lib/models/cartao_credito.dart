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

  /// Token do cartão no gateway (PagBank) — usado para pagar sem
  /// redigitar os dados. Nulo em cartões antigos (apenas mascarados).
  final String? gatewayCardId;
  final String? holderCpf;

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
    this.gatewayCardId,
    this.holderCpf,
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
    int paraInt(dynamic v, int fallback) {
      if (v is int) return v;
      return int.tryParse('$v') ?? fallback;
    }

    return CartaoCredito(
      id: paraInt(json['id'], 0),
      userId: json['user_id'] as String? ?? '',
      apelido: json['apelido'] as String? ?? '',
      numeroMascarado: json['numero_mascarado'] as String? ?? '',
      bandeira: json['bandeira'] as String? ?? '',
      titular: json['titular'] as String? ?? '',
      mesValidade: paraInt(json['mes_validade'], 1),
      anoValidade: paraInt(json['ano_validade'], 2030),
      padrao: json['padrao'] as bool? ?? false,
      gatewayCardId: json['gateway_card_id'] as String?,
      holderCpf: json['holder_cpf'] as String?,
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
        if (gatewayCardId != null) 'gateway_card_id': gatewayCardId,
        if (holderCpf != null) 'holder_cpf': holderCpf,
      };
}
