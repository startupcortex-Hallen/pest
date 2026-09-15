import 'package:flutter/material.dart';
import '../../../../core/helpers/theme_colors.dart';
import '../../../../services/admin_service.dart';

class AdminUsuarioPicker extends StatefulWidget {
  const AdminUsuarioPicker({super.key});

  static Future<Map<String, dynamic>?> show(BuildContext context) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const AdminUsuarioPicker(),
    );
  }

  @override
  State<AdminUsuarioPicker> createState() => _AdminUsuarioPickerState();
}

class _AdminUsuarioPickerState extends State<AdminUsuarioPicker> {
  final _service = AdminService();
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
      _usuarios = await _service.fetchUsuarios();
    } catch (e) {
      debugPrint('Erro usuarios: $e');
    }
    if (mounted) setState(() => _loading = false);
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

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        top: 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 8, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Selecionar Usuário',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Buscar por nome ou email...',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: ThemeColors.surface(context),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          SizedBox(
            height: 380,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : filtrados.isEmpty
                    ? Center(
                        child: Text('Nenhum usuário encontrado',
                            style: TextStyle(color: ThemeColors.secondaryText(context))))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: filtrados.length,
                        itemBuilder: (context, i) {
                          final u = filtrados[i];
                          final nome = u['nome'] as String? ?? '';
                          final email = u['email'] as String? ?? '';
                          final funcao = u['funcao'] as String? ?? '';
                          final unidade = u['unidades'] is Map
                              ? (u['unidades'] as Map)['nome'] as String?
                              : null;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            decoration: BoxDecoration(
                              color: ThemeColors.surface(context),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: ThemeColors.primary(context).withValues(alpha: 0.1),
                                child: Text(
                                  nome.isEmpty ? '?' : nome[0].toUpperCase(),
                                  style: TextStyle(
                                      color: ThemeColors.primary(context), fontWeight: FontWeight.bold),
                                ),
                              ),
                              title: Text(nome, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                '$email${unidade != null ? '  •  $unidade' : ''}',
                                style: TextStyle(fontSize: 12, color: ThemeColors.secondaryText(context)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: funcao.isNotEmpty && funcao != 'usuario'
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: ThemeColors.secondary(context).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(funcao,
                                          style: TextStyle(
                                              fontSize: 9,
                                              color: ThemeColors.secondary(context),
                                              fontWeight: FontWeight.w600)),
                                    )
                                  : null,
                              onTap: () => Navigator.pop(context, u),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
