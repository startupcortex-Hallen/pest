import 'package:flutter_test/flutter_test.dart';
import 'package:o_pest_shop/core/helpers/pedido_status.dart';
import 'package:o_pest_shop/models/frete.dart';
import 'package:o_pest_shop/services/frete_service.dart';

void main() {
  group('FreteService.haversineKm', () {
    test('um grau de longitude no equador equivale a ~111 km', () {
      final km = FreteService.haversineKm(0, 0, 0, 1);
      expect(km, closeTo(111.19, 0.5));
    });

    test('mesma coordenada retorna zero', () {
      expect(FreteService.haversineKm(-12.15, -44.99, -12.15, -44.99), 0);
    });
  });

  group('FreteService.calcularLocal', () {
    const unidade = UnidadeFreteConfig(
      id: 1,
      nome: 'Loja Centro',
      latitude: -12.15,
      longitude: -44.99,
      taxaEntrega: 9,
      freteGratisAcima: 100,
      freteModo: 'distancia',
      freteTaxaBase: 5,
      freteValorKm: 2,
      freteKmMinimo: 1,
      freteRaioMaxKm: 10,
      freteFatorRota: 1,
      freteTempoKmMin: 3,
      prazoEntregaMin: 60,
    );

    test('cobra taxa base + valor por km excedente', () {
      final service = FreteService();
      final resultado = service.calcularLocal(
        unidade: unidade,
        latitude: -12.14,
        longitude: -44.99,
        subtotal: 50,
      );

      expect(resultado.foraArea, isFalse);
      expect(resultado.distanciaKm, greaterThan(1));
      expect(resultado.valor, greaterThan(5));
      expect(resultado.previsaoEntregaMin, greaterThanOrEqualTo(60));
    });

    test('frete grátis acima do valor mínimo da loja', () {
      final service = FreteService();
      final resultado = service.calcularLocal(
        unidade: unidade,
        latitude: -12.14,
        longitude: -44.99,
        subtotal: 150,
      );

      expect(resultado.gratis, isTrue);
      expect(resultado.valor, 0);
    });

    test('marca fora da área quando passa do raio máximo', () {
      final service = FreteService();
      final resultado = service.calcularLocal(
        unidade: unidade,
        latitude: -12.30,
        longitude: -44.99,
        subtotal: 50,
      );

      expect(resultado.foraArea, isTrue);
    });

    test('modo faixas usa a faixa que contém a distância', () {
      const porFaixa = UnidadeFreteConfig(
        id: 3,
        nome: 'Loja Faixas',
        latitude: -12.15,
        longitude: -44.99,
        freteModo: 'faixas',
        freteFatorRota: 1,
        faixas: [
          FaixaFrete(kmInicio: 0, kmFim: 2, valor: 6),
          FaixaFrete(kmInicio: 2, kmFim: 5, valor: 9),
        ],
      );
      final service = FreteService();
      final resultado = service.calcularLocal(
        unidade: porFaixa,
        latitude: -12.14,
        longitude: -44.99,
        subtotal: 10,
      );

      expect(resultado.foraArea, isFalse);
      expect(resultado.valor, 6);
    });

    test(
      'Salvador x Barreiras usa a faixa de 500-1000 km (não a taxa fixa)',
      () {
        const loja = UnidadeFreteConfig(
          id: 4,
          nome: 'Loja Salvador',
          latitude: -12.8845497,
          longitude: -38.4316243,
          taxaEntrega: 9.90,
          freteModo: 'faixas',
          freteFatorRota: 1.20,
          fretePesoInclusoKg: 1,
          freteValorKgExtra: 2.50,
          faixas: [
            FaixaFrete(kmInicio: 0, kmFim: 30, valor: 9.90),
            FaixaFrete(kmInicio: 30, kmFim: 80, valor: 14.90),
            FaixaFrete(kmInicio: 80, kmFim: 200, valor: 19.90),
            FaixaFrete(kmInicio: 200, kmFim: 500, valor: 29.90),
            FaixaFrete(kmInicio: 500, kmFim: 1000, valor: 39.90),
            FaixaFrete(kmInicio: 1000, kmFim: 1600, valor: 49.90),
          ],
        );
        final service = FreteService();
        final resultado = service.calcularLocal(
          unidade: loja,
          latitude: -12.144,
          longitude: -44.996,
          subtotal: 100,
          pesoKg: 0.35,
        );

        expect(resultado.foraArea, isFalse);
        expect(resultado.distanciaKm, closeTo(860.76, 2));
        expect(resultado.valor, 39.90);
      },
    );

    test('peso acima do incluso acrescenta valor por kg extra', () {
      const loja = UnidadeFreteConfig(
        id: 5,
        nome: 'Loja Salvador',
        latitude: -12.8845497,
        longitude: -38.4316243,
        freteModo: 'faixas',
        freteFatorRota: 1.20,
        fretePesoInclusoKg: 1,
        freteValorKgExtra: 2.50,
        faixas: [FaixaFrete(kmInicio: 500, kmFim: 1000, valor: 39.90)],
      );
      final service = FreteService();
      final resultado = service.calcularLocal(
        unidade: loja,
        latitude: -12.144,
        longitude: -44.996,
        subtotal: 100,
        pesoKg: 3.2,
      );

      expect(resultado.valor, 47.40);
    });

    test('distância fora das faixas não cai na taxa fixa', () {
      const loja = UnidadeFreteConfig(
        id: 6,
        nome: 'Loja Faixas',
        latitude: -12.15,
        longitude: -44.99,
        taxaEntrega: 8.99,
        freteModo: 'faixas',
        freteFatorRota: 1,
        faixas: [FaixaFrete(kmInicio: 0, kmFim: 5, valor: 9.90)],
      );
      final service = FreteService();
      final resultado = service.calcularLocal(
        unidade: loja,
        latitude: -12.30,
        longitude: -44.99,
        subtotal: 100,
      );

      expect(resultado.foraArea, isTrue);
      expect(resultado.valor, 0);
    });

    test('modo fixo usa a taxa de entrega da loja', () {
      const fixa = UnidadeFreteConfig(
        id: 2,
        nome: 'Loja Fixa',
        taxaEntrega: 7.5,
        freteModo: 'fixo',
      );
      final service = FreteService();
      final resultado = service.calcularLocal(
        unidade: fixa,
        latitude: -12.14,
        longitude: -44.99,
        subtotal: 10,
      );

      expect(resultado.valor, 7.5);
      expect(resultado.foraArea, isFalse);
    });
  });

  group('FreteResultado', () {
    test('formata distA�ncia e previsA�o', () {
      const resultado = FreteResultado(
        unidadeId: 1,
        distanciaKm: 2.36,
        valor: 8,
        previsaoEntregaMin: 75,
      );

      expect(resultado.distanciaTexto, '2,4 km');
      expect(resultado.previsaoTexto, '~1h15');
    });

    test('lê opções dos Correios e troca o serviço escolhido', () {
      final resultado = FreteResultado.fromJson(1, {
        'cotacao_id': '11111111-1111-4111-8111-111111111111',
        'provider': 'correios',
        'servico': 'PAC',
        'servico_codigo': '03298',
        'transportadora': 'Correios',
        'valor': 18.9,
        'prazo_dias': 7,
        'opcoes': [
          {
            'cotacao_id': '11111111-1111-4111-8111-111111111111',
            'provider': 'correios',
            'servico': 'PAC',
            'servico_codigo': '03298',
            'transportadora': 'Correios',
            'valor': 18.9,
            'prazo_dias': 7,
          },
          {
            'cotacao_id': '22222222-2222-4222-8222-222222222222',
            'provider': 'correios',
            'servico': 'SEDEX',
            'servico_codigo': '03220',
            'transportadora': 'Correios',
            'valor': 32.5,
            'prazo_dias': 3,
          },
        ],
      });

      expect(resultado.opcoes.length, 2);
      expect(resultado.modalidadeTexto, 'Correios · PAC');
      expect(resultado.previsaoTexto, '~7d');

      final sedex = resultado.copyWithOpcao(resultado.opcoes[1]);
      expect(sedex.valor, 32.5);
      expect(sedex.cotacaoId, '22222222-2222-4222-8222-222222222222');
      expect(sedex.modalidadeTexto, 'Correios · SEDEX');
      expect(sedex.previsaoTexto, '~3d');
    });
  });

  group('Timeline do pedido', () {
    test('usa o ciclo dos Correios para envio por transportadora', () {
      final etapas = etapasTimelinePara({
        'tipo_entrega': 'entrega',
        'frete_provider': 'correios',
      });
      expect(etapas, containsAll(['postado', 'em_transito']));
      expect(etapas, isNot(contains('saiu_para_entrega')));
    });

    test('mantém o ciclo local para retirada/entrega própria', () {
      final etapas = etapasTimelinePara({'tipo_entrega': 'retirada'});
      expect(etapas, contains('saiu_para_entrega'));
      expect(etapas, isNot(contains('postado')));
    });
  });
}
