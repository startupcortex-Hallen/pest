import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/cart_item.dart';
import 'supabase_service.dart';

/// Resultado de um pedido criado no checkout.
class PedidoCriado {
  final int id;
  final int unidadeId;
  final String unidadeNome;
  final String? pixCopiaCola;
  final double total;
  final int itensCount;

  PedidoCriado({
    required this.id,
    required this.unidadeId,
    required this.unidadeNome,
    this.pixCopiaCola,
    required this.total,
    required this.itensCount,
  });
}

class CheckoutService {
  final SupabaseClient _client = SupabaseService.instance.client;

  /// Cria os pedidos por unidade (marketplace) de forma ATÔMICA no banco
  /// (RPC `finalizar_checkout`): valida estoque server-side, grava pedido +
  /// itens + o uso do cupom em UMA transação. Se algo falhar, nada é
  /// persistido — sem pedidos "fantasma" ou duplicados.
  ///
  /// O pagamento real (PIX/crédito/débito/boleto) acontece em seguida pela
  /// Edge Function `pagamentos` (PagBank) — nunca mais pelo cliente.
  ///
  /// [cupomDescontoTotal] é o valor R$ do desconto do cupom sobre o subtotal
  /// geral — distribuído proporcionalmente entre os pedidos de cada unidade.
  Future<List<PedidoCriado>> finalizar({
    required String userId,
    required List<CartItem> itens,
    double cupomDescontoTotal = 0,
    int? cupomId,
    String tipoEntrega = 'retirada',
    String? enderecoEntrega,
    String? cepEntrega,
  }) async {
    if (itens.isEmpty) return [];

    final payload = itens.map((i) => {
          'produto_id': i.produtoId,
          'quantidade': i.quantidade,
          if (i.cor != null && i.cor!.isNotEmpty) 'cor': i.cor,
          'preco_atual': i.precoAtual,
          'total': i.total,
          'unidade_id': i.produtoUnidadeId ?? 1,
        }).toList();

    try {
      final r = await _client.rpc('finalizar_checkout', params: {
        'p_user_id': userId,
        'p_itens': payload,
        'p_cupom_desconto_total': cupomDescontoTotal,
        'p_cupom_id': cupomId,
        'p_tipo_entrega': tipoEntrega,
        if (tipoEntrega == 'entrega' && enderecoEntrega != null)
          'p_endereco_entrega': enderecoEntrega,
        if (tipoEntrega == 'entrega' && cepEntrega != null)
          'p_cep_entrega': cepEntrega,
      });
      final lista = (r as List?) ?? [];
      return lista.map((p) {
        final m = (p as Map).cast<String, dynamic>();
        return PedidoCriado(
          id: (m['id'] as num).toInt(),
          unidadeId: (m['unidade_id'] as num).toInt(),
          unidadeNome: m['unidade_nome'] as String? ?? 'Loja',
          pixCopiaCola: m['pix_copia_cola'] as String?,
          total: (m['total'] as num?)?.toDouble() ?? 0,
          itensCount: (m['itens_count'] as num?)?.toInt() ?? 0,
        );
      }).toList();
    } catch (e) {
      // Transação revertida no banco — o erro já traz o contexto.
      throw StateError('Não foi possível finalizar o pedido. $e');
    }
  }
}
