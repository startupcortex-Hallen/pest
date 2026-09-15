import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/helpers/theme_colors.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/helpers/scale_helper.dart';
import '../../../models/nutricionista.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/nutrition_service.dart';

class NutricionistasScreen extends StatefulWidget {
  const NutricionistasScreen({super.key});

  @override
  State<NutricionistasScreen> createState() => _NutricionistasScreenState();
}

class _NutricionistasScreenState extends State<NutricionistasScreen> {
  final _service = NutritionService();
  List<Nutricionista> _nutricionistas = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final data = await _service.fetchNutricionistas();
      _nutricionistas = data.map((j) => Nutricionista.fromJson(j)).toList();
    } catch (e) { debugPrint('Erro nutricionistas: $e'); }
    if (mounted) setState(() => _loading = false);
  }

  void _agendar(Nutricionista n) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Agendar com ${n.nome}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Preço: R\$ ${n.precoConsulta?.toStringAsFixed(2) ?? '0,00'}'),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                labelText: 'Data e hora (YYYY-MM-DD HH:MM)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(
            onPressed: () async {
              final userId = context.read<AuthProvider>().user?.id;
              if (userId != null && ctrl.text.isNotEmpty) {
                await _service.agendarConsulta(userId, n.id, ctrl.text);
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Consulta agendada!')));
              }
            },
            child: const Text('Confirmar', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeColors.background(context),
      appBar: AppBar(
        backgroundColor: ThemeColors.surface(context),
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => context.pop()),
        title: const Text('Nutricionistas'),
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _nutricionistas.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.medical_services_rounded, size: 64, color: ThemeColors.hint(context)),
                  const SizedBox(height: 16),
                  const Text('Nenhum nutricionista disponível'),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: _nutricionistas.length,
              itemBuilder: (_, i) {
                final n = _nutricionistas[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: ThemeColors.surface(context),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(AppSpacing.md),
                    leading: CircleAvatar(
                      radius: context.w(28).clamp(22, 36),
                      backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                      backgroundImage: n.avatarUrl != null ? NetworkImage(n.avatarUrl!) : null,
                      child: n.avatarUrl == null
                        ? Text(n.nome.isNotEmpty ? n.nome[0].toUpperCase() : 'N', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold))
                        : null,
                    ),
                    title: Text(n.nome, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (n.crn != null) Text('CRN: ${n.crn}', style: const TextStyle(fontSize: 12, color: AppColors.secondaryText)),
                        if (n.bio != null) Text(n.bio!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.hint)),
                      ],
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('R\$ ${n.precoConsulta?.toStringAsFixed(2) ?? '0,00'}', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 32,
                          child: ElevatedButton(
                            onPressed: () => _agendar(n),
                            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12)),
                            child: const Text('Agendar', style: TextStyle(fontSize: 11)),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
