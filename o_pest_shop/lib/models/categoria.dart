class Categoria {
  final int id;
  final String nome;
  final String? icone;

  Categoria({required this.id, required this.nome, this.icone});

  factory Categoria.fromJson(Map<String, dynamic> json) {
    return Categoria(
      id: json['id'] as int,
      nome: json['nome'] as String,
      icone: json['icone'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'nome': nome, 'icone': icone};
}
