import 'package:flutter_test/flutter_test.dart';
import 'package:o_pest_shop/models/cupom.dart';

Cupom _cupom({
  String tipo = 'percentual',
  double valor = 10,
  double valorMinimo = 0,
  int usoMaximo = 10,
  int usosAtuais = 0,
  bool ativo = true,
  DateTime? validade,
}) =>
    Cupom(
      id: 1,
      codigo: 'TESTE',
      tipo: tipo,
      valor: valor,
      valorMinimo: valorMinimo,
      dataValidade: validade ?? DateTime.now().add(const Duration(days: 1)),
      usoMaximo: usoMaximo,
      usosAtuais: usosAtuais,
      ativo: ativo,
    );

void main() {
  group('Cupom.aplicarDesconto', () {
    test('percentual aplica o desconto proporcional', () {
      expect(_cupom(valor: 10).aplicarDesconto(100), closeTo(90, 0.001));
    });

    test('fixo subtrai o valor do desconto', () {
      expect(
        _cupom(tipo: 'fixo', valor: 15).aplicarDesconto(100),
        closeTo(85, 0.001),
      );
    });

    test('não desconta abaixo do valor mínimo do cupom', () {
      final c = _cupom(tipo: 'fixo', valor: 20, valorMinimo: 50);
      expect(c.aplicarDesconto(40), 40);
    });

    test('nunca deixa o total negativo (cupom fixo grande)', () {
      expect(_cupom(tipo: 'fixo', valor: 200).aplicarDesconto(100), 0);
    });

    test('nunca deixa o total negativo (percentual acima de 100%)', () {
      expect(_cupom(valor: 150).aplicarDesconto(100), 0);
    });
  });

  group('Cupom.valido', () {
    test('expirado é inválido', () {
      final c = _cupom(
        validade: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(c.valido, isFalse);
    });

    test('esgotado é inválido', () {
      expect(_cupom(usoMaximo: 5, usosAtuais: 5).valido, isFalse);
    });

    test('inativo é inválido', () {
      expect(_cupom(ativo: false).valido, isFalse);
    });

    test('ativo dentro da validade e com usos disponíveis é válido', () {
      expect(_cupom().valido, isTrue);
    });
  });
}
