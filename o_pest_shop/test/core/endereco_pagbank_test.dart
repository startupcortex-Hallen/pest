import 'package:flutter_test/flutter_test.dart';
import 'package:o_pest_shop/core/helpers/endereco_pagbank.dart';

void main() {
  group('EnderecoPagbank', () {
    test('converte o endereço do checkout para o formato do 3DS', () {
      final e = EnderecoPagbank.deTexto(
        'Rua das Flores, 123, Apto 4, Centro, São Paulo - SP, CEP 01001-000',
        '01001000',
      );

      expect(e, isNotNull);
      expect(e!.street, 'Rua das Flores');
      expect(e.number, '123');
      expect(e.complement, 'Apto 4');
      expect(e.locality, 'Centro');
      expect(e.city, 'São Paulo');
      expect(e.region, 'SP');
      expect(e.postalCode, '01001000');
      expect(e.completo, isTrue);
      expect(e.toJson3ds()['country'], 'BRA');
      expect(e.toJson3ds()['regionCode'], 'SP');
    });

    test('usa o endereço de entrega do pedido', () {
      final e = EnderecoPagbank.dePedido({
        'tipo_entrega': 'entrega',
        'endereco_entrega': 'Av. Brasil, 500, Loja 2, Jardim América, Campinas - SP, CEP 13010-000',
        'cep_entrega': '13010000',
      });

      expect(e, isNotNull);
      expect(e!.street, 'Av. Brasil');
      expect(e.number, '500');
      expect(e.locality, 'Jardim América');
      expect(e.city, 'Campinas');
      expect(e.region, 'SP');
    });

    test('retirada usa o endereço salvo do cliente', () {
      final e = EnderecoPagbank.dePedido(
        {'tipo_entrega': 'retirada'},
        enderecoSalvo: {
          'rua': 'Rua A',
          'numero': '10',
          'complemento': '',
          'bairro': 'Centro',
          'cidade': 'Santos',
          'uf': 'SP',
          'cep': '11010-000',
        },
      );

      expect(e, isNotNull);
      expect(e!.street, 'Rua A');
      expect(e.postalCode, '11010000');
      expect(e.completo, isTrue);
    });

    test('não inventa endereço quando não há dado válido', () {
      expect(EnderecoPagbank.dePedido({'tipo_entrega': 'retirada'}), isNull);
      expect(EnderecoPagbank.deTexto('Rua sem cidade', '01001000'), isNull);
      expect(
        EnderecoPagbank.deTexto('Rua A, 10, Centro, Cidade - SP', '123'),
        isNull,
      );
    });
  });
}
