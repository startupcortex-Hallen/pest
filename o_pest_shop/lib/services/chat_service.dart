import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

class ChatService {
  final SupabaseClient _client = SupabaseService.instance.client;

  /// Busca uma conversa existente entre o cliente e a unidade, ou cria uma nova
  Future<int> buscarOuCriarConversa(String usuarioId, int unidadeId) async {
    final existente = await _client
        .from('conversas')
        .select('id')
        .eq('usuario_id', usuarioId)
        .eq('unidade_id', unidadeId)
        .limit(1)
        .maybeSingle();

    if (existente != null) {
      return existente['id'] as int;
    }

    try {
      final nova = await _client
          .from('conversas')
          .insert({
            'usuario_id': usuarioId,
            'unidade_id': unidadeId,
          })
          .select('id')
          .single();
      return nova['id'] as int;
    } on PostgrestException catch (e) {
      // Corrida entre duas aberturas do chat: se o unique index da migration
      // já criou a conversa, reaproveita em vez de falhar.
      if (e.code == '23505') {
        final atual = await _client
            .from('conversas')
            .select('id')
            .eq('usuario_id', usuarioId)
            .eq('unidade_id', unidadeId)
            .limit(1)
            .maybeSingle();
        if (atual != null) return atual['id'] as int;
      }
      rethrow;
    }
  }

  /// Busca as mensagens em uma única consulta, com o perfil do remetente
  /// embutido (elimina o N+1 de uma consulta por mensagem).
  Future<List<Map<String, dynamic>>> fetchMensagens(int conversaId) async {
    final r = await _client
        .from('mensagens')
        .select(
          'id,conversa_id,remetente_id,texto,created_at,'
          'perfis!mensagens_remetente_id_fkey(nome,avatar_url,funcao)',
        )
        .eq('conversa_id', conversaId)
        .order('created_at')
        .limit(200);
    if (r is! List) return [];
    return r.cast<Map<String, dynamic>>();
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
        .from('unidades_publicas')
        .select('nome,foto_url')
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
        .select(
          'id,usuario_id,unidade_id,ultima_mensagem,updated_at,'
          'unidades(nome),perfis!conversas_usuario_id_fkey(nome,avatar_url)',
        );

    if (funcao != 'admin' && unidadeId != null) {
      query = query.eq('unidade_id', unidadeId);
    }

    final r = await query
        .not('usuario_id', 'eq', userId.toString())
        .order('updated_at', ascending: false)
        .limit(50);

    return (r as List).cast<Map<String, dynamic>>();
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
