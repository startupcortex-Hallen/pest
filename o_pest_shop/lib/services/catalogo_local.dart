import '../models/produto.dart';

class CatalogoLocal {
  CatalogoLocal._();

  static const int limitePadrao = 50;

  static const String _comAcento =
      'áàâãäéèêëíìîïóòôõöúùûüçñÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ';
  static const String _semAcento =
      'aaaaaeeeeiiiiooooouuuucnAAAAAEEEEIIIIOOOOOUUUUCN';

  static String normalizar(String texto) {
    final buffer = StringBuffer();
    for (final rune in texto.runes) {
      final caractere = String.fromCharCode(rune);
      final indice = _comAcento.indexOf(caractere);
      buffer.write(indice >= 0 ? _semAcento[indice] : caractere);
    }
    return buffer.toString().toLowerCase();
  }

  static List<Map<String, dynamic>> filtrar(
    List<Map<String, dynamic>> produtos, {
    int? categoriaId,
    int? marcaId,
    int? unidadeId,
    int? lastId,
    int? excluirId,
    String? search,
    bool? emPromocao,
    int limite = limitePadrao,
  }) {
    if (limite <= 0) return const [];
    final termo = search == null || search.trim().isEmpty
        ? null
        : normalizar(search.trim());
    final saida = <Map<String, dynamic>>[];

    for (final item in produtos) {
      final id = item['id'];
      if (id is! int) continue;
      if (item['ativo'] == false) continue;
      if (lastId != null && id <= lastId) continue;
      if (excluirId != null && id == excluirId) continue;
      if (categoriaId != null && item['categoria_id'] != categoriaId) continue;
      if (marcaId != null && item['marca_id'] != marcaId) continue;
      if (unidadeId != null && item['unidade_id'] != unidadeId) continue;
      if (emPromocao != null &&
          (item['em_promocao'] == true) != emPromocao) {
        continue;
      }
      if (termo != null) {
        final nome = item['nome'] as String? ?? '';
        final descricao = item['descricao'] as String? ?? '';
        if (!normalizar('$nome $descricao').contains(termo)) continue;
      }

      saida.add(item);
      if (saida.length >= limite) break;
    }

    return saida;
  }

  static List<Produto> paraProdutos(List<Map<String, dynamic>> itens) {
    return itens.map(Produto.fromJson).toList(growable: false);
  }
}
