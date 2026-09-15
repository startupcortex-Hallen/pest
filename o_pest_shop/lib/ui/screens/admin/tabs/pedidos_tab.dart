import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/helpers/pedido_status.dart';
import '../../../../core/helpers/theme_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../services/admin_service.dart';
import '../../../widgets/animated_card_entry.dart';
import '../admin_utils.dart';

class PedidosTab extends StatefulWidget {
  const PedidosTab({super.key});

  @override
  State<PedidosTab> createState() => _PedidosTabState();
}

class _PedidosTabState extends State<PedidosTab> {
  final _service = AdminService();
  final _buscaCtrl = TextEditingController();
  Timer? _debounce;
  RealtimeChannel? _channel;
  List<Map<String, dynamic>> _pedidos = [];
  Map<int, List<Map<String, dynamic>>> _entregadoresPorUnidade = {};
  bool _loading = true;
  String? _grupoAtivo;
  final Set<int> _expandidos = {};
  // Todos os status válidos. "saiu_para_entrega" e "entregue" pertencem ao
  // ciclo do entregador, mas precisam estar na lista para o Dropdown renderizar
  // pedidos nesses estados sem assertion error ("There should be exactly one
  // item with the DropdownButton's value"). As transições inválidas são
  // desabilitadas na UI e rejeitadas pela máquina de estados do banco.
  static const _statusLista = [
    'pendente', 'pago', 'em_preparo', 'pronto_para_entrega',
    'saiu_para_entrega', 'entregue', 'cancelado',
  ];

  /// Transições permitidas pela máquina de estados do banco (fn_pedido_status).
  /// Itens fora desta lista são desabilitados no dropdown.
  static Set<String> _transicoesPermitidas(Map<String, dynamic> p) {
    final atual = p['status'] as String? ?? 'pendente';
    final tipo = p['tipo_entrega'] as String? ?? 'retirada';
    switch (atual) {
      case 'pendente':
        return {'pago', 'cancelado'};
      case 'pago':
        return {'em_preparo', 'cancelado'};
      case 'em_preparo':
        return {'pronto_para_entrega', 'cancelado'};
      case 'pronto_para_entrega':
        // Retirada: a loja confirma a entrega direto. Entrega: só o entregador.
        return tipo == 'retirada' ? {'entregue', 'cancelado'} : {'cancelado'};
      case 'saiu_para_entrega':
        return {'entregue'};
      default:
        return {};
    }
  }

  // Grupos do painel — divide os pedidos como nas grandes lojas
  static const _grupos = <String, List<String>>{
    'Aguardando pagamento': ['pendente'],
    'Em andamento': ['pago', 'em_preparo', 'pronto_para_entrega', 'saiu_para_entrega'],
    'Entregues': ['entregue'],
    'Cancelados': ['cancelado'],
  };

  List<Map<String, dynamic>> get _pedidosFiltrados {
    if (_grupoAtivo == null) return _pedidos;
    final statuses = _grupos[_grupoAtivo] ?? const [];
    return _pedidos.where((p) => statuses.contains(p['status'])).toList();
  }

  int _contagemDe(String? grupo) {
    if (grupo == null) return _pedidos.length;
    final statuses = _grupos[grupo] ?? const [];
    return _pedidos.where((p) => statuses.contains(p['status'])).length;
  }

  @override
  void initState() {
    super.initState();
    _carregar();
    _carregarEntregadores();
    // Realtime: pedido novo ou status alterado atualiza a lista sozinho
    _channel = Supabase.instance.client
        .channel('admin_pedidos')
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
    _debounce?.cancel();
    _buscaCtrl.dispose();
    _channel?.unsubscribe();
    super.dispose();
  }

  /// Carrega TODOS os entregadores uma vez (evita N+1 por card expandido).
  Future<void> _carregarEntregadores() async {
    try {
      final r = await Supabase.instance.client
          .from('perfis')
          .select('id, nome, unidade_id')
          .eq('funcao', 'entregador')
          .order('nome');
      if (r is List) {
        final mapa = <int, List<Map<String, dynamic>>>{};
        for (final e in r) {
          final eMap = (e as Map).cast<String, dynamic>();
          final uid = eMap['unidade_id'] as int? ?? 0;
          mapa.putIfAbsent(uid, () => []);
          mapa[uid]!.add(eMap);
        }
        if (mounted) setState(() => _entregadoresPorUnidade = mapa);
      }
    } catch (e) {
      debugPrint('Erro entregadores: $e');
    }
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    try {
      _pedidos = await _service.fetchPedidos(
        busca: _buscaCtrl.text.trim().isEmpty ? null : _buscaCtrl.text.trim(),
      );
    } catch (e) {
      debugPrint('Erro pedidos: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _mudarStatus(Map<String, dynamic> pedido, String novo) async {
    if (novo == pedido['status']) return;
    try {
      await _service.updatePedidoStatus(pedido['id'] as int, novo);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Status atualizado para "${rotuloStatusCurto(novo)}"')),
        );
      }
      _carregar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mapErroAdmin(e))));
    }
  }

  Future<void> _atribuirEntregador(Map<String, dynamic> pedido, String? entregadorId) async {
    try {
      await Supabase.instance.client.rpc('atribuir_entregador', params: {
        'p_pedido_id': pedido['id'],
        'p_entregador_id': entregadorId,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(entregadorId == null
              ? 'Entregador removido do pedido #${pedido['id']}'
              : 'Entregador atribuído ao pedido #${pedido['id']}'),
        ));
      }
      _carregar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mapErroAdmin(e))));
    }
  }

  /// A loja envia a solicitação de entrega ao entregador atribuído.
  Future<void> _solicitarEntrega(Map<String, dynamic> pedido) async {
    if (pedido['entregador_id'] == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Atribua um entregador antes de solicitar a entrega.'),
            backgroundColor: Color(0xFFF23D4F),
          ),
        );
      }
      return;
    }
    await _mudarStatus(pedido, 'pronto_para_entrega');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
            children: [
              _buildStatusChip('Todos (${_contagemDe(null)})', null, _grupoAtivo == null, () {
                setState(() => _grupoAtivo = null);
              }),
              ..._grupos.keys.map((g) => Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: _buildStatusChip('$g (${_contagemDe(g)})', g, _grupoAtivo == g, () {
                      setState(() => _grupoAtivo = g);
                    }),
                  )),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 8, AppSpacing.lg, 8),
          child: TextField(
            controller: _buscaCtrl,
            decoration: InputDecoration(
              hintText: 'Buscar por cliente ou email',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              filled: true,
              fillColor: ThemeColors.surface(context),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
            onChanged: (_) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 400), () => _carregar());
            },
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _pedidosFiltrados.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.receipt_long_rounded, size: 48, color: ThemeColors.hint(context)),
                          const SizedBox(height: 12),
                          Text('Nenhum pedido encontrado',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text('Tente alterar o filtro ou a busca.',
                              style: TextStyle(color: ThemeColors.secondaryText(context))),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 4, AppSpacing.lg, 24),
                      itemCount: _pedidosFiltrados.length,
                      itemBuilder: (context, index) => _buildPedidoCard(_pedidosFiltrados[index], index),
                    ),
        ),
      ],
    );
  }

  Widget _buildStatusChip(String label, String? status, bool selected, VoidCallback onTap) {
    final cor = status == null ? const Color(0xFFC6C6C6) : corStatusPedido(status);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? cor.withValues(alpha: 0.15) : const Color(0xFF1F1F1F),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: selected ? cor : const Color(0xFFC6C6C6))),
      ),
    );
  }

  /// Extrai com segurança a primeira imagem de um produto vinculado ao item do pedido.
  String? _primeiraImagemProduto(dynamic produtos) {
    if (produtos is! Map) return null;
    final url = produtos['url_imagem'];
    if (url is List && url.isNotEmpty) return url.first.toString();
    if (url is String && url.isNotEmpty) return url;
    return null;
  }

  Widget _buildPedidoCard(Map<String, dynamic> p, int index) {
    final perfil = p['perfis'] is Map ? (p['perfis'] as Map) : null;
    final unidade = p['unidades'] is Map ? (p['unidades'] as Map)['nome'] as String? : null;
    final nomeCliente = perfil?['nome'] as String? ?? 'Cliente';
    final email = perfil?['email'] as String? ?? '';
    final telefone = perfil?['telefone'] as String? ?? '';
    final status = p['status'] as String? ?? 'pendente';
    final cor = corStatusPedido(status);
    final itens = (p['pedido_itens'] as List?) ?? [];
    final expandido = _expandidos.contains(p['id']);

    return AnimatedCardEntry(
      index: index,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            ListTile(
              leading: CircleAvatar(
                backgroundColor: cor.withValues(alpha: 0.12),
                child: Icon(Icons.receipt_long_rounded, color: cor, size: 20),
              ),
              title: Text(nomeCliente,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${formatarMoeda(p['total'])}  •  ${formatarData(p['created_at'] as String?)}',
                      style: TextStyle(fontSize: 12, color: ThemeColors.secondaryText(context))),
                  if (unidade != null)
                    Text(unidade,
                        style: TextStyle(
                            fontSize: 11, color: ThemeColors.primary(context), fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                ],
              ),
              trailing: _statusDropdown(p, (novo) => _mudarStatus(p, novo)),
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
                    Text('Pedido #${p['id']}  •  Itens (${itens.length})',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700, color: ThemeColors.secondaryText(context))),
                    const SizedBox(height: 6),
                    ...itens.map((it) {
                      final img = _primeiraImagemProduto(it['produtos']);
                      final nomeProduto = it['produtos'] is Map
                          ? (it['produtos'] as Map)['nome'] as String? ?? ''
                          : '';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: SizedBox(
                                width: 32,
                                height: 32,
                                child: img != null
                                    ? CachedNetworkImage(
                                        imageUrl: img,
                                        fit: BoxFit.cover,
                                        errorWidget: (_, __, ___) =>
                                            Container(color: ThemeColors.surfaceVariant(context)))
                                    : Container(
                                        color: ThemeColors.surfaceVariant(context),
                                        child: Icon(Icons.image_outlined,
                                            size: 14, color: ThemeColors.hint(context))),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                nomeProduto +
                                    ((it['cor'] != null && (it['cor'] as String).isNotEmpty)
                                        ? '  ·  ${it['cor']}'
                                        : ''),
                                style: const TextStyle(fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text('${it['quantidade'] ?? 1}x',
                                style: TextStyle(fontSize: 12, color: ThemeColors.secondaryText(context))),
                            const SizedBox(width: 8),
                            Text(formatarMoeda(it['preco_unitario']),
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 4),
                    if (telefone.isNotEmpty)
                      Text('Telefone: $telefone',
                          style: TextStyle(fontSize: 11, color: ThemeColors.secondaryText(context))),
                    if (email.isNotEmpty)
                      Text('Email: $email',
                          style: TextStyle(fontSize: 11, color: ThemeColors.secondaryText(context))),
                    if (p['pix_copia_cola'] != null && (p['pix_copia_cola'] as String).isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text('PIX: ${p['pix_copia_cola']}',
                          style: TextStyle(fontSize: 11, color: ThemeColors.secondaryText(context))),
                    ],
                    if (p['tipo_entrega'] != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        p['tipo_entrega'] == 'entrega'
                            ? 'Entrega: ${p['endereco_entrega'] ?? 'sem endereço'}'
                            : 'Retirada na unidade',
                        style: TextStyle(fontSize: 11, color: ThemeColors.secondaryText(context)),
                      ),
                    ],
                    const SizedBox(height: 8),
                    // Atribuir entregador (cache — sem N+1)
                    Builder(builder: (context) {
                      final entregadores =
                          _entregadoresPorUnidade[p['unidade_id'] as int? ?? 0] ?? [];
                      final atual = p['entregador_id'] as String?;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0084FF).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.delivery_dining_rounded, size: 14, color: Color(0xFF0084FF)),
                            const SizedBox(width: 6),
                            const Text('Entregador:',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF0084FF))),
                            const SizedBox(width: 4),
                            Expanded(
                              child: DropdownButton<String>(
                                value: atual,
                                isDense: true,
                                underline: const SizedBox(),
                                style: const TextStyle(fontSize: 11, color: Color(0xFF0084FF), fontWeight: FontWeight.w600),
                                icon: const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF0084FF), size: 20),
                                items: [
                                  const DropdownMenuItem(value: null, child: Text('Sem entregador', style: TextStyle(fontSize: 11, color: Color(0xFFC6C6C6)))),
                                  ...entregadores.map((e) => DropdownMenuItem(
                                        value: e['id'] as String,
                                        child: Text(e['nome'] as String? ?? '', style: const TextStyle(fontSize: 11)),
                                      )),
                                ],
                                onChanged: (v) {
                                  if (v != atual) _atribuirEntregador(p, v);
                                },
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    if (p['status'] == 'em_preparo') ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 40,
                        child: ElevatedButton.icon(
                          onPressed: () => _solicitarEntrega(p),
                          icon: const Icon(Icons.delivery_dining_rounded, size: 16),
                          label: const Text('Solicitar entrega ao entregador',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0084FF),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ] else if (p['status'] == 'pronto_para_entrega' &&
                        p['tipo_entrega'] == 'retirada') ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 40,
                        child: ElevatedButton.icon(
                          onPressed: () => _mudarStatus(p, 'entregue'),
                          icon: const Icon(Icons.storefront_rounded, size: 16),
                          label: const Text('Confirmar retirada na unidade',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00A650),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ] else if (p['status'] == 'pronto_para_entrega') ...[
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          'Aguardando o entregador iniciar a entrega...',
                          style: TextStyle(fontSize: 12, color: ThemeColors.hint(context)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusDropdown(Map<String, dynamic> p, ValueChanged<String> onChanged) {
    final atual = p['status'] as String? ?? 'pendente';
    final cor = corStatusPedido(atual);
    final permitidas = _transicoesPermitidas(p);
    // Garante que o status atual sempre exista como item → evita assertion da
    // DropdownButton em pedidos com 'saiu_para_entrega'/'entregue'.
    final itens = <String>{..._statusLista, atual}.toList();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: DropdownButton<String>(
        value: atual,
        underline: const SizedBox(),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cor),
        icon: Icon(Icons.arrow_drop_down_rounded, color: cor, size: 20),
        isDense: true,
        items: itens
            .map((s) => DropdownMenuItem(
                value: s,
                enabled: s == atual || permitidas.contains(s),
                child: Text(rotuloStatusCurto(s),
                    style: TextStyle(fontSize: 11, color: corStatusPedido(s), fontWeight: FontWeight.w600))))
            .toList(),
        onChanged: (v) {
          if (v != null && v != atual) onChanged(v);
        },
      ),
    );
  }
}
