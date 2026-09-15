import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/plano_refeicao.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/nutrition_service.dart';

class PlanoNutricionalScreen extends StatefulWidget {
  const PlanoNutricionalScreen({super.key});

  @override
  State<PlanoNutricionalScreen> createState() => _PlanoNutricionalScreenState();
}

class _PlanoNutricionalScreenState extends State<PlanoNutricionalScreen> {
  List<PlanoRefeicao> _refeicoes = [];
  bool _loading = true;
  int _aguaHoje = 0;
  String _diaSelecionado = 'seg';
  final List<String> _dias = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final userId = context.read<AuthProvider>().user?.id;
    if (userId == null) return;

    try {
      final response = await Supabase.instance.client
          .from('plano_refeicoes')
          .select()
          .eq('user_id', userId)
          .eq('dia_semana', _diaSelecionado)
          .order('id');

      if (response is List) {
        _refeicoes = response.map((j) => PlanoRefeicao.fromJson(j as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      debugPrint('Erro carregar refeições: $e');
    }
    try {
      final agua = await Supabase.instance.client
        .from('agua_registro')
        .select('ml')
        .eq('user_id', userId)
        .eq('data', DateTime.now().toIso8601String().split('T')[0])
        .maybeSingle();
      if (agua != null) _aguaHoje = agua['ml'] as int? ?? 0;
    } catch (_) {}

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _alternarConcluido(int id, bool atual) async {
    await Supabase.instance.client
        .from('plano_refeicoes')
        .update({'concluido': !atual})
        .eq('id', id);
    _carregar();
  }

  Future<void> _registrarRefeicao() async {
    final nomeCtrl = TextEditingController();
    final caloriasCtrl = TextEditingController();
    final horarioCtrl = TextEditingController();

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nova Refeição'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nomeCtrl, decoration: const InputDecoration(labelText: 'Nome', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: caloriasCtrl, decoration: const InputDecoration(labelText: 'Calorias', border: OutlineInputBorder()), keyboardType: TextInputType.number),
            const SizedBox(height: 8),
            TextField(controller: horarioCtrl, decoration: const InputDecoration(labelText: 'Horário', border: OutlineInputBorder()),),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, {'nome': nomeCtrl.text.trim(), 'calorias': caloriasCtrl.text.trim(), 'horario': horarioCtrl.text.trim()}),
            child: const Text('Salvar', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );

    if (result == null) return;
    try {
      await Supabase.instance.client.from('plano_refeicoes').insert({
        'user_id': context.read<AuthProvider>().user?.id,
        'dia_semana': _diaSelecionado,
        'tipo': result['nome'],
        'horario': result['horario'],
        'calorias': int.tryParse(result['calorias'] ?? '') ?? 0,
        'descricao': result['nome'],
      });
      _carregar();
    } catch (e) { debugPrint('Erro registrar: $e'); }
  }

  IconData _iconeParaTipo(String tipo) {
    switch (tipo) {
      case 'Café da Manhã': return Icons.breakfast_dining_rounded;
      case 'Almoço': return Icons.lunch_dining_rounded;
      case 'Lanche da Tarde': return Icons.cookie_rounded;
      case 'Jantar': return Icons.dinner_dining_rounded;
      default: return Icons.restaurant_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalCalorias = _refeicoes.fold<int>(0, (sum, r) => sum + r.calorias);
    final proteinasG = (totalCalorias * 0.3 / 4).round();
    final carbosG = (totalCalorias * 0.45 / 4).round();
    final gordurasG = (totalCalorias * 0.25 / 9).round();
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // AppBar azul
          Container(
            padding: EdgeInsets.fromLTRB(AppSpacing.lg, MediaQuery.of(context).padding.top + AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
            decoration: const BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: AppColors.onPrimary),
                      onPressed: () => context.pop(),
                    ),
                    Text('Plano Nutricional',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.calendar_today_rounded, color: AppColors.onPrimary),
                      onPressed: () {},
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                // Card calorias
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkSurface : AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.2), blurRadius: 8, offset: const Offset(4, 4))],
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Calorias Diárias', style: TextStyle(color: AppColors.secondaryText, fontSize: 12)),
                              const SizedBox(height: 4),
                              Text('$totalCalorias / 2.200 kcal',
                                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.primaryText)),
                            ],
                          ),
                          SizedBox(
                            width: 56, height: 56,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                CircularProgressIndicator(
                                  value: (totalCalorias / 2200).clamp(0, 1),
                                  strokeWidth: 4,
                                  backgroundColor: AppColors.divider,
                                  color: AppColors.primary,
                                ),
                                const Center(
                                  child: Text('84%', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primary)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          _buildMacro('Proteínas', '${proteinasG}g / 150g', (proteinasG / 150).clamp(0, 1), AppColors.info, isDark),
                          const SizedBox(width: 12),
                          _buildMacro('Carbos', '${carbosG}g / 250g', (carbosG / 250).clamp(0, 1), AppColors.warning, isDark),
                          const SizedBox(width: 12),
                          _buildMacro('Gorduras', '${gordurasG}g / 65g', (gordurasG / 65).clamp(0, 1), AppColors.success, isDark),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Conteúdo scrollável
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                // Mês + navegação
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text(_mesAtual(),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primaryText)),
                        const SizedBox(width: 4),
                        const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.primaryText, size: 20),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left_rounded, color: AppColors.secondaryText),
                          onPressed: () {},
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right_rounded, color: AppColors.secondaryText),
                          onPressed: () {},
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                // Dias da semana
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _dias.map((dia) {
                      final selecionado = dia == _diaSelecionado;
                      return GestureDetector(
                        onTap: () {
                          setState(() => _diaSelecionado = dia);
                          _carregar();
                        },
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: selecionado ? AppColors.primary : AppColors.surfaceVariant,
                            borderRadius: BorderRadius.circular(10),
                            border: selecionado ? null : Border.all(color: AppColors.outline),
                          ),
                          child: Text(dia[0].toUpperCase() + dia.substring(1),
                              style: TextStyle(
                                color: selecionado ? AppColors.onPrimary : AppColors.primaryText,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              )),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                // Refeições
                if (!_loading) ...[
                  const Text('Refeições de Hoje',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primaryText)),
                  const SizedBox(height: AppSpacing.md),
                  if (_refeicoes.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
                      child: const Center(child: Text('Nenhuma refeição cadastrada para hoje.',
                          style: TextStyle(color: AppColors.secondaryText))),
                    )
                  else
                    ..._refeicoes.map((ref) => _buildMealCard(ref, isDark)),
                ] else
                  const Center(child: CircularProgressIndicator()),
                const SizedBox(height: AppSpacing.lg),
                // Card hidratação
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkSurface : AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 50, height: 50,
                        decoration: BoxDecoration(color: AppColors.info.withValues(alpha: 0.15), shape: BoxShape.circle),
                        child: const Icon(Icons.water_drop_rounded, color: AppColors.info, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Hidratação', style: TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text('${(_aguaHoje / 1000).toStringAsFixed(1)}L / 2.5L atingidos', style: TextStyle(fontSize: 12, color: AppColors.secondaryText)),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: LinearProgressIndicator(
                                value: (_aguaHoje / 2500).clamp(0, 1),
                                backgroundColor: AppColors.divider,
                                color: AppColors.info,
                                minHeight: 8,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: () async {
                          final userId = context.read<AuthProvider>().user?.id;
                          if (userId != null) {
                            await NutritionService().registrarAgua(userId, 250);
                            _carregar();
                          }
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.info,
                          side: const BorderSide(color: AppColors.info),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        child: const Text('+250ml', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _registrarRefeicao(),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Registrar'),
      ),
    );
  }

  String _mesAtual() {
    const meses = ['Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho', 'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'];
    return meses[DateTime.now().month - 1];
  }

  Widget _buildMacro(String label, String value, double progress, Color color, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: progress, backgroundColor: AppColors.divider, color: color, minHeight: 4,
              ),
            ),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 9, color: isDark ? AppColors.darkSecondaryText : AppColors.secondaryText)),
          ],
        ),
      ),
    );
  }

  Widget _buildMealCard(PlanoRefeicao ref, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.15), blurRadius: 6, offset: const Offset(3, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Icon(_iconeParaTipo(ref.tipo), color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(ref.tipo, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('${ref.calorias} kcal', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 13)),
                      ],
                    ),
                    Text(ref.horario, style: const TextStyle(color: AppColors.secondaryText, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(ref.descricao, style: TextStyle(color: isDark ? AppColors.darkSecondaryText : AppColors.secondaryText, fontSize: 13, height: 1.4)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: () => _alternarConcluido(ref.id, ref.concluido),
                icon: Icon(ref.concluido ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
                    size: 16, color: ref.concluido ? AppColors.success : AppColors.hint),
                label: Text(ref.concluido ? 'Feito' : 'Confirmar',
                    style: TextStyle(fontSize: 12, color: ref.concluido ? AppColors.success : AppColors.hint)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
