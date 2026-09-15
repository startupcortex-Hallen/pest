import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/helpers/theme_colors.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/gym_service.dart';

class PersonalScreen extends StatefulWidget {
  const PersonalScreen({super.key});

  @override
  State<PersonalScreen> createState() => _PersonalScreenState();
}

class _PersonalScreenState extends State<PersonalScreen> {
  final _service = GymService();
  List<Map<String, dynamic>> _personais = [];
  List<Map<String, dynamic>> _sessoes = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _carregar(); }

  Future<void> _carregar() async {
    final userId = context.read<AuthProvider>().user?.id;
    final unidadeId = context.read<AuthProvider>().user?.unidadeId ?? 1;
    if (userId == null) return;
    try {
      _personais = await _service.fetchPersonais(unidadeId);
      _sessoes = await _service.fetchMinhasSessoes(userId);
    } catch (e) { debugPrint('Erro personal: $e'); }
    if (mounted) setState(() => _loading = false);
  }

  void _agendar(Map<String, dynamic> personal) {
    final dataCtrl = TextEditingController();
    showDialog(
      context: context, builder: (ctx) => AlertDialog(
        title: Text('Agendar com ${personal['nome']}'),
        content: TextField(controller: dataCtrl, decoration: const InputDecoration(labelText: 'Data e hora (YYYY-MM-DD HH:MM)', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(onPressed: () async {
            final userId = context.read<AuthProvider>().user?.id;
            if (userId != null && dataCtrl.text.isNotEmpty) {
              await _service.agendarPersonal({'unidade_id': context.read<AuthProvider>().user?.unidadeId ?? 1, 'personal_id': personal['id'], 'aluno_id': userId, 'data_hora': dataCtrl.text});
              if (ctx.mounted) Navigator.pop(ctx);
              _carregar();
            }
          }, child: const Text('Confirmar', style: TextStyle(color: AppColors.primary))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeColors.background(context),
      appBar: AppBar(backgroundColor: ThemeColors.surface(context), leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => context.pop()), title: const Text('Personal Trainer')),
      body: _loading ? const Center(child: CircularProgressIndicator()) : ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          const Text('Profissionais Disponíveis', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          if (_personais.isEmpty) const Text('Nenhum personal disponível'),
          ..._personais.map((p) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(color: ThemeColors.surface(context), borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: CircleAvatar(child: Text((p['nome'] as String? ?? '?')[0].toUpperCase())),
              title: Text(p['nome'] as String? ?? ''),
              trailing: ElevatedButton(onPressed: () => _agendar(p), child: const Text('Agendar', style: TextStyle(fontSize: 12))),
            ),
          )),
          const SizedBox(height: 24),
          const Text('Minhas Sessões', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          if (_sessoes.isEmpty) const Text('Nenhuma sessão agendada'),
          ..._sessoes.map((s) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(color: ThemeColors.surface(context), borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: (s['status'] == 'concluida' ? AppColors.success : AppColors.primary).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.person_rounded, color: s['status'] == 'concluida' ? AppColors.success : AppColors.primary)),
              title: Text('${s['data_hora'] as String? ?? ''}', style: const TextStyle(fontSize: 14)),
              subtitle: Text(s['status'] as String? ?? '', style: const TextStyle(fontSize: 11)),
              trailing: s['status'] == 'concluida'
                ? const Icon(Icons.check_circle_rounded, color: AppColors.success)
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                    child: const Text('PENDENTE', style: TextStyle(fontSize: 9, color: AppColors.warning, fontWeight: FontWeight.w700))),
            ),
          )),
        ],
      ),
    );
  }
}
