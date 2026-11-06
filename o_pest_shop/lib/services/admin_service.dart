import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/categoria.dart';
import '../models/produto.dart';
import 'supabase_service.dart';

class AdminService {
  final SupabaseClient _client = SupabaseService.instance.client;

  // ─── DASHBOARD ─────────────────────────────────────

  Future<Map<String, dynamic>> fetchDashboard({
    int? unidadeId,
    int dias = 30,
  }) async {
    final resultado = await _client.rpc(
      'dashboard_resumo',
      params: {'p_unidade_id': unidadeId, 'p_dias': dias},
    );
    if (resultado is Map) return resultado.cast<String, dynamic>();
    return {};
  }

  // ─── PRODUTOS ──────────────────────────────────────

  Future<List<Produto>> fetchProdutos({String? search}) async {
    // A leitura administrativa passa por RPC porque a tabela base não expõe
    // custo/ML para o role authenticated (proteção contra vazamento).
    final response = await _client.rpc(
      'admin_listar_produtos',
      params: {'p_unidade_id': null},
    );
    if (response is! List) return [];
    final lista = response
        .map((json) => Produto.fromJson(json as Map<String, dynamic>))
        .toList();

    // Ordena: com estoque → estoque baixo → sem estoque
    lista.sort((a, b) {
      int prio(Produto p) {
        if (p.estoque <= 0) return 2; // sem estoque
        if (p.estoque <= 3) return 1; // estoque baixo
        return 0; // com estoque
      }

      final cmp = prio(a).compareTo(prio(b));
      if (cmp != 0) return cmp;
      return a.id.compareTo(b.id);
    });

    if (search != null && search.isNotEmpty) {
      return lista
          .where((p) => p.nome.toLowerCase().contains(search.toLowerCase()))
          .toList();
    }
    return lista;
  }

  /// Unidades com os campos privados (PIX/repasse). Somente admin/equipe.
  Future<List<Map<String, dynamic>>> fetchUnidadesAdmin({int? unidadeId}) async {
    final response = await _client.rpc(
      'admin_listar_unidades',
      params: {'p_unidade_id': unidadeId},
    );
    if (response is! List) return [];
    return response
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList(growable: false);
  }

  Future<void> insertProduto(Map<String, dynamic> data) async {
    await _client.from('produtos').insert(data);
  }

  Future<void> updateProduto(int id, Map<String, dynamic> data) async {
    await _client.from('produtos').update(data).eq('id', id);
  }

  Future<void> deleteProduto(int id) async {
    // Guarda as URLs, mas só apaga do Storage DEPOIS que o banco confirmar a
    // exclusão. Se houver pedido vinculado, o delete falha e as fotos do
    // produto continuam intactas.
    final urls = <String>[];
    try {
      final prod = await _client
          .from('produtos')
          .select('url_imagem')
          .eq('id', id)
          .maybeSingle();
      if (prod != null) {
        final raw = prod['url_imagem'];
        if (raw is List) {
          urls.addAll(raw.whereType<String>());
        } else if (raw is String) {
          final clean = raw.replaceAll(RegExp(r'[{}"\[\]]'), '');
          urls.addAll(
            clean
                .split(',')
                .where((s) => s.trim().isNotEmpty)
                .map((s) => s.trim()),
          );
        }
      }
    } catch (_) {}

    // carrinho/favoritos/galeria têm ON DELETE CASCADE no banco.
    await _client.from('produtos').delete().eq('id', id);

    for (final url in urls) {
      if (!url.contains('/Produtos/')) continue;
      final fileName = url.split('/Produtos/').last;
      try {
        await _client.storage.from('Produtos').remove([fileName]);
      } catch (_) {}
    }
  }

  // ─── CATEGORIAS ────────────────────────────────────

  Future<List<Categoria>> fetchCategorias() async {
    final response = await _client.from('categorias').select().order('id');
    if (response is! List) return [];
    return response
        .map((json) => Categoria.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<void> insertCategoria(String nome, String? icone) async {
    await _client.from('categorias').insert({'nome': nome, 'icone': icone});
  }

  Future<void> updateCategoria(int id, String nome, String? icone) async {
    await _client
        .from('categorias')
        .update({'nome': nome, 'icone': icone})
        .eq('id', id);
  }

  Future<void> deleteCategoria(int id) async {
    await _client.from('categorias').delete().eq('id', id);
  }

  // ─── MARCAS ────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchMarcas() async {
    final response = await _client.from('marcas').select().order('id');
    if (response is! List) return [];
    return response.cast<Map<String, dynamic>>();
  }

  Future<void> insertMarca(String nome) async {
    await _client.from('marcas').insert({'nome': nome});
  }

  Future<void> updateMarca(int id, String nome) async {
    await _client.from('marcas').update({'nome': nome}).eq('id', id);
  }

  Future<void> deleteMarca(int id) async {
    await _client.from('marcas').delete().eq('id', id);
  }

  // ─── FEED POSTS ────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchPosts() async {
    final response = await _client
        .from('posts_feed')
        .select('*, perfis(nome, funcao), unidades(nome)')
        .order('created_at', ascending: false);
    if (response is! List) return [];
    return response
        .cast<Map<String, dynamic>>()
        .where((p) {
          final categoria = (p['categoria'] as String? ?? '').toLowerCase();
          return !categoria.startsWith('vaga') && categoria != 'emprego';
        })
        .toList();
  }

  Future<void> insertPost(Map<String, dynamic> data) async {
    await _client.from('posts_feed').insert(data);
  }

  Future<void> updatePost(String id, Map<String, dynamic> data) async {
    await _client.from('posts_feed').update(data).eq('id', id);
  }

  Future<void> deletePost(String id) async {
    // Remove vínculos (comentários e curtidas) antes de excluir o post.
    try {
      await _client.from('post_comentarios').delete().eq('post_id', id);
    } catch (_) {}
    try {
      await _client.from('post_likes').delete().eq('post_id', id);
    } catch (_) {}
    await _client.from('posts_feed').delete().eq('id', id);
  }

  // ─── PEDIDOS ─────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchPedidos({
    String? status,
    List<String>? statuses,
    String? busca,
    int? unidadeId,
    int limite = 50,
    int offset = 0,
  }) async {
    final filtroStatus = statuses ?? (status == null ? null : [status]);
    // Paginação, busca, status e escopo de loja são resolvidos no servidor.
    try {
      final r = await _client.rpc(
        'admin_listar_pedidos_v2',
        params: {
          'p_busca': busca,
          'p_statuses': filtroStatus,
          'p_unidade_id': unidadeId,
          'p_limit': limite,
          'p_offset': offset,
        },
      );
      if (r is List) return r.cast<Map<String, dynamic>>();
      return [];
    } on PostgrestException catch (e) {
      // Compatibilidade enquanto a migration nova não foi aplicada.
      if (e.code != 'PGRST202' && e.code != '42883') rethrow;
    }

    try {
      final r = await _client.rpc(
        'admin_listar_pedidos',
        params: {
          'p_busca': busca,
          'p_status': status,
          'p_unidade_id': unidadeId,
          'p_limit': limite,
          'p_offset': offset,
        },
      );
      if (r is List) return r.cast<Map<String, dynamic>>();
      return [];
    } on PostgrestException catch (e) {
      if (e.code != 'PGRST202' && e.code != '42883') rethrow;
    }

    var query = _client
        .from('pedidos')
        .select(
          '*, pedido_itens(*, produtos!produto_id(nome, url_imagem)), perfis!pedidos_user_id_fkey(nome, email, telefone), unidades(nome), pagamentos(*)',
        );
    if (filtroStatus != null && filtroStatus.isNotEmpty) {
      query = query.inFilter('status', filtroStatus);
    }
    if (unidadeId != null) {
      query = query.eq('unidade_id', unidadeId);
    }
    final r = await query
        .order('created_at', ascending: false)
        .range(offset, offset + limite - 1);
    if (r is! List) return [];
    var pedidos = r.cast<Map<String, dynamic>>();
    if (busca != null && busca.isNotEmpty) {
      final q = busca.toLowerCase();
      pedidos = pedidos.where((p) {
        final perfil = p['perfis'];
        final nome = perfil is Map ? (perfil['nome'] as String? ?? '') : '';
        final email = perfil is Map ? (perfil['email'] as String? ?? '') : '';
        return nome.toLowerCase().contains(q) ||
            email.toLowerCase().contains(q) ||
            (p['id']?.toString() ?? '') == q;
      }).toList();
    }
    return pedidos;
  }

  Future<Map<String, int>> fetchContadoresPedidos({int? unidadeId}) async {
    try {
      final r = await _client.rpc(
        'admin_contar_pedidos',
        params: {'p_unidade_id': unidadeId},
      );
      if (r is Map) {
        return r.map(
          (key, value) => MapEntry(key.toString(), (value as num?)?.toInt() ?? 0),
        );
      }
    } on PostgrestException catch (e) {
      if (e.code != 'PGRST202' && e.code != '42883') rethrow;
    }
    return {};
  }

  Future<void> cancelarPedidoComMotivo(int id, String motivo) async {
    await _client.rpc(
      'cancelar_pedido_com_motivo',
      params: {'p_pedido_id': id, 'p_motivo': motivo},
    );
  }

  Future<void> updatePedidoStatus(int id, String status) async {
    // Transição validada pela máquina de estados do banco (trigger)
    await _client.rpc(
      'alterar_status_pedido',
      params: {'p_pedido_id': id, 'p_status': status},
    );
  }

  Future<Map<String, dynamic>?> fetchPedidoDetalhe(int id) async {
    final r = await _client
        .from('pedidos')
        .select(
          '*, pedido_itens(*, produtos!produto_id(nome, url_imagem, peso_kg, comprimento_cm, largura_cm, altura_cm)), '
          'perfis!pedidos_user_id_fkey(nome, email, telefone, cpf), '
          'unidades(id,nome,endereco,bairro,cidade,uf,cep,numero,complemento,'
          'horario_seg,horario_ter,horario_qua,horario_qui,horario_sex,'
          'horario_sab,horario_dom,prazo_retirada_min,prazo_entrega_min,'
          'latitude,longitude,taxa_entrega,frete_gratis_acima,frete_modo,'
          'frete_taxa_base,frete_valor_km,frete_km_minimo,frete_raio_max_km,'
          'frete_fator_rota,frete_tempo_km_min,frete_peso_incluso_kg,'
          'frete_valor_kg_extra), '
          'pagamentos(*), envios(*, envio_eventos(*))',
        )
        .eq('id', id)
        .maybeSingle();
    return r == null ? null : (r as Map).cast<String, dynamic>();
  }

  Future<List<Map<String, dynamic>>> fetchPedidoHistorico(int id) async {
    final r = await _client
        .from('pedido_historico')
        .select('*, perfis(nome)')
        .eq('pedido_id', id)
        .order('criado_em', ascending: true);
    if (r is! List) return [];
    return r.cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> fetchPedidoAuditoria(int id) async {
    final r = await _client
        .from('pedido_auditoria')
        .select('*, perfis(nome)')
        .eq('pedido_id', id)
        .order('criado_em', ascending: false);
    if (r is! List) return [];
    return r.cast<Map<String, dynamic>>();
  }

  Future<int> confirmarPagamentoManual(int id, String motivo) async {
    final r = await _client.rpc(
      'confirmar_pagamento_manual',
      params: {'p_pedido_id': id, 'p_motivo': motivo},
    );
    return (r as num?)?.toInt() ?? 0;
  }

  Future<void> resolverRevisaoPagamento(
    int pagamentoId,
    String resolucao,
  ) async {
    await _client.rpc(
      'resolver_revisao_pagamento',
      params: {'p_pagamento_id': pagamentoId, 'p_resolucao': resolucao},
    );
  }

  Future<void> atualizarRastreio(
    int pedidoId,
    String? codigo,
    String? url,
  ) async {
    await _client.rpc(
      'atualizar_rastreio',
      params: {'p_pedido_id': pedidoId, 'p_codigo': codigo, 'p_url': url},
    );
  }

  // ── ETIQUETAS / CORREIOS ────────────────────────────────────────────────

  Future<Map<String, dynamic>> _invokeEtiqueta(
    String acao,
    int pedidoId, {
    Map<String, dynamic> extra = const {},
  }) async {
    try {
      final resposta = await _client.functions.invoke(
        'frete-etiqueta',
        body: {'acao': acao, 'pedido_id': pedidoId, ...extra},
      );
      final data = resposta.data;
      if (data is Map) return data.cast<String, dynamic>();
      return {};
    } on FunctionException catch (e) {
      final detalhe = e.details;
      final mensagem = detalhe is Map
          ? (detalhe['erro'] ?? detalhe['error'])
          : null;
      throw StateError(
        mensagem?.toString() ??
            'Não foi possível processar a etiqueta (${e.status}).',
      );
    }
  }

  Future<Map<String, dynamic>> gerarEtiqueta(
    int pedidoId, {
    String layout = 'PADRAO',
  }) {
    return _invokeEtiqueta('gerar', pedidoId, extra: {'layout': layout});
  }

  Future<Map<String, dynamic>> imprimirEtiqueta(int pedidoId) {
    return _invokeEtiqueta('imprimir', pedidoId);
  }

  Future<Map<String, dynamic>> cancelarEtiqueta(int pedidoId) {
    return _invokeEtiqueta('cancelar', pedidoId);
  }

  Future<Map<String, dynamic>> sincronizarEnvio(int pedidoId) {
    return _invokeEtiqueta('sincronizar', pedidoId);
  }

  Future<Map<String, dynamic>> simularEventoEnvio(int pedidoId, String status) {
    return _invokeEtiqueta(
      'simular_evento',
      pedidoId,
      extra: {'status': status},
    );
  }

  Future<void> atualizarNotaFiscalPedido(
    int pedidoId,
    String? chave,
    String? numero,
  ) async {
    await _client.rpc(
      'atualizar_nota_fiscal_pedido',
      params: {'p_pedido_id': pedidoId, 'p_chave': chave, 'p_numero': numero},
    );
  }

  // ─── USUÁRIOS (seletores admin) ─────────────────

  Future<List<Map<String, dynamic>>> fetchUsuarios() async {
    final r = await _client
        .from('perfis')
        .select('id, nome, email, funcao, unidade_id, unidades(nome)')
        .order('nome')
        .limit(200);
    if (r is! List) return [];
    return r.cast<Map<String, dynamic>>();
  }

  // ─── COMENTÁRIOS (moderação) ────────────────────

  Future<List<Map<String, dynamic>>> fetchComentariosPost(String postId) async {
    final r = await _client
        .from('post_comentarios')
        .select('*, perfis(nome, avatar_url)')
        .eq('post_id', postId)
        .order('created_at', ascending: false);
    if (r is! List) return [];
    return r.cast<Map<String, dynamic>>();
  }

  Future<void> deleteComentario(String id) async {
    await _client.from('post_comentarios').delete().eq('id', id);
  }
}
