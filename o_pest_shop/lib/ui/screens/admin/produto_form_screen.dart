import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/home_provider.dart';
import '../../../services/admin_service.dart';
import '../../../core/theme/app_colors.dart';

class ProdutoFormScreen extends StatefulWidget {
  final Map<String, dynamic>? produto;
  const ProdutoFormScreen({super.key, this.produto});

  @override
  State<ProdutoFormScreen> createState() => _ProdutoFormScreenState();
}

class _CurrencyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digitsOnly = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    if (digitsOnly.isEmpty) {
      return const TextEditingValue(text: '');
    }
    final value = int.parse(digitsOnly);
    final reais = value ~/ 100;
    final centavos = value % 100;
    final formatted = '${reais.toString()},${centavos.toString().padLeft(2, '0')}';
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _ProdutoFormScreenState extends State<ProdutoFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nomeCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _precoCtrl = TextEditingController();
  final _precoPromocionalCtrl = TextEditingController();
  final _adminService = AdminService();

  int? _categoriaId;
  int? _marcaId;
  bool _emPromocao = false;
  bool _saving = false;
  int? _unidadeIdEditando;

  int _estoque = 1;
  List<String> _imagens = [];
  final List<String> _cores = [];

  static const _paletaCores = [
    'Preto', 'Branco', 'Vermelho', 'Dourado', 'Azul', 'Verde', 'Amarelo',
    'Cinza', 'Prata', 'Rosa', 'Laranja', 'Roxo', 'Marrom',
  ];

  List<Map<String, dynamic>> _categorias = [];
  List<Map<String, dynamic>> _marcas = [];
  List<Map<String, dynamic>> _unidades = [];

  String? _marcaNome;
  String? _categoriaNome;
  String? _unidadeNome;

  static const int maxImages = 5;

  bool get _isEditing => widget.produto != null;

  @override
  void initState() {
    super.initState();
    _loadData();
    if (_isEditing) {
      final p = widget.produto!;
      _nomeCtrl.text = p['nome'] ?? '';
      _descCtrl.text = p['descricao'] ?? '';
      _precoCtrl.text = (p['preco'] ?? 0.0).toStringAsFixed(2).replaceAll('.', ',');
      final promo = p['preco_promocional'];
      if (promo != null) {
        _precoPromocionalCtrl.text = (promo as num).toStringAsFixed(2).replaceAll('.', ',');
      }
      final raw = p['url_imagem'];
      if (raw is List) {
        _imagens = raw.cast<String>();
      } else if (raw is String && raw.isNotEmpty) {
        _imagens = [raw];
      }
      final rawCores = p['cores'];
      if (rawCores is List) {
        _cores.addAll(rawCores.whereType<String>());
      } else if (rawCores is String && rawCores.isNotEmpty) {
        _cores.addAll(rawCores.replaceAll(RegExp(r'[{}]'), '').split(','));
      }
      _categoriaId = p['categoria_id'] as int?;
      _marcaId = p['marca_id'] as int?;
      _emPromocao = p['em_promocao'] == true;
      _estoque = p['estoque'] as int? ?? 1;
      _unidadeIdEditando = p['unidade_id'] as int?;
    }
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _descCtrl.dispose();
    _precoCtrl.dispose();
    _precoPromocionalCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final cats = await _adminService.fetchCategorias();
      final marcas = await _adminService.fetchMarcas();
      final unidades = await Supabase.instance.client
          .from('unidades')
          .select('id, nome, bairro, foto_url')
          .order('nome');
      setState(() {
        _categorias = cats.map((c) => {'id': c.id, 'nome': c.nome}).toList();
        _marcas = marcas;
        _unidades = (unidades as List).cast<Map<String, dynamic>>();
        if (_categoriaId != null) {
          _categoriaNome = _categorias.firstWhere((c) => c['id'] == _categoriaId, orElse: () => {'nome': ''})['nome'] as String?;
        }
        if (_marcaId != null) {
          _marcaNome = _marcas.firstWhere((m) => m['id'] == _marcaId, orElse: () => {'nome': ''})['nome'] as String?;
        }
        if (_unidadeIdEditando != null) {
          final u = _unidades.firstWhere((u) => u['id'] == _unidadeIdEditando, orElse: () => {'nome': '', 'bairro': ''});
          _unidadeNome = '${u['nome']} (${u['bairro'] ?? ''})';
        }
      });
    } catch (e) {
      debugPrint('Erro: $e');
    }
  }

  Future<void> _pickImageForSlot(int slotIndex) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (file == null) return;

    try {
      final bytes = await file.readAsBytes();
      final fileName = 'produto_${DateTime.now().millisecondsSinceEpoch}_${slotIndex}.jpg';

      await Supabase.instance.client.storage.from('Produtos').uploadBinary(
        fileName, bytes,
        fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
      );

      final url = Supabase.instance.client.storage.from('Produtos').getPublicUrl(fileName);
      while (_imagens.length <= slotIndex) {
        _imagens.add('');
      }
      _imagens[slotIndex] = url;
    } catch (e) {
      debugPrint('Erro upload: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao fazer upload: $e'), backgroundColor: AppColors.error),
        );
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;

    final imagensValidas = _imagens.where((url) => url.isNotEmpty).toList();
    final precoText = _precoCtrl.text.replaceAll(',', '.').trim();
    final preco = double.tryParse(precoText);

    // Validação de todos os campos obrigatórios
    String? erro;
    if (imagensValidas.isEmpty) {
      erro = 'Adicione pelo menos uma foto.';
    } else if (preco == null || preco <= 0) {
      erro = 'Informe um preço válido.';
    } else if (_categoriaId == null) {
      erro = 'Selecione uma categoria.';
    } else if (_marcaId == null) {
      erro = 'Selecione uma marca.';
    } else if (_unidadeIdEditando == null) {
      erro = 'Selecione uma unidade.';
    } else if (_emPromocao) {
      final promoText = _precoPromocionalCtrl.text.replaceAll(',', '.').trim();
      final promo = double.tryParse(promoText);
      if (promo == null || promo <= 0) {
        erro = 'Informe o preço promocional.';
      } else if (promo >= preco!) {
        erro = 'Preço promocional deve ser menor que o preço normal.';
      }
    }

    if (erro != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(erro), backgroundColor: AppColors.error),
        );
      }
      return;
    }

    setState(() => _saving = true);

    final data = <String, dynamic>{
      'nome': _nomeCtrl.text.trim(),
      'descricao': _descCtrl.text.trim(),
      'preco': preco,
      'estoque': _estoque,
      'categoria_id': _categoriaId,
      'marca_id': _marcaId,
      'em_promocao': _emPromocao,
    };
    if (_emPromocao) {
      final promoText = _precoPromocionalCtrl.text.replaceAll(',', '.').trim();
      data['preco_promocional'] = double.tryParse(promoText);
    } else {
      data['preco_promocional'] = null;
    }
    final unidadeId = _isEditing ? _unidadeIdEditando : _unidadeIdEditando ?? context.read<AuthProvider>().user?.unidadeId;
    if (unidadeId != null) data['unidade_id'] = unidadeId;
    if (imagensValidas.isNotEmpty) data['url_imagem'] = imagensValidas;
    if (_cores.isNotEmpty) data['cores'] = List.from(_cores);

    try {
      if (_isEditing) {
        await _adminService.updateProduto(widget.produto!['id'] as int, data);
      } else {
        await _adminService.insertProduto(data);
      }
      if (mounted) {
        context.read<HomeProvider>().refresh();
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Erro ao salvar: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildFotosSection(),
                      const SizedBox(height: AppSpacing.lg),
                      _buildTituloSection(),
                      const SizedBox(height: AppSpacing.lg),
                      _buildDescricaoSection(),
                      const SizedBox(height: AppSpacing.lg),
                      _buildCoresSection(),
                      const SizedBox(height: AppSpacing.lg),
                      _buildUnidadeSection(),
                      const SizedBox(height: AppSpacing.lg),
                      _buildPrecoEstoqueSection(),
                      const SizedBox(height: AppSpacing.lg),
                      _buildEnvioSection(),
                      const SizedBox(height: AppSpacing.lg),
                      SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _saving ? null : _salvar,
                          child: _saving
                              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
                              : Text(_isEditing ? 'Atualizar Anúncio' : 'Confirmar e Publicar'),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: AppColors.primaryText),
                onPressed: () => Navigator.pop(context),
              ),
              Text('O que você está vendendo?',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
          TextButton(
            onPressed: () {},
            child: const Text('Ajuda', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, {bool required = false}) {
    return Row(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        if (required) const Text(' *', style: TextStyle(color: AppColors.error, fontSize: 16)),
      ],
    );
  }

  // ─── FOTOS ──────────────────────────────────────────

  Widget _buildFotosSection() {
    final preenchidas = _imagens.where((url) => url.isNotEmpty).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Fotos', required: true),
        const SizedBox(height: 4),
        Text('Adicione até $maxImages fotos. Clique em qualquer slot para adicionar.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.secondaryText)),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (int i = 0; i < maxImages; i++) _buildImageSlot(index: i),
          ],
        ),
      ],
    );
  }

  Widget _buildImageSlot({required int index}) {
    final hasImage = index < _imagens.length && _imagens[index].isNotEmpty;
    return GestureDetector(
      onTap: hasImage
          ? null
          : () => _pickImageForSlot(index),
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: hasImage ? AppColors.primary : AppColors.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: hasImage
            ? Stack(
                children: [
                  CachedNetworkImage(imageUrl: _imagens[index], width: 100, height: 100, fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const Icon(Icons.image_outlined, color: AppColors.hint, size: 32),
                    placeholder: (_, __) => Container(color: Colors.white)),
                  Positioned(
                    top: 2, right: 2,
                    child: GestureDetector(
                      onTap: () => setState(() => _imagens[index] = ''),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: AppColors.error, shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close_rounded, color: Colors.white, size: 14),
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_rounded, color: AppColors.hint, size: 28),
                  const SizedBox(height: 4),
                  Text('Adicionar', style: TextStyle(fontSize: 10, color: AppColors.hint)),
                ],
              ),
      ),
    );
  }

  // ─── TÍTULO E IDENTIFICAÇÃO ────────────────────────

  Widget _buildTituloSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Título e Identificação', required: true),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          controller: _nomeCtrl,
          decoration: InputDecoration(
            labelText: 'Título do anúncio',
            hintText: 'Ex: Camiseta O Pest - Tam G',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
            filled: true,
            fillColor: AppColors.surface,
          ),
          validator: (v) => v == null || v.trim().isEmpty ? 'Obrigatório' : null,
        ),
        const SizedBox(height: AppSpacing.md),
        _buildSelectorRow(
          icon: Icons.label_rounded,
          label: 'Marca',
          value: _marcaNome ?? 'Selecionar',
          onTap: () => _showPickerDialog('marca'),
          showError: _marcaId == null,
        ),
        const SizedBox(height: AppSpacing.md),
        _buildSelectorRow(
          icon: Icons.category_rounded,
          label: 'Categoria',
          value: _categoriaNome ?? 'Selecionar',
          onTap: () => _showPickerDialog('categoria'),
          showError: _categoriaId == null,
        ),
      ],
    );
  }

  Widget _buildSelectorRow({required IconData icon, required String label, required String value, required VoidCallback onTap, bool showError = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: showError ? AppColors.error : AppColors.outline,
            width: showError ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 12, color: AppColors.secondaryText)),
                  Text(value, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.hint),
          ],
        ),
      ),
    );
  }

  // ─── SELEÇÃO DE UNIDADE ────────────────────────────

  Widget _buildUnidadeFallback(String nome) {
    return Container(
      color: const Color(0xFFF0F0F0),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.store_rounded, size: 24, color: const Color(0xFFBBBBBB)),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                nome.isNotEmpty ? nome.substring(0, 1).toUpperCase() : '?',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFFBBBBBB)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoresSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Cores disponíveis'),
        const SizedBox(height: 4),
        const Text(
          'Toque para marcar as cores do produto',
          style: TextStyle(fontSize: 12, color: AppColors.secondaryText),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _paletaCores.map((cor) {
            final selecionada = _cores.contains(cor);
            return GestureDetector(
              onTap: () => setState(() {
                if (selecionada) {
                  _cores.remove(cor);
                } else {
                  _cores.add(cor);
                }
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: selecionada ? AppColors.primary.withValues(alpha: 0.15) : AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selecionada ? AppColors.primary : AppColors.darkOutline,
                    width: selecionada ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _corDeChip(cor),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      cor,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: selecionada ? AppColors.primaryText : AppColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Color _corDeChip(String nome) {
    final n = nome.toLowerCase();
    if (n.contains('preto')) return const Color(0xFF111111);
    if (n.contains('branco')) return const Color(0xFFF5F5F5);
    if (n.contains('vermelho') || n.contains('vinho')) return const Color(0xFFE50914);
    if (n.contains('dourado') || n.contains('gold')) return const Color(0xFFD4AF37);
    if (n.contains('azul')) return const Color(0xFF2D65F6);
    if (n.contains('verde')) return const Color(0xFF00A650);
    if (n.contains('amarelo')) return const Color(0xFFFFC400);
    if (n.contains('rosa')) return const Color(0xFFFF80AB);
    if (n.contains('laranja')) return const Color(0xFFFF7A00);
    if (n.contains('roxo') || n.contains('violeta')) return const Color(0xFF9C27B0);
    if (n.contains('cinza') || n.contains('prata')) return const Color(0xFF9E9E9E);
    if (n.contains('marrom')) return const Color(0xFF795548);
    return const Color(0xFFE50914);
  }

  Widget _buildUnidadeSection() {
    if (_unidades.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Unidade', required: true),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 140,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _unidades.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final u = _unidades[i];
              final isSel = _unidadeIdEditando == u['id'];
              final fotoUrl = u['foto_url'] as String?;
              return GestureDetector(
                onTap: () => setState(() {
                  _unidadeIdEditando = u['id'] as int;
                  _unidadeNome = '${u['nome']} (${u['bairro'] ?? ''})';
                }),
                child: Container(
                  width: 120,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSel ? const Color(0xFFE50914) : const Color(0xFF2C2C2C),
                      width: isSel ? 2 : 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      Column(
                        children: [
                          Expanded(
                            child: Container(
                              width: double.infinity,
                              color: const Color(0xFF1F1F1F),
                              child: fotoUrl != null && fotoUrl.isNotEmpty
                                  ? Image.network(fotoUrl, fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => _buildUnidadeFallback(u['nome'] as String))
                                  : _buildUnidadeFallback(u['nome'] as String),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                            child: Text(
                              u['nome'] as String,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                color: isSel ? const Color(0xFFE50914) : const Color(0xFFEDEDED),
                                fontWeight: isSel ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (isSel)
                        Positioned(
                          top: 4, right: 4,
                          child: Icon(Icons.check_circle_rounded, size: 18, color: const Color(0xFFE50914)),
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

  void _showPickerDialog(String type) {
    if (type == 'unidade') return; // substituído por cards horizontais inline

    final items = type == 'marca' ? _marcas : _categorias;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text(type == 'marca' ? 'Selecionar Marca' : 'Selecionar Categoria',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: AppSpacing.md),
          ...items.map((item) => ListTile(
            title: Text(item['nome'] as String),
            leading: Icon(type == 'marca' ? Icons.label_rounded : Icons.category_rounded, color: AppColors.primary),
            trailing: (type == 'marca' && item['id'] == _marcaId) || (type == 'categoria' && item['id'] == _categoriaId)
                ? const Icon(Icons.check_rounded, color: AppColors.primary)
                : null,
            onTap: () {
              setState(() {
                if (type == 'marca') {
                  _marcaId = item['id'] as int;
                  _marcaNome = item['nome'] as String;
                } else {
                  _categoriaId = item['id'] as int;
                  _categoriaNome = item['nome'] as String;
                }
              });
              Navigator.pop(ctx);
            },
          )),
        ],
      ),
    );
  }

  // ─── DESCRIÇÃO ──────────────────────────────────────

  Widget _buildDescricaoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Descrição', required: true),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          controller: _descCtrl,
          maxLines: 8,
          maxLength: 2000,
          textAlignVertical: TextAlignVertical.top,
          decoration: InputDecoration(
            hintText: 'Descreva o produto, materiais e detalhes...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
            filled: true,
            fillColor: AppColors.darkSurface,
            counterText: '${_descCtrl.text.length}/2000',
          ),
          validator: (v) => v == null || v.trim().isEmpty ? 'Obrigatório' : null,
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  // ─── PREÇO E ESTOQUE ───────────────────────────────

  Widget _buildPrecoEstoqueSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Preço e Estoque', required: true),
        const SizedBox(height: AppSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _buildPrecoField(
                label: _isEditing && _emPromocao ? 'Preço original' : 'Preço',
                controller: _precoCtrl,
                enabled: !(_isEditing && _emPromocao),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.xs),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_rounded, color: AppColors.primary),
                      onPressed: () => setState(() { if (_estoque > 0) _estoque--; }),
                    ),
                    Column(
                      children: [
                        Text('Estoque', style: TextStyle(fontSize: 10, color: AppColors.secondaryText)),
                        Text('$_estoque', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_rounded, color: AppColors.primary),
                      onPressed: () => setState(() => _estoque++),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (_emPromocao) ...[
          const SizedBox(height: AppSpacing.md),
          _buildPrecoField(
            label: 'Preço promocional',
            controller: _precoPromocionalCtrl,
            enabled: true,
            isPromo: true,
          ),
        ],
      ],
    );
  }

  Widget _buildPrecoField({
    required String label,
    required TextEditingController controller,
    required bool enabled,
    bool isPromo = false,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: label,
        hintText: '0,00',
        prefixIcon: Icon(
          isPromo ? Icons.discount_rounded : Icons.payments_rounded,
          size: 20,
          color: isPromo ? AppColors.error : null,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        filled: true,
        fillColor: enabled ? AppColors.surface : const Color(0xFF1F1F1F),
      ),
      keyboardType: TextInputType.number,
      inputFormatters: [_CurrencyInputFormatter()],
    );
  }

  // ─── ENVIO ──────────────────────────────────────────

  Widget _buildEnvioSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Envio', required: true),
        const SizedBox(height: AppSpacing.md),
        _buildToggleRow(
          icon: Icons.local_shipping_rounded,
          iconColor: AppColors.primary,
          title: 'O Pest Envios',
          subtitle: 'Envio rápido para região',
          value: true,
        ),
        const SizedBox(height: AppSpacing.sm),
        _buildPromocaoToggle(),
      ],
    );
  }

  Widget _buildToggleRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    ValueChanged<bool>? onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.primary, width: 1.5),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.secondaryText)),
              ],
            ),
          ),
          Container(
            width: 44,
            height: 24,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildPromocaoToggle() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          const Icon(Icons.sell_rounded, color: AppColors.onSurface, size: 24),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Oferecer promoção', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                Text('Destaque seu produto com um preço especial',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.secondaryText)),
              ],
            ),
          ),
          Switch.adaptive(
            value: _emPromocao,
            onChanged: (v) => setState(() => _emPromocao = v),
            activeColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}
