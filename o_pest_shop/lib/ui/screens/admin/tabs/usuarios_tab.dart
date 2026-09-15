import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/helpers/theme_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../widgets/animated_card_entry.dart';
import '../admin_utils.dart';

class UsuariosTab extends StatefulWidget {
  const UsuariosTab({super.key});

  @override
  State<UsuariosTab> createState() => _UsuariosTabState();
}

class _UsuariosTabState extends State<UsuariosTab> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _usuarios = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    try {
      final r = await Supabase.instance.client
          .from('perfis')
          .select('id, nome, email, funcao, unidade_id, unidades(nome)')
          .order('nome');
      _usuarios = (r as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('Erro usuarios: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Color _corFuncao(String funcao) {
    switch (funcao) {
      case 'admin': return ThemeColors.warning(context);
      case 'atendente': return ThemeColors.info(context);
      default: return ThemeColors.secondary(context);
    }
  }

  Future<void> _mudarFuncao(Map<String, dynamic> u, String novaFuncao) async {
    if (novaFuncao == u['funcao']) return;
    try {
      await Supabase.instance.client.from('perfis').update({'funcao': novaFuncao}).eq('id', u['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Função de "${u['nome']}" atualizada')));
      }
      _carregar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mapErroAdmin(e))));
    }
  }

  Future<void> _excluir(Map<String, dynamic> u) async {
    if (!await confirmarExclusao(context, titulo: 'Excluir usuário')) return;
    try {
      await Supabase.instance.client.from('perfis').delete().eq('id', u['id']);
      _carregar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mapErroAdmin(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchCtrl.text.toLowerCase().trim();
    final filtrados = _usuarios.where((u) {
      if (query.isEmpty) return true;
      final nome = (u['nome'] as String? ?? '').toLowerCase();
      final email = (u['email'] as String? ?? '').toLowerCase();
      return nome.contains(query) || email.contains(query);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 12, AppSpacing.lg, 8),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Buscar por nome ou email',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              filled: true,
              fillColor: ThemeColors.surface(context),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : filtrados.isEmpty
                  ? Center(
                      child: Text('Nenhum usuário encontrado',
                          style: TextStyle(color: ThemeColors.secondaryText(context))))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 4, AppSpacing.lg, 24),
                      itemCount: filtrados.length,
                      itemBuilder: (context, index) {
                        final u = filtrados[index];
                        final funcao = u['funcao'] as String? ?? 'usuario';
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
                                child: Text(
                                    ((u['nome'] as String? ?? '').isEmpty ? '?' : (u['nome'] as String)[0])
                                        .toUpperCase(),
                                    style: TextStyle(
                                        color: ThemeColors.primary(context), fontWeight: FontWeight.bold)),
                              ),
                              title: Text(u['nome'] as String? ?? '',
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                  '${u['email'] ?? ''}  •  ${(u['unidades'] as Map?)?['nome'] ?? 'Sem unidade'}',
                                  style: TextStyle(fontSize: 12, color: ThemeColors.secondaryText(context)),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _corFuncao(funcao).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: DropdownButton<String>(
                                      value: funcao,
                                      underline: const SizedBox(),
                                      style: TextStyle(
                                          fontSize: 11, fontWeight: FontWeight.w600, color: _corFuncao(funcao)),
                                      iconSize: 18,
                                      items: const [
                                        DropdownMenuItem(value: 'usuario', child: Text('Usuário')),
                                        DropdownMenuItem(value: 'atendente', child: Text('Atendente')),
                                        DropdownMenuItem(value: 'admin', child: Text('Admin')),
                                      ],
                                      onChanged: (novaFuncao) {
                                        if (novaFuncao != null) _mudarFuncao(u, novaFuncao);
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    icon: Icon(Icons.delete_outline_rounded, color: ThemeColors.error(context)),
                                    onPressed: () => _excluir(u),
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
