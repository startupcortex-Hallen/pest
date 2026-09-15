import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/helpers/theme_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../services/admin_service.dart';
import '../../../widgets/animated_card_entry.dart';
import '../admin_utils.dart';

class AulasTab extends StatefulWidget {
  const AulasTab({super.key});

  @override
  State<AulasTab> createState() => _AulasTabState();
}

class _AulasTabState extends State<AulasTab> {
  final _service = AdminService();
  List<Map<String, dynamic>> _aulas = [];
  List<Map<String, dynamic>> _unidades = [];
  bool _loading = true;

  static const _dias = ['seg', 'ter', 'qua', 'qui', 'sex', 'sab', 'dom'];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    try {
      final resultados = await Future.wait([
        _service.fetchAulasAdmin(),
        Supabase.instance.client.from('unidades').select('id, nome, bairro').order('nome'),
      ]);
      _aulas = resultados[0];
      _unidades = resultados[1];
    } catch (e) {
      debugPrint('Erro aulas: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _mostrarForm({Map<String, dynamic>? aula}) async {
    String? dia = aula?['dia_semana'] as String?;
    int? unidadeId = aula?['unidade_id'] as int?;
    final nomeCtrl = TextEditingController(text: aula?['nome'] as String? ?? '');
    final instrutorCtrl = TextEditingController(text: aula?['instrutor'] as String? ?? '');
    final horarioCtrl = TextEditingController(text: aula?['horario'] as String? ?? '');
    final duracaoCtrl = TextEditingController(text: aula?['duracao']?.toString() ?? '60');
    final vagasCtrl = TextEditingController(text: aula?['vagas']?.toString() ?? '20');
    final descCtrl = TextEditingController(text: aula?['descricao'] as String? ?? '');

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
                  Text(aula != null ? 'Editar Aula' : 'Nova Aula',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextField(controller: nomeCtrl, decoration: adminInputDec(context, 'Nome da aula', hint: 'Ex: Spinning')),
                  const SizedBox(height: 12),
                  TextField(controller: instrutorCtrl, decoration: adminInputDec(context, 'Instrutor')),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _dias.contains(dia) ? dia : null,
                    decoration: adminInputDec(context, 'Dia da semana'),
                    items: _dias.map((d) => DropdownMenuItem(value: d, child: Text(nomeDiaSemana(d)))).toList(),
                    onChanged: (v) => setSheetState(() => dia = v),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: horarioCtrl,
                          decoration: adminInputDec(context, 'Horário', hint: 'Ex: 19:00'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: duracaoCtrl,
                          decoration: adminInputDec(context, 'Duração (min)'),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: vagasCtrl,
                          decoration: adminInputDec(context, 'Vagas'),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: unidadeId != null && _unidades.any((u) => u['id'] == unidadeId) ? unidadeId : null,
                          decoration: adminInputDec(context, 'Unidade'),
                          items: _unidades
                              .map((u) => DropdownMenuItem(value: u['id'] as int, child: Text(u['nome'] as String)))
                              .toList(),
                          onChanged: (v) => setSheetState(() => unidadeId = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    maxLines: 3,
                    decoration: adminInputDec(context, 'Descrição'),
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
                            if (nomeCtrl.text.trim().isEmpty) {
                              erro = 'Informe o nome da aula.';
                            } else if (dia == null) {
                              erro = 'Selecione o dia da semana.';
                            } else if (unidadeId == null) {
                              erro = 'Selecione a unidade.';
                            }
                            if (erro != null) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erro)));
                              return;
                            }
                            Navigator.pop(ctx, {
                              'nome': nomeCtrl.text.trim(),
                              'instrutor': instrutorCtrl.text.trim(),
                              'dia_semana': dia,
                              'horario': horarioCtrl.text.trim(),
                              'duracao': int.tryParse(duracaoCtrl.text.trim()) ?? 60,
                              'vagas': int.tryParse(vagasCtrl.text.trim()) ?? 20,
                              'unidade_id': unidadeId,
                              'descricao': descCtrl.text.trim(),
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE50914),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text(aula != null ? 'Salvar' : 'Criar Aula'),
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
      if (aula != null) {
        await _service.updateAula(aula['id'] as int, result);
      } else {
        await _service.insertAula(result);
      }
      _carregar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mapErroAdmin(e))));
    }
  }

  Future<void> _excluir(Map<String, dynamic> a) async {
    if (!await confirmarExclusao(context, titulo: 'Excluir aula')) return;
    try {
      await _service.deleteAula(a['id'] as int);
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
                    onPressed: () => _mostrarForm(),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Nova Aula'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ThemeColors.primary(context),
                      foregroundColor: ThemeColors.onPrimary(context),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _aulas.isEmpty
                    ? Center(
                        child: Text('Nenhuma aula cadastrada',
                            style: TextStyle(color: ThemeColors.secondaryText(context))))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                        itemCount: _aulas.length,
                        itemBuilder: (context, index) {
                          final a = _aulas[index];
                          final unidade = a['unidades'] is Map ? (a['unidades'] as Map)['nome'] as String? : null;
                          final ocupadas = a['vagas_ocupadas'] as int? ?? 0;
                          final vagas = a['vagas'] as int? ?? 0;
                          final lotada = vagas > 0 && ocupadas >= vagas;
                          return AnimatedCardEntry(
                            index: index,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: ThemeColors.primary(context).withValues(alpha: 0.1),
                                  child: Icon(Icons.fitness_center_rounded,
                                      color: ThemeColors.primary(context), size: 20),
                                ),
                                title: Text(a['nome'] as String? ?? '',
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        '${nomeDiaSemana(a['dia_semana'] as String?)}  •  ${a['horario'] ?? ''}  •  ${a['instrutor'] ?? ''}',
                                        style:
                                            TextStyle(fontSize: 11, color: ThemeColors.secondaryText(context))),
                                    Text(
                                        '$ocupadas/$vagas vagas ocupadas',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: lotada ? ThemeColors.error(context) : ThemeColors.success(context),
                                            fontWeight: FontWeight.w600)),
                                    if (unidade != null)
                                      Text(unidade,
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: ThemeColors.hint(context),
                                              fontWeight: FontWeight.w600)),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(Icons.edit_rounded, color: ThemeColors.info(context)),
                                      onPressed: () => _mostrarForm(aula: a),
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.delete_outline_rounded, color: ThemeColors.error(context)),
                                      onPressed: () => _excluir(a),
                                    ),
                                  ],
                                ),
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
