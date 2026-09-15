import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/helpers/theme_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../services/admin_service.dart';
import '../../../widgets/animated_card_entry.dart';
import '../admin_utils.dart';

class DesafiosTab extends StatefulWidget {
  const DesafiosTab({super.key});

  @override
  State<DesafiosTab> createState() => _DesafiosTabState();
}

class _DesafiosTabState extends State<DesafiosTab> {
  final _service = AdminService();
  List<Map<String, dynamic>> _desafios = [];
  List<Map<String, dynamic>> _unidades = [];
  bool _loading = true;
  final Set<int> _expandidos = {};

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    try {
      final resultados = await Future.wait([
        _service.fetchDesafiosAdmin(),
        Supabase.instance.client.from('unidades').select('id, nome, bairro').order('nome'),
      ]);
      _desafios = resultados[0];
      _unidades = resultados[1];
    } catch (e) {
      debugPrint('Erro desafios: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _mostrarForm({Map<String, dynamic>? desafio}) async {
    int? unidadeId = desafio?['unidade_id'] as int?;
    bool ativo = desafio?['ativo'] != false;
    final nomeCtrl = TextEditingController(text: desafio?['nome'] as String? ?? '');
    final descCtrl = TextEditingController(text: desafio?['descricao'] as String? ?? '');
    final metaCtrl = TextEditingController(text: desafio?['meta']?.toString() ?? '');

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
                  Text(desafio != null ? 'Editar Desafio' : 'Novo Desafio',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextField(controller: nomeCtrl, decoration: adminInputDec(context, 'Nome do desafio')),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    maxLines: 3,
                    decoration: adminInputDec(context, 'Descrição'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: metaCtrl,
                          decoration: adminInputDec(context, 'Meta (progresso)', hint: 'Ex: 30'),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: unidadeId != null && _unidades.any((u) => u['id'] == unidadeId)
                              ? unidadeId
                              : null,
                          decoration: adminInputDec(context, 'Unidade'),
                          items: _unidades
                              .map((u) => DropdownMenuItem(value: u['id'] as int, child: Text(u['nome'] as String)))
                              .toList(),
                          onChanged: (v) => setSheetState(() => unidadeId = v),
                        ),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Ativo'),
                    value: ativo,
                    onChanged: (v) => setSheetState(() => ativo = v),
                  ),
                  const SizedBox(height: 8),
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
                              erro = 'Informe o nome do desafio.';
                            } else if (unidadeId == null) {
                              erro = 'Selecione a unidade.';
                            }
                            if (erro != null) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erro)));
                              return;
                            }
                            Navigator.pop(ctx, {
                              'nome': nomeCtrl.text.trim(),
                              'descricao': descCtrl.text.trim(),
                              'meta': int.tryParse(metaCtrl.text.trim()) ?? 30,
                              'unidade_id': unidadeId,
                              'ativo': ativo,
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE50914),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text(desafio != null ? 'Salvar' : 'Criar Desafio'),
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
      if (desafio != null) {
        await _service.updateDesafio(desafio['id'] as int, result);
      } else {
        await _service.insertDesafio(result);
      }
      _carregar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mapErroAdmin(e))));
    }
  }

  Future<void> _excluir(Map<String, dynamic> d) async {
    if (!await confirmarExclusao(context, titulo: 'Excluir desafio')) return;
    try {
      await _service.deleteDesafio(d['id'] as int);
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
                    label: const Text('Novo Desafio'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ThemeColors.primary(context),
                      foregroundColor: ThemeColors.onPrimary(context),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _desafios.isEmpty
                    ? Center(
                        child: Text('Nenhum desafio cadastrado',
                            style: TextStyle(color: ThemeColors.secondaryText(context))))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 24),
                        itemCount: _desafios.length,
                        itemBuilder: (context, index) {
                          final d = _desafios[index];
                          final participantes = (d['desafios_participantes'] as List?) ?? [];
                          final unidade = d['unidades'] is Map ? (d['unidades'] as Map)['nome'] as String? : null;
                          final ativo = d['ativo'] != false;
                          final expandido = _expandidos.contains(d['id']);
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
                                      child: Icon(Icons.emoji_events_rounded,
                                          color: ThemeColors.primary(context), size: 20),
                                    ),
                                    title: Text(d['nome'] as String? ?? '',
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('${participantes.length} participantes  •  Meta: ${d['meta'] ?? '—'}',
                                            style:
                                                TextStyle(fontSize: 11, color: ThemeColors.secondaryText(context))),
                                        if (unidade != null)
                                          Text(unidade,
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  color: ThemeColors.primary(context),
                                                  fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: (ativo ? const Color(0xFF00A650) : const Color(0xFFF23D4F))
                                                .withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(ativo ? 'Ativo' : 'Inativo',
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  color: ativo ? const Color(0xFF00A650) : const Color(0xFFF23D4F),
                                                  fontWeight: FontWeight.w700)),
                                        ),
                                        IconButton(
                                          icon: Icon(Icons.edit_rounded, color: ThemeColors.info(context)),
                                          onPressed: () => _mostrarForm(desafio: d),
                                        ),
                                        IconButton(
                                          icon: Icon(Icons.delete_outline_rounded, color: ThemeColors.error(context)),
                                          onPressed: () => _excluir(d),
                                        ),
                                      ],
                                    ),
                                    onTap: () => setState(() {
                                      if (!_expandidos.add(d['id'] as int)) _expandidos.remove(d['id'] as int);
                                    }),
                                  ),
                                  if (expandido) ...[
                                    Divider(height: 1, color: ThemeColors.divider(context)),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 8, AppSpacing.md, 12),
                                      child: participantes.isEmpty
                                          ? Text('Sem participantes ainda',
                                              style: TextStyle(
                                                  fontSize: 12, color: ThemeColors.secondaryText(context)))
                                          : Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: participantes.map((p) {
                                                final perfil = p['perfis'] is Map ? (p['perfis'] as Map) : null;
                                                final progresso = p['progresso'] as int? ?? 0;
                                                final meta = (d['meta'] as num?)?.toDouble() ?? 1;
                                                return Padding(
                                                  padding: const EdgeInsets.only(bottom: 8),
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          Expanded(
                                                            child: Text(
                                                                perfil?['nome'] as String? ?? 'Participante',
                                                                style: const TextStyle(
                                                                    fontSize: 12, fontWeight: FontWeight.w600),
                                                                maxLines: 1,
                                                                overflow: TextOverflow.ellipsis),
                                                          ),
                                                          Text('$progresso / ${d['meta'] ?? '—'}',
                                                              style: TextStyle(
                                                                  fontSize: 11,
                                                                  color: ThemeColors.secondaryText(context))),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 4),
                                                      ClipRRect(
                                                        borderRadius: BorderRadius.circular(6),
                                                        child: LinearProgressIndicator(
                                                          value: (progresso / meta).clamp(0, 1),
                                                          minHeight: 6,
                                                          backgroundColor: ThemeColors.surfaceVariant(context),
                                                          color: ThemeColors.success(context),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              }).toList(),
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
