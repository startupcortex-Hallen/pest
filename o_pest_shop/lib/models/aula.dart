class Aula {
  final int id;
  final int unidadeId;
  final String nome;
  final String instrutor;
  final String diaSemana;
  final String horario;
  final int duracao;
  final int vagas;
  final int vagasOcupadas;
  final String? descricao;

  Aula({required this.id, required this.unidadeId, required this.nome, required this.instrutor,
    required this.diaSemana, required this.horario, this.duracao = 60, this.vagas = 20,
    this.vagasOcupadas = 0, this.descricao});

  factory Aula.fromJson(Map<String, dynamic> j) => Aula(
    id: j['id'] as int, unidadeId: j['unidade_id'] as int, nome: j['nome'] as String? ?? '',
    instrutor: j['instrutor'] as String? ?? '', diaSemana: j['dia_semana'] as String? ?? '',
    horario: j['horario'] as String? ?? '', duracao: j['duracao'] as int? ?? 60,
    vagas: j['vagas'] as int? ?? 20, vagasOcupadas: j['vagas_ocupadas'] as int? ?? 0,
    descricao: j['descricao'] as String?);
}

class PersonalSession {
  final int id; final int unidadeId; final String personalId; final String alunoId;
  final String dataHora; final int duracao; final String status; final double? valor;
  final String? observacao; final bool concluido;

  PersonalSession({required this.id, required this.unidadeId, required this.personalId,
    required this.alunoId, required this.dataHora, this.duracao = 50, this.status = 'agendada',
    this.valor, this.observacao, this.concluido = false});

  factory PersonalSession.fromJson(Map<String, dynamic> j) => PersonalSession(
    id: j['id'] as int, unidadeId: j['unidade_id'] as int,
    personalId: j['personal_id'] as String? ?? '', alunoId: j['aluno_id'] as String? ?? '',
    dataHora: j['data_hora'] as String? ?? '', duracao: j['duracao'] as int? ?? 50,
    status: j['status'] as String? ?? 'agendada', valor: (j['valor'] as num?)?.toDouble(),
    observacao: j['observacao'] as String?, concluido: j['concluido'] as bool? ?? false);
}

class Avaliacao {
  final int id; final String userId; final int unidadeId; final String dataAvaliacao;
  final double? peso; final double? altura; final double? percentualGordura;
  final double? massaMuscular; final double? imc;
  final double? bracoEsquerdo, bracoDireito, cintura, quadril, coxaEsquerda, coxaDireita;

  Avaliacao({required this.id, required this.userId, required this.unidadeId,
    required this.dataAvaliacao, this.peso, this.altura, this.percentualGordura,
    this.massaMuscular, this.imc, this.bracoEsquerdo, this.bracoDireito, this.cintura,
    this.quadril, this.coxaEsquerda, this.coxaDireita});

  factory Avaliacao.fromJson(Map<String, dynamic> j) => Avaliacao(
    id: j['id'] as int, userId: j['user_id'] as String? ?? '',
    unidadeId: j['unidade_id'] as int, dataAvaliacao: j['data_avaliacao'] as String? ?? '',
    peso: (j['peso'] as num?)?.toDouble(), altura: (j['altura'] as num?)?.toDouble(),
    percentualGordura: (j['percentual_gordura'] as num?)?.toDouble(),
    massaMuscular: (j['massa_muscular'] as num?)?.toDouble(),
    imc: (j['imc'] as num?)?.toDouble(),
    bracoEsquerdo: (j['braco_esquerdo'] as num?)?.toDouble(),
    bracoDireito: (j['braco_direito'] as num?)?.toDouble(),
    cintura: (j['cintura'] as num?)?.toDouble(),
    quadril: (j['quadril'] as num?)?.toDouble(),
    coxaEsquerda: (j['coxa_esquerda'] as num?)?.toDouble(),
    coxaDireita: (j['coxa_direita'] as num?)?.toDouble());
}
