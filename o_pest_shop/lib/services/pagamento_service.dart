import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/pagamento.dart';
import 'supabase_service.dart';

/// Fala com a Edge Function `pagamentos` (integração real com o PagBank):
/// criação de cobrança por PIX/crédito/débito/boleto e consulta de status.
class PagamentoService {
  final SupabaseClient _client = SupabaseService.instance.client;

  Future<Map<String, dynamic>> _invoke(
    String acao, [
    Map<String, dynamic> extra = const {},
  ]) async {
    final FunctionResponse resposta;
    try {
      resposta = await _client.functions.invoke(
        'pagamentos',
        body: {'acao': acao, ...extra},
      );
    } on FunctionException catch (e) {
      final detalhe = e.details;
      if (detalhe is Map && detalhe['erro'] != null) {
        throw StateError(detalhe['erro'].toString());
      }
      throw StateError(
        'Não foi possível falar com o servidor de pagamentos. '
        'Verifique a conexão e tente novamente.',
      );
    }
    final data = resposta.data;
    if (data is Map && data['erro'] != null) {
      throw StateError(data['erro'].toString());
    }
    if (data is! Map) {
      throw StateError('Resposta inválida do servidor de pagamentos.');
    }
    return Map<String, dynamic>.from(data);
  }

  /// Chave pública do PagBank para criptografar o cartão no navegador.
  Future<String> chavePublica() async {
    final r = await _invoke('chave_publica');
    final chave = r['public_key'] as String?;
    if (chave == null || chave.isEmpty) {
      throw StateError('Chave de pagamento indisponível. Tente novamente.');
    }
    return chave;
  }

  /// Sessão 3DS (obrigatória para cartão de débito) + ambiente.
  Future<Map<String, String>> sessao3ds() async {
    final r = await _invoke('sessao_3ds');
    return {
      'session': r['session'] as String? ?? '',
      'env': r['env'] as String? ?? 'SANDBOX',
    };
  }

  /// Enquanto o PagBank não está ativo, o servidor pode liberar um modo de
  /// simulação (secret SIMULACAO_PAGAMENTO=true). A tela só mostra o botão
  /// de simulação quando essa flag está ligada.
  Future<bool> simulacaoDisponivel() async {
    try {
      final r = await _invoke('simulacao_disponivel');
      return r['disponivel'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Confirma um pagamento simulado no servidor (PIX/cartão/boleto), com a
  /// mesma trilha de pedido, estoque, histórico e comprovante do webhook.
  Future<Pagamento> simular({
    required List<int> pedidoIds,
    required String metodo,
    int parcelas = 1,
    Map<String, dynamic>? cartao,
  }) async {
    final r = await _invoke('simular', {
      'pedido_ids': pedidoIds,
      'metodo': metodo,
      'parcelas': parcelas,
      if (cartao != null) 'cartao': cartao,
    });
    final pagamento = r['pagamento'];
    if (pagamento is! Map) {
      throw StateError('Pagamento simulado sem retorno do servidor.');
    }
    return Pagamento.fromJson(Map<String, dynamic>.from(pagamento));
  }

  /// Cria a cobrança única do carrinho (valor recalculado no servidor).
  Future<Pagamento> criar({
    required List<int> pedidoIds,
    required String metodo,
    int parcelas = 1,
    Map<String, dynamic>? cartao,
    String? tresdsId,
  }) async {
    final r = await _invoke('criar', {
      'pedido_ids': pedidoIds,
      'metodo': metodo,
      'parcelas': parcelas,
      if (cartao != null) 'cartao': cartao,
      if (tresdsId != null) 'tresds_id': tresdsId,
    });
    final pagamento = r['pagamento'];
    if (pagamento is! Map) {
      throw StateError('Cobrança criada sem retorno do servidor.');
    }
    return Pagamento.fromJson(Map<String, dynamic>.from(pagamento));
  }

  /// Status atualizado da cobrança (fallback do webhook / polling).
  Future<Pagamento> consultar(int pagamentoId) async {
    final r = await _invoke('consultar', {'pagamento_id': pagamentoId});
    final pagamento = r['pagamento'];
    if (pagamento is! Map) {
      throw StateError('Cobrança não encontrada.');
    }
    return Pagamento.fromJson(Map<String, dynamic>.from(pagamento));
  }

  /// Cancela/estorna a cobrança no PagBank e encerra os pedidos vinculados.
  /// Pago → estorno; pendente → cancelamento. Exige ser o dono ou admin.
  /// Lê o status já persistido no banco (webhook), sem chamar o PagBank.
  Future<Pagamento?> statusLocal(int pagamentoId) async {
    final row = await _client
        .from('pagamentos')
        .select('*')
        .eq('id', pagamentoId)
        .maybeSingle();
    if (row == null) return null;
    return Pagamento.fromJson(Map<String, dynamic>.from(row));
  }

  Future<Pagamento> cancelar(int pagamentoId) async {
    final r = await _invoke('cancelar', {'pagamento_id': pagamentoId});
    final pagamento = r['pagamento'];
    if (pagamento is! Map) {
      throw StateError('Cobrança não encontrada.');
    }
    return Pagamento.fromJson(Map<String, dynamic>.from(pagamento));
  }
}
