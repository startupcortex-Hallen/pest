import 'package:flutter_test/flutter_test.dart';
import 'package:o_pest_shop/models/produto.dart';
import 'package:o_pest_shop/services/app_config_service.dart';
import 'package:o_pest_shop/services/catalogo_service.dart';

void main() {
  group('AppConfig', () {
    test('lê flags aninhadas e mensagem de manutenção', () {
      final config = AppConfig.fromMap({
        'checkout': {'ativo': false},
        'pagamentos': {'ativo': true, 'pix_only': true},
        'frete': {'ativo': false},
        'manutencao': {'ativo': true, 'mensagem': 'Volte em instantes'},
      });

      expect(config.checkoutAtivo, isFalse);
      expect(config.pagamentosAtivo, isTrue);
      expect(config.freteAtivo, isFalse);
      expect(config.pixOnly, isTrue);
      expect(config.manutencao, isTrue);
      expect(config.mensagemManutencao, 'Volte em instantes');
    });

    test('usa padrões seguros quando a tabela está vazia', () {
      final config = AppConfig.fromMap({});
      expect(config.checkoutAtivo, isTrue);
      expect(config.pagamentosAtivo, isTrue);
      expect(config.pixOnly, isFalse);
      expect(config.manutencao, isFalse);
    });

    test('round-trip de cache preserva as flags', () {
      const original = AppConfig(
        checkoutAtivo: false,
        pagamentosAtivo: true,
        freteAtivo: false,
        pixOnly: true,
        manutencao: true,
        mensagemManutencao: 'Manutenção',
      );
      final cache = AppConfig.fromCache(original.toMap());
      expect(cache.checkoutAtivo, isFalse);
      expect(cache.pagamentosAtivo, isTrue);
      expect(cache.pixOnly, isTrue);
      expect(cache.manutencao, isTrue);
      expect(cache.mensagemManutencao, 'Manutenção');
    });
  });

  group('CatalogoSnapshot', () {
    test('parseia listas e versão', () {
      final snapshot = CatalogoSnapshot.fromJson({
        'versao': '2026-11-05T12:00:00.000Z',
        'categorias': [
          {'id': 1, 'nome': 'Suplementos'},
        ],
        'produtos': [
          {'id': 10, 'nome': 'Whey'},
        ],
        'promocoes': [],
        'banners': [
          {'id': 1, 'imagem_url': 'https://exemplo/banner.webp'},
        ],
        'unidades': [],
      });

      expect(snapshot.categorias, hasLength(1));
      expect(snapshot.produtos, hasLength(1));
      expect(snapshot.banners, hasLength(1));
      expect(snapshot.geradoEm, isNotNull);

      final json = snapshot.toJson();
      expect(json['categorias'], hasLength(1));
      expect(json['produtos'], hasLength(1));
    });
  });

  group('Produto público', () {
    test('lê nomes achatados da view produtos_publicos', () {
      final produto = Produto.fromJson({
        'id': 7,
        'nome': 'Camisa',
        'preco': 99.9,
        'estoque': 3,
        'categoria_id': 2,
        'unidade_id': 4,
        'categoria_nome': 'Vestuário',
        'marca_nome': 'O Pest',
        'unidade_nome': 'Loja Centro',
        'url_imagem': ['https://exemplo/camisa.webp'],
      });

      expect(produto.categoriaNome, 'Vestuário');
      expect(produto.marcaNome, 'O Pest');
      expect(produto.unidadeNome, 'Loja Centro');
      expect(produto.unidadeId, 4);
      expect(produto.urlImagem.single, contains('camisa.webp'));
    });
  });
}
