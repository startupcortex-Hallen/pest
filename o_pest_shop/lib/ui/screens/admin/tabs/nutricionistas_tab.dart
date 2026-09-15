import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/helpers/theme_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../services/admin_service.dart';
import '../../../widgets/animated_card_entry.dart';
import '../admin_utils.dart';

class NutricionistasTab extends StatefulWidget {
  const NutricionistasTab({super.key});

  @override
  State<NutricionistasTab> createState() => _NutricionistasTabState();
}

class _NutricionistasTabState extends State<NutricionistasTab> {
  final _service = AdminService();
  List<Map<String, dynamic>> _nutricionistas = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    try {
      _nutricionistas = await _service.fetchNutricionistas();
    } catch (e) {
      debugPrint('Erro nutricionistas: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _mostrarForm({Map<String, dynamic>? n}) async {
    final nomeCtrl = TextEditingController(text: n?['nome'] as String? ?? '');
    final emailCtrl = TextEditingController(text: n?['email'] as String? ?? '');
    final crnCtrl = TextEditingController(text: n?['crn'] as String? ?? '');
    final bioCtrl = TextEditingController(text: n?['bio'] as String? ?? '');
    final precoCtrl = TextEditingController(text: n?['preco_consulta'] != null
        ? (n!['preco_consulta'] as num).toStringAsFixed(2)
        : '');
    bool disponivel = n?['disponivel'] != false;
    String? avatarUrl = n?['avatar_url'] as String?;
    bool salvando = false;

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
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
                  Text(n != null ? 'Editar Nutricionista' : 'Novo Nutricionista',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  // Avatar
                  Center(
                    child: GestureDetector(
                      onTap: () async {
                        final picker = ImagePicker();
                        final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
                        if (file == null) return;
                        setSheetState(() => salvando = true);
                        try {
                          final bytes = await file.readAsBytes();
                          final fileName = 'nutricionista_${DateTime.now().millisecondsSinceEpoch}.jpg';
                          await Supabase.instance.client.storage.from('Produtos').uploadBinary(
                            fileName, bytes,
                            fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
                          );
                          avatarUrl = Supabase.instance.client.storage.from('Produtos').getPublicUrl(fileName);
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Erro ao enviar foto: $e')));
                          }
                        }
                        setSheetState(() => salvando = false);
                      },
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 40,
                            backgroundColor: ThemeColors.primary(context).withValues(alpha: 0.1),
                            foregroundImage: avatarUrl != null && avatarUrl!.isNotEmpty
                                ? CachedNetworkImageProvider(avatarUrl!)
                                : null,
                            child: salvando
                                ? const SizedBox(
                                    width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                                : Text(
                                    (nomeCtrl.text.isEmpty ? 'N' : nomeCtrl.text[0]).toUpperCase(),
                                    style: TextStyle(
                                        fontSize: 26,
                                        color: ThemeColors.primary(context),
                                        fontWeight: FontWeight.bold),
                                  ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: ThemeColors.primary(context),
                                shape: BoxShape.circle,
                                border: Border.all(color: ThemeColors.surface(context), width: 2),
                              ),
                              child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(controller: nomeCtrl, decoration: adminInputDec(context, 'Nome')),
                  const SizedBox(height: 12),
                  TextField(controller: emailCtrl, decoration: adminInputDec(context, 'Email')),
                  const SizedBox(height: 12),
                  TextField(controller: crnCtrl, decoration: adminInputDec(context, 'CRN', hint: 'Ex: CRN-5 12345')),
                  const SizedBox(height: 12),
                  TextField(
                    controller: precoCtrl,
                    decoration: adminInputDec(context, 'Preço da consulta', hint: 'Ex: 120.00'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: bioCtrl,
                    maxLines: 3,
                    decoration: adminInputDec(context, 'Bio'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Disponível para consultas'),
                    value: disponivel,
                    onChanged: (v) => setSheetState(() => disponivel = v),
                  ),
                  const SizedBox(height: 8),
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
                            if (nomeCtrl.text.trim().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Informe o nome.')));
                              return;
                            }
                            Navigator.pop(ctx, {
                              'nome': nomeCtrl.text.trim(),
                              'email': emailCtrl.text.trim(),
                              'crn': crnCtrl.text.trim(),
                              'preco_consulta': double.tryParse(precoCtrl.text.trim().replaceAll(',', '.')),
                              'bio': bioCtrl.text.trim(),
                              'disponivel': disponivel,
                              if (avatarUrl != null) 'avatar_url': avatarUrl,
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE50914),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text(n != null ? 'Salvar' : 'Cadastrar'),
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
    result.removeWhere((k, v) => v == null);
    try {
      if (n != null) {
        await _service.updateNutricionista(n['id'] as int, result);
      } else {
        await _service.insertNutricionista(result);
      }
      _carregar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mapErroAdmin(e))));
    }
  }

  Future<void> _excluir(Map<String, dynamic> n) async {
    if (!await confirmarExclusao(context, titulo: 'Excluir nutricionista')) return;
    try {
      await _service.deleteNutricionista(n['id'] as int);
      _carregar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mapErroAdmin(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return _loading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () => _mostrarForm(),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Novo Nutricionista'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ThemeColors.primary(context),
                      foregroundColor: ThemeColors.onPrimary(context),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _nutricionistas.isEmpty
                    ? Center(
                        child: Text('Nenhum nutricionista cadastrado',
                            style: TextStyle(color: ThemeColors.secondaryText(context))))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                        itemCount: _nutricionistas.length,
                        itemBuilder: (context, index) {
                          final n = _nutricionistas[index];
                          final disponivel = n['disponivel'] != false;
                          final cor = disponivel ? const Color(0xFF00A650) : const Color(0xFFF23D4F);
                          final preco = n['preco_consulta'] as num?;
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
                                  radius: 22,
                                  backgroundColor: ThemeColors.primary(context).withValues(alpha: 0.1),
                                  foregroundImage: n['avatar_url'] != null
                                      ? CachedNetworkImageProvider(n['avatar_url'] as String)
                                      : null,
                                  child: Text(
                                    ((n['nome'] as String? ?? '?').isEmpty ? '?' : (n['nome'] as String)[0])
                                        .toUpperCase(),
                                    style: TextStyle(
                                        color: ThemeColors.primary(context), fontWeight: FontWeight.bold),
                                  ),
                                ),
                                title: Text(n['nome'] as String? ?? '',
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (n['crn'] != null && (n['crn'] as String).isNotEmpty)
                                      Text(n['crn'] as String,
                                          style: TextStyle(
                                              fontSize: 11, color: ThemeColors.secondaryText(context))),
                                    Text(
                                        preco != null ? 'Consulta: ${formatarMoeda(preco)}' : '',
                                        style: TextStyle(
                                            fontSize: 11, color: ThemeColors.secondaryText(context))),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: cor.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(disponivel ? 'Disponível' : 'Indisponível',
                                          style: TextStyle(
                                              fontSize: 10, color: cor, fontWeight: FontWeight.w700)),
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.edit_rounded, color: ThemeColors.info(context)),
                                      onPressed: () => _mostrarForm(n: n),
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.delete_outline_rounded, color: ThemeColors.error(context)),
                                      onPressed: () => _excluir(n),
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
