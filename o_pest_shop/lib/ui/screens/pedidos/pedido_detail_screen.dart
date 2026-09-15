import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/helpers/abrir_mapa.dart';
import '../../../core/helpers/pedido_status.dart';
import '../../../core/helpers/theme_colors.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/cart_provider.dart';
import '../../../services/checkout_service.dart';
import 'pagamento_screen.dart';

/// Detalhe do pedido para o cliente — padrão Mercado Livre/Shopee:
/// timeline de status, itens com foto, resumo, loja e ações.
class PedidoDetailScreen extends StatefulWidget {
  final Map<String, dynamic> pedido;

  const PedidoDetailScreen({super.key, required this.pedido});

  @override
  State<PedidoDetailScreen> createState() => _PedidoDetailScreenState();
}

class _PedidoDetailScreenState extends State<PedidoDetailScreen> {
  late Map<String, dynamic> _pedido;
  bool _processando = false;
  // Timeline data-driven: status -> data/hora reais do pedido_historico
  Map<String, String> _historico = {};
  RealtimeChannel? _channel;
  RealtimeChannel? _histChannel;

  @override
  void initState() {
    super.initState();
    _pedido = widget.pedido;
    _carregarHistorico();
    _inscreverRealtime();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _histChannel?.unsubscribe();
    super.dispose();
  }

  /// Realtime: o cliente acompanha o pedido ao vivo (status e timeline).
  void _inscreverRealtime() {
    final id = _pedido['id'];
    _channel = Supabase.instance.client
        .channel('pedido_detail_$id')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'pedidos',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: '$id',
          ),
          callback: (_) => _recarregarPedido(),
        )
        .subscribe();
    _histChannel = Supabase.instance.client
        .channel('pedido_hist_$id')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'pedido_historico',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'pedido_id',
            value: '$id',
          ),
          callback: (_) => _carregarHistorico(),
        )
        .subscribe();
  }

  Future<void> _recarregarPedido() async {
    if (!mounted) return;
    final userId = context.read<AuthProvider>().user?.id;
    if (userId == null) return;
    try {
      final atualizado = await Supabase.instance.client
          .from('pedidos')
          .select('*, pedido_itens(*, produtos!produto_id(nome, url_imagem)), unidades(nome, cidade, endereco, bairro, horario_seg, horario_ter, horario_qua, horario_qui, horario_sex, horario_sab, horario_dom, prazo_retirada_min, prazo_entrega_min)')
          .eq('id', _pedido['id'])
          .eq('user_id', userId)
          .maybeSingle();
      if (atualizado != null && mounted) {
        _atualizarLocal((atualizado as Map).cast<String, dynamic>());
      }
    } catch (_) {}
  }

  Future<void> _carregarHistorico() async {
    try {
      final r = await Supabase.instance.client
          .from('pedido_historico')
          .select('status, criado_em')
          .eq('pedido_id', _pedido['id'])
          .order('criado_em', ascending: true);
      if (r is List && mounted) {
        final mapa = <String, String>{};
        for (final h in r) {
          final hMap = (h as Map).cast<String, dynamic>();
          mapa[hMap['status'] as String? ?? ''] = hMap['criado_em'] as String? ?? '';
        }
        setState(() => _historico = mapa);
      }
    } catch (_) {}
  }

  List<Map<String, dynamic>> get _itens =>
      ((_pedido['pedido_itens'] as List?) ?? []).cast<Map<String, dynamic>>();

  Map<String, dynamic>? get _unidade =>
      _pedido['unidades'] is Map ? (_pedido['unidades'] as Map).cast<String, dynamic>() : null;

  String? get _status => _pedido['status'] as String?;

  double get _subtotal => _itens.fold<double>(
      0, (s, i) => s + ((i['preco_unitario'] as num?)?.toDouble() ?? 0) * (i['quantidade'] as int? ?? 1));

  double get _total => (_pedido['total'] as num?)?.toDouble() ?? 0;

  String get _tipoEntrega => _pedido['tipo_entrega'] as String? ?? 'retirada';

  Future<void> _atualizarLocal(Map<String, dynamic> novo) async {
    setState(() => _pedido = novo);
  }

  Future<void> _pagarAgora() async {
    final p = _pedido;
    final unidade = _unidade;
    final criado = PedidoCriado(
      id: p['id'] as int,
      unidadeId: (p['unidade_id'] as num?)?.toInt() ?? 1,
      unidadeNome: unidade?['nome'] as String? ?? 'Loja',
      pixCopiaCola: p['pix_copia_cola'] as String?,
      total: _total,
      itensCount: _itens.length,
    );
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PagamentoScreen(pedidos: [criado], total: _total),
      ),
    );
    // Ao voltar da tela de pagamento, recarrega o pedido (status pode ter mudado)
    // — SEMPRE com o dono (evita IDOR).
    if (!mounted) return;
    final userId = context.read<AuthProvider>().user?.id;
    if (userId == null) return;
    final atualizado = await Supabase.instance.client
        .from('pedidos')
        .select('*, pedido_itens(*, produtos!produto_id(nome, url_imagem)), unidades(nome, cidade, endereco, bairro, horario_seg, horario_ter, horario_qua, horario_qui, horario_sex, horario_sab, horario_dom, prazo_retirada_min, prazo_entrega_min)')
        .eq('id', p['id'])
        .eq('user_id', userId)
        .maybeSingle();
    if (atualizado != null && mounted) _atualizarLocal((atualizado as Map).cast<String, dynamic>());
    _carregarHistorico();
  }

  Future<void> _cancelar() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar pedido'),
        content: const Text('Tem certeza que deseja cancelar este pedido?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Cancelar pedido', style: TextStyle(color: ThemeColors.error(ctx))),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _processando = true);
    try {
      // Cancelamento via RPC — a máquina de estados do banco valida a
      // permissão e devolve o estoque de forma idempotente (1x).
      await Supabase.instance.client.rpc('cancelar_pedido', params: {
        'p_pedido_id': _pedido['id'],
      });
      final novo = Map<String, dynamic>.from(_pedido)..['status'] = 'cancelado';
      if (mounted) _atualizarLocal(novo);
      _carregarHistorico();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao cancelar: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  Future<void> _comprarNovamente() async {
    final cart = context.read<CartProvider>();
    for (final i in _itens) {
      await cart.adicionar(i['produto_id'] as int,
          quantidade: i['quantidade'] as int? ?? 1,
          cor: i['cor'] as String?);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Itens adicionados ao carrinho!'),
          backgroundColor: AppColors.success,
        ),
      );
      context.go('/carrinho');
    }
  }

  Future<void> _abrirMapa() async {
    final endereco = _pedido['endereco_entrega'] as String? ?? '';
    if (endereco.isEmpty) return;
    await abrirMapa(endereco);
  }

  @override
  Widget build(BuildContext context) {
    final status = _status ?? 'pendente';
    final cor = corStatusPedido(status);
    final idx = indiceEtapa(status);
    final unidade = _unidade;
    final tipo = _tipoEntrega;
    final entrega = tipo == 'entrega';
    final podeCancelar = status == 'pendente' || status == 'pago';
    final podePagar = status == 'pendente';
    final enderecoEntrega = _pedido['endereco_entrega'] as String? ?? '';

    return Scaffold(
      backgroundColor: ThemeColors.background(context),
      appBar: AppBar(
        backgroundColor: ThemeColors.surface(context),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/pedidos');
            }
          },
        ),
        title: Text('Pedido #${_pedido['id']}',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          // Status atual
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: cor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(entrega ? Icons.delivery_dining_rounded : Icons.storefront_rounded, color: cor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(rotuloStatusPedido(status),
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: cor)),
                      if (unidade != null)
                        Text(
                          previsaoTexto(unidade, tipo),
                          style: TextStyle(fontSize: 12, color: ThemeColors.secondaryText(context)),
                        ),
                      if (status == 'entregue' && _pedido['recebedor_nome'] != null)
                        Text(
                          'Recebido por: ${_pedido['recebedor_nome']}',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF00A650), fontWeight: FontWeight.w600),
                        ),
                    ],
                  ),
                ),
                if (entrega && status == 'saiu_para_entrega' && enderecoEntrega.isNotEmpty)
                  IconButton(
                    icon: Icon(Icons.map_rounded, color: cor),
                    onPressed: _abrirMapa,
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Timeline
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: ThemeColors.surface(context),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: List.generate(etapasTimeline.length, (i) {
                final concluido = idx >= i;
                final atual = idx == i;
                final icone = concluido ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        Icon(icone,
                            size: 22,
                            color: concluido ? corStatusPedido(etapasTimeline[i]) : ThemeColors.hint(context)),
                        if (i < etapasTimeline.length - 1)
                          Container(
                            width: 2,
                            height: 26,
                            color: idx > i ? corStatusPedido(etapasTimeline[i]) : ThemeColors.divider(context),
                          ),
                      ],
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              rotuloStatusPedido(etapasTimeline[i]),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: atual ? FontWeight.w700 : FontWeight.w500,
                                color: concluido ? ThemeColors.primaryText(context) : ThemeColors.hint(context),
                              ),
                            ),
                            // Data/hora REAL de cada etapa (pedido_historico)
                            if (concluido && _historico[etapasTimeline[i]] != null)
                              Text(formatarDataHora(_historico[etapasTimeline[i]]),
                                  style: TextStyle(fontSize: 11, color: ThemeColors.secondaryText(context))),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Entrega / Endereço
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: ThemeColors.surface(context),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entrega ? 'Entrega' : 'Retirada na unidade',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                if (entrega && enderecoEntrega.isNotEmpty) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.location_on_rounded, size: 18, color: Color(0xFFE50914)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(enderecoEntrega, style: const TextStyle(fontSize: 13))),
                    ],
                  ),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: _abrirMapa,
                    child: const Text('Abrir no mapa',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFE50914))),
                  ),
                ] else if (unidade != null) ...[
                  Row(
                    children: [
                      const Icon(Icons.store_rounded, size: 18, color: Color(0xFFE50914)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(unidade['nome'] as String? ?? 'Loja', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                    ],
                  ),
                  if (unidade['endereco'] != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 26, top: 4),
                      child: Text('${unidade['endereco']}${unidade['bairro'] != null ? ' - ${unidade['bairro']}' : ''}',
                          style: TextStyle(fontSize: 12, color: ThemeColors.secondaryText(context))),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Itens
          Text('Itens (${_itens.length})', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: ThemeColors.surface(context),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: _itens.map((i) {
                final prod = i['produtos'] is Map ? (i['produtos'] as Map) : null;
                final rawImg = prod?['url_imagem'];
                String? img;
                if (rawImg is List && rawImg.isNotEmpty) {
                  img = rawImg.first.toString();
                } else if (rawImg is String && rawImg.isNotEmpty) {
                  img = rawImg;
                }
                final qtd = i['quantidade'] as int? ?? 1;
                final preco = (i['preco_unitario'] as num?)?.toDouble() ?? 0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: img != null
                              ? CachedNetworkImage(
                                  imageUrl: img,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) =>
                                      Container(color: ThemeColors.surfaceVariant(context), child: Icon(Icons.image_outlined, size: 20, color: ThemeColors.hint(context))),
                                )
                              : Container(
                                  color: ThemeColors.surfaceVariant(context),
                                  child: Icon(Icons.image_outlined, size: 20, color: ThemeColors.hint(context))),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(prod?['nome'] as String? ?? 'Produto',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                            if (i['cor'] != null && (i['cor'] as String).isNotEmpty)
                              Text('Cor: ${i['cor']}',
                                  style: TextStyle(fontSize: 11, color: ThemeColors.primary(context), fontWeight: FontWeight.w600)),
                            Text('$qtd x R\$ ${preco.toStringAsFixed(2)}',
                                style: TextStyle(fontSize: 12, color: ThemeColors.secondaryText(context))),
                          ],
                        ),
                      ),
                      Text('R\$ ${(preco * qtd).toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Resumo
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: ThemeColors.surface(context),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                _linha('Subtotal', 'R\$ ${_subtotal.toStringAsFixed(2)}'),
                if (_subtotal > _total)
                  _linha('Desconto', '-R\$ ${(_subtotal - _total).toStringAsFixed(2)}', cor: const Color(0xFF00A650)),
                _linha('Entrega', entrega ? 'Entrega' : 'Retirada na unidade'),
                _linha('Pagamento', _pedido['pagamento'] != null ? (_pedido['pagamento'] == 'cartao' ? 'Cartão de crédito' : 'PIX') : '—'),
                if (_pedido['transacao_id'] != null)
                  _linha('Transação', '#${_pedido['transacao_id']}'),
                const Divider(height: 20),
                _linha('Total', 'R\$ ${_total.toStringAsFixed(2)}', bold: true),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Loja
          if (unidade != null)
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: ThemeColors.surface(context),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE50914).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.store_rounded, color: Color(0xFFE50914)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(unidade['nome'] as String? ?? 'Loja',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                        Text('Vendido e entregue pela loja',
                            style: TextStyle(fontSize: 11, color: ThemeColors.secondaryText(context))),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => context.push(
                      '/chat/${_pedido['unidade_id']}/${Uri.encodeComponent(unidade['nome'] as String? ?? 'Loja')}',
                    ),
                    icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                    label: const Text('Falar com a loja'),
                    style: TextButton.styleFrom(foregroundColor: const Color(0xFFE50914)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.lg),

          // Ações
          if (podePagar)
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _processando ? null : _pagarAgora,
                icon: const Icon(Icons.payments_rounded, size: 20),
                label: const Text('Pagar agora', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE50914),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          if (podeCancelar) ...[
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: 48,
              child: OutlinedButton(
                onPressed: _processando ? null : _cancelar,
                style: OutlinedButton.styleFrom(
                  foregroundColor: ThemeColors.error(context),
                  side: BorderSide(color: ThemeColors.error(context)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Cancelar pedido', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 48,
            child: TextButton.icon(
              onPressed: _comprarNovamente,
              icon: const Icon(Icons.replay_rounded, size: 18),
              label: const Text('Comprar novamente'),
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFE50914)),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }

  Widget _linha(String label, String valor, {Color? cor, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  color: cor ?? ThemeColors.secondaryText(context),
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
          Text(valor,
              style: TextStyle(
                  fontSize: 13,
                  color: cor ?? ThemeColors.primaryText(context),
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w600)),
        ],
      ),
    );
  }
}
