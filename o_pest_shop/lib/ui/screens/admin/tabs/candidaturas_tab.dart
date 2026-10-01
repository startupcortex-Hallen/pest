import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/helpers/theme_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../services/admin_service.dart';
import '../../../widgets/animated_card_entry.dart';
import '../../../widgets/app_states.dart';
import '../admin_utils.dart';

/// Aba de Candidaturas (vagas) — extraída do admin_screen para reduzir o
/// arquivo monólito. É autossuficiente: carrega e exclui via AdminService.
class CandidaturasTab extends StatefulWidget {
  const CandidaturasTab({super.key});

  @override
  State<CandidaturasTab> createState() => _CandidaturasTabState();
}

class _CandidaturasTabState extends State<CandidaturasTab> {
  final _adminService = AdminService();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _adminService.fetchCandidaturas();
  }

  void _recarregar() {
    setState(() => _future = _adminService.fetchCandidaturas());
  }

  Future<void> _excluir(Map<String, dynamic> c) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir candidatura'),
        content: const Text('Tem certeza?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Excluir', style: TextStyle(color: ThemeColors.error(ctx))),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _adminService.deleteCandidatura('${c['id']}');
      _recarregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(mapErroAdmin(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppSkeletonList(itemCount: 5, itemHeight: 88);
        }
        if (snapshot.hasError) {
          return AppErrorState(
            message: 'Não foi possível carregar as candidaturas.',
            onRetry: _recarregar,
          );
        }

        final candidaturas = snapshot.data ?? [];
        if (candidaturas.isEmpty) {
          return const AppEmptyState(
            icon: Icons.description_outlined,
            title: 'Nenhuma candidatura recebida',
            message: 'As candidaturas às vagas do feed aparecem aqui.',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(AppSpacing.lg),
          itemCount: candidaturas.length,
          itemBuilder: (context, index) {
            final c = candidaturas[index];
            final vagaTitulo = c['vaga_titulo'] as String?;
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
                    backgroundColor:
                        ThemeColors.primary(context).withValues(alpha: 0.1),
                    child: Text(
                      ((c['nome'] as String? ?? '').isEmpty
                              ? '?'
                              : (c['nome'] as String? ?? '?')[0])
                          .toUpperCase(),
                      style: TextStyle(
                        color: ThemeColors.primary(context),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(c['nome'] as String? ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${c['email'] ?? ''}  •  ${c['telefone'] ?? ''}',
                          style: TextStyle(
                              fontSize: 12,
                              color: ThemeColors.secondaryText(context))),
                      Text('Vaga: ${vagaTitulo ?? ''}',
                          style: TextStyle(
                              fontSize: 11, color: ThemeColors.hint(context))),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (c['url_curriculo'] != null)
                        IconButton(
                          icon: Icon(Icons.download_rounded,
                              color: ThemeColors.primary(context)),
                          onPressed: () async {
                            final uri =
                                Uri.tryParse(c['url_curriculo'] as String);
                            if (uri != null) {
                              await launchUrl(uri,
                                  mode: LaunchMode.externalApplication);
                            }
                          },
                        ),
                      IconButton(
                        icon: Icon(Icons.delete_outline_rounded,
                            color: ThemeColors.error(context)),
                        onPressed: () => _excluir(c),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
