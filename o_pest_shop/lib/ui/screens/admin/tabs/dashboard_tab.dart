import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/helpers/theme_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../services/admin_service.dart';

class AdminDashboardTab extends StatefulWidget {
  final int? unidadeFiltro;
  final bool permitirSelecionarLoja;

  const AdminDashboardTab({
    super.key,
    this.unidadeFiltro,
    this.permitirSelecionarLoja = true,
  });

  @override
  State<AdminDashboardTab> createState() => _AdminDashboardTabState();
}

class _AdminDashboardTabState extends State<AdminDashboardTab> {
  final _service = AdminService();
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _unidades = [];
  int? _unidadeId;
  int _dias = 30;
  bool _carregando = true;
  String? _erro;
  Map<String, dynamic> _dados = {};
  RealtimeChannel? _channel;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _unidadeId = widget.unidadeFiltro;
    if (widget.permitirSelecionarLoja) _carregarUnidades();
    _carregar();
    _inscreverRealtime();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _channel?.unsubscribe();
    super.dispose();
  }

  void _inscreverRealtime() {
    _channel = Supabase.instance.client
        .channel('admin_dashboard')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'pedidos',
          callback: (_) => _agendarAtualizacao(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'pagamentos',
          callback: (_) => _agendarAtualizacao(),
        )
        .subscribe();
  }

  void _agendarAtualizacao() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () {
      if (mounted) _carregar();
    });
  }

  Future<void> _carregarUnidades() async {
    try {
      final r = await _client.from('unidades').select('id, nome').order('nome');
      if (mounted) {
        setState(() => _unidades = (r as List).cast<Map<String, dynamic>>());
      }
    } catch (_) {}
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final dados = await _service.fetchDashboard(
        unidadeId: _unidadeId,
        dias: _dias,
      );
      if (mounted) setState(() => _dados = dados);
    } catch (e) {
      final fallback = await _fallback();
      if (mounted) {
        setState(() {
          _dados = fallback;
          _erro =
              'Modo simplificado: aplique a migration do dashboard para ver todos os indicadores.';
        });
      }
    }
    if (mounted) setState(() => _carregando = false);
  }

  Future<Map<String, dynamic>> _fallback() async {
    try {
      dynamic pedidosQuery = _client
          .from('pedidos')
          .select('status, total, created_at, unidade_id')
          .order('created_at', ascending: false)
          .limit(500);
      if (_unidadeId != null) {
        pedidosQuery = pedidosQuery.eq('unidade_id', _unidadeId!);
      }
      final pedidos = ((await pedidosQuery) as List)
          .cast<Map<String, dynamic>>();
      dynamic produtosQuery = _client
          .from('produtos')
          .select('estoque, unidade_id');
      if (_unidadeId != null) {
        produtosQuery = produtosQuery.eq('unidade_id', _unidadeId!);
      }
      final produtos = ((await produtosQuery) as List)
          .cast<Map<String, dynamic>>();
      final hoje = DateTime.now();
      final inicio = hoje.subtract(Duration(days: _dias - 1));
      double soma(Iterable<Map<String, dynamic>> itens) =>
          itens.fold(0, (s, p) => s + ((p['total'] as num?)?.toDouble() ?? 0));
      final validos = pedidos.where((p) {
        final status = p['status'] as String? ?? '';
        return status != 'cancelado' && status != 'pendente';
      });
      final porStatus = <String, int>{};
      for (final p in pedidos) {
        final s = p['status'] as String? ?? 'pendente';
        porStatus[s] = (porStatus[s] ?? 0) + 1;
      }
      return {
        'vendas_hoje': soma(
          validos.where((p) {
            final d = DateTime.tryParse(p['created_at'] as String? ?? '');
            return d != null &&
                d.day == hoje.day &&
                d.month == hoje.month &&
                d.year == hoje.year;
          }),
        ),
        'vendas_7d': soma(
          validos.where((p) {
            final d = DateTime.tryParse(p['created_at'] as String? ?? '');
            return d != null &&
                d.isAfter(hoje.subtract(const Duration(days: 7)));
          }),
        ),
        'vendas_30d': soma(
          validos.where((p) {
            final d = DateTime.tryParse(p['created_at'] as String? ?? '');
            return d != null && d.isAfter(inicio);
          }),
        ),
        'pedidos_abertos': pedidos
            .where(
              (p) => const {
                'pendente',
                'pago',
                'em_preparo',
                'pronto_para_entrega',
                'saiu_para_entrega',
              }.contains(p['status']),
            )
            .length,
        'pedidos_hoje': pedidos.where((p) {
          final d = DateTime.tryParse(p['created_at'] as String? ?? '');
          return d != null &&
              d.day == hoje.day &&
              d.month == hoje.month &&
              d.year == hoje.year;
        }).length,
        'cancelados': pedidos.where((p) => p['status'] == 'cancelado').length,
        'estoque_baixo': produtos
            .where((p) => ((p['estoque'] as num?)?.toInt() ?? 0) <= 3)
            .length,
        'por_status': porStatus,
        'por_loja': const [],
        'top_produtos': const [],
        'serie_dias': const [],
        'clientes_novos': 0,
        'entregas_atrasadas': 0,
        'ticket_medio': validos.isEmpty ? 0 : soma(validos) / validos.length,
      };
    } catch (_) {
      return {};
    }
  }

  String _moeda(dynamic valor) {
    final v = (valor as num?)?.toDouble() ?? 0;
    return 'R\$ ${v.toStringAsFixed(2)}';
  }

  int _inteiro(dynamic valor) => (valor as num?)?.toInt() ?? 0;

  String _rotuloStatus(String s) {
    switch (s) {
      case 'pendente':
        return 'Aguardando';
      case 'pago':
        return 'Pagos';
      case 'em_preparo':
        return 'Em preparo';
      case 'pronto_para_entrega':
        return 'Prontos';
      case 'postado':
        return 'Postados';
      case 'em_transito':
        return 'Em trânsito';
      case 'saiu_para_entrega':
        return 'Em entrega';
      case 'entregue':
        return 'Entregues';
      case 'cancelado':
        return 'Cancelados';
      default:
        return s;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) return const Center(child: CircularProgressIndicator());

    final porStatus =
        (_dados['por_status'] as Map?)?.cast<String, dynamic>() ?? {};
    final porLoja = (_dados['por_loja'] as List?) ?? [];
    final topProdutos = (_dados['top_produtos'] as List?) ?? [];
    final serie = (_dados['serie_dias'] as List?) ?? [];

    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Visão geral',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _periodoDropdown(),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Atualizar',
                onPressed: _carregar,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          if (widget.permitirSelecionarLoja) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<int?>(
              value: _unidadeId,
              decoration: InputDecoration(
                labelText: 'Loja',
                isDense: true,
                filled: true,
                fillColor: ThemeColors.surface(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('Todas as lojas'),
                ),
                ..._unidades.map(
                  (u) => DropdownMenuItem<int?>(
                    value: (u['id'] as num).toInt(),
                    child: Text(u['nome'] as String? ?? 'Loja'),
                  ),
                ),
              ],
              onChanged: (v) {
                setState(() => _unidadeId = v);
                _carregar();
              },
            ),
          ],
          if (_erro != null) ...[
            const SizedBox(height: 8),
            Text(
              _erro!,
              style: TextStyle(
                fontSize: 11,
                color: ThemeColors.secondaryText(context),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _card(
                'Vendas hoje',
                _moeda(_dados['vendas_hoje']),
                Icons.payments_rounded,
                const Color(0xFF00A650),
              ),
              _card(
                'Vendas 7 dias',
                _moeda(_dados['vendas_7d']),
                Icons.trending_up_rounded,
                const Color(0xFF0084FF),
              ),
              _card(
                'Vendas $_dias dias',
                _moeda(_dados['vendas_30d']),
                Icons.bar_chart_rounded,
                const Color(0xFFE50914),
              ),
              _card(
                'Recebido (pagamentos)',
                _moeda(_dados['recebido_pagamentos']),
                Icons.account_balance_wallet_rounded,
                const Color(0xFF00A650),
              ),
              _card(
                'Pedidos abertos',
                '${_inteiro(_dados['pedidos_abertos'])}',
                Icons.receipt_long_rounded,
                const Color(0xFFFFAD01),
              ),
              _card(
                'Pedidos hoje',
                '${_inteiro(_dados['pedidos_hoje'])}',
                Icons.today_rounded,
                const Color(0xFF0084FF),
              ),
              _card(
                'Ticket médio',
                _moeda(_dados['ticket_medio']),
                Icons.confirmation_number_rounded,
                const Color(0xFF00A650),
              ),
              _card(
                'Cancelados',
                '${_inteiro(_dados['cancelados'])}',
                Icons.cancel_rounded,
                const Color(0xFFF23D4F),
              ),
              _card(
                'Estoque baixo',
                '${_inteiro(_dados['estoque_baixo'])}',
                Icons.inventory_2_rounded,
                const Color(0xFFFFAD01),
              ),
              _card(
                'Entregas atrasadas',
                '${_inteiro(_dados['entregas_atrasadas'])}',
                Icons.delivery_dining_rounded,
                const Color(0xFFF23D4F),
              ),
            ],
          ),
          if (serie.isNotEmpty) ...[
            const SizedBox(height: 20),
            _secao('Receita por dia'),
            const SizedBox(height: 8),
            _serieBars(serie),
          ],
          if (porStatus.isNotEmpty) ...[
            const SizedBox(height: 20),
            _secao('Pedidos por status'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: porStatus.entries
                  .map(
                    (e) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: ThemeColors.surfaceVariant(context),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${_rotuloStatus(e.key)}: ${_inteiro(e.value)}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          if (topProdutos.isNotEmpty) ...[
            const SizedBox(height: 20),
            _secao('Produtos mais vendidos'),
            const SizedBox(height: 8),
            ...topProdutos
                .take(8)
                .map(
                  (p) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.inventory_2_outlined, size: 20),
                    title: Text(p['nome'] as String? ?? 'Produto'),
                    trailing: Text(
                      '${_inteiro(p['quantidade'])} un • ${_moeda(p['receita'])}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
          ],
          if (porLoja.isNotEmpty) ...[
            const SizedBox(height: 20),
            _secao('Desempenho por loja'),
            const SizedBox(height: 8),
            ...porLoja.map(
              (l) => Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: ThemeColors.surface(context),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.storefront_rounded,
                      size: 18,
                      color: Color(0xFFE50914),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l['nome'] as String? ?? 'Loja',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      '${_inteiro(l['pedidos'])} pedidos • ${_moeda(l['receita'])}',
                      style: TextStyle(
                        fontSize: 11,
                        color: ThemeColors.secondaryText(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _periodoDropdown() {
    return DropdownButton<int>(
      value: _dias,
      underline: const SizedBox(),
      isDense: true,
      items: const [
        DropdownMenuItem(value: 7, child: Text('7 dias')),
        DropdownMenuItem(value: 30, child: Text('30 dias')),
        DropdownMenuItem(value: 90, child: Text('90 dias')),
      ],
      onChanged: (v) {
        if (v == null) return;
        setState(() => _dias = v);
        _carregar();
      },
    );
  }

  Widget _card(String titulo, String valor, IconData icone, Color cor) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ThemeColors.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 20, color: cor),
          const SizedBox(height: 8),
          Text(
            valor,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: cor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            titulo,
            style: TextStyle(
              fontSize: 10,
              color: ThemeColors.secondaryText(context),
            ),
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  Widget _secao(String titulo) {
    return Text(
      titulo,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
    );
  }

  Widget _serieBars(List serie) {
    final maiores = serie
        .map((d) => (d['total'] as num?)?.toDouble() ?? 0)
        .fold<double>(0, (a, b) => a > b ? a : b);
    return SizedBox(
      height: 120,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: serie.map((d) {
          final total = (d['total'] as num?)?.toDouble() ?? 0;
          final altura = maiores == 0 ? 2.0 : (total / maiores) * 90;
          final dia = (d['dia'] as String? ?? '').split('-');
          final rotulo = dia.length == 3 ? '${dia[2]}/${dia[1]}' : '';
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    height: altura.clamp(2.0, 90.0).toDouble(),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE50914).withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (serie.length <= 12)
                    Text(
                      rotulo,
                      style: const TextStyle(fontSize: 8),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
