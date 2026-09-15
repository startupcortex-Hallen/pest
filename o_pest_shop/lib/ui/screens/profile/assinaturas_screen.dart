import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/helpers/theme_colors.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/nutrition_service.dart';

class AssinaturasScreen extends StatefulWidget {
  const AssinaturasScreen({super.key});

  @override
  State<AssinaturasScreen> createState() => _AssinaturasScreenState();
}

class _AssinaturasScreenState extends State<AssinaturasScreen> {
  List<Map<String, dynamic>> _assinaturas = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final userId = context.read<AuthProvider>().user?.id;
    if (userId == null) return;
    try {
      _assinaturas = await NutritionService().fetchAssinaturas(userId);
    } catch (e) { debugPrint('Erro assinaturas: $e'); }
    if (mounted) setState(() => _loading = false);
  }

  Color _corPlano(String plano) {
    switch (plano) {
      case 'vip': return const Color(0xFFFFD700);
      case 'premium': return AppColors.primary;
      default: return AppColors.success;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeColors.background(context),
      appBar: AppBar(
        backgroundColor: ThemeColors.surface(context),
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => context.pop()),
        title: const Text('Minhas Assinaturas'),
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _assinaturas.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.card_membership_outlined, size: 64, color: ThemeColors.hint(context)),
                  const SizedBox(height: 16),
                  const Text('Nenhuma assinatura ativa'),
                  const SizedBox(height: 8),
                  TextButton(onPressed: () {}, child: const Text('Ver planos disponíveis')),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: _assinaturas.length,
              itemBuilder: (_, i) {
                final a = _assinaturas[i];
                final plano = a['plano'] as String? ?? 'basico';
                final status = a['status'] as String? ?? '';
                final bonus = a['bonus'] as bool? ?? false;
                return Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: ThemeColors.surface(context),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: status == 'ativo' ? _corPlano(plano).withValues(alpha: 0.3) : AppColors.divider),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(AppSpacing.md),
                    leading: Container(
                      width: 52, height: 52,
                      decoration: BoxDecoration(
                        color: _corPlano(plano).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        plano == 'vip' ? Icons.star_rounded : plano == 'premium' ? Icons.diamond_rounded : Icons.local_activity_rounded,
                        color: _corPlano(plano),
                      ),
                    ),
                    title: Row(
                      children: [
                        Text(plano.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold)),
                        if (bonus) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                            child: const Text('BÔNUS', style: TextStyle(fontSize: 9, color: AppColors.warning, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ],
                    ),
                    subtitle: Text(status == 'ativo' ? 'Ativo' : 'Cancelado', style: TextStyle(color: status == 'ativo' ? AppColors.success : AppColors.error)),
                    trailing: status == 'ativo'
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                          child: const Text('ATIVO', style: TextStyle(fontSize: 10, color: AppColors.success, fontWeight: FontWeight.w700)),
                        )
                      : null,
                  ),
                );
              },
            ),
    );
  }
}
