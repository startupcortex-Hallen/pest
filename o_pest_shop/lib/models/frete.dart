class Coordenadas {
  final double latitude;
  final double longitude;
  final String fonte;

  const Coordenadas({
    required this.latitude,
    required this.longitude,
    this.fonte = 'manual',
  });

  bool get valida => latitude.abs() <= 90 && longitude.abs() <= 180;
}

class OpcaoFrete {
  final String? cotacaoId;
  final String provider;
  final String servico;
  final String? servicoCodigo;
  final String transportadora;
  final double valor;
  final int prazoDias;

  const OpcaoFrete({
    this.cotacaoId,
    this.provider = 'correios',
    required this.servico,
    this.servicoCodigo,
    this.transportadora = 'Correios',
    required this.valor,
    this.prazoDias = 0,
  });

  factory OpcaoFrete.fromJson(Map<String, dynamic> json) {
    return OpcaoFrete(
      cotacaoId: json['cotacao_id'] as String?,
      provider: json['provider'] as String? ?? 'correios',
      servico: json['servico'] as String? ?? 'Envio',
      servicoCodigo: json['servico_codigo'] as String?,
      transportadora: json['transportadora'] as String? ?? 'Correios',
      valor: (json['valor'] as num?)?.toDouble() ?? 0,
      prazoDias: (json['prazo_dias'] as num?)?.toInt() ?? 0,
    );
  }

  String get rotulo =>
      '$transportadora · $servico${prazoDias > 0 ? ' · ${prazoDias}d' : ''}';
}

class FreteResultado {
  final int unidadeId;
  final double? distanciaKm;
  final double valor;
  final int? previsaoEntregaMin;
  final bool gratis;
  final bool foraArea;
  final String? mensagem;
  final bool calculadoNoServidor;
  final String? cotacaoId;
  final String? provider;
  final String? servico;
  final String? servicoCodigo;
  final String? transportadora;
  final double? pesoKg;
  final List<OpcaoFrete> opcoes;

  const FreteResultado({
    required this.unidadeId,
    this.distanciaKm,
    required this.valor,
    this.previsaoEntregaMin,
    this.gratis = false,
    this.foraArea = false,
    this.mensagem,
    this.calculadoNoServidor = false,
    this.cotacaoId,
    this.provider,
    this.servico,
    this.servicoCodigo,
    this.transportadora,
    this.pesoKg,
    this.opcoes = const [],
  });

  factory FreteResultado.fromJson(
    int unidadeId,
    Map<String, dynamic> json, {
    bool servidor = true,
  }) {
    final prazoDias = (json['prazo_dias'] as num?)?.toInt();
    final opcoesJson = json['opcoes'];
    final opcoes = <OpcaoFrete>[];
    if (opcoesJson is List) {
      for (final item in opcoesJson) {
        if (item is Map) {
          opcoes.add(OpcaoFrete.fromJson(item.cast<String, dynamic>()));
        }
      }
    }
    final cotacaoId = json['cotacao_id'] as String?;
    if (opcoes.isEmpty && cotacaoId != null) {
      opcoes.add(
        OpcaoFrete(
          cotacaoId: cotacaoId,
          provider: json['provider'] as String? ?? 'correios',
          servico: json['servico'] as String? ?? 'Envio',
          servicoCodigo: json['servico_codigo'] as String?,
          transportadora: json['transportadora'] as String? ?? 'Correios',
          valor: (json['valor'] as num?)?.toDouble() ?? 0,
          prazoDias: prazoDias ?? 0,
        ),
      );
    }
    return FreteResultado(
      unidadeId: unidadeId,
      distanciaKm: (json['distancia_km'] as num?)?.toDouble(),
      valor: (json['valor'] as num?)?.toDouble() ?? 0,
      previsaoEntregaMin:
          (json['previsao_entrega_min'] as num?)?.toInt() ??
          (prazoDias != null ? prazoDias * 1440 : null),
      gratis: json['gratis'] == true,
      foraArea: json['fora_area'] == true,
      mensagem: json['mensagem'] as String?,
      calculadoNoServidor: servidor,
      cotacaoId: cotacaoId,
      provider: json['provider'] as String?,
      servico: json['servico'] as String?,
      servicoCodigo: json['servico_codigo'] as String?,
      transportadora: json['transportadora'] as String?,
      pesoKg: (json['peso_kg'] as num?)?.toDouble(),
      opcoes: opcoes,
    );
  }

  FreteResultado copyWithOpcao(OpcaoFrete opcao) {
    return FreteResultado(
      unidadeId: unidadeId,
      distanciaKm: distanciaKm,
      valor: opcao.valor,
      previsaoEntregaMin: opcao.prazoDias > 0 ? opcao.prazoDias * 1440 : null,
      gratis: opcao.valor <= 0,
      foraArea: foraArea,
      mensagem: mensagem,
      calculadoNoServidor: calculadoNoServidor,
      cotacaoId: opcao.cotacaoId,
      provider: opcao.provider,
      servico: opcao.servico,
      servicoCodigo: opcao.servicoCodigo,
      transportadora: opcao.transportadora,
      pesoKg: pesoKg,
      opcoes: opcoes,
    );
  }

  String get modalidadeTexto {
    if (transportadora != null && servico != null) {
      return '$transportadora · $servico';
    }
    return distanciaTexto;
  }

  String get distanciaTexto {
    if (distanciaKm == null) return 'distância não calculada';
    return '${distanciaKm!.toStringAsFixed(1).replaceAll('.', ',')} km';
  }

  String get previsaoTexto {
    final min = previsaoEntregaMin;
    if (min == null || min <= 0) return '';
    final dias = min ~/ 1440;
    if (dias >= 1) return '~${dias}d';
    if (min < 60) return '~$min min';
    final horas = min ~/ 60;
    final resto = min % 60;
    return resto == 0
        ? '~${horas}h'
        : '~${horas}h${resto.toString().padLeft(2, '0')}';
  }
}

class FaixaFrete {
  final double kmInicio;
  final double kmFim;
  final double valor;

  const FaixaFrete({
    required this.kmInicio,
    required this.kmFim,
    required this.valor,
  });

  factory FaixaFrete.fromJson(Map<String, dynamic> json) {
    return FaixaFrete(
      kmInicio: (json['km_inicio'] as num?)?.toDouble() ?? 0,
      kmFim: (json['km_fim'] as num?)?.toDouble() ?? 0,
      valor: (json['valor'] as num?)?.toDouble() ?? 0,
    );
  }
}

class UnidadeFreteConfig {
  final int id;
  final String nome;
  final double? latitude;
  final double? longitude;
  final double taxaEntrega;
  final double? freteGratisAcima;
  final String freteModo;
  final double freteTaxaBase;
  final double freteValorKm;
  final double freteKmMinimo;
  final double? freteRaioMaxKm;
  final double freteFatorRota;
  final double freteTempoKmMin;
  final double fretePesoInclusoKg;
  final double freteValorKgExtra;
  final int prazoEntregaMin;
  final List<FaixaFrete> faixas;

  const UnidadeFreteConfig({
    required this.id,
    required this.nome,
    this.latitude,
    this.longitude,
    this.taxaEntrega = 0,
    this.freteGratisAcima,
    this.freteModo = 'fixo',
    this.freteTaxaBase = 0,
    this.freteValorKm = 0,
    this.freteKmMinimo = 0,
    this.freteRaioMaxKm,
    this.freteFatorRota = 1.3,
    this.freteTempoKmMin = 3,
    this.fretePesoInclusoKg = 1,
    this.freteValorKgExtra = 2.5,
    this.prazoEntregaMin = 120,
    this.faixas = const [],
  });

  UnidadeFreteConfig comFaixas(List<FaixaFrete> novasFaixas) {
    return UnidadeFreteConfig(
      id: id,
      nome: nome,
      latitude: latitude,
      longitude: longitude,
      taxaEntrega: taxaEntrega,
      freteGratisAcima: freteGratisAcima,
      freteModo: freteModo,
      freteTaxaBase: freteTaxaBase,
      freteValorKm: freteValorKm,
      freteKmMinimo: freteKmMinimo,
      freteRaioMaxKm: freteRaioMaxKm,
      freteFatorRota: freteFatorRota,
      freteTempoKmMin: freteTempoKmMin,
      fretePesoInclusoKg: fretePesoInclusoKg,
      freteValorKgExtra: freteValorKgExtra,
      prazoEntregaMin: prazoEntregaMin,
      faixas: novasFaixas,
    );
  }

  factory UnidadeFreteConfig.fromJson(Map<String, dynamic> json) {
    final rawFaixas = json['faixas'];
    final faixas = <FaixaFrete>[];
    if (rawFaixas is List) {
      for (final item in rawFaixas) {
        if (item is Map) {
          faixas.add(FaixaFrete.fromJson(item.cast<String, dynamic>()));
        }
      }
    }
    return UnidadeFreteConfig(
      id: (json['id'] as num).toInt(),
      nome: json['nome'] as String? ?? 'Loja',
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      taxaEntrega: (json['taxa_entrega'] as num?)?.toDouble() ?? 0,
      freteGratisAcima: (json['frete_gratis_acima'] as num?)?.toDouble(),
      freteModo: json['frete_modo'] as String? ?? 'fixo',
      freteTaxaBase:
          (json['frete_taxa_base'] as num?)?.toDouble() ??
          (json['taxa_entrega'] as num?)?.toDouble() ??
          0,
      freteValorKm: (json['frete_valor_km'] as num?)?.toDouble() ?? 0,
      freteKmMinimo: (json['frete_km_minimo'] as num?)?.toDouble() ?? 0,
      freteRaioMaxKm: (json['frete_raio_max_km'] as num?)?.toDouble(),
      freteFatorRota: (json['frete_fator_rota'] as num?)?.toDouble() ?? 1.3,
      freteTempoKmMin: (json['frete_tempo_km_min'] as num?)?.toDouble() ?? 3,
      fretePesoInclusoKg:
          (json['frete_peso_incluso_kg'] as num?)?.toDouble() ?? 1,
      freteValorKgExtra:
          (json['frete_valor_kg_extra'] as num?)?.toDouble() ?? 2.5,
      prazoEntregaMin: (json['prazo_entrega_min'] as num?)?.toInt() ?? 120,
      faixas: faixas,
    );
  }
}
