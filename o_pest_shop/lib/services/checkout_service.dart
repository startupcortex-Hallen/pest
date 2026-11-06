import 'dart:math';

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
  final double taxaEntrega;
  final double? distanciaKm;
  final int? previsaoEntregaMin;

  PedidoCriado({
    required this.id,
    required this.unidadeId,
    required this.unidadeNome,
    this.pixCopiaCola,
    required this.total,
    required this.itensCount,
    this.taxaEntrega = 0,
    this.distanciaKm,
    this.previsaoEntregaMin,
  });
}

class CheckoutService {
  final SupabaseClient _client = SupabaseService.instance.client;

  /// Chave v4 usada para tornar o checkout idempotente em retries de rede.
  /// O app gera uma vez por tentativa e reutiliza enquanto a compra não conclui.
  static String novoIdempotencyKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

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
    double? enderecoLat,
    double? enderecoLng,
    List<Map<String, dynamic>> cotacoesExternas = const [],
    Map<String, dynamic>? endereco,
    String? destinatarioCpf,
    String? destinatarioTelefone,
    List<Map<String, dynamic>> fretePorUnidade = const [],
    int? enderecoUsuarioId,
    String? idempotencyKey,
  }) async {
    if (itens.isEmpty) return [];

    final payload = itens
        .map(
          (i) => {
            'produto_id': i.produtoId,
            'quantidade': i.quantidade,
            if (i.cor != null && i.cor!.isNotEmpty) 'cor': i.cor,
            'preco_atual': i.precoAtual,
            'total': i.total,
            'unidade_id': i.produtoUnidadeId ?? 1,
          },
        )
        .toList();

    try {
      dynamic r;
      final params = <String, dynamic>{
        'p_user_id': userId,
        'p_itens': payload,
        'p_cupom_desconto_total': cupomDescontoTotal,
        'p_cupom_id': cupomId,
        'p_tipo_entrega': tipoEntrega,
        if (tipoEntrega == 'entrega' && enderecoEntrega != null)
          'p_endereco_entrega': enderecoEntrega,
        if (tipoEntrega == 'entrega' && cepEntrega != null)
          'p_cep_entrega': cepEntrega,
        if (tipoEntrega == 'entrega' && enderecoLat != null)
          'p_endereco_lat': enderecoLat,
        if (tipoEntrega == 'entrega' && enderecoLng != null)
          'p_endereco_lng': enderecoLng,
      };
      final chave = idempotencyKey ?? novoIdempotencyKey();
      try {
        // v6: valida loja/produto ativos, endereço salvo, cotação (CEP, peso e
        // itens), estoque e idempotência com hash do payload no servidor.
        r = await _client.rpc(
          'finalizar_checkout_v6',
          params: {
            ...params,
            'p_cotacoes': cotacoesExternas,
            'p_idempotency_key': chave,
            'p_endereco': endereco,
            'p_destinatario_cpf': destinatarioCpf,
            'p_destinatario_telefone': destinatarioTelefone,
            'p_fretes': fretePorUnidade,
            'p_endereco_usuario_id': enderecoUsuarioId,
          },
        );
      } on PostgrestException catch (e) {
        if (e.code == 'PGRST202' || e.code == '42883') {
          throw StateError(
            'O checkout seguro (v6) ainda não foi aplicado no banco. '
            'Atualize as migrations antes de finalizar a compra.',
          );
        }
        rethrow;
      }
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
          taxaEntrega: (m['taxa_entrega'] as num?)?.toDouble() ?? 0,
          distanciaKm: (m['distancia_km'] as num?)?.toDouble(),
          previsaoEntregaMin: (m['previsao_entrega_min'] as num?)?.toInt(),
        );
      }).toList();
    } catch (e) {
      // Transação revertida no banco — o erro já traz o contexto.
      throw StateError('Não foi possível finalizar o pedido. $e');
    }
  }
}
