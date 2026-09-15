import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/helpers/theme_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../services/admin_service.dart';
import '../../../widgets/animated_card_entry.dart';
import '../admin_utils.dart';
import '../widgets/admin_usuario_picker.dart';

class ProfissionaisTab extends StatefulWidget {
  const ProfissionaisTab({super.key});

  @override
  State<ProfissionaisTab> createState() => _ProfissionaisTabState();
}

class _ProfissionaisTabState extends State<ProfissionaisTab> {
  final _service = AdminService();
  List<Map<String, dynamic>> _profissionais = [];
  List<Map<String, dynamic>> _filiacoes = [];
  List<Map<String, dynamic>> _unidades = [];
  bool _loading = true;
  String _filtroFuncao = '';

  static const _funcoes = ['nutricionista', 'personal'];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    try {
      final resultados = await Future.wait([
        _service.fetchProfissionais(),
        _service.fetchTodasFiliacoes(),
        Supabase.instance.client.from('unidades').select('id, nome, bairro, foto_url').order('nome'),
      ]);
      _profissionais = resultados[0];
      _filiacoes = resultados[1];
      _unidades = resultados[2];
    } catch (e) {
      debugPrint('Erro profissionais: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  List<Map<String, dynamic>> _filiacoesDo(Map<String, dynamic> p) {
    return _filiacoes.where((f) => f['user_id'] == p['id']).toList();
  }

  Color _corFuncao(String funcao) {
    switch (funcao) {
      case 'nutricionista': return const Color(0xFF00A650);
      case 'personal': return const Color(0xFFE50914);
      default: return const Color(0xFFC6C6C6);
    }
  }

  Future<void> _mostrarForm({Map<String, dynamic>? profissional}) async {
    Map<String, dynamic>? usuario = profissional != null
        ? {
            'id': profissional['id'],
            'nome': profissional['nome'],
            'email': profissional['email'],
          }
        : null;
    String? funcao = profissional?['funcao'] as String?;
    final filiadasAtuais = profissional != null ? _filiacoesDo(profissional) : <Map<String, dynamic>>[];
    final Set<int> unidadesSelecionadas = filiadasAtuais.map((f) => f['unidade_id'] as int).toSet();
    int? principalId = filiadasAtuais.any((f) => f['principal'] == true)
        ? filiadasAtuais.firstWhere((f) => f['principal'] == true)['unidade_id'] as int
        : (unidadesSelecionadas.isNotEmpty ? unidadesSelecionadas.first : null);

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          final isNutricionista = funcao == 'nutricionista';
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
                  Text(profissional != null ? 'Editar Profissional' : 'Novo Profissional',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  AdminCampoSelecao(
                    label: 'Usuário',
                    valor: usuario?['nome'] as String? ?? 'Selecionar',
                    erro: usuario == null,
                    onTap: profissional != null
                        ? null
                        : () async {
                            final u = await AdminUsuarioPicker.show(context);
                            if (u != null) setSheetState(() => usuario = u);
                          },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _funcoes.contains(funcao) ? funcao : null,
                    decoration: adminInputDec(context, 'Cargo'),
                    items: const [
                      DropdownMenuItem(value: 'nutricionista', child: Text('Nutricionista')),
                      DropdownMenuItem(value: 'personal', child: Text('Personal')),
                    ],
                    onChanged: (v) => setSheetState(() {
                      funcao = v;
                      if (v == 'personal' && unidadesSelecionadas.length > 1) {
                        unidadesSelecionadas.removeWhere((id) => id != principalId);
                      }
                    }),
                  ),
                  const SizedBox(height: 16),
                  if (isNutricionista)
                    Text('Nutricionista pode se afiliar a várias unidades — marque uma como Principal.',
                        style: TextStyle(fontSize: 12, color: ThemeColors.secondaryText(context)))
                  else
                    Text('Personal só pode ser filiado a uma unidade.',
                        style: TextStyle(fontSize: 12, color: ThemeColors.secondaryText(context))),
                  const SizedBox(height: 8),
                  if (_unidades.isEmpty)
                    const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
                  else
                    ..._unidades.map((u) {
                      final id = u['id'] as int;
                      final filiada = unidadesSelecionadas.contains(id);
                      final isPrincipal = id == principalId;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: ThemeColors.surface(context),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: filiada ? ThemeColors.primary(context) : ThemeColors.outline(context),
                            width: filiada ? 1.5 : 1,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Row(
                            children: [
                              if (isNutricionista)
                                Checkbox(
                                  value: filiada,
                                  onChanged: (v) => setSheetState(() {
                                    if (v == true) {
                                      unidadesSelecionadas.add(id);
                                      if (principalId == null) principalId = id;
                                    } else {
                                      unidadesSelecionadas.remove(id);
                                      if (principalId == id) {
                                        principalId = unidadesSelecionadas.isNotEmpty
                                            ? unidadesSelecionadas.first
                                            : null;
                                      }
                                    }
                                  }),
                                )
                              else
                                Radio<int>(
                                  value: id,
                                  groupValue: filiada ? id : null,
                                  onChanged: (_) => setSheetState(() {
                                    unidadesSelecionadas.clear();
                                    unidadesSelecionadas.add(id);
                                    principalId = id;
                                  }),
                                ),
                              Expanded(
                                child: Text(u['nome'] as String? ?? '',
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ),
                              if (isNutricionista && filiada)
                                GestureDetector(
                                  onTap: () => setSheetState(() => principalId = id),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isPrincipal
                                          ? const Color(0xFFFFAD01).withValues(alpha: 0.15)
                                          : ThemeColors.surfaceVariant(context),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.star_rounded,
                                            size: 14,
                                            color: isPrincipal
                                                ? const Color(0xFFFFAD01)
                                                : ThemeColors.hint(context)),
                                        const SizedBox(width: 4),
                                        Text(isPrincipal ? 'Principal' : 'Definir principal',
                                            style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: isPrincipal
                                                    ? const Color(0xFFFFAD01)
                                                    : ThemeColors.secondaryText(context))),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    }),
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
                            } else if (funcao == null) {
                              erro = 'Selecione o cargo.';
                            } else if (unidadesSelecionadas.isEmpty) {
                              erro = isNutricionista
                                  ? 'Afili o profissional a pelo menos uma unidade.'
                                  : 'Selecione a unidade do personal.';
                            }
                            if (erro != null) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erro)));
                              return;
                            }
                            Navigator.pop(ctx, {
                              'user_id': usuario!['id'],
                              'funcao': funcao,
                              'unidade_ids': unidadesSelecionadas.toList(),
                              'principal_id': isNutricionista ? principalId : unidadesSelecionadas.first,
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE50914),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text(profissional != null ? 'Salvar' : 'Adicionar Profissional'),
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
      await _service.salvarFiliacoes(
        result['user_id'] as String,
        result['funcao'] as String,
        (result['unidade_ids'] as List).cast<int>(),
        result['principal_id'] as int?,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profissional salvo')));
      }
      _carregar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mapErroAdmin(e))));
    }
  }

  Future<void> _remover(Map<String, dynamic> p) async {
    if (!await confirmarExclusao(context,
        titulo: 'Remover profissional',
        mensagem:
            'As filiações de "${p['nome']}" serão removidas e a função voltará para usuário comum.')) {
      return;
    }
    try {
      await _service.removerProfissional(p['id'] as String);
      _carregar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mapErroAdmin(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = _filtroFuncao.isEmpty
        ? _profissionais
        : _profissionais.where((p) => p['funcao'] == _filtroFuncao).toList();

    return _loading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
                  children: [
                    _buildFuncaoChip('Todos', null, _filtroFuncao.isEmpty, () {
                      setState(() => _filtroFuncao = '');
                    }),
                    ..._funcoes.map((f) => Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: _buildFuncaoChip(capitalizar(f), f, _filtroFuncao == f, () {
                            setState(() => _filtroFuncao = f);
                          }),
                        )),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () => _mostrarForm(),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Novo Profissional'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ThemeColors.primary(context),
                      foregroundColor: ThemeColors.onPrimary(context),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: filtrados.isEmpty
                    ? Center(
                        child: Text('Nenhum profissional cadastrado',
                            style: TextStyle(color: ThemeColors.secondaryText(context))))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 24),
                        itemCount: filtrados.length,
                        itemBuilder: (context, index) {
                          final p = filtrados[index];
                          final funcao = p['funcao'] as String? ?? '';
                          final cor = _corFuncao(funcao);
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
                                    ((p['nome'] as String? ?? '').isEmpty ? '?' : (p['nome'] as String)[0])
                                        .toUpperCase(),
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
                                      child: Text(capitalizar(funcao),
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
                                                    const Icon(Icons.star_rounded,
                                                        size: 11, color: Color(0xFFFFAD01)),
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
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(Icons.edit_rounded, color: ThemeColors.info(context)),
                                      onPressed: () => _mostrarForm(profissional: p),
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.delete_outline_rounded, color: ThemeColors.error(context)),
                                      onPressed: () => _remover(p),
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

  Widget _buildFuncaoChip(String label, String? funcao, bool selected, VoidCallback onTap) {
    final cor = funcao == null ? const Color(0xFFC6C6C6) : _corFuncao(funcao);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? cor.withValues(alpha: 0.15) : const Color(0xFF1F1F1F),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: selected ? cor : const Color(0xFFC6C6C6))),
      ),
    );
  }
}
