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
  /// itens + PIX da unidade e o uso do cupom em UMA transação. Se algo
  /// falhar, nada é persistido — sem pedidos "fantasma" ou duplicados.
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

  /// Confirma o pagamento via RPC (idempotente): só o dono e apenas se o
  /// pedido ainda estiver pendente. O trigger do banco faz a baixa de
  /// estoque (atômica) e avança para "em preparo" automaticamente.
  Future<void> confirmarPagamento({
    required String userId,
    required int pedidoId,
    required String metodo,
  }) async {
    await _client.rpc('confirmar_pagamento', params: {
      'p_pedido_id': pedidoId,
      'p_metodo': metodo,
    });
  }

  /// Autorização de cartão — SIMULADA no servidor (sem gateway real).
  /// Valida permissões do pedido/cartão e a validade, grava a transação e
  /// aprova o pagamento (o trigger baixa estoque e avança para "em preparo").
  Future<Map<String, dynamic>> processarPagamentoCartao({
    required int pedidoId,
    required int cartaoId,
    required int parcelas,
  }) async {
    final result = await _client.rpc('processar_pagamento_cartao', params: {
      'p_pedido_id': pedidoId,
      'p_cartao_id': cartaoId,
      'p_parcelas': parcelas,
    });
    if (result is Map) return Map<String, dynamic>.from(result);
    return const {};
  }
}
