class PlanoRefeicao {
  final int id;
  final String diaSemana;
  final String tipo;
  final String horario;
  final int calorias;
  final String descricao;
  final String icone;
  final bool concluido;

  PlanoRefeicao({
    required this.id,
    required this.diaSemana,
    required this.tipo,
    required this.horario,
    required this.calorias,
    required this.descricao,
    this.icone = 'restaurant_rounded',
    this.concluido = false,
  });

  factory PlanoRefeicao.fromJson(Map<String, dynamic> json) {
    return PlanoRefeicao(
      id: json['id'] as int,
      diaSemana: json['dia_semana'] as String? ?? 'seg',
      tipo: json['tipo'] as String? ?? '',
      horario: json['horario'] as String? ?? '',
      calorias: json['calorias'] as int? ?? 0,
      descricao: json['descricao'] as String? ?? '',
      icone: json['icone'] as String? ?? 'restaurant_rounded',
      concluido: json['concluido'] as bool? ?? false,
    );
  }
}
