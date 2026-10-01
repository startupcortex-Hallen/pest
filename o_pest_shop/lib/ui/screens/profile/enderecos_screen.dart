import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/endereco.dart';
import '../../../services/endereco_service.dart';
import '../../../providers/auth_provider.dart';

/// CRUD completo dos endereços de entrega do usuário.
class EnderecosScreen extends StatefulWidget {
  const EnderecosScreen({super.key});

  @override
  State<EnderecosScreen> createState() => _EnderecosScreenState();
}

class _EnderecosScreenState extends State<EnderecosScreen> {
  final _service = EnderecoService();
  List<Endereco> _enderecos = [];
  bool _loading = true;

  String? get _userId => context.read<AuthProvider>().user?.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _carregar());
  }

  Future<void> _carregar() async {
    final userId = _userId;
    if (userId == null) return;
    setState(() => _loading = true);
    try {
      _enderecos = await _service.fetch(userId);
    } catch (e) {
      debugPrint('Erro endereços: $e');
      _enderecos = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _excluir(Endereco e) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir endereço'),
        content: Text('Remover "${e.apelido.isNotEmpty ? e.apelido : 'este endereço'}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _service.excluir(e.id);
      await _carregar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Endereço excluído.')),
        );
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao excluir: $err'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _definirPrincipal(Endereco e) async {
    final userId = _userId;
    if (userId == null) return;
    try {
      await _service.definirPrincipal(userId, e.id);
      await _carregar();
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $err'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _abrirForm([Endereco? endereco]) async {
    final userId = _userId;
    if (userId == null) return;

    final apelidoCtrl = TextEditingController(text: endereco?.apelido ?? '');
    final cepCtrl = TextEditingController(text: endereco?.cep ?? '');
    final ruaCtrl = TextEditingController(text: endereco?.rua ?? '');
    final numeroCtrl = TextEditingController(text: endereco?.numero ?? '');
    final complementoCtrl = TextEditingController(text: endereco?.complemento ?? '');
    final bairroCtrl = TextEditingController(text: endereco?.bairro ?? '');
    final cidadeCtrl = TextEditingController(text: endereco?.cidade ?? '');
    final ufCtrl = TextEditingController(text: endereco?.uf ?? '');
    var principal = endereco?.principal ?? _enderecos.isEmpty;
    var salvando = false;
    final formKey = GlobalKey<FormState>();
    final cepMask = MaskTextInputFormatter(
      mask: '#####-###',
      filter: {'#': RegExp(r'[0-9]')},
    );

    Future<void> buscarCep() async {
      final cep = cepCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
      if (cep.length != 8) return;
      try {
        final res = await http.get(Uri.parse('https://viacep.com.br/ws/$cep/json/'));
        final json = jsonDecode(utf8.decode(res.bodyBytes));
        if (json is Map && json['erro'] != true) {
          ruaCtrl.text = json['logradouro'] as String? ?? ruaCtrl.text;
          bairroCtrl.text = json['bairro'] as String? ?? bairroCtrl.text;
          cidadeCtrl.text = json['localidade'] as String? ?? cidadeCtrl.text;
          ufCtrl.text = json['uf'] as String? ?? ufCtrl.text;
        }
      } catch (_) {}
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(endereco == null ? 'Novo endereço' : 'Editar endereço'),
          content: SizedBox(
            width: 420,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: apelidoCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Apelido (ex: Casa, Trabalho)',
                      ),
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: cepCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [cepMask],
                            decoration: const InputDecoration(labelText: 'CEP'),
                            validator: (v) {
                              final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                              if (digits.length != 8) return 'CEP inválido';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 52,
                          child: OutlinedButton(
                            onPressed: () async {
                              await buscarCep();
                              setDialogState(() {});
                            },
                            child: const Text('Buscar'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            controller: ruaCtrl,
                            decoration: const InputDecoration(labelText: 'Rua'),
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Obrigatório' : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: numeroCtrl,
                            decoration: const InputDecoration(labelText: 'Número'),
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Obrigatório' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextFormField(
                      controller: complementoCtrl,
                      decoration: const InputDecoration(labelText: 'Complemento (opcional)'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextFormField(
                      controller: bairroCtrl,
                      decoration: const InputDecoration(labelText: 'Bairro'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Obrigatório' : null,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            controller: cidadeCtrl,
                            decoration: const InputDecoration(labelText: 'Cidade'),
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Obrigatório' : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: ufCtrl,
                            decoration: const InputDecoration(labelText: 'UF'),
                            maxLength: 2,
                            validator: (v) => (v == null || v.trim().length != 2) ? 'UF' : null,
                          ),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      title: const Text('Endereço principal'),
                      value: principal,
                      onChanged: (v) => setDialogState(() => principal = v),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: salvando ? null : () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: salvando
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDialogState(() => salvando = true);
                      final cep = cepCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
                      try {
                        if (endereco == null) {
                          await _service.adicionar(
                            userId,
                            apelido: apelidoCtrl.text.trim(),
                            cep: cep,
                            rua: ruaCtrl.text.trim(),
                            numero: numeroCtrl.text.trim(),
                            complemento: complementoCtrl.text.trim(),
                            bairro: bairroCtrl.text.trim(),
                            cidade: cidadeCtrl.text.trim(),
                            uf: ufCtrl.text.trim().toUpperCase(),
                            principal: principal,
                          );
                        } else {
                          await _service.atualizar(
                            userId,
                            endereco.id,
                            apelido: apelidoCtrl.text.trim(),
                            cep: cep,
                            rua: ruaCtrl.text.trim(),
                            numero: numeroCtrl.text.trim(),
                            complemento: complementoCtrl.text.trim(),
                            bairro: bairroCtrl.text.trim(),
                            cidade: cidadeCtrl.text.trim(),
                            uf: ufCtrl.text.trim().toUpperCase(),
                            principal: principal,
                          );
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                        await _carregar();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Endereço salvo!')),
                          );
                        }
                      } catch (err) {
                        setDialogState(() => salvando = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Erro ao salvar: $err'), backgroundColor: AppColors.error),
                          );
                        }
                      }
                    },
              child: salvando
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Salvar'),
            ),
          ],
        ),
      ),
    );

    apelidoCtrl.dispose();
    cepCtrl.dispose();
    ruaCtrl.dispose();
    numeroCtrl.dispose();
    complementoCtrl.dispose();
    bairroCtrl.dispose();
    cidadeCtrl.dispose();
    ufCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        title: Text(
          'Meus endereços',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirForm(),
        icon: const Icon(Icons.add_location_alt_rounded),
        label: const Text('Novo endereço'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _enderecos.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.location_off_rounded, size: 48, color: AppColors.secondaryText),
                        const SizedBox(height: AppSpacing.md),
                        const Text(
                          'Nenhum endereço salvo ainda.\nToque em "Novo endereço" para cadastrar.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.secondaryText),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  itemCount: _enderecos.length,
                  itemBuilder: (context, i) {
                    final e = _enderecos[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: AppSpacing.md),
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        border: Border.all(
                          color: e.principal ? AppColors.primary : AppColors.outline,
                          width: e.principal ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                e.principal ? Icons.star_rounded : Icons.location_on_outlined,
                                size: 18,
                                color: e.principal ? AppColors.primary : AppColors.secondaryText,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  e.apelido.isNotEmpty ? e.apelido : 'Endereço',
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                ),
                              ),
                              if (!e.principal)
                                TextButton(
                                  onPressed: () => _definirPrincipal(e),
                                  child: const Text('Usar como principal', style: TextStyle(fontSize: 12)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(e.resumo,
                              style: const TextStyle(fontSize: 13, color: AppColors.secondaryText)),
                          const SizedBox(height: AppSpacing.sm),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton.icon(
                                onPressed: () => _abrirForm(e),
                                icon: const Icon(Icons.edit_rounded, size: 16),
                                label: const Text('Editar', style: TextStyle(fontSize: 12)),
                              ),
                              TextButton.icon(
                                onPressed: () => _excluir(e),
                                icon: const Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.error),
                                label: const Text('Excluir',
                                    style: TextStyle(fontSize: 12, color: AppColors.error)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
