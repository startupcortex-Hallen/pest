class Cupom {
  final int id;
  final String codigo;
  final String tipo;
  final double valor;
  final double valorMinimo;
  final DateTime dataValidade;
  final int usoMaximo;
  final int usosAtuais;
  final bool ativo;

  Cupom({
    required this.id,
    required this.codigo,
    required this.tipo,
    required this.valor,
    this.valorMinimo = 0,
    required this.dataValidade,
    this.usoMaximo = 1,
    this.usosAtuais = 0,
    this.ativo = true,
  });

  bool get valido =>
      ativo &&
      usosAtuais < usoMaximo &&
      dataValidade.isAfter(DateTime.now());

  String get descricao {
    if (tipo == 'percentual') return '$codigo - ${valor.toInt()}% OFF';
    return '$codigo - R\$ ${valor.toStringAsFixed(2)} OFF';
  }

  double aplicarDesconto(double total) {
    if (total < valorMinimo) return total;
    if (tipo == 'percentual') {
      // Clamp impede resultado negativo (ex.: cupom acima de 100%)
      return (total * (1 - valor / 100)).clamp(0, total);
    }
    return (total - valor).clamp(0, total);
  }

  factory Cupom.fromJson(Map<String, dynamic> json) {
    return Cupom(
      id: json['id'] as int,
      codigo: json['codigo'] as String? ?? '',
      tipo: json['tipo'] as String? ?? 'percentual',
      valor: (json['valor'] as num?)?.toDouble() ?? 0,
      valorMinimo: (json['valor_minimo'] as num?)?.toDouble() ?? 0,
      dataValidade: DateTime.tryParse(json['data_validade'] as String? ?? '') ??
          DateTime.now().add(const Duration(days: 30)),
      usoMaximo: json['uso_maximo'] as int? ?? 1,
      usosAtuais: json['usos_atuais'] as int? ?? 0,
      ativo: json['ativo'] as bool? ?? true,
    );
  }
}
