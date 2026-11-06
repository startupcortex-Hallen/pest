import 'package:flutter_test/flutter_test.dart';
import 'package:o_pest_shop/services/catalogo_local.dart';

void main() {
  final produtos = <Map<String, dynamic>>[
    {
      'id': 1,
      'nome': 'Whey Protein Concentrado',
      'descricao': 'Sabor chocolate',
      'preco': 129.9,
      'categoria_id': 10,
      'marca_id': 100,
      'unidade_id': 1000,
      'estoque': 8,
      'em_promocao': true,
      'ativo': true,
    },
    {
      'id': 2,
      'nome': 'Creatina Monohidratada',
      'descricao': 'Pote 300g',
      'preco': 89.9,
      'categoria_id': 10,
      'marca_id': 101,
      'unidade_id': 1000,
      'estoque': 0,
      'em_promocao': false,
      'ativo': true,
    },
    {
      'id': 3,
      'nome': 'Camisa Treino',
      'descricao': 'Tecido dry fit',
      'preco': 59.9,
      'categoria_id': 20,
      'marca_id': 100,
      'unidade_id': 1001,
      'estoque': 3,
      'em_promocao': false,
      'ativo': true,
    },
    {
      'id': 4,
      'nome': 'Produto Inativo',
      'descricao': 'Não deve aparecer',
      'preco': 10,
      'categoria_id': 10,
      'ativo': false,
    },
  ];

  group('CatalogoLocal', () {
    test('normaliza acentos e caixa', () {
      expect(CatalogoLocal.normalizar('Creatína AÇÃO'), 'creatina acao');
    });

    test('busca por nome e descrição sem diferenciar acento', () {
      final resultado = CatalogoLocal.filtrar(produtos, search: 'creatina');
      expect(resultado.map((p) => p['id']), [2]);

      final porDescricao = CatalogoLocal.filtrar(produtos, search: 'chocolate');
      expect(porDescricao.map((p) => p['id']), [1]);
    });

    test('filtra categoria, marca e unidade', () {
      final categoria = CatalogoLocal.filtrar(produtos, categoriaId: 10);
      expect(categoria.map((p) => p['id']), [1, 2]);

      final marca = CatalogoLocal.filtrar(produtos, marcaId: 100);
      expect(marca.map((p) => p['id']), [1, 3]);

      final unidade = CatalogoLocal.filtrar(produtos, unidadeId: 1001);
      expect(unidade.map((p) => p['id']), [3]);
    });

    test('respeita cursor, limite e exclusão', () {
      final aposPrimeiro = CatalogoLocal.filtrar(produtos, lastId: 1);
      expect(aposPrimeiro.map((p) => p['id']), [2, 3]);

      final limitado = CatalogoLocal.filtrar(produtos, limite: 1);
      expect(limitado.map((p) => p['id']), [1]);

      final semProduto = CatalogoLocal.filtrar(produtos, excluirId: 1);
      expect(semProduto.map((p) => p['id']), [2, 3]);
    });

    test('filtra promoções e ignora inativos', () {
      final promocoes = CatalogoLocal.filtrar(produtos, emPromocao: true);
      expect(promocoes.map((p) => p['id']), [1]);

      final todos = CatalogoLocal.filtrar(produtos);
      expect(todos.any((p) => p['id'] == 4), isFalse);
    });

    test('converte para Produto', () {
      final lista = CatalogoLocal.paraProdutos(
        CatalogoLocal.filtrar(produtos, categoriaId: 20),
      );
      expect(lista, hasLength(1));
      expect(lista.single.nome, 'Camisa Treino');
      expect(lista.single.precoAtual, 59.9);
    });
  });
}
