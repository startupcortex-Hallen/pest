import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/categoria.dart';
import '../models/produto.dart';
import 'supabase_service.dart';

class AdminService {
  final SupabaseClient _client = SupabaseService.instance.client;

  // ─── PRODUTOS ──────────────────────────────────────

  Future<List<Produto>> fetchProdutos({String? search}) async {
    final response = await _client
        .from('produtos')
        .select('*, categorias(nome), marcas(nome), unidades(nome)')
        .order('id');
    if (response is! List) return [];
    final lista = response
        .map((json) => Produto.fromJson(json as Map<String, dynamic>))
        .toList();

    // Ordena: com estoque → estoque baixo → sem estoque
    lista.sort((a, b) {
      int prio(Produto p) {
        if (p.estoque <= 0) return 2;   // sem estoque
        if (p.estoque <= 3) return 1;   // estoque baixo
        return 0;                        // com estoque
      }
      final cmp = prio(a).compareTo(prio(b));
      if (cmp != 0) return cmp;
      return a.id.compareTo(b.id);
    });

    if (search != null && search.isNotEmpty) {
      return lista.where((p) => p.nome.toLowerCase().contains(search.toLowerCase())).toList();
    }
    return lista;
  }

  Future<void> insertProduto(Map<String, dynamic> data) async { await _client.from('produtos').insert(data); }
  Future<void> updateProduto(int id, Map<String, dynamic> data) async { await _client.from('produtos').update(data).eq('id', id); }
  Future<void> deleteProduto(int id) async {
    // Busca imagens antes de deletar para limpar storage
    try {
      final prod = await _client.from('produtos').select('url_imagem').eq('id', id).maybeSingle();
      if (prod != null) {
        final raw = prod['url_imagem'];
        List<String> urls = [];
        if (raw is List) {
          urls = raw.cast<String>();
        } else if (raw is String) {
          final clean = raw.replaceAll(RegExp(r'[{}"\[\]]'), '');
          urls = clean.split(',').where((s) => s.trim().isNotEmpty).map((s) => s.trim()).toList();
        }
        for (final url in urls) {
          if (url.contains('/Produtos/')) {
            final fileName = url.split('/Produtos/').last;
            try { await _client.storage.from('Produtos').remove([fileName]); } catch (_) {}
          }
        }
      }
    } catch (_) {}
    // Remove vínculos temporários (carrinho/favoritos) antes de excluir o produto
    try { await _client.from('carrinho').delete().eq('produto_id', id); } catch (_) {}
    try { await _client.from('favoritos').delete().eq('produto_id', id); } catch (_) {}
    await _client.from('produtos').delete().eq('id', id);
  }

  // ─── CATEGORIAS ────────────────────────────────────

  Future<List<Categoria>> fetchCategorias() async {
    final response = await _client.from('categorias').select().order('id');
    if (response is! List) return [];
    return response.map((json) => Categoria.fromJson(json as Map<String, dynamic>)).toList();
  }

  Future<void> insertCategoria(String nome, String? icone) async { await _client.from('categorias').insert({'nome': nome, 'icone': icone}); }
  Future<void> updateCategoria(int id, String nome, String? icone) async { await _client.from('categorias').update({'nome': nome, 'icone': icone}).eq('id', id); }
  Future<void> deleteCategoria(int id) async { await _client.from('categorias').delete().eq('id', id); }

  // ─── MARCAS ────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchMarcas() async {
    final response = await _client.from('marcas').select().order('id');
    if (response is! List) return [];
    return response.cast<Map<String, dynamic>>();
  }

  Future<void> insertMarca(String nome) async { await _client.from('marcas').insert({'nome': nome}); }
  Future<void> updateMarca(int id, String nome) async { await _client.from('marcas').update({'nome': nome}).eq('id', id); }
  Future<void> deleteMarca(int id) async { await _client.from('marcas').delete().eq('id', id); }

  // ─── FEED POSTS ────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchPosts() async {
    final response = await _client.from('posts_feed').select('*, perfis(nome, funcao), unidades(nome)').order('created_at', ascending: false);
    if (response is! List) return [];
    return response.cast<Map<String, dynamic>>();
  }

  Future<void> insertPost(Map<String, dynamic> data) async { await _client.from('posts_feed').insert(data); }
  Future<void> updatePost(String id, Map<String, dynamic> data) async { await _client.from('posts_feed').update(data).eq('id', id); }
  Future<void> deletePost(String id) async {
    // Remove vínculos (comentários, curtidas, candidaturas) antes de excluir o post
    try { await _client.from('post_comentarios').delete().eq('post_id', id); } catch (_) {}
    try { await _client.from('post_likes').delete().eq('post_id', id); } catch (_) {}
    try { await _client.from('candidaturas').delete().eq('vaga_id', id); } catch (_) {}
    await _client.from('posts_feed').delete().eq('id', id);
  }

  // ─── CANDIDATURAS ───────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchCandidaturas() async {
    final response = await _client.from('candidaturas').select('*, posts_feed(titulo)').order('created_at', ascending: false);
    if (response is! List) return [];
    final candidaturas = response.cast<Map<String, dynamic>>();
    for (final c in candidaturas) {
      final vaga = c['posts_feed'];
      if (vaga is Map) c['vaga_titulo'] = vaga['titulo'];
      c.remove('posts_feed');
    }
    return candidaturas;
  }

  Future<void> deleteCandidatura(String id) async { await _client.from('candidaturas').delete().eq('id', id); }

  // ─── NUTRIÇÃO ─────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchPlanoRefeicoes() async {
    final r = await _client.from('plano_refeicoes').select('*, perfis(nome)').order('id');
    return (r as List).cast<Map<String, dynamic>>();
  }

  Future<void> insertPlanoRefeicao(Map<String, dynamic> data) async {
    await _client.from('plano_refeicoes').insert(data);
  }

  Future<void> updatePlanoRefeicao(int id, Map<String, dynamic> data) async {
    await _client.from('plano_refeicoes').update(data).eq('id', id);
  }

  Future<void> deletePlanoRefeicao(int id) async {
    await _client.from('plano_refeicoes').delete().eq('id', id);
  }

  Future<List<Map<String, dynamic>>> fetchAssinaturas() async {
    final r = await _client.from('assinaturas').select('*, perfis(nome)').order('id', ascending: false);
    return (r as List).cast<Map<String, dynamic>>();
  }

  Future<void> insertAssinatura(Map<String, dynamic> data) async {
    await _client.from('assinaturas').insert(data);
  }

  Future<void> updateAssinatura(int id, Map<String, dynamic> data) async {
    await _client.from('assinaturas').update(data).eq('id', id);
  }

  Future<void> deleteAssinatura(int id) async {
    await _client.from('assinaturas').delete().eq('id', id);
  }

  Future<List<Map<String, dynamic>>> fetchNutricionistas() async {
    final r = await _client.from('nutricionistas').select().order('nome');
    return (r as List).cast<Map<String, dynamic>>();
  }

  Future<void> insertNutricionista(Map<String, dynamic> data) async {
    await _client.from('nutricionistas').insert(data);
  }

  Future<void> updateNutricionista(int id, Map<String, dynamic> data) async {
    await _client.from('nutricionistas').update(data).eq('id', id);
  }

  Future<void> deleteNutricionista(int id) async {
    await _client.from('nutricionistas').delete().eq('id', id);
  }

  Future<List<Map<String, dynamic>>> fetchConsultas() async {
    final r = await _client.from('consultas').select('*, perfis(nome), nutricionistas(nome)').order('data_hora', ascending: false);
    return (r as List).cast<Map<String, dynamic>>();
  }

  Future<void> updateConsultaStatus(int id, String status) async {
    await _client.from('consultas').update({'status': status}).eq('id', id);
  }

  // ─── TREINOS ─────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchTreinos() async {
    final r = await _client.from('treinos').select('*, exercicios(*), perfis(nome)').order('ordem');
    return (r as List).cast<Map<String, dynamic>>();
  }

  Future<void> insertTreino(Map<String, dynamic> data) async {
    await _client.from('treinos').insert(data);
  }

  Future<void> updateTreino(int id, Map<String, dynamic> data) async {
    await _client.from('treinos').update(data).eq('id', id);
  }

  Future<void> deleteTreino(int id) async {
    // Remove os exercícios do treino antes de excluir
    try { await _client.from('exercicios').delete().eq('treino_id', id); } catch (_) {}
    await _client.from('treinos').delete().eq('id', id);
  }

  Future<void> insertExercicio(Map<String, dynamic> data) async {
    await _client.from('exercicios').insert(data);
  }

  Future<void> updateExercicio(int id, Map<String, dynamic> data) async {
    await _client.from('exercicios').update(data).eq('id', id);
  }

  Future<void> deleteExercicio(int id) async {
    await _client.from('exercicios').delete().eq('id', id);
  }

  // ─── PEDIDOS ─────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchPedidos({String? status, String? busca}) async {
    var query = _client
        .from('pedidos')
        .select('*, pedido_itens(*, produtos!produto_id(nome, url_imagem)), perfis!pedidos_user_id_fkey(nome, email, telefone), unidades(nome)');
    if (status != null && status.isNotEmpty) {
      query = query.eq('status', status);
    }
    final r = await query.order('created_at', ascending: false).limit(100);
    if (r is! List) return [];
    var pedidos = r.cast<Map<String, dynamic>>();
    if (busca != null && busca.isNotEmpty) {
      final q = busca.toLowerCase();
      pedidos = pedidos.where((p) {
        final perfil = p['perfis'];
        final nome = perfil is Map ? (perfil['nome'] as String? ?? '') : '';
        final email = perfil is Map ? (perfil['email'] as String? ?? '') : '';
        return nome.toLowerCase().contains(q) || email.toLowerCase().contains(q);
      }).toList();
    }
    return pedidos;
  }

  Future<void> updatePedidoStatus(int id, String status) async {
    // Transição validada pela máquina de estados do banco (trigger)
    await _client.rpc('alterar_status_pedido', params: {
      'p_pedido_id': id,
      'p_status': status,
    });
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

  // ─── AULAS ──────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchAulasAdmin() async {
    final r = await _client
        .from('aulas')
        .select('*, unidades(nome)')
        .order('dia_semana')
        .order('horario');
    if (r is! List) return [];
    return r.cast<Map<String, dynamic>>();
  }

  Future<void> insertAula(Map<String, dynamic> data) async {
    await _client.from('aulas').insert(data);
  }

  Future<void> updateAula(int id, Map<String, dynamic> data) async {
    await _client.from('aulas').update(data).eq('id', id);
  }

  Future<void> deleteAula(int id) async {
    // Remove as inscrições da aula antes de excluir
    try { await _client.from('aulas_inscricao').delete().eq('aula_id', id); } catch (_) {}
    await _client.from('aulas').delete().eq('id', id);
  }

  // ─── DESAFIOS ───────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchDesafiosAdmin() async {
    final r = await _client
        .from('desafios')
        .select('*, unidades(nome), desafios_participantes(user_id, progresso, perfis(nome))')
        .order('id', ascending: false);
    if (r is! List) return [];
    return r.cast<Map<String, dynamic>>();
  }

  Future<void> insertDesafio(Map<String, dynamic> data) async {
    await _client.from('desafios').insert(data);
  }

  Future<void> updateDesafio(int id, Map<String, dynamic> data) async {
    await _client.from('desafios').update(data).eq('id', id);
  }

  Future<void> deleteDesafio(int id) async {
    // Remove os participantes do desafio antes de excluir
    try { await _client.from('desafios_participantes').delete().eq('desafio_id', id); } catch (_) {}
    await _client.from('desafios').delete().eq('id', id);
  }

  // ─── PROFISSIONAIS / FILIAÇÕES ─────────────────────

  static const List<String> cargosProfissionais = ['nutricionista', 'personal'];

  Future<List<Map<String, dynamic>>> fetchProfissionais() async {
    final r = await _client
        .from('perfis')
        .select('id, nome, email, funcao, unidade_id, avatar_url, unidades(nome)')
        .inFilter('funcao', cargosProfissionais)
        .order('nome');
    if (r is! List) return [];
    return r.cast<Map<String, dynamic>>();
  }

  /// Todas as filiações (para o admin ver tudo).
  Future<List<Map<String, dynamic>>> fetchTodasFiliacoes() async {
    final r = await _client
        .from('perfis_unidades')
        .select('*, unidades(nome, bairro, foto_url)')
        .order('principal', ascending: false);
    if (r is! List) return [];
    return r.cast<Map<String, dynamic>>();
  }

  /// Filiações de um profissional (próprio usuário via RLS).
  Future<List<Map<String, dynamic>>> fetchFiliacoesDoUsuario(String userId) async {
    final r = await _client
        .from('perfis_unidades')
        .select('*, unidades(nome, bairro, foto_url, endereco)')
        .eq('user_id', userId)
        .order('principal', ascending: false);
    if (r is! List) return [];
    return r.cast<Map<String, dynamic>>();
  }

  /// Substitui as filiações do profissional e mantém perfis.unidade_id em sincronia
  /// (personal: unidade única; nutricionista: unidade principal).
  Future<void> salvarFiliacoes(String userId, String funcao, List<int> unidadeIds, int? principalId) async {
    await _client.from('perfis_unidades').delete().eq('user_id', userId);
    if (unidadeIds.isNotEmpty) {
      await _client.from('perfis_unidades').insert(
        unidadeIds.map((uid) => {
          'user_id': userId,
          'unidade_id': uid,
          'principal': uid == principalId,
        }).toList(),
      );
    }
    final unidadeIdSync = principalId ?? (unidadeIds.isEmpty ? null : unidadeIds.first);
    await _client.from('perfis')
        .update({'funcao': funcao, 'unidade_id': unidadeIdSync})
        .eq('id', userId);
  }

  /// Remove o profissional: apaga filiações e volta a função para usuário comum.
  Future<void> removerProfissional(String userId) async {
    await _client.from('perfis_unidades').delete().eq('user_id', userId);
    await _client.from('perfis').update({'funcao': 'usuario', 'unidade_id': null}).eq('id', userId);
  }
}
