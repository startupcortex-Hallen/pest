import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/helpers/theme_colors.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/gym_service.dart';

class DesafiosScreen extends StatefulWidget {
  const DesafiosScreen({super.key});

  @override
  State<DesafiosScreen> createState() => _DesafiosScreenState();
}

class _DesafiosScreenState extends State<DesafiosScreen> {
  final _service = GymService();
  List<Map<String, dynamic>> _desafios = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _carregar(); }

  Future<void> _carregar() async {
    final unidadeId = context.read<AuthProvider>().user?.unidadeId ?? 1;
    try { _desafios = await _service.fetchDesafios(unidadeId); } catch (e) { debugPrint('Erro desafios: $e'); }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final userId = context.watch<AuthProvider>().user?.id;
    return Scaffold(
      backgroundColor: ThemeColors.background(context),
      appBar: AppBar(backgroundColor: ThemeColors.surface(context), leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => context.pop()), title: const Text('Desafios')),
      body: _loading ? const Center(child: CircularProgressIndicator()) : ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: _desafios.map((d) {
          final participantes = (d['desafios_participantes'] as List?) ?? [];
          final participando = userId != null && participantes.any((p) => (p as Map)['user_id'] == userId);
          int meuProgresso = 0;
          if (userId != null) {
            final meu = participantes.cast<Map<String, dynamic>>().where((p) => p['user_id'] == userId).toList();
            if (meu.isNotEmpty) meuProgresso = meu.first['progresso'] as int? ?? 0;
          }
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [AppColors.primary.withValues(alpha: 0.1), AppColors.primary.withValues(alpha: 0.05)]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.emoji_events_rounded, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(d['nome'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text('${participantes.length} participantes', style: TextStyle(fontSize: 12, color: ThemeColors.secondaryText(context))),
                ])),
              ]),
              const SizedBox(height: 12),
              if (d['descricao'] != null) Text(d['descricao'] as String, style: TextStyle(color: ThemeColors.secondaryText(context))),
              const SizedBox(height: 12),
              if (participando) ...[
                ClipRRect(borderRadius: BorderRadius.circular(10), child: LinearProgressIndicator(value: (meuProgresso / ((d['meta'] as num?)?.toDouble() ?? 1)).clamp(0, 1), minHeight: 8, backgroundColor: AppColors.divider, color: AppColors.success)),
                const SizedBox(height: 4),
                Text('$meuProgresso / ${d['meta']}', style: TextStyle(fontSize: 11, color: ThemeColors.secondaryText(context))),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: double.infinity, height: 40,
                child: ElevatedButton(
                  onPressed: participando ? null : () async {
                    final uid = context.read<AuthProvider>().user?.id;
                    if (uid != null) { await _service.participarDesafio(d['id'] as int, uid); _carregar(); }
                  },
                  child: Text(participando ? 'Participando' : 'Participar'),
                ),
              ),
            ]),
          );
        }).toList(),
      ),
    );
  }
}
