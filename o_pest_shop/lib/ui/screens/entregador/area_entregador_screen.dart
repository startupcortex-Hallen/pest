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
import '../../widgets/animated_card_entry.dart';

/// Área do Entregador — entregas atribuídas a mim (ou todas, para admin),
/// com ações "Saiu para entrega" e "Entregue".
class AreaEntregadorScreen extends StatefulWidget {
  const AreaEntregadorScreen({super.key});

  @override
  State<AreaEntregadorScreen> createState() => _AreaEntregadorScreenState();
}

class _AreaEntregadorScreenState extends State<AreaEntregadorScreen> {
  List<Map<String, dynamic>> _pedidos = [];
  bool _loading = true;
  bool _isAdmin = false;
  final Set<int> _expandidos = {};
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _carregar();
    // Realtime: solicitação nova/status alterado atualiza a lista sozinho
    _channel = Supabase.instance.client
        .channel('entregador_pedidos')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'pedidos',
          callback: (_) => _carregar(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _carregar() async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;
    _isAdmin = user.funcao == 'admin';
    setState(() => _loading = true);
    try {
      // Somente pedidos PRONTOS PARA ENTREGA ou SAIU PARA ENTREGA
      // (pedidos em preparação NÃO aparecem) e apenas entregas (não retirada).
      var query = Supabase.instance.client
          .from('pedidos')
          .select('*, pedido_itens(*, produtos!produto_id(nome, url_imagem)), unidades(nome, endereco, bairro), perfis!pedidos_user_id_fkey(nome, telefone)')
          .inFilter('status', ['pronto_para_entrega', 'saiu_para_entrega'])
          .neq('tipo_entrega', 'retirada');
      if (!_isAdmin) {
        query = query.eq('entregador_id', user.id);
      }
      final r = await query.order('created_at', ascending: false);
      if (r is List) _pedidos = r.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('Erro entregas: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _confirmarEntrega(Map<String, dynamic> p) async {
    _mudarStatus(p, 'entregue');
  }

  Future<void> _mudarStatus(Map<String, dynamic> p, String novo) async {
    String? recebedor;
    if (novo == 'entregue') {
      recebedor = await _pedirNomeRecebedor(p);
      if (recebedor == null) return;
    }
    try {
      // Transição via RPC — a máquina de estados do banco valida papel e estado
      await Supabase.instance.client.rpc('alterar_status_pedido', params: {
        'p_pedido_id': p['id'],
        'p_status': novo,
        if (recebedor != null) 'p_recebedor': recebedor,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(novo == 'entregue'
              ? 'Pedido #${p['id']} marcado como entregue!'
              : 'Pedido #${p['id']} saiu para entrega.'),
          backgroundColor: novo == 'entregue' ? AppColors.success : AppColors.info,
        ));
      }
      _carregar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: AppColors.error),
      );
    }
  }

  Future<String?> _pedirNomeRecebedor(Map<String, dynamic> p) async {
    final recebedorCtrl = TextEditingController();
    final nome = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nome de quem recebeu'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Informe o nome de quem recebeu o pedido #${p['id']}:'),
            const SizedBox(height: 12),
            TextField(
              controller: recebedorCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nome de quem recebeu',
                hintText: 'Ex: João da Silva',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              if (recebedorCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Informe o nome de quem recebeu.'), backgroundColor: AppColors.error),
                );
                return;
              }
              Navigator.pop(ctx, recebedorCtrl.text.trim());
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00A650), foregroundColor: Colors.white),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    recebedorCtrl.dispose();
    return nome == null || nome.isEmpty ? null : nome;
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
        title: const Text('Área do Entregador'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregar,
              color: ThemeColors.primary(context),
              child: _pedidos.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        Padding(
                          padding: EdgeInsets.only(top: 120),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.delivery_dining_rounded, size: 56, color: Color(0xFF9C9C9C)),
                                SizedBox(height: 12),
                                Text('Nenhuma entrega atribuída', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                                SizedBox(height: 4),
                                Text('Os pedidos aparecem aqui quando a loja atribuir a você.', style: TextStyle(fontSize: 12, color: Color(0xFF9C9C9C))),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      itemCount: _pedidos.length,
                      itemBuilder: (context, index) {
                        final p = _pedidos[index];
                        final status = p['status'] as String? ?? 'pago';
                        final cor = corStatusPedido(status);
                        final unidade = p['unidades'] is Map ? (p['unidades'] as Map) : null;
                        final cliente = p['perfis'] is Map ? (p['perfis'] as Map) : null;
                        final endereco = p['endereco_entrega'] as String? ?? '';
                        final expandido = _expandidos.contains(p['id']);
                        return AnimatedCardEntry(
                          index: index,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: AppSpacing.md),
                            decoration: BoxDecoration(
                              color: ThemeColors.surface(context),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              children: [
                                ListTile(
                                  leading: Container(
                                    width: 44, height: 44,
                                    decoration: BoxDecoration(
                                      color: cor.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(Icons.delivery_dining_rounded, color: cor),
                                  ),
                                  title: Text('Pedido #${p['id']}',
                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('${unidade?['nome'] ?? ''}  •  R\$ ${(p['total'] as num?)?.toStringAsFixed(2) ?? '0,00'}',
                                          style: TextStyle(fontSize: 12, color: ThemeColors.secondaryText(context))),
                                      Text(rotuloStatusCurto(status),
                                          style: TextStyle(fontSize: 11, color: cor, fontWeight: FontWeight.w700)),
                                    ],
                                  ),
                                  onTap: () => setState(() {
                                    if (!_expandidos.add(p['id'] as int)) _expandidos.remove(p['id'] as int);
                                  }),
                                ),
                                if (expandido) ...[
                                  Divider(height: 1, color: ThemeColors.divider(context)),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(AppSpacing.md, 8, AppSpacing.md, 12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (cliente != null) ...[
                                          Text('Cliente: ${cliente['nome'] ?? ''}',
                                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                          if (cliente['telefone'] != null)
                                            Text('Tel: ${cliente['telefone']}',
                                                style: TextStyle(fontSize: 11, color: ThemeColors.secondaryText(context))),
                                        ],
                                        const SizedBox(height: 6),
                                        if (p['tipo_entrega'] == 'entrega' && endereco.isNotEmpty) ...[
                                          Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Icon(Icons.location_on_rounded, size: 16, color: Color(0xFFE50914)),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(endereco, style: const TextStyle(fontSize: 12)),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          GestureDetector(
                                            onTap: () => abrirMapa(endereco),
                                            child: const Text('Abrir no mapa',
                                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFE50914))),
                                          ),
                                        ] else
                                          Text('Retirada na unidade: ${unidade?['nome'] ?? ''}',
                                              style: TextStyle(fontSize: 12, color: ThemeColors.secondaryText(context))),
                                        const SizedBox(height: 10),
                                        if (status == 'pronto_para_entrega')
                                          SizedBox(
                                            width: double.infinity,
                                            height: 44,
                                            child: ElevatedButton.icon(
                                              onPressed: () => _mudarStatus(p, 'saiu_para_entrega'),
                                              icon: const Icon(Icons.directions_bike_rounded, size: 18),
                                              label: const Text('Iniciar entrega',
                                                  style: TextStyle(fontWeight: FontWeight.w700)),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: const Color(0xFF0084FF),
                                                foregroundColor: Colors.white,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                              ),
                                            ),
                                          )
                                        else if (status == 'saiu_para_entrega')
                                          SizedBox(
                                            width: double.infinity,
                                            height: 44,
                                            child: ElevatedButton.icon(
                                              onPressed: () => _confirmarEntrega(p),
                                              icon: const Icon(Icons.check_rounded, size: 18),
                                              label: const Text('Confirmar entrega',
                                                  style: TextStyle(fontWeight: FontWeight.w700)),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: const Color(0xFF00A650),
                                                foregroundColor: Colors.white,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                              ),
                                            ),
                                          )
                                        else
                                          Center(
                                            child: Text(
                                              'Aguardando a loja liberar a entrega...',
                                              style: TextStyle(fontSize: 12, color: ThemeColors.hint(context)),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
