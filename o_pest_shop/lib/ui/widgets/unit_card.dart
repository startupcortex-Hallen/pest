import 'package:flutter/material.dart';
import '../../core/helpers/scale_helper.dart';
import '../../core/helpers/theme_colors.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

bool _verificarAberto(Map<String, dynamic>? horarios) {
  if (horarios == null || horarios.isEmpty) return true;
  final dias = ['dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sab'];
  final hoje = dias[DateTime.now().weekday % 7];
  final horaStr = horarios[hoje] as String?;
  if (horaStr == null || horaStr.isEmpty || horaStr == 'Fechado') return false;
  final partes = horaStr.split('-');
  if (partes.length != 2) return false;
  try {
    final agora = DateTime.now();
    final abertura = partes[0].split(':').map(int.parse).toList();
    final fechamento = partes[1].split(':').map(int.parse).toList();
    final agoraMin = agora.hour * 60 + agora.minute;
    final aberturaMin = abertura[0] * 60 + abertura[1];
    final fechamentoMin = fechamento[0] * 60 + fechamento[1];
    return agoraMin >= aberturaMin && agoraMin <= fechamentoMin;
  } catch (e) {
    return false;
  }
}

class UnitCard extends StatelessWidget {
  final String nome;
  final String? bairro;
  final String? endereco;
  final String? distancia;
  final String? fotoUrl;
  final String? statusLabel;
  final Color? statusColor;
  final Map<String, dynamic>? horarios;
  final VoidCallback? onTap;

  const UnitCard({
    super.key,
    required this.nome,
    this.bairro,
    this.endereco,
    this.distancia,
    this.fotoUrl,
    this.statusLabel,
    this.statusColor,
    this.horarios,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final aberto = _verificarAberto(horarios);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.darkSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.darkOutline),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(
                  width: double.infinity,
                  height: context.h(160).clamp(130.0, 200.0),
                  color: const Color(0xFF1A1A1A),
                  child: fotoUrl != null && fotoUrl!.isNotEmpty
                      ? Image.network(fotoUrl!, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildImagePlaceholder())
                      : _buildImagePlaceholder(),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4)],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8, height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: aberto ? const Color(0xFF00A650) : const Color(0xFFF23D4F),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          aberto ? 'Aberto' : 'Fechado',
                          style: TextStyle(
                            fontSize: context.sp(11),
                            fontWeight: FontWeight.w600,
                            color: aberto ? const Color(0xFF00A650) : const Color(0xFFF23D4F),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: EdgeInsets.all(context.w(AppSpacing.md)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(nome,
                      style: TextStyle(
                        fontSize: context.sp(16),
                        fontWeight: FontWeight.w700,
                        color: AppColors.darkPrimaryText,
                      ),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  if (bairro != null && bairro!.isNotEmpty) ...[
                    Row(
                      children: [
                        Icon(Icons.location_on_rounded, size: context.sp(14), color: AppColors.darkPrimary),
                        SizedBox(width: context.w(6)),
                        Text(bairro!,
                            style: TextStyle(fontSize: context.sp(13), fontWeight: FontWeight.w500, color: AppColors.darkPrimary),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ],
                  if (endereco != null && endereco!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.location_on_rounded, size: context.sp(14), color: AppColors.darkPrimary),
                        SizedBox(width: context.w(6)),
                        Expanded(
                          child: Text(endereco!,
                              style: TextStyle(fontSize: context.sp(12), color: AppColors.darkPrimary),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (distancia != null && distancia!.isNotEmpty) ...[
                        Icon(Icons.near_me_rounded, size: context.sp(14), color: AppColors.darkPrimary),
                        const SizedBox(width: 4),
                        Text(distancia!, style: TextStyle(fontSize: context.sp(12), color: AppColors.darkPrimary, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 12),
                      ],
                      if (statusLabel != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: (statusColor ?? const Color(0xFFFFAD01)).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            statusLabel!,
                            style: TextStyle(fontSize: context.sp(10), color: statusColor ?? const Color(0xFFFFAD01), fontWeight: FontWeight.w700),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePlaceholder() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.storefront_rounded, size: 40, color: const Color(0xFF777777)),
          const SizedBox(height: 4),
          Text('Sem foto', style: TextStyle(fontSize: 11, color: const Color(0xFF777777))),
        ],
      ),
    );
  }
}
