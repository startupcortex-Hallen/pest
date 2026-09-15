import 'package:flutter/material.dart';
import '../../../core/helpers/theme_colors.dart';
import '../../../core/theme/app_spacing.dart';

String mapErroAdmin(dynamic e) {
  final msg = e.toString().toLowerCase();
  if (msg.contains('duplicate key') || msg.contains('unique constraint')) return 'Registro duplicado.';
  if (msg.contains('foreign key')) return 'Registro vinculado a outros dados. Não é possível excluir.';
  if (msg.contains('violates row-level security')) return 'Sem permissão para esta operação.';
  if (msg.contains('23505')) return 'Já existe um registro com este identificador.';
  return 'Erro ao executar operação. Tente novamente.';
}

String formatarMoeda(dynamic valor) {
  final v = (valor as num?)?.toDouble() ?? 0;
  return 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';
}

String capitalizar(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

String nomeDiaSemana(String? d) {
  switch (d) {
    case 'seg': return 'Segunda-feira';
    case 'ter': return 'Terça-feira';
    case 'qua': return 'Quarta-feira';
    case 'qui': return 'Quinta-feira';
    case 'sex': return 'Sexta-feira';
    case 'sab': return 'Sábado';
    case 'dom': return 'Domingo';
    default: return d ?? '';
  }
}

String formatarData(String? iso) {
  final dt = DateTime.tryParse(iso ?? '')?.toLocal();
  if (dt == null) return '';
  String p(int v) => v.toString().padLeft(2, '0');
  return '${p(dt.day)}/${p(dt.month)}/${dt.year} ${p(dt.hour)}:${p(dt.minute)}';
}

Future<bool> confirmarExclusao(BuildContext context, {required String titulo, String? mensagem}) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titulo),
      content: Text(mensagem ?? 'Tem certeza?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Excluir', style: TextStyle(color: ThemeColors.error(ctx)))),
      ],
    ),
  );
  return confirm == true;
}

InputDecoration adminInputDec(BuildContext context, String label, {String? hint}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    filled: true,
    fillColor: ThemeColors.surface(context),
  );
}

class AdminCampoSelecao extends StatelessWidget {
  final String label;
  final String valor;
  final VoidCallback? onTap;
  final bool erro;

  const AdminCampoSelecao({
    super.key,
    required this.label,
    required this.valor,
    this.onTap,
    this.erro = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 12),
        decoration: BoxDecoration(
          color: ThemeColors.surface(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: erro ? ThemeColors.error(context) : ThemeColors.outline(context),
            width: erro ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 12, color: ThemeColors.secondaryText(context))),
                  const SizedBox(height: 2),
                  Text(
                    valor,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ThemeColors.primaryText(context)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: ThemeColors.hint(context)),
          ],
        ),
      ),
    );
  }
}
