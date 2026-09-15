import 'package:flutter/material.dart';
import '../../../../core/helpers/theme_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../services/admin_service.dart';
import '../../../widgets/animated_card_entry.dart';
import '../admin_utils.dart';
import '../widgets/admin_usuario_picker.dart';

class AssinaturasTab extends StatefulWidget {
  const AssinaturasTab({super.key});

  @override
  State<AssinaturasTab> createState() => _AssinaturasTabState();
}

class _AssinaturasTabState extends State<AssinaturasTab> {
  final _service = AdminService();
  List<Map<String, dynamic>> _assinaturas = [];
  bool _loading = true;

  static const _planos = ['basico', 'premium', 'vip'];
  static const _statusLista = ['ativo', 'cancelado', 'expirado'];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    try {
      _assinaturas = await _service.fetchAssinaturas();
    } catch (e) {
      debugPrint('Erro assinaturas: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Color _corStatus(String status) {
    switch (status) {
      case 'ativo': return const Color(0xFF00A650);
      case 'cancelado': return const Color(0xFFF23D4F);
      case 'expirado': return const Color(0xFFFFAD01);
      default: return const Color(0xFFC6C6C6);
    }
  }

  Future<void> _mostrarForm({Map<String, dynamic>? assinatura}) async {
    Map<String, dynamic>? usuario = assinatura != null
        ? {
            'id': assinatura['user_id'],
            'nome': assinatura['perfis'] is Map
                ? (assinatura['perfis'] as Map)['nome']
                : 'Usuário ${assinatura['user_id']}',
          }
        : null;
    String? plano = assinatura?['plano'] as String?;
    String? status = assinatura?['status'] as String?;
    final valorCtrl = TextEditingController(text: assinatura?['valor'] != null
        ? (assinatura!['valor'] as num).toStringAsFixed(2)
        : '');
    bool bonus = assinatura?['bonus'] == true;
    DateTime? dataInicio = assinatura?['data_inicio'] != null
        ? DateTime.tryParse(assinatura!['data_inicio'] as String)
        : null;
    DateTime? dataFim = assinatura?['data_fim'] != null
        ? DateTime.tryParse(assinatura!['data_fim'] as String)
        : null;

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
                  Text(assinatura != null ? 'Editar Assinatura' : 'Nova Assinatura',
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
                    value: _planos.contains(plano) ? plano : null,
                    decoration: adminInputDec(context, 'Plano'),
                    items: _planos
                        .map((p) => DropdownMenuItem(value: p, child: Text(capitalizar(p))))
                        .toList(),
                    onChanged: (v) => setSheetState(() => plano = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _statusLista.contains(status) ? status : null,
                    decoration: adminInputDec(context, 'Status'),
                    items: _statusLista
                        .map((s) => DropdownMenuItem(value: s, child: Text(capitalizar(s))))
                        .toList(),
                    onChanged: (v) => setSheetState(() => status = v),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: valorCtrl,
                    decoration: adminInputDec(context, 'Valor mensal', hint: 'Ex: 99.90'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(dataInicio != null
                        ? 'Início: ${dataInicio!.toLocal().toString().split(' ')[0]}'
                        : 'Data de início'),
                    trailing: const Icon(Icons.calendar_month_rounded),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: dataInicio ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                      );
                      if (picked != null) setSheetState(() => dataInicio = picked);
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(dataFim != null
                        ? 'Fim: ${dataFim!.toLocal().toString().split(' ')[0]}'
                        : 'Data de término'),
                    trailing: const Icon(Icons.calendar_month_rounded),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: dataFim ?? DateTime.now().add(const Duration(days: 30)),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                      );
                      if (picked != null) setSheetState(() => dataFim = picked);
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Bônus'),
                    value: bonus,
                    onChanged: (v) => setSheetState(() => bonus = v),
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
                            if (usuario == null) {
                              erro = 'Selecione um usuário.';
                            } else if (plano == null) {
                              erro = 'Selecione o plano.';
                            } else if (status == null) {
                              erro = 'Selecione o status.';
                            }
                            if (erro != null) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erro)));
                              return;
                            }
                            Navigator.pop(ctx, {
                              'user_id': usuario!['id'],
                              'plano': plano,
                              'status': status,
                              'valor': double.tryParse(valorCtrl.text.trim().replaceAll(',', '.')),
                              'data_inicio': dataInicio?.toIso8601String(),
                              'data_fim': dataFim?.toIso8601String(),
                              'bonus': bonus,
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE50914),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text(assinatura != null ? 'Salvar' : 'Criar Assinatura'),
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
    result.removeWhere((k, v) => v == null);
    try {
      if (assinatura != null) {
        await _service.updateAssinatura(assinatura['id'] as int, result);
      } else {
        await _service.insertAssinatura(result);
      }
      _carregar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mapErroAdmin(e))));
    }
  }

  Future<void> _excluir(Map<String, dynamic> a) async {
    if (!await confirmarExclusao(context, titulo: 'Excluir assinatura')) return;
    try {
      await _service.deleteAssinatura(a['id'] as int);
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
                    label: const Text('Nova Assinatura'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ThemeColors.primary(context),
                      foregroundColor: ThemeColors.onPrimary(context),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _assinaturas.isEmpty
                    ? Center(
                        child: Text('Nenhuma assinatura cadastrada',
                            style: TextStyle(color: ThemeColors.secondaryText(context))))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                        itemCount: _assinaturas.length,
                        itemBuilder: (context, index) {
                          final a = _assinaturas[index];
                          final perfil = a['perfis'] is Map ? (a['perfis'] as Map) : null;
                          final status = a['status'] as String? ?? '';
                          final cor = _corStatus(status);
                          final valor = a['valor'] as num?;
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
                                  backgroundColor: cor.withValues(alpha: 0.12),
                                  child: Icon(Icons.card_membership_rounded, color: cor, size: 20),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                          '${capitalizar(a['plano'] as String? ?? '')}  •  ${formatarMoeda(valor)}',
                                          style: const TextStyle(fontWeight: FontWeight.w600),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: cor.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(capitalizar(status),
                                          style: TextStyle(
                                              fontSize: 10, color: cor, fontWeight: FontWeight.w700)),
                                    ),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(perfil?['nome'] as String? ?? '',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: ThemeColors.primary(context),
                                            fontWeight: FontWeight.w600)),
                                    Text(
                                        '${a['data_inicio'] != null ? (a['data_inicio'] as String).substring(0, 10) : '—'} até ${a['data_fim'] != null ? (a['data_fim'] as String).substring(0, 10) : '—'}${a['bonus'] == true ? '  •  Bônus' : ''}',
                                        style:
                                            TextStyle(fontSize: 11, color: ThemeColors.secondaryText(context))),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(Icons.edit_rounded, color: ThemeColors.info(context)),
                                      onPressed: () => _mostrarForm(assinatura: a),
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
