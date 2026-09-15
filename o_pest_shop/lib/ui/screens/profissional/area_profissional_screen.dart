import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/helpers/theme_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/admin_service.dart';
import '../../widgets/animated_card_entry.dart';

/// Área do Profissional (nutricionista/personal).
/// - Admin: vê todos os profissionais e suas filiações.
/// - Profissional: vê apenas as próprias unidades afiliadas (principal em destaque).
class AreaProfissionalScreen extends StatefulWidget {
  const AreaProfissionalScreen({super.key});

  @override
  State<AreaProfissionalScreen> createState() => _AreaProfissionalScreenState();
}

class _AreaProfissionalScreenState extends State<AreaProfissionalScreen> {
  final _service = AdminService();
  List<Map<String, dynamic>> _profissionais = [];
  List<Map<String, dynamic>> _filiacoes = [];
  bool _loading = true;
  bool _isAdmin = false;
  String _minhaFuncao = '';

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final user = context.read<AuthProvider>().user;
    _isAdmin = user?.funcao == 'admin';
    _minhaFuncao = user?.funcao ?? '';
    setState(() => _loading = true);
    try {
      if (_isAdmin) {
        final resultados = await Future.wait([
          _service.fetchProfissionais(),
          _service.fetchTodasFiliacoes(),
        ]);
        _profissionais = resultados[0];
        _filiacoes = resultados[1];
      } else if (user != null) {
        _filiacoes = await _service.fetchFiliacoesDoUsuario(user.id);
      }
    } catch (e) {
      debugPrint('Erro área profissional: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  String get _titulo {
    if (_isAdmin) return 'Profissionais';
    return _minhaFuncao == 'personal' ? 'Área do Personal' : 'Área do Nutricionista';
  }

  List<Map<String, dynamic>> _filiacoesDo(Map<String, dynamic> p) {
    return _filiacoes.where((f) => f['user_id'] == p['id']).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeColors.background(context),
      appBar: AppBar(
        backgroundColor: ThemeColors.surface(context),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: Text(_titulo),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _isAdmin
              ? _buildAdminView()
              : _buildMinhaVisao(),
    );
  }

  // ─── VISÃO DO PROFISSIONAL (suas unidades) ─────────

  Widget _buildMinhaVisao() {
    if (_filiacoes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.store_mall_directory_outlined, size: 48, color: ThemeColors.hint(context)),
            const SizedBox(height: 12),
            Text('Você ainda não está afiliado a nenhuma unidade',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Fale com o administrador para vincular suas unidades.',
                style: TextStyle(color: ThemeColors.secondaryText(context))),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: _filiacoes.length,
      itemBuilder: (context, index) {
        final f = _filiacoes[index];
        final unidade = f['unidades'] is Map ? (f['unidades'] as Map) : null;
        final nome = unidade?['nome'] as String? ?? 'Unidade';
        final bairro = unidade?['bairro'] as String? ?? '';
        final endereco = unidade?['endereco'] as String? ?? '';
        final fotoUrl = unidade?['foto_url'] as String?;
        final isPrincipal = f['principal'] == true;
        return AnimatedCardEntry(
          index: index,
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    Container(
                      width: double.infinity,
                      height: 140,
                      color: const Color(0xFF1F1F1F),
                      child: fotoUrl != null && fotoUrl.isNotEmpty
                          ? Image.network(fotoUrl, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _fallbackUnidade(nome))
                          : _fallbackUnidade(nome),
                    ),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: isPrincipal ? const Color(0xFFFFAD01) : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.star_rounded,
                                size: 14, color: isPrincipal ? Colors.white : const Color(0xFF9C9C9C)),
                            const SizedBox(width: 4),
                            Text(
                              isPrincipal ? 'Principal' : 'Filiada',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isPrincipal ? Colors.white : const Color(0xFFC6C6C6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(nome,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      if (bairro.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.location_on_rounded, size: 14, color: ThemeColors.primary(context)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(bairro,
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: ThemeColors.primary(context),
                                      fontWeight: FontWeight.w500),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ),
                      ],
                      if (endereco.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.location_on_outlined, size: 14, color: ThemeColors.secondaryText(context)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(endereco,
                                  style: TextStyle(
                                      fontSize: 12, color: ThemeColors.secondaryText(context)),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(isPrincipal ? 'Unidade de referência para seus atendimentos.'
                          : 'Unidade afiliada.',
                          style: TextStyle(fontSize: 11, color: ThemeColors.hint(context))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _fallbackUnidade(String nome) {
    return Container(
      color: const Color(0xFF1F1F1F),
      child: Center(
        child: Text(
          nome.isNotEmpty ? nome[0].toUpperCase() : '?',
          style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Color(0xFF9C9C9C)),
        ),
      ),
    );
  }

  // ─── VISÃO DO ADMIN (todos os profissionais) ───────

  Widget _buildAdminView() {
    if (_profissionais.isEmpty) {
      return Center(
        child: Text('Nenhum profissional cadastrado',
            style: TextStyle(color: ThemeColors.secondaryText(context))),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: _profissionais.length,
      itemBuilder: (context, index) {
        final p = _profissionais[index];
        final funcao = p['funcao'] as String? ?? '';
        final cor = funcao == 'nutricionista' ? const Color(0xFF00A650) : const Color(0xFFE50914);
        final filiacoes = _filiacoesDo(p);
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
                child: Text(
                  ((p['nome'] as String? ?? '').isEmpty ? '?' : (p['nome'] as String)[0]).toUpperCase(),
                  style: TextStyle(color: cor, fontWeight: FontWeight.bold),
                ),
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(p['nome'] as String? ?? '',
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
                    child: Text(funcao,
                        style: TextStyle(fontSize: 10, color: cor, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p['email'] as String? ?? '',
                      style: TextStyle(fontSize: 11, color: ThemeColors.secondaryText(context)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (filiacoes.isEmpty)
                    Text('Sem unidades afiliadas',
                        style: TextStyle(fontSize: 11, color: ThemeColors.hint(context)))
                  else
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: filiacoes.map((f) {
                          final unidade = f['unidades'] is Map ? (f['unidades'] as Map) : null;
                          final isPrincipal = f['principal'] == true;
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isPrincipal
                                  ? const Color(0xFFFFAD01).withValues(alpha: 0.15)
                                  : ThemeColors.surfaceVariant(context),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isPrincipal) ...[
                                  const Icon(Icons.star_rounded, size: 11, color: Color(0xFFFFAD01)),
                                  const SizedBox(width: 3),
                                ],
                                Text(unidade?['nome'] as String? ?? '',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: isPrincipal
                                            ? const Color(0xFFFFAD01)
                                            : ThemeColors.secondaryText(context))),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
