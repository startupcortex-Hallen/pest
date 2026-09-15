class Treino {
  final int id;
  final String userId;
  final String nome;
  final String diaSemana;
  final int ordem;

  Treino({
    required this.id,
    required this.userId,
    required this.nome,
    required this.diaSemana,
    this.ordem = 0,
  });

  factory Treino.fromJson(Map<String, dynamic> json) => Treino(
    id: json['id'] as int,
    userId: json['user_id'] as String? ?? '',
    nome: json['nome'] as String? ?? '',
    diaSemana: json['dia_semana'] as String? ?? '',
    ordem: json['ordem'] as int? ?? 0,
  );
}
