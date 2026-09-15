import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/helpers/pedido_status.dart';
import '../../../core/helpers/theme_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../providers/auth_provider.dart';
import '../../widgets/animated_card_entry.dart';
import 'pedido_detail_screen.dart';

class PedidosScreen extends StatefulWidget {
  const PedidosScreen({super.key});

  @override
  State<PedidosScreen> createState() => _PedidosScreenState();
}

class _PedidosScreenState extends State<PedidosScreen> {
  static const _pageSize = 20;
  List<Map<String, dynamic>> _pedidos = [];
  bool _loading = true;
  bool _carregandoMais = false;
  bool _temMais = true;
  int _pagina = 0;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final userId = context.read<AuthProvider>().user?.id;
    if (userId == null) return;
    _pagina = 0;
    try {
      // Expira pedidos não pagos (padrão grandes apps): pendentes antigos
      // são cancelados antes de listar.
      try {
        await Supabase.instance.client.rpc('cancelar_pendentes_expirados');
      } catch (_) {}
      final response = await Supabase.instance.client
        .from('pedidos')
        .select('*, pedido_itens(*, produtos!produto_id(nome, url_imagem)), unidades(nome, cidade, endereco, bairro, horario_seg, horario_ter, horario_qua, horario_qui, horario_sex, horario_sab, horario_dom, prazo_retirada_min, prazo_entrega_min)')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .range(0, _pageSize - 1);
      if (response is List) {
        _pedidos = response.cast<Map<String, dynamic>>();
        _temMais = _pedidos.length == _pageSize;
      }
    } catch (e) { debugPrint('Erro pedidos: $e'); }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _carregarMais() async {
    final userId = context.read<AuthProvider>().user?.id;
    if (userId == null || _carregandoMais || !_temMais) return;
    setState(() => _carregandoMais = true);
    try {
      final inicio = (_pagina + 1) * _pageSize;
      final response = await Supabase.instance.client
        .from('pedidos')
        .select('*, pedido_itens(*, produtos!produto_id(nome, url_imagem)), unidades(nome, cidade, endereco, bairro, horario_seg, horario_ter, horario_qua, horario_qui, horario_sex, horario_sab, horario_dom, prazo_retirada_min, prazo_entrega_min)')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .range(inicio, inicio + _pageSize - 1);
      if (response is List) {
        final novos = response.cast<Map<String, dynamic>>();
        if (novos.isEmpty) {
          _temMais = false;
        } else {
          final ids = _pedidos.map((p) => p['id']).toSet();
          _pedidos.addAll(novos.where((p) => !ids.contains(p['id'])));
          _pagina++;
          _temMais = novos.length == _pageSize;
        }
      }
    } catch (e) { debugPrint('Erro carregar mais: $e'); }
    if (mounted) setState(() => _carregandoMais = false);
  }

  List<Map<String, dynamic>> _itensDe(Map<String, dynamic> p) =>
      ((p['pedido_itens'] as List?) ?? []).cast<Map<String, dynamic>>();

  IconData _iconeStatus(String status) {
    switch (status) {
      case 'pendente': return Icons.schedule_rounded;
      case 'pago': return Icons.payments_rounded;
      case 'em_preparo': return Icons.local_dining_rounded;
      case 'pronto_para_entrega': return Icons.inventory_2_rounded;
      case 'saiu_para_entrega': return Icons.delivery_dining_rounded;
      case 'entregue': return Icons.check_circle_rounded;
      case 'cancelado': return Icons.cancel_rounded;
      default: return Icons.receipt_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
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
              context.go('/');
            }
          },
        ),
        title: const Text('Meus Pedidos'),
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _pedidos.isEmpty
          ? const Center(child: Text('Nenhum pedido ainda'))
          : RefreshIndicator(
              onRefresh: _carregar,
              color: ThemeColors.primary(context),
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.lg),
                itemCount: _pedidos.length + (_temMais ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i >= _pedidos.length) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: _carregandoMais
                            ? const CircularProgressIndicator(strokeWidth: 2)
                            : TextButton(
                                onPressed: _carregarMais,
                                child: const Text('Carregar mais pedidos'),
                              ),
                      ),
                    );
                  }
                  final p = _pedidos[i];
                  final unidade = p['unidades'] as Map<String, dynamic>?;
                  final status = p['status'] as String? ?? 'pendente';
                  final cor = corStatusPedido(status);
                  final itens = _itensDe(p);
                  return AnimatedCardEntry(
                    index: i,
                    child: GestureDetector(
                      onTap: () async {
                        final resultado = await Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                            builder: (_) => PedidoDetailScreen(pedido: p),
                          ),
                        );
                        if (resultado == true) _carregar();
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: AppSpacing.md),
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: ThemeColors.surface(context),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 42, height: 42,
                                  decoration: BoxDecoration(
                                    color: cor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(Icons.receipt_rounded, color: cor, size: 22),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Pedido #${p['id']}',
                                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                      Text(
                                        formatarDataHora(p['created_at'] as String?),
                                        style: TextStyle(fontSize: 11, color: ThemeColors.secondaryText(context)),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: cor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(_iconeStatus(status), size: 12, color: cor),
                                      const SizedBox(width: 4),
                                      Text(
                                        rotuloStatusCurto(status).toUpperCase(),
                                        style: TextStyle(fontSize: 9, color: cor, fontWeight: FontWeight.w700),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            // Mini progresso do pedido (prévia visual das etapas)
                            if (status != 'cancelado') ...[
                              const SizedBox(height: 10),
                              Row(
                                children: List.generate(etapasTimeline.length, (i) {
                                  final idx = indiceEtapa(status);
                                  final done = i <= idx;
                                  return Expanded(
                                    child: Container(
                                      height: 4,
                                      margin: const EdgeInsets.symmetric(horizontal: 2),
                                      decoration: BoxDecoration(
                                        color: done
                                            ? corStatusPedido(etapasTimeline[i])
                                            : ThemeColors.surfaceVariant(context),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                  );
                                }),
                              ),
                            ],
                            if (itens.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              SizedBox(
                                height: 52,
                                child: ListView(
                                  scrollDirection: Axis.horizontal,
                                  children: itens.map((i) {
                                    final prod = i['produtos'] is Map ? (i['produtos'] as Map) : null;
                                    final rawImg = prod?['url_imagem'];
                                    String? img;
                                    if (rawImg is List && rawImg.isNotEmpty) {
                                      img = rawImg.first.toString();
                                    } else if (rawImg is String && rawImg.isNotEmpty) {
                                      img = rawImg;
                                    }
                                    final qtd = i['quantidade'] as int? ?? 1;
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 10),
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
                                                      errorWidget: (_, __, ___) => Container(
                                                          color: ThemeColors.surfaceVariant(context),
                                                          child: Icon(Icons.image_outlined, size: 20, color: ThemeColors.hint(context))),
                                                    )
                                                  : Container(
                                                      color: ThemeColors.surfaceVariant(context),
                                                      child: Icon(Icons.image_outlined, size: 20, color: ThemeColors.hint(context))),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          ConstrainedBox(
                                            constraints: const BoxConstraints(maxWidth: 110),
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(prod?['nome'] as String? ?? 'Produto',
                                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis),
                                                if (i['cor'] != null && (i['cor'] as String).isNotEmpty)
                                                  Text('Cor: ${i['cor']}',
                                                      style: TextStyle(fontSize: 9, color: ThemeColors.primary(context), fontWeight: FontWeight.w600)),
                                                Text('$qtd x',
                                                    style: TextStyle(fontSize: 10, color: ThemeColors.secondaryText(context))),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    '${unidade?['nome'] ?? ''}  •  ${itens.length} ${itens.length == 1 ? 'item' : 'itens'}',
                                    style: TextStyle(fontSize: 11, color: ThemeColors.secondaryText(context)),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text('R\$ ${(p['total'] as num?)?.toStringAsFixed(2) ?? '0,00'}',
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
