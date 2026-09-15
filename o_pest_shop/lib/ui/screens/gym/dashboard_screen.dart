import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/helpers/theme_colors.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/gym_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _service = GymService();
  Map<String, dynamic>? _dados;
  bool _loading = true;

  @override
  void initState() { super.initState(); _carregar(); }

  Future<void> _carregar() async {
    final unidadeId = context.read<AuthProvider>().user?.unidadeId ?? 1;
    try { _dados = await _service.fetchDashboard(unidadeId); } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeColors.background(context),
      appBar: AppBar(backgroundColor: ThemeColors.surface(context), leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => context.pop()), title: const Text('Dashboard')),
      body: _loading ? const Center(child: CircularProgressIndicator()) : ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Row(children: [
            Expanded(child: _card('Alunos', '${_dados?['alunos'] ?? '-'}', Icons.people_rounded, AppColors.info)),
            const SizedBox(width: 12),
            Expanded(child: _card('Aulas Hoje', '${_dados?['aulas_hoje'] ?? '-'}', Icons.event_rounded, AppColors.success)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _card('Receita do Mês', 'R\$ ${(_dados?['receita_mes'] as num?)?.toStringAsFixed(2) ?? '0,00'}', Icons.monetization_on_rounded, AppColors.warning)),
            const SizedBox(width: 12),
            Expanded(child: _card('Unidade', '${context.watch<AuthProvider>().user?.unidadeNome ?? '-'}', Icons.store_rounded, AppColors.primary)),
          ]),
          const SizedBox(height: 24),
          const Text('Acesso Rápido', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          _botao(Icons.event_rounded, 'Agenda de Aulas', '/aulas'),
          _botao(Icons.person_rounded, 'Personal Trainer', '/personal'),
          _botao(Icons.monitor_heart_outlined, 'Avaliações', '/avaliacao'),
          _botao(Icons.trending_up_rounded, 'Meu Progresso', '/progresso'),
          _botao(Icons.emoji_events_rounded, 'Desafios', '/desafios'),
          _botao(Icons.card_giftcard_rounded, 'Indique e Ganhe', '/indicacao'),
          _botao(Icons.chat_rounded, 'Chat', '/conversas'),
        ],
      ),
    );
  }

  Widget _card(String label, String valor, IconData icone, Color cor) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: ThemeColors.surface(context), borderRadius: BorderRadius.circular(16)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icone, color: cor, size: 28),
      const SizedBox(height: 8),
      Text(valor, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: cor)),
      Text(label, style: TextStyle(fontSize: 12, color: ThemeColors.secondaryText(context))),
    ]),
  );

  Widget _botao(IconData icone, String label, String rota) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      onTap: () => context.push(rota),
      leading: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
        child: Icon(icone, color: AppColors.primary),
      ),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: const Icon(Icons.chevron_right_rounded),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      tileColor: ThemeColors.surface(context),
    ),
  );
}
