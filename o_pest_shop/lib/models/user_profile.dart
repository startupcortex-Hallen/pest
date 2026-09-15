class UserProfile {
  final String id;
  final String nome;
  final String email;
  final String perfil;
  final String? funcao;
  final String? telefone;
  final String? avatarUrl;
  final String? cpf;
  final int? unidadeId;
  final String? unidadeNome;
  final String? objetivo;
  final String? codigo;
  final int pontos;

  UserProfile({
    required this.id,
    required this.nome,
    required this.email,
    this.perfil = 'cliente',
    this.funcao,
    this.telefone,
    this.avatarUrl,
    this.cpf,
    this.unidadeId,
    this.unidadeNome,
    this.objetivo,
    this.codigo,
    this.pontos = 0,
  });

  bool get isAdmin => funcao == 'admin';
  bool get isAtendente => funcao == 'atendente';
  bool get canModerate => isAdmin || isAtendente;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    int? unidadeId;
    String? unidadeNome;
    final unidade = json['unidades'] as Map<String, dynamic>?;
    if (unidade != null) {
      unidadeId = unidade['id'] as int?;
      unidadeNome = unidade['nome'] as String?;
    }
    return UserProfile(
      id: json['id'] as String,
      nome: json['nome'] as String? ?? '',
      email: json['email'] as String? ?? '',
      perfil: json['perfil'] as String? ?? 'cliente',
      funcao: json['funcao'] as String?,
      telefone: json['telefone'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      cpf: json['cpf'] as String?,
      unidadeId: unidadeId ?? json['unidade_id'] as int?,
      unidadeNome: unidadeNome,
      objetivo: json['objetivo'] as String?,
      codigo: json['codigo'] as String?,
      pontos: json['pontos'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'nome': nome,
        'email': email,
        'perfil': perfil,
        'funcao': funcao,
        'telefone': telefone,
        'avatar_url': avatarUrl,
        'cpf': cpf,
        'unidade_id': unidadeId,
        'objetivo': objetivo,
        'codigo': codigo,
        'pontos': pontos,
      };
}
