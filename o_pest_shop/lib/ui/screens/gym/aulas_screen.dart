import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/helpers/theme_colors.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/aula.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/gym_service.dart';

class AulasScreen extends StatefulWidget {
  const AulasScreen({super.key});

  @override
  State<AulasScreen> createState() => _AulasScreenState();
}

class _AulasScreenState extends State<AulasScreen> {
  final _service = GymService();
  List<Aula> _aulas = [];
  List<bool> _inscrito = [];
  bool _loading = true;
  final _dias = ['seg', 'ter', 'qua', 'qui', 'sex', 'sab', 'dom'];
  String _diaSelecionado = DateTime.now().weekday <= 7 ? ['dom','seg','ter','qua','qui','sex','sab'][DateTime.now().weekday] : 'seg';

  @override
  void initState() { super.initState(); _carregar(); }

  Future<void> _carregar() async {
    final userId = context.read<AuthProvider>().user?.id;
    final unidadeId = context.read<AuthProvider>().user?.unidadeId ?? 1;
    try {
      _aulas = (await _service.fetchAulas(unidadeId)).map((j) => Aula.fromJson(j)).toList();
      _inscrito = await Future.wait(_aulas.map((a) => _service.checkInscricao(a.id, userId ?? '', DateTime.now().toIso8601String().split('T')[0])));
    } catch (e) { debugPrint('Erro aulas: $e'); }
    if (mounted) setState(() => _loading = false);
  }

  String _nomeDia(String d) => ({'seg':'Seg','ter':'Ter','qua':'Qua','qui':'Qui','sex':'Sex','sab':'Sáb','dom':'Dom'})[d] ?? d;

  @override
  Widget build(BuildContext context) {
    final filtradas = _aulas.where((a) => a.diaSemana == _diaSelecionado).toList();
    return Scaffold(
      backgroundColor: ThemeColors.background(context),
      appBar: AppBar(backgroundColor: ThemeColors.surface(context), leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => context.pop()), title: const Text('Agenda de Aulas')),
      body: _loading ? const Center(child: CircularProgressIndicator()) : Column(
        children: [
          Container(
            height: 60,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ListView.builder(
              scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _dias.length,
              itemBuilder: (_, i) {
                final dia = _dias[i];
                final sel = dia == _diaSelecionado;
                return GestureDetector(
                  onTap: () => setState(() => _diaSelecionado = dia),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: sel ? AppColors.primary : ThemeColors.surfaceVariant(context),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(_nomeDia(dia), style: TextStyle(color: sel ? Colors.white : ThemeColors.primaryText(context), fontWeight: FontWeight.w600)),
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: filtradas.isEmpty
              ? const Center(child: Text('Nenhuma aula neste dia'))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: filtradas.length,
                  itemBuilder: (_, i) {
                    final a = filtradas[i];
                    final idx = _aulas.indexOf(a);
                    final inscrito = idx < _inscrito.length && _inscrito[idx];
                    final lotado = a.vagasOcupadas >= a.vagas;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(color: ThemeColors.surface(context), borderRadius: BorderRadius.circular(16)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: Container(
                          width: 52, height: 52,
                          decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
                          child: const Icon(Icons.fitness_center_rounded, color: AppColors.primary),
                        ),
                        title: Text(a.nome, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${a.horario}  •  ${a.instrutor}', style: TextStyle(color: ThemeColors.secondaryText(context), fontSize: 12)),
                            Text('${a.vagas - a.vagasOcupadas} vagas', style: TextStyle(fontSize: 11, color: lotado ? AppColors.error : AppColors.success)),
                          ],
                        ),
                        trailing: inscrito
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                              child: const Text('INSCRITO', style: TextStyle(fontSize: 10, color: AppColors.success, fontWeight: FontWeight.w700)),
                            )
                          : ElevatedButton(
                              onPressed: lotado ? null : () async {
                                final userId = context.read<AuthProvider>().user?.id;
                                if (userId == null) return;
                                await _service.inscreverAula(a.id, userId, DateTime.now().toIso8601String().split('T')[0]);
                                _carregar();
                              },
                              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
                              child: Text(lotado ? 'Lotada' : 'Inscrever', style: const TextStyle(fontSize: 11)),
                            ),
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
}
