import 'package:flutter/material.dart';
import '../../../../core/helpers/theme_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../services/admin_service.dart';
import '../../../widgets/animated_card_entry.dart';
import '../admin_utils.dart';
import '../widgets/admin_usuario_picker.dart';

class TreinosTab extends StatefulWidget {
  const TreinosTab({super.key});

  @override
  State<TreinosTab> createState() => _TreinosTabState();
}

class _TreinosTabState extends State<TreinosTab> {
  final _service = AdminService();
  List<Map<String, dynamic>> _treinos = [];
  bool _loading = true;
  final Set<int> _expandidos = {};
  static const _dias = ['seg', 'ter', 'qua', 'qui', 'sex', 'sab', 'dom'];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    try {
      _treinos = await _service.fetchTreinos();
    } catch (e) {
      debugPrint('Erro treinos: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _mostrarFormTreino({Map<String, dynamic>? treino}) async {
    Map<String, dynamic>? usuario = treino != null
        ? {
            'id': treino['user_id'],
            'nome': treino['perfis'] is Map
                ? (treino['perfis'] as Map)['nome']
                : 'Usuário ${treino['user_id']}',
          }
        : null;
    String? dia = treino?['dia_semana'] as String?;
    final nomeCtrl = TextEditingController(text: treino?['nome'] as String? ?? '');
    final ordemCtrl = TextEditingController(text: treino?['ordem']?.toString() ?? '');

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              left: 24,
              right: 24,
              top: 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(treino != null ? 'Editar Treino' : 'Novo Treino',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  AdminCampoSelecao(
                    label: 'Usuário',
                    valor: usuario?['nome'] as String? ?? 'Selecionar',
                    erro: usuario == null,
                    onTap: () async {
                      final u = await AdminUsuarioPicker.show(context);
                      if (u != null) setSheetState(() => usuario = u);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nomeCtrl,
                    decoration: adminInputDec(context, 'Nome do treino', hint: 'Ex: Treino A - Inferiores'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _dias.contains(dia) ? dia : null,
                    decoration: adminInputDec(context, 'Dia da semana'),
                    items: _dias.map((d) => DropdownMenuItem(value: d, child: Text(nomeDiaSemana(d)))).toList(),
                    onChanged: (v) => setSheetState(() => dia = v),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: ordemCtrl,
                    decoration: adminInputDec(context, 'Ordem', hint: 'Ex: 1'),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFC6C6C6),
                            side: const BorderSide(color: Color(0xFF9C9C9C)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () {
                            String? erro;
                            if (usuario == null) {
                              erro = 'Selecione um usuário.';
                            } else if (nomeCtrl.text.trim().isEmpty) {
                              erro = 'Informe o nome do treino.';
                            } else if (dia == null) {
                              erro = 'Selecione o dia da semana.';
                            }
                            if (erro != null) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erro)));
                              return;
                            }
                            Navigator.pop(ctx, {
                              'user_id': usuario!['id'],
                              'nome': nomeCtrl.text.trim(),
                              'dia_semana': dia,
                              'ordem': int.tryParse(ordemCtrl.text.trim()) ?? 0,
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE50914),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text(treino != null ? 'Salvar' : 'Criar Treino'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (result == null) return;
    try {
      if (treino != null) {
        await _service.updateTreino(treino['id'] as int, result);
      } else {
        await _service.insertTreino(result);
      }
      _carregar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mapErroAdmin(e))));
    }
  }

  Future<void> _excluirTreino(Map<String, dynamic> t) async {
    if (!await confirmarExclusao(context, titulo: 'Excluir treino')) return;
    try {
      await _service.deleteTreino(t['id'] as int);
      _carregar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mapErroAdmin(e))));
    }
  }

  Future<void> _mostrarFormExercicio(Map<String, dynamic> treino, {Map<String, dynamic>? exercicio}) async {
    final nomeCtrl = TextEditingController(text: exercicio?['nome'] as String? ?? '');
    final aparelhoCtrl = TextEditingController(text: exercicio?['aparelho'] as String? ?? '');
    final grupoCtrl = TextEditingController(text: exercicio?['grupo_muscular'] as String? ?? '');
    final seriesCtrl = TextEditingController(text: exercicio?['series']?.toString() ?? '4');
    final repsCtrl = TextEditingController(text: exercicio?['repeticoes'] as String? ?? '8-12');
    final cargaCtrl = TextEditingController(text: exercicio?['carga_sugerida'] as String? ?? '');
    final ordemCtrl = TextEditingController(text: exercicio?['ordem']?.toString() ?? '');

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 24,
            right: 24,
            top: 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(exercicio != null ? 'Editar Exercício' : 'Novo Exercício',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                TextField(controller: nomeCtrl, decoration: adminInputDec(context, 'Nome', hint: 'Ex: Agachamento')), 
                const SizedBox(height: 12),
                TextField(controller: aparelhoCtrl, decoration: adminInputDec(context, 'Aparelho', hint: 'Ex: Smith')),
                const SizedBox(height: 12),
                TextField(controller: grupoCtrl, decoration: adminInputDec(context, 'Grupo muscular', hint: 'Ex: Pernas')),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: seriesCtrl,
                        decoration: adminInputDec(context, 'Séries'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: repsCtrl,
                        decoration: adminInputDec(context, 'Repetições', hint: 'Ex: 8-12'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: cargaCtrl,
                        decoration: adminInputDec(context, 'Carga sugerida', hint: 'Ex: 20kg'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: ordemCtrl,
                        decoration: adminInputDec(context, 'Ordem'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFC6C6C6),
                          side: const BorderSide(color: Color(0xFF9C9C9C)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Cancelar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: () {
                          if (nomeCtrl.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Informe o nome do exercício.')));
                            return;
                          }
                          Navigator.pop(ctx, {
                            'nome': nomeCtrl.text.trim(),
                            'aparelho': aparelhoCtrl.text.trim(),
                            'grupo_muscular': grupoCtrl.text.trim(),
                            'series': int.tryParse(seriesCtrl.text.trim()) ?? 4,
                            'repeticoes': repsCtrl.text.trim().isEmpty ? '8-12' : repsCtrl.text.trim(),
                            'carga_sugerida': cargaCtrl.text.trim(),
                            'ordem': int.tryParse(ordemCtrl.text.trim()) ?? 0,
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE50914),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(exercicio != null ? 'Salvar' : 'Adicionar'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );

    if (result == null) return;
    try {
      if (exercicio != null) {
        await _service.updateExercicio(exercicio['id'] as int, result);
      } else {
        await _service.insertExercicio({'treino_id': treino['id'], ...result});
      }
      _carregar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mapErroAdmin(e))));
    }
  }

  Future<void> _excluirExercicio(Map<String, dynamic> exercicio) async {
    if (!await confirmarExclusao(context, titulo: 'Excluir exercício')) return;
    try {
      await _service.deleteExercicio(exercicio['id'] as int);
      _carregar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mapErroAdmin(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return _loading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () => _mostrarFormTreino(),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Novo Treino'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ThemeColors.primary(context),
                      foregroundColor: ThemeColors.onPrimary(context),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _treinos.isEmpty
                    ? Center(
                        child: Text('Nenhum treino cadastrado',
                            style: TextStyle(color: ThemeColors.secondaryText(context))))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 24),
                        itemCount: _treinos.length,
                        itemBuilder: (context, index) {
                          final t = _treinos[index];
                          final perfil = t['perfis'] is Map ? (t['perfis'] as Map) : null;
                          final exercicios = (t['exercicios'] as List?) ?? [];
                          final expandido = _expandidos.contains(t['id']);
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
                                      backgroundColor: ThemeColors.primary(context).withValues(alpha: 0.1),
                                      child: Icon(Icons.fitness_center_rounded,
                                          color: ThemeColors.primary(context), size: 20),
                                    ),
                                    title: Text(t['nome'] as String? ?? '', maxLines: 1),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            '${nomeDiaSemana(t['dia_semana'] as String?)}  •  ${exercicios.length} exercícios',
                                            style:
                                                TextStyle(fontSize: 11, color: ThemeColors.secondaryText(context))),
                                        Text(perfil?['nome'] as String? ?? '',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: ThemeColors.primary(context),
                                                fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: Icon(Icons.edit_rounded, color: ThemeColors.info(context)),
                                          onPressed: () => _mostrarFormTreino(treino: t),
                                        ),
                                        IconButton(
                                          icon: Icon(Icons.delete_outline_rounded, color: ThemeColors.error(context)),
                                          onPressed: () => _excluirTreino(t),
                                        ),
                                      ],
                                    ),
                                    onTap: () => setState(() {
                                      if (!_expandidos.add(t['id'] as int)) _expandidos.remove(t['id'] as int);
                                    }),
                                  ),
                                  if (expandido) ...[
                                    Divider(height: 1, color: ThemeColors.divider(context)),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 8, AppSpacing.md, 12),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          ...exercicios.map((ex) => Container(
                                                margin: const EdgeInsets.only(bottom: 6),
                                                decoration: BoxDecoration(
                                                  color: ThemeColors.surfaceVariant(context),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: ListTile(
                                                  dense: true,
                                                  leading: const Icon(Icons.sports_gymnastics_rounded, size: 20),
                                                  title: Text(ex['nome'] as String? ?? '',
                                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                                  subtitle: Text(
                                                      '${ex['series'] ?? ''}x ${ex['repeticoes'] ?? ''}  •  ${ex['aparelho'] ?? ''}${(ex['carga_sugerida'] != null && (ex['carga_sugerida'] as String).isNotEmpty) ? '  •  ${ex['carga_sugerida']}' : ''}',
                                                      style: TextStyle(
                                                          fontSize: 11, color: ThemeColors.secondaryText(context))),
                                                  trailing: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      IconButton(
                                                        iconSize: 18,
                                                        icon: Icon(Icons.edit_rounded,
                                                            color: ThemeColors.info(context), size: 16),
                                                        onPressed: () =>
                                                            _mostrarFormExercicio(t, exercicio: ex),
                                                      ),
                                                      IconButton(
                                                        iconSize: 18,
                                                        icon: Icon(Icons.delete_outline_rounded,
                                                            color: ThemeColors.error(context), size: 16),
                                                        onPressed: () => _excluirExercicio(ex),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              )),
                                          TextButton.icon(
                                            onPressed: () => _mostrarFormExercicio(t),
                                            icon: const Icon(Icons.add_rounded, size: 18),
                                            label: const Text('Adicionar Exercício'),
                                            style: TextButton.styleFrom(
                                                foregroundColor: ThemeColors.primary(context)),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
  }
}
