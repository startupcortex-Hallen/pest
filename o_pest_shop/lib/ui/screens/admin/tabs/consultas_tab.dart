import 'package:flutter/material.dart';
import '../../../../core/helpers/theme_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../services/admin_service.dart';
import '../../../widgets/animated_card_entry.dart';
import '../admin_utils.dart';

class ConsultasTab extends StatefulWidget {
  const ConsultasTab({super.key});

  @override
  State<ConsultasTab> createState() => _ConsultasTabState();
}

class _ConsultasTabState extends State<ConsultasTab> {
  final _service = AdminService();
  List<Map<String, dynamic>> _consultas = [];
  bool _loading = true;

  static const _statusLista = ['pendente', 'confirmada', 'realizada'];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    try {
      _consultas = await _service.fetchConsultas();
    } catch (e) {
      debugPrint('Erro consultas: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Color _corStatus(String status) {
    switch (status) {
      case 'confirmada': return const Color(0xFFE50914);
      case 'realizada': return const Color(0xFF00A650);
      case 'pendente': return const Color(0xFFFFAD01);
      default: return const Color(0xFFC6C6C6);
    }
  }

  Future<void> _mudarStatus(Map<String, dynamic> c, String novo) async {
    if (novo == c['status']) return;
    try {
      await _service.updateConsultaStatus(c['id'] as int, novo);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Consulta atualizada para "${capitalizar(novo)}"')),
        );
      }
      _carregar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mapErroAdmin(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return _loading
        ? const Center(child: CircularProgressIndicator())
        : _consultas.isEmpty
            ? Center(
                child: Text('Nenhuma consulta agendada',
                    style: TextStyle(color: ThemeColors.secondaryText(context))))
            : ListView.builder(
                padding: const EdgeInsets.all(AppSpacing.lg),
                itemCount: _consultas.length,
                itemBuilder: (context, index) {
                  final c = _consultas[index];
                  final perfil = c['perfis'] is Map ? (c['perfis'] as Map) : null;
                  final nutri = c['nutricionistas'] is Map ? (c['nutricionistas'] as Map) : null;
                  final status = c['status'] as String? ?? 'pendente';
                  final cor = _corStatus(status);
                  final tipo = c['tipo'] as String?;
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
                          child: Icon(Icons.event_available_rounded, color: ThemeColors.primary(context), size: 20),
                        ),
                        title: Text(perfil?['nome'] as String? ?? 'Paciente',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Com ${nutri?['nome'] ?? ''}  •  ${formatarData(c['data_hora'] as String?)}',
                                style: TextStyle(fontSize: 11, color: ThemeColors.secondaryText(context))),
                            if (tipo != null)
                              Text(capitalizar(tipo),
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: ThemeColors.primary(context),
                                      fontWeight: FontWeight.w600)),
                          ],
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: cor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: DropdownButton<String>(
                            value: status,
                            underline: const SizedBox(),
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cor),
                            icon: Icon(Icons.arrow_drop_down_rounded, color: cor, size: 20),
                            isDense: true,
                            items: _statusLista
                                .map((s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(capitalizar(s),
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: _corStatus(s),
                                            fontWeight: FontWeight.w600))))
                                .toList(),
                            onChanged: (v) {
                              if (v != null && v != status) _mudarStatus(c, v);
                            },
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
  }
}
