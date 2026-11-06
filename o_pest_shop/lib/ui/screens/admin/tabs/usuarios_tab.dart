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
  static const _funcoes = [
    'cliente',
    'usuario',
    'atendente',
    'entregador',
    'gestor',
    'admin',
  ];

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
          .select('id, nome, email, funcao, unidade_id, status_conta, unidades(nome)')
          .order('nome');
      _usuarios = (r as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('Erro usuarios: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  String _funcaoNormalizada(dynamic valor) {
    final funcao = (valor as String? ?? 'usuario').trim().toLowerCase();
    return _funcoes.contains(funcao) ? funcao : 'usuario';
  }

  String _rotuloFuncao(String funcao) {
    switch (funcao) {
      case 'cliente':
        return 'Cliente';
      case 'usuario':
        return 'Usuário';
      case 'atendente':
        return 'Atendente';
      case 'entregador':
        return 'Entregador';
      case 'gestor':
        return 'Gestor';
      case 'admin':
        return 'Admin';
      default:
        return capitalizar(funcao);
    }
  }

  Color _corFuncao(String funcao) {
    switch (funcao) {
      case 'admin':
        return ThemeColors.warning(context);
      case 'atendente':
        return ThemeColors.info(context);
      case 'gestor':
        return ThemeColors.primary(context);
      default:
        return ThemeColors.secondary(context);
    }
  }

  Future<void> _mudarFuncao(Map<String, dynamic> u, String novaFuncao) async {
    if (novaFuncao == _funcaoNormalizada(u['funcao'])) return;
    try {
      await Supabase.instance.client
          .from('perfis')
          .update({'funcao': novaFuncao})
          .eq('id', u['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Função de "${u['nome']}" atualizada')),
        );
      }
      _carregar();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(mapErroAdmin(e))));
    }
  }

  Future<void> _excluir(Map<String, dynamic> u) async {
    final meuId = Supabase.instance.client.auth.currentUser?.id;
    if (u['id'] == meuId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Você não pode excluir a própria conta.')),
      );
      return;
    }
    try {
      final pedidos = await Supabase.instance.client
          .from('pedidos')
          .select('id')
          .eq('user_id', u['id'])
          .limit(1);
      if ((pedidos as List).isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Este usuário possui pedidos. Para bloquear o acesso, altere a função dele.',
              ),
            ),
          );
        }
        return;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(mapErroAdmin(e))));
      }
      return;
    }
    if (!mounted) return;
    if (!await confirmarExclusao(
      context,
      titulo: 'Excluir usuário',
      mensagem:
          'Isso remove o perfil e o acesso de "${u['nome']}". Essa ação não pode ser desfeita.',
    )) {
      return;
    }
    try {
      await Supabase.instance.client.rpc(
        'admin_excluir_usuario',
        params: {'p_user_id': u['id']},
      );
      _carregar();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(mapErroAdmin(e))));
    }
  }

  Future<void> _bloquear(Map<String, dynamic> u, bool bloquear) async {
    try {
      await Supabase.instance.client.rpc(
        'admin_bloquear_usuario',
        params: {'p_user_id': u['id'], 'p_bloquear': bloquear},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              bloquear
                  ? '${u['nome']} foi bloqueado.'
                  : '${u['nome']} foi desbloqueado.',
            ),
          ),
        );
      }
      _carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(mapErroAdmin(e))));
      }
    }
  }

  Future<void> _anonimizar(Map<String, dynamic> u) async {
    if (!await confirmarExclusao(
      context,
      titulo: 'Anonimizar (LGPD)',
      mensagem:
          'Os dados pessoais de "${u['nome']}" serão removidos, mas os pedidos '
          'e o histórico financeiro serão preservados. O acesso será bloqueado. '
          'Essa ação não pode ser desfeita.',
    )) {
      return;
    }
    try {
      await Supabase.instance.client.rpc(
        'anonimizar_usuario',
        params: {
          'p_user_id': u['id'],
          'p_motivo': 'Solicitação LGPD pelo painel administrativo',
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dados anonimizados com sucesso.')),
        );
      }
      _carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(mapErroAdmin(e))));
      }
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
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            12,
            AppSpacing.lg,
            8,
          ),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Buscar por nome ou email',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
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
                  child: Text(
                    'Nenhum usuário encontrado',
                    style: TextStyle(color: ThemeColors.secondaryText(context)),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    4,
                    AppSpacing.lg,
                    24,
                  ),
                  itemCount: filtrados.length,
                  itemBuilder: (context, index) {
                    final u = filtrados[index];
                    final funcao = _funcaoNormalizada(u['funcao']);
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
                            backgroundColor: ThemeColors.primary(
                              context,
                            ).withValues(alpha: 0.1),
                            child: Text(
                              ((u['nome'] as String? ?? '').isEmpty
                                      ? '?'
                                      : (u['nome'] as String)[0])
                                  .toUpperCase(),
                              style: TextStyle(
                                color: ThemeColors.primary(context),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(
                            u['nome'] as String? ?? '',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${u['email'] ?? ''}  •  ${(u['unidades'] as Map?)?['nome'] ?? 'Sem unidade'}'
                            '${(u['status_conta'] ?? 'ativo') != 'ativo' ? '  •  ${(u['status_conta'] == 'anonimizado') ? 'ANONIMIZADO' : 'BLOQUEADO'}' : ''}',
                            style: TextStyle(
                              fontSize: 12,
                              color: (u['status_conta'] ?? 'ativo') == 'ativo'
                                  ? ThemeColors.secondaryText(context)
                                  : ThemeColors.error(context),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _corFuncao(
                                    funcao,
                                  ).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: DropdownButton<String>(
                                  value: funcao,
                                  underline: const SizedBox(),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: _corFuncao(funcao),
                                  ),
                                  iconSize: 18,
                                  items: _funcoes
                                      .map(
                                        (f) => DropdownMenuItem(
                                          value: f,
                                          child: Text(_rotuloFuncao(f)),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (novaFuncao) {
                                    if (novaFuncao != null)
                                      _mudarFuncao(u, novaFuncao);
                                  },
                                ),
                              ),
                              const SizedBox(width: 4),
                              PopupMenuButton<String>(
                                icon: Icon(
                                  Icons.more_vert_rounded,
                                  color: ThemeColors.secondaryText(context),
                                ),
                                onSelected: (acao) {
                                  switch (acao) {
                                    case 'bloquear':
                                      _bloquear(u, true);
                                      break;
                                    case 'desbloquear':
                                      _bloquear(u, false);
                                      break;
                                    case 'anonimizar':
                                      _anonimizar(u);
                                      break;
                                    case 'excluir':
                                      _excluir(u);
                                      break;
                                  }
                                },
                                itemBuilder: (context) => [
                                  if ((u['status_conta'] ?? 'ativo') == 'ativo')
                                    const PopupMenuItem(
                                      value: 'bloquear',
                                      child: Text('Bloquear conta'),
                                    )
                                  else if ((u['status_conta'] ?? 'ativo') ==
                                      'bloqueado')
                                    const PopupMenuItem(
                                      value: 'desbloquear',
                                      child: Text('Desbloquear conta'),
                                    ),
                                  const PopupMenuItem(
                                    value: 'anonimizar',
                                    child: Text('Anonimizar (LGPD)'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'excluir',
                                    child: Text('Excluir usuário'),
                                  ),
                                ],
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
