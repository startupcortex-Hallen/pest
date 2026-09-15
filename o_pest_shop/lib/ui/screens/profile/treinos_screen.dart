import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/helpers/theme_colors.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/treino.dart';
import '../../../models/exercicio.dart';
import '../../../providers/auth_provider.dart';

class TreinosScreen extends StatefulWidget {
  const TreinosScreen({super.key});

  @override
  State<TreinosScreen> createState() => _TreinosScreenState();
}

class _TreinosScreenState extends State<TreinosScreen> {
  List<Treino> _treinos = [];
  Map<int, List<Exercicio>> _exercicios = {};
  bool _loading = true;
  int? _treinoExpandido;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final userId = context.read<AuthProvider>().user?.id;
    if (userId == null) return;
    try {
      final r = await Supabase.instance.client
        .from('treinos')
        .select('*, exercicios(*)')
        .eq('user_id', userId)
        .order('ordem');
      if (r is List) {
        for (final t in r) {
          final treino = Treino.fromJson(t as Map<String, dynamic>);
          _treinos.add(treino);
          final exs = (t['exercicios'] as List?) ?? [];
          _exercicios[treino.id] = exs.map((e) => Exercicio.fromJson(e as Map<String, dynamic>)).toList();
        }
      }
    } catch (e) { debugPrint('Erro treinos: $e'); }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _alternarConcluido(int exercicioId, bool atual) async {
    await Supabase.instance.client.from('exercicios').update({'concluido': !atual}).eq('id', exercicioId);
    _carregar();
  }

  String _nomeDia(String dia) {
    const nomes = {'seg': 'Segunda', 'ter': 'Terça', 'qua': 'Quarta', 'qui': 'Quinta', 'sex': 'Sexta', 'sab': 'Sábado', 'dom': 'Domingo'};
    return nomes[dia] ?? dia;
  }

  IconData _iconeMusculo(String? grupo) {
    switch (grupo?.toLowerCase()) {
      case 'peito': return Icons.fitness_center_rounded;
      case 'costas': return Icons.accessibility_new_rounded;
      case 'perna': return Icons.directions_run_rounded;
      case 'braço': case 'braco': return Icons.fitness_center_rounded;
      case 'ombro': return Icons.self_improvement_rounded;
      default: return Icons.fitness_center_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeColors.background(context),
      appBar: AppBar(
        backgroundColor: ThemeColors.surface(context),
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => context.pop()),
        title: const Text('Meus Treinos'),
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _treinos.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fitness_center_rounded, size: 64, color: ThemeColors.hint(context)),
                  const SizedBox(height: 16),
                  const Text('Nenhum treino cadastrado'),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: _treinos.length,
              itemBuilder: (_, i) {
                final t = _treinos[i];
                final exs = _exercicios[t.id] ?? [];
                final expandido = _treinoExpandido == t.id;
                final concluidos = exs.where((e) => e.concluido).length;
                return Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: ThemeColors.surface(context),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        onTap: () => setState(() => _treinoExpandido = expandido ? null : t.id),
                        leading: Container(
                          width: 48, height: 48,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.fitness_center_rounded, color: AppColors.primary),
                        ),
                        title: Text(t.nome, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Row(
                          children: [
                            Text(_nomeDia(t.diaSemana), style: TextStyle(fontSize: 12, color: ThemeColors.secondaryText(context))),
                            const SizedBox(width: 8),
                            if (exs.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                                child: Text('$concluidos/${exs.length}', style: TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w600)),
                              ),
                          ],
                        ),
                        trailing: Icon(expandido ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: ThemeColors.hint(context)),
                      ),
                      if (expandido && exs.isNotEmpty)
                        ...exs.map((e) => Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Container(
                            decoration: BoxDecoration(
                              color: ThemeColors.surfaceVariant(context),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: ListTile(
                              dense: true,
                              leading: Icon(
                                e.concluido ? Icons.check_circle_rounded : Icons.panorama_fish_eye_rounded,
                                color: e.concluido ? AppColors.success : ThemeColors.hint(context),
                                size: 22,
                              ),
                              title: Text(e.nome, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, decoration: e.concluido ? TextDecoration.lineThrough : null)),
                              subtitle: Text(
                                '${e.series}x${e.repeticoes}${e.aparelho != null ? '  •  ${e.aparelho}' : ''}${e.cargaSugerida != null ? '  •  ${e.cargaSugerida}' : ''}',
                                style: TextStyle(fontSize: 11, color: ThemeColors.secondaryText(context)),
                              ),
                              onTap: () => _alternarConcluido(e.id, e.concluido),
                            ),
                          ),
                        )),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
