import 'package:flutter/material.dart';
import '../../../../core/helpers/theme_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../services/admin_service.dart';
import '../../../widgets/animated_card_entry.dart';
import '../admin_utils.dart';
import '../widgets/admin_usuario_picker.dart';

class NutricaoTab extends StatefulWidget {
  const NutricaoTab({super.key});

  @override
  State<NutricaoTab> createState() => _NutricaoTabState();
}

class _NutricaoTabState extends State<NutricaoTab> {
  final _service = AdminService();
  List<Map<String, dynamic>> _refeicoes = [];
  bool _loading = true;

  static const _dias = ['seg', 'ter', 'qua', 'qui', 'sex', 'sab', 'dom'];
  static const _tipos = [
    'Café da Manhã', 'Lanche da Manhã', 'Almoço', 'Lanche da Tarde',
    'Jantar', 'Ceia', 'Pré-Treino', 'Pós-Treino',
  ];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    try {
      _refeicoes = await _service.fetchPlanoRefeicoes();
    } catch (e) {
      debugPrint('Erro refeições: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  IconData _iconeTipo(String? tipo) {
    switch (tipo) {
      case 'Café da Manhã': return Icons.breakfast_dining_rounded;
      case 'Almoço': return Icons.lunch_dining_rounded;
      case 'Lanche da Tarde': return Icons.cookie_rounded;
      case 'Jantar': return Icons.dinner_dining_rounded;
      default: return Icons.restaurant_rounded;
    }
  }

  Future<void> _mostrarForm({Map<String, dynamic>? refeicao}) async {
    Map<String, dynamic>? usuario = refeicao != null
        ? {
            'id': refeicao['user_id'],
            'nome': refeicao['perfis'] is Map
                ? (refeicao['perfis'] as Map)['nome']
                : 'Usuário ${refeicao['user_id']}',
          }
        : null;
    String? dia = refeicao?['dia_semana'] as String?;
    String? tipo = refeicao?['tipo'] as String?;
    final horarioCtrl = TextEditingController(text: refeicao?['horario'] as String? ?? '');
    final caloriasCtrl = TextEditingController(text: refeicao?['calorias']?.toString() ?? '');
    final descCtrl = TextEditingController(text: refeicao?['descricao'] as String? ?? '');

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
                  Text(refeicao != null ? 'Editar Refeição' : 'Nova Refeição',
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
                  DropdownButtonFormField<String>(
                    value: _dias.contains(dia) ? dia : null,
                    decoration: adminInputDec(context, 'Dia da semana'),
                    items: _dias.map((d) => DropdownMenuItem(value: d, child: Text(nomeDiaSemana(d)))).toList(),
                    onChanged: (v) => setSheetState(() => dia = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _tipos.contains(tipo) ? tipo : null,
                    decoration: adminInputDec(context, 'Tipo de refeição'),
                    items: _tipos.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                    onChanged: (v) => setSheetState(() => tipo = v),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: horarioCtrl,
                    decoration: adminInputDec(context, 'Horário', hint: 'Ex: 08:00'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: caloriasCtrl,
                    decoration: adminInputDec(context, 'Calorias'),
                    keyboardType: TextInputType.number,
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
                            if (usuario == null) {
                              erro = 'Selecione um usuário.';
                            } else if (dia == null) {
                              erro = 'Selecione o dia da semana.';
                            } else if (tipo == null) {
                              erro = 'Selecione o tipo de refeição.';
                            }
                            if (erro != null) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erro)));
                              return;
                            }
                            Navigator.pop(ctx, {
                              'user_id': usuario!['id'],
                              'dia_semana': dia,
                              'tipo': tipo,
                              'horario': horarioCtrl.text.trim(),
                              'calorias': int.tryParse(caloriasCtrl.text.trim()) ?? 0,
                              'descricao': descCtrl.text.trim(),
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE50914),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text(refeicao != null ? 'Salvar' : 'Criar Refeição'),
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
      if (refeicao != null) {
        await _service.updatePlanoRefeicao(refeicao['id'] as int, result);
      } else {
        await _service.insertPlanoRefeicao(result);
      }
      _carregar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mapErroAdmin(e))));
    }
  }

  Future<void> _excluir(Map<String, dynamic> r) async {
    if (!await confirmarExclusao(context, titulo: 'Excluir refeição')) return;
    try {
      await _service.deletePlanoRefeicao(r['id'] as int);
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
                    label: const Text('Nova Refeição'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ThemeColors.primary(context),
                      foregroundColor: ThemeColors.onPrimary(context),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _refeicoes.isEmpty
                    ? Center(
                        child: Text('Nenhuma refeição cadastrada',
                            style: TextStyle(color: ThemeColors.secondaryText(context))))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                        itemCount: _refeicoes.length,
                        itemBuilder: (context, index) {
                          final r = _refeicoes[index];
                          final perfil = r['perfis'] is Map ? (r['perfis'] as Map) : null;
                          return AnimatedCardEntry(
                            index: index,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: ThemeColors.primary(context).withValues(alpha: 0.1),
                                  child: Icon(_iconeTipo(r['tipo'] as String?),
                                      color: ThemeColors.primary(context), size: 20),
                                ),
                                title: Text(r['tipo'] as String? ?? '', maxLines: 1),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        '${nomeDiaSemana(r['dia_semana'] as String?)}  •  ${r['horario'] ?? ''}  •  ${r['calorias'] ?? 0} kcal',
                                        style: TextStyle(fontSize: 11, color: ThemeColors.secondaryText(context))),
                                    Text(perfil?['nome'] as String? ?? '',
                                        style: TextStyle(
                                            fontSize: 11, color: ThemeColors.primary(context), fontWeight: FontWeight.w600)),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(Icons.edit_rounded, color: ThemeColors.info(context)),
                                      onPressed: () => _mostrarForm(refeicao: r),
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.delete_outline_rounded, color: ThemeColors.error(context)),
                                      onPressed: () => _excluir(r),
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
