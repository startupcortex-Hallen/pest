class Endereco {
  final int id;
  final String userId;
  final String apelido;
  final String cep;
  final String rua;
  final String numero;
  final String complemento;
  final String bairro;
  final String cidade;
  final String uf;
  final bool principal;
  final double? latitude;
  final double? longitude;
  final String? geocodeFonte;

  Endereco({
    required this.id,
    required this.userId,
    this.apelido = '',
    this.cep = '',
    this.rua = '',
    this.numero = '',
    this.complemento = '',
    this.bairro = '',
    this.cidade = '',
    this.uf = '',
    this.principal = false,
    this.latitude,
    this.longitude,
    this.geocodeFonte,
  });

  bool get temCoordenadas => latitude != null && longitude != null;

  /// Endereço completo no mesmo padrão usado no carrinho/mapa das unidades.
  String get resumo {
    final partes = <String>[
      if (rua.isNotEmpty) '$rua${numero.isNotEmpty ? ', $numero' : ''}',
      if (complemento.isNotEmpty) complemento,
      if (bairro.isNotEmpty) bairro,
      if (cidade.isNotEmpty || uf.isNotEmpty)
        '$cidade${uf.isNotEmpty ? ' - $uf' : ''}',
    ];
    final endereco = partes.join(', ');
    return cep.length == 8 ? '$endereco, CEP $cep' : endereco;
  }

  factory Endereco.fromJson(Map<String, dynamic> json) {
    return Endereco(
      id: json['id'] as int,
      userId: json['user_id'] as String? ?? '',
      apelido: json['apelido'] as String? ?? '',
      cep: json['cep'] as String? ?? '',
      rua: json['rua'] as String? ?? '',
      numero: json['numero'] as String? ?? '',
      complemento: json['complemento'] as String? ?? '',
      bairro: json['bairro'] as String? ?? '',
      cidade: json['cidade'] as String? ?? '',
      uf: json['uf'] as String? ?? '',
      principal: json['principal'] == true,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      geocodeFonte: json['geocode_fonte'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'apelido': apelido,
        'cep': cep,
        'rua': rua,
        'numero': numero,
        'complemento': complemento,
        'bairro': bairro,
        'cidade': cidade,
        'uf': uf,
        'principal': principal,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (geocodeFonte != null) 'geocode_fonte': geocodeFonte,
      };
}
