import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/frete.dart';
import 'supabase_service.dart';

/// Geocodificação + cotação de frete por distância.
///
/// A cotação oficial é feita no Supabase pela RPC `calcular_frete` e o
/// checkout recalcula tudo no servidor. Quando a migration ainda não foi
/// aplicada, o app cai no cálculo local usando a configuração da loja para
/// não travar a navegação.
class FreteService {
  SupabaseClient get _client => SupabaseService.instance.client;

  static final Map<String, Coordenadas?> _cacheGeocode = {};

  Future<List<UnidadeFreteConfig>> buscarConfiguracoes(
    Iterable<int> unidadeIds,
  ) async {
    final ids = unidadeIds.toSet().toList();
    if (ids.isEmpty) return [];
    final resposta = await _client
        .from('unidades_publicas')
        .select(
          'id,nome,latitude,longitude,taxa_entrega,frete_gratis_acima,'
          'frete_modo,frete_taxa_base,frete_valor_km,frete_km_minimo,'
          'frete_raio_max_km,frete_fator_rota,frete_tempo_km_min,'
          'frete_peso_incluso_kg,frete_valor_kg_extra,prazo_entrega_min',
        )
        .inFilter('id', ids);
    if (resposta is! List) return [];
    var configs = resposta
        .cast<Map<String, dynamic>>()
        .map(UnidadeFreteConfig.fromJson)
        .toList();

    final idsFaixas = configs
        .where((c) => c.freteModo == 'faixas')
        .map((c) => c.id)
        .toList();
    if (idsFaixas.isNotEmpty) {
      try {
        final faixasResp = await _client
            .from('frete_faixas')
            .select()
            .inFilter('unidade_id', idsFaixas)
            .eq('ativo', true)
            .order('km_inicio');
        final porUnidade = <int, List<FaixaFrete>>{};
        for (final row in (faixasResp as List).cast<Map<String, dynamic>>()) {
          final unidadeId = (row['unidade_id'] as num).toInt();
          porUnidade
              .putIfAbsent(unidadeId, () => [])
              .add(FaixaFrete.fromJson(row));
        }
        configs = configs
            .map((c) => c.comFaixas(porUnidade[c.id] ?? const []))
            .toList();
      } catch (_) {
        // Tabela de faixas ainda não existe: mantém fallback fixo.
      }
    }
    return configs;
  }

  /// Geocodifica CEP/endereço. Usa BrasilAPI (que às vezes já devolve
  /// coordenadas do CEP) e cai para o Nominatim/OpenStreetMap.
  Future<Coordenadas?> geocodificar({
    String? cep,
    String? rua,
    String? numero,
    String? bairro,
    String? cidade,
    String? uf,
  }) async {
    final cepDigitos = (cep ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    final chave = [
      cepDigitos,
      rua ?? '',
      numero ?? '',
      bairro ?? '',
      cidade ?? '',
      uf ?? '',
    ].join('|').toLowerCase().trim();
    if (_cacheGeocode.containsKey(chave)) return _cacheGeocode[chave];

    if (cepDigitos.length == 8) {
      final porCep = await _geocodificarBrasilApi(cepDigitos);
      if (porCep != null) {
        _cacheGeocode[chave] = porCep;
        return porCep;
      }
    }

    final porEndereco = await _geocodificarNominatim(
      cep: cepDigitos,
      rua: rua,
      numero: numero,
      bairro: bairro,
      cidade: cidade,
      uf: uf,
    );
    _cacheGeocode[chave] = porEndereco;
    return porEndereco;
  }

  Future<Coordenadas?> _geocodificarBrasilApi(String cep) async {
    try {
      final res = await http
          .get(Uri.parse('https://brasilapi.com.br/api/cep/v2/$cep'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(utf8.decode(res.bodyBytes));
      if (json is! Map) return null;
      final location = json['location'];
      if (location is! Map) return null;
      final coordinates = location['coordinates'];
      if (coordinates is! Map) return null;
      final lat = double.tryParse('${coordinates['latitude'] ?? ''}');
      final lng = double.tryParse('${coordinates['longitude'] ?? ''}');
      if (lat == null || lng == null) return null;
      final coord = Coordenadas(
        latitude: lat,
        longitude: lng,
        fonte: 'brasilapi',
      );
      return coord.valida ? coord : null;
    } catch (_) {
      return null;
    }
  }

  Future<Coordenadas?> _geocodificarNominatim({
    required String cep,
    String? rua,
    String? numero,
    String? bairro,
    String? cidade,
    String? uf,
  }) async {
    try {
      final partes = <String>[
        if ((rua ?? '').trim().isNotEmpty)
          '${rua!.trim()}${(numero ?? '').trim().isNotEmpty ? ', ${numero!.trim()}' : ''}',
        if ((bairro ?? '').trim().isNotEmpty) bairro!.trim(),
        if ((cidade ?? '').trim().isNotEmpty) cidade!.trim(),
        if ((uf ?? '').trim().isNotEmpty) uf!.trim(),
        if (cep.isNotEmpty) cep,
        'Brasil',
      ];
      if (partes.length <= 2) return null;

      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'format': 'jsonv2',
        'limit': '1',
        'addressdetails': '0',
        'countrycodes': 'br',
        'accept-language': 'pt-BR',
        'q': partes.join(', '),
      });
      final res = await http
          .get(
            uri,
            headers: {
              'User-Agent': 'OPestShop/1.0 (contato@opest.com.br)',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(utf8.decode(res.bodyBytes));
      if (json is! List || json.isEmpty) return null;
      final primeiro = json.first;
      if (primeiro is! Map) return null;
      final lat = double.tryParse('${primeiro['lat'] ?? ''}');
      final lng = double.tryParse('${primeiro['lon'] ?? ''}');
      if (lat == null || lng == null) return null;
      final coord = Coordenadas(
        latitude: lat,
        longitude: lng,
        fonte: 'nominatim',
      );
      return coord.valida ? coord : null;
    } catch (_) {
      return null;
    }
  }

  /// Cotação oficial no servidor. Retorna `null` se a RPC ainda não existir.
  Future<FreteResultado?> calcularNoServidor({
    required int unidadeId,
    required double latitude,
    required double longitude,
    required double subtotal,
    bool todosFreteGratis = false,
    double pesoKg = 0,
  }) async {
    try {
      final resposta = await _client.rpc(
        'calcular_frete',
        params: {
          'p_unidade_id': unidadeId,
          'p_lat': latitude,
          'p_lng': longitude,
          'p_subtotal': subtotal,
          'p_todos_frete_gratis': todosFreteGratis,
          'p_peso_kg': pesoKg,
        },
      );
      if (resposta is Map) {
        return FreteResultado.fromJson(
          unidadeId,
          resposta.cast<String, dynamic>(),
        );
      }
      return null;
    } on PostgrestException catch (e) {
      // PGRST202 = função ainda não existe no banco (migration pendente).
      if (e.code == 'PGRST202' || e.code == '42883') return null;
      rethrow;
    } catch (_) {
      return null;
    }
  }

  /// Cotação real via Correios ou Melhor Envio (Edge Function).
  Future<FreteResultado?> cotarTransportadora({
    required int unidadeId,
    required String cepDestino,
  }) async {
    final FunctionResponse resposta;
    try {
      resposta = await _client.functions.invoke(
        'frete-cotacao',
        body: {'unidade_id': unidadeId, 'cep_destino': cepDestino},
      );
    } on FunctionException catch (e) {
      final detalhe = e.details;
      final mensagem = detalhe is Map ? detalhe['error'] : null;
      throw StateError(
        mensagem?.toString() ??
            'Não foi possível cotar o frete na transportadora.',
      );
    }
    final data = resposta.data;
    if (data is! Map) {
      throw StateError('Resposta inválida da cotação de frete.');
    }
    final map = Map<String, dynamic>.from(data);
    if (map['error'] != null) {
      throw StateError(map['error'].toString());
    }
    return FreteResultado.fromJson(unidadeId, map);
  }

  FreteResultado calcularLocal({
    required UnidadeFreteConfig unidade,
    required double latitude,
    required double longitude,
    required double subtotal,
    bool todosFreteGratis = false,
    double pesoKg = 0,
  }) {
    final origemLat = unidade.latitude;
    final origemLng = unidade.longitude;
    final distancia = (origemLat == null || origemLng == null)
        ? null
        : haversineKm(origemLat, origemLng, latitude, longitude) *
              unidade.freteFatorRota;

    final gratis =
        todosFreteGratis ||
        (unidade.freteGratisAcima != null &&
            subtotal >= unidade.freteGratisAcima!);

    if (!gratis &&
        distancia != null &&
        unidade.freteRaioMaxKm != null &&
        distancia > unidade.freteRaioMaxKm! &&
        unidade.freteModo != 'fixo') {
      return FreteResultado(
        unidadeId: unidade.id,
        distanciaKm: distancia,
        valor: 0,
        foraArea: true,
        mensagem: 'Endereço fora do raio de entrega da loja',
      );
    }

    final peso = math.max(pesoKg, 0.3);
    final pesoExtra = gratis
        ? 0.0
        : math.max(peso - unidade.fretePesoInclusoKg, 0).ceil() *
              unidade.freteValorKgExtra;

    double valor;
    if (gratis) {
      valor = 0;
    } else if (unidade.freteModo == 'distancia' && distancia != null) {
      valor =
          unidade.freteTaxaBase +
          math.max(distancia - unidade.freteKmMinimo, 0) *
              unidade.freteValorKm +
          pesoExtra;
    } else if (unidade.freteModo == 'faixas' && distancia != null) {
      double? valorFaixa;
      for (final faixa in unidade.faixas) {
        if (distancia >= faixa.kmInicio && distancia <= faixa.kmFim) {
          valorFaixa = faixa.valor;
          break;
        }
      }
      if (valorFaixa == null) {
        return FreteResultado(
          unidadeId: unidade.id,
          distanciaKm: distancia,
          valor: 0,
          foraArea: true,
          mensagem:
              'Distância fora das faixas de entrega cadastradas pela loja',
        );
      }
      valor = valorFaixa + pesoExtra;
    } else {
      valor = unidade.taxaEntrega;
    }

    final eta =
        unidade.prazoEntregaMin +
        (math.max(distancia ?? 0, 0) * unidade.freteTempoKmMin).ceil();

    return FreteResultado(
      unidadeId: unidade.id,
      distanciaKm: distancia,
      valor: double.parse(valor.clamp(0, double.infinity).toStringAsFixed(2)),
      previsaoEntregaMin: eta,
      gratis: gratis,
      calculadoNoServidor: false,
    );
  }

  static double haversineKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const raioTerra = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return raioTerra * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double graus) => graus * math.pi / 180.0;
}
