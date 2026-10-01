import 'package:flutter_test/flutter_test.dart';
import 'package:o_pest_shop/models/cart_item.dart';

CartItem _item({
  int qtd = 1,
  double preco = 100,
  double? promo,
  bool emPromocao = false,
  int estoque = 5,
  bool freteGratis = false,
}) =>
    CartItem(
      id: 1,
      userId: 'u',
      produtoId: 1,
      quantidade: qtd,
      produtoPreco: preco,
      produtoPrecoPromocional: promo,
      produtoEmPromocao: emPromocao,
      produtoEstoque: estoque,
      produtoFreteGratis: freteGratis,
    );

void main() {
  test('total usa preço promocional quando há promoção', () {
    final i = _item(qtd: 3, preco: 100, promo: 80, emPromocao: true);
    expect(i.precoAtual, 80);
    expect(i.total, 240);
    expect(i.economia, 60);
  });

  test('sem promoção usa preço cheio', () {
    final i = _item(qtd: 2);
    expect(i.precoAtual, 100);
    expect(i.total, 200);
    expect(i.economia, 0);
  });

  test('promoção maior que o preço é ignorada', () {
    final i = _item(preco: 50, promo: 60, emPromocao: true);
    expect(i.temPromocao, isFalse);
    expect(i.precoAtual, 50);
  });

  test('esgotado quando o estoque é zero', () {
    expect(_item(estoque: 0).esgotado, isTrue);
    expect(_item(estoque: 1).esgotado, isFalse);
  });

  test('fromJson lê produtos embutidos e a primeira imagem', () {
    final item = CartItem.fromJson({
      'id': 7,
      'user_id': 'u1',
      'produto_id': 3,
      'quantidade': 2,
      'cor': 'Preto',
      'produtos': {
        'nome': 'Camisa',
        'preco': 59.9,
        'preco_promocional': null,
        'em_promocao': false,
        'url_imagem': ['http://img/1.jpg', 'http://img/2.jpg'],
        'estoque': 4,
        'unidade_id': 2,
        'frete_gratis': true,
      },
    });
    expect(item.produtoNome, 'Camisa');
    expect(item.produtoImagem, 'http://img/1.jpg');
    expect(item.produtoUnidadeId, 2);
    expect(item.cor, 'Preto');
    expect(item.produtoFreteGratis, isTrue);
    expect(item.total, closeTo(119.8, 0.001));
  });
}
