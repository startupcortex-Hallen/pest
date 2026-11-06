import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/helpers/theme_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../admin_utils.dart';

class BannersTab extends StatefulWidget {
  const BannersTab({super.key});

  @override
  State<BannersTab> createState() => _BannersTabState();
}

class _BannersTabState extends State<BannersTab> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _banners = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    try {
      final r = await _client
          .from('banners')
          .select()
          .order('ordem')
          .order('id', ascending: false);
      _banners = (r as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('Erro banners: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _abrirForm([Map<String, dynamic>? banner]) async {
    final titulo = TextEditingController(text: banner?['titulo'] as String? ?? '');
    final imagem = TextEditingController(text: banner?['imagem_url'] as String? ?? '');
    final link = TextEditingController(text: banner?['link_url'] as String? ?? '');
    final ordem = TextEditingController(text: '${banner?['ordem'] ?? 0}');
    final inicio = TextEditingController(
      text: _dataTexto(banner?['data_inicio']),
    );
    final fim = TextEditingController(text: _dataTexto(banner?['data_fim']));
    var ativo = banner?['ativo'] != false;

    final salvar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(banner == null ? 'Novo banner' : 'Editar banner'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titulo,
                  decoration: const InputDecoration(labelText: 'Título'),
                ),
                TextField(
                  controller: imagem,
                  decoration: const InputDecoration(
                    labelText: 'URL da imagem',
                    hintText: 'https://...',
                  ),
                ),
                TextField(
                  controller: link,
                  decoration: const InputDecoration(
                    labelText: 'Link (opcional)',
                    hintText: '/produto/123 ou https://...',
                  ),
                ),
                TextField(
                  controller: ordem,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Ordem',
                    helperText: 'Menor aparece primeiro',
                  ),
                ),
                TextField(
                  controller: inicio,
                  decoration: const InputDecoration(
                    labelText: 'Início (opcional)',
                    hintText: 'dd/mm/aaaa',
                  ),
                ),
                TextField(
                  controller: fim,
                  decoration: const InputDecoration(
                    labelText: 'Fim (opcional)',
                    hintText: 'dd/mm/aaaa',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: ativo,
                  onChanged: (v) => setDialog(() => ativo = v),
                  title: const Text('Ativo'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );

    if (salvar != true) return;
    if (imagem.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Informe a URL da imagem.')),
        );
      }
      return;
    }

    final dados = <String, dynamic>{
      'titulo': titulo.text.trim().isEmpty ? null : titulo.text.trim(),
      'imagem_url': imagem.text.trim(),
      'link_url': link.text.trim().isEmpty ? null : link.text.trim(),
      'ordem': int.tryParse(ordem.text.trim()) ?? 0,
      'ativo': ativo,
      'data_inicio': _parseData(inicio.text),
      'data_fim': _parseData(fim.text),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    try {
      if (banner == null) {
        await _client.from('banners').insert(dados);
      } else {
        await _client.from('banners').update(dados).eq('id', banner['id']);
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

  String _dataTexto(dynamic valor) {
    if (valor == null) return '';
    final d = DateTime.tryParse(valor.toString());
    if (d == null) return '';
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  dynamic _parseData(String texto) {
    final t = texto.trim();
    if (t.isEmpty) return null;
    final partes = t.split('/');
    if (partes.length == 3) {
      final dia = int.tryParse(partes[0]);
      final mes = int.tryParse(partes[1]);
      final ano = int.tryParse(partes[2]);
      if (dia != null && mes != null && ano != null) {
        return DateTime(ano, mes, dia).toUtc().toIso8601String();
      }
    }
    return DateTime.tryParse(t)?.toUtc().toIso8601String();
  }

  Future<void> _excluir(Map<String, dynamic> banner) async {
    if (!await confirmarExclusao(
      context,
      titulo: 'Excluir banner',
      mensagem: 'Remover "${banner['titulo'] ?? 'banner'}" da home?',
    )) {
      return;
    }
    try {
      await _client.from('banners').delete().eq('id', banner['id']);
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
    if (_loading) return const Center(child: CircularProgressIndicator());

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            12,
            AppSpacing.lg,
            8,
          ),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Banners da home',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _abrirForm(),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Novo'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _banners.isEmpty
              ? Center(
                  child: Text(
                    'Nenhum banner cadastrado',
                    style: TextStyle(
                      color: ThemeColors.secondaryText(context),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    4,
                    AppSpacing.lg,
                    24,
                  ),
                  itemCount: _banners.length,
                  itemBuilder: (context, index) {
                    final b = _banners[index];
                    final ativo = b['ativo'] == true;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            b['imagem_url'] as String? ?? '',
                            width: 64,
                            height: 48,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 64,
                              height: 48,
                              color: ThemeColors.surfaceVariant(context),
                              child: const Icon(Icons.image_not_supported),
                            ),
                          ),
                        ),
                        title: Text(
                          (b['titulo'] as String?)?.trim().isNotEmpty == true
                              ? b['titulo'] as String
                              : 'Banner #${b['id']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          'Ordem ${b['ordem'] ?? 0}  •  ${ativo ? 'Ativo' : 'Inativo'}'
                          '${b['link_url'] != null ? '\n${b['link_url']}' : ''}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: ativo
                                ? ThemeColors.secondaryText(context)
                                : ThemeColors.error(context),
                          ),
                        ),
                        isThreeLine: b['link_url'] != null,
                        trailing: PopupMenuButton<String>(
                          onSelected: (acao) {
                            if (acao == 'editar') _abrirForm(b);
                            if (acao == 'excluir') _excluir(b);
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'editar',
                              child: Text('Editar'),
                            ),
                            PopupMenuItem(
                              value: 'excluir',
                              child: Text('Excluir'),
                            ),
                          ],
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
