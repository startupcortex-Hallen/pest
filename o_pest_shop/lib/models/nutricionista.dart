class Nutricionista {
  final int id;
  final String nome;
  final String? email;
  final String? telefone;
  final String? crn;
  final String? bio;
  final String? avatarUrl;
  final double? precoConsulta;
  final bool disponivel;

  Nutricionista({
    required this.id,
    required this.nome,
    this.email,
    this.telefone,
    this.crn,
    this.bio,
    this.avatarUrl,
    this.precoConsulta,
    this.disponivel = true,
  });

  factory Nutricionista.fromJson(Map<String, dynamic> json) => Nutricionista(
    id: json['id'] as int,
    nome: json['nome'] as String? ?? '',
    email: json['email'] as String?,
    telefone: json['telefone'] as String?,
    crn: json['crn'] as String?,
    bio: json['bio'] as String?,
    avatarUrl: json['avatar_url'] as String?,
    precoConsulta: (json['preco_consulta'] as num?)?.toDouble(),
    disponivel: json['disponivel'] as bool? ?? true,
  );
}
