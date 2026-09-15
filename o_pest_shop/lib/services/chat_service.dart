import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

class ChatService {
  final SupabaseClient _client = SupabaseService.instance.client;

  /// Busca uma conversa existente entre o cliente e a unidade, ou cria uma nova
  Future<int> buscarOuCriarConversa(String usuarioId, int unidadeId) async {
    // Procura conversa existente
    final existente = await _client
        .from('conversas')
        .select('id')
        .eq('usuario_id', usuarioId)
        .eq('unidade_id', unidadeId)
        .maybeSingle();

    if (existente != null) {
      return existente['id'] as int;
    }

    // Cria nova conversa
    final nova = await _client
        .from('conversas')
        .insert({
          'usuario_id': usuarioId,
          'unidade_id': unidadeId,
        })
        .select('id')
        .single();

    return nova['id'] as int;
  }

  /// Busca as mensagens de uma conversa (sem join - perfis buscados separadamente)
  Future<List<Map<String, dynamic>>> fetchMensagens(int conversaId) async {
    final r = await _client
        .from('mensagens')
        .select()
        .eq('conversa_id', conversaId)
        .order('created_at');
    final mensagens = (r as List).cast<Map<String, dynamic>>();
    // Busca perfil de cada remetente
    for (final m in mensagens) {
      await _preencherPerfil(m);
    }
    return mensagens;
  }

  /// Preenche o perfil do remetente na mensagem
  Future<void> _preencherPerfil(Map<String, dynamic> mensagem) async {
    try {
      final perfil = await _client
          .from('perfis')
          .select('nome, avatar_url, funcao')
          .eq('id', mensagem['remetente_id'])
          .maybeSingle();
      if (perfil != null) mensagem['perfis'] = perfil;
    } catch (_) {}
  }

  /// Envia uma mensagem
  Future<void> enviarMensagem(int conversaId, String userId, String texto) async {
    await _client.from('mensagens').insert({
      'conversa_id': conversaId,
      'remetente_id': userId,
      'texto': texto,
    });
    await _client.from('conversas').update({
      'ultima_mensagem': texto,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', conversaId);
  }

  /// Escuta mensagens em tempo real
  RealtimeChannel listenMensagens(int conversaId, void Function(Map<String, dynamic>) onMessage) {
    return _client
        .channel('mensagens_$conversaId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          table: 'mensagens',
          schema: 'public',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversa_id',
            value: conversaId.toString(),
          ),
          callback: (payload) {
            onMessage(payload.newRecord);
          },
        )
        .subscribe();
  }

  /// Busca o nome e foto da unidade
  Future<Map<String, dynamic>?> fetchUnidadeInfo(int unidadeId) async {
    final r = await _client
        .from('unidades')
        .select('nome, foto_url')
        .eq('id', unidadeId)
        .maybeSingle();
    return r as Map<String, dynamic>?;
  }

  /// Verifica se o usuário é atendente/admin da unidade
  Future<bool> usuarioEquipeDaUnidade(String userId, int unidadeId) async {
    try {
      final perfil = await _client
          .from('perfis')
          .select('funcao, unidade_id')
          .eq('id', userId)
          .maybeSingle();
      if (perfil == null) return false;
      final funcao = perfil['funcao'] as String?;
      final perfilUnidadeId = perfil['unidade_id'];
      if (funcao == 'admin') return true;
      if ((funcao == 'atendente' || funcao == 'admin') && perfilUnidadeId == unidadeId) return true;
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Busca conversas para a central de atendimento
  Future<List<Map<String, dynamic>>> fetchConversasAtendente(String userId) async {
    final perfil = await _client
        .from('perfis')
        .select('funcao, unidade_id')
        .eq('id', userId)
        .single();
    final funcao = perfil['funcao'] as String?;
    final unidadeId = perfil['unidade_id'] as int?;

    var query = _client
        .from('conversas')
        .select('*, unidades(nome)');

    if (funcao != 'admin' && unidadeId != null) {
      query = query.eq('unidade_id', unidadeId);
    }

    final r = await query
        .not('usuario_id', 'eq', userId.toString())
        .order('updated_at', ascending: false);

    final conversas = (r as List).cast<Map<String, dynamic>>();

    // Busca perfil de cada cliente
    for (final c in conversas) {
      try {
        final perfil = await _client
            .from('perfis')
            .select('nome, avatar_url')
            .eq('id', c['usuario_id'])
            .maybeSingle();
        if (perfil != null) c['perfis'] = perfil;
      } catch (_) {}
    }

    return conversas;
  }

  /// Escuta novas mensagens na central de atendimento
  RealtimeChannel listenNovasMensagens(void Function(Map<String, dynamic>) onMessage) {
    return _client
        .channel('novas_mensagens')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          table: 'mensagens',
          schema: 'public',
          callback: (payload) {
            onMessage(payload.newRecord);
          },
        )
        .subscribe();
  }

  /// Busca pedidos do usuário para esta unidade
  Future<List<Map<String, dynamic>>> fetchPedidos(String userId, int unidadeId) async {
    try {
      final r = await _client
          .from('pedidos')
          .select('*, pedido_itens(*, produtos!produto_id(nome, url_imagem))')
          .eq('user_id', userId)
          .eq('unidade_id', unidadeId)
          .order('created_at', ascending: false);
      return (r as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }
}
