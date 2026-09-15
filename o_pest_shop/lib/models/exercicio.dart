class Exercicio {
  final int id;
  final int treinoId;
  final String nome;
  final String? aparelho;
  final String? grupoMuscular;
  final int series;
  final String repeticoes;
  final String? cargaSugerida;
  final String? observacao;
  final int ordem;
  final bool concluido;

  Exercicio({
    required this.id,
    required this.treinoId,
    required this.nome,
    this.aparelho,
    this.grupoMuscular,
    this.series = 4,
    this.repeticoes = '8-12',
    this.cargaSugerida,
    this.observacao,
    this.ordem = 0,
    this.concluido = false,
  });

  factory Exercicio.fromJson(Map<String, dynamic> json) => Exercicio(
    id: json['id'] as int,
    treinoId: json['treino_id'] as int,
    nome: json['nome'] as String? ?? '',
    aparelho: json['aparelho'] as String?,
    grupoMuscular: json['grupo_muscular'] as String?,
    series: json['series'] as int? ?? 4,
    repeticoes: json['repeticoes'] as String? ?? '8-12',
    cargaSugerida: json['carga_sugerida'] as String?,
    observacao: json['observacao'] as String?,
    ordem: json['ordem'] as int? ?? 0,
    concluido: json['concluido'] as bool? ?? false,
  );
}
