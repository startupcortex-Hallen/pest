import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/helpers/categoria_icons.dart';
import '../../../core/helpers/scale_helper.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/helpers/theme_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/produto.dart';
import '../../../services/admin_service.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/home_provider.dart';
import 'produto_form_screen.dart';
import 'unidade_form_screen.dart';
import 'admin_utils.dart';
import 'tabs/assinaturas_tab.dart';
import 'tabs/pedidos_tab.dart';
import 'tabs/usuarios_tab.dart';
import '../../widgets/animated_card_entry.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final _adminService = AdminService();
  final _searchCtrl = TextEditingController();
  final _postsSearchCtrl = TextEditingController();

  List<Produto> _produtos = [];
  List<Produto> _produtosFiltrados = [];
  List<Map<String, dynamic>> _categorias = [];
  List<Map<String, dynamic>> _marcas = [];
  List<Map<String, dynamic>> _posts = [];
  bool _loading = true;
  Timer? _debounce;
  String _postFiltroCategoria = '';

  // Filtros - única fonte de verdade
  Set<int> _filtroCategoriaIds = {};
  Set<int> _filtroMarcaIds = {};
  Set<int> _filtroUnidadeIds = {};
  String? _filtroEstoque; // 'com_estoque', 'sem_estoque', null

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 18, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) _loadTabData(_tabCtrl.index);
    });
    _loadTabData(0);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    _postsSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTabData(int tab) async {
    setState(() => _loading = true);
    try {
      if (tab == 0) {
        _produtos = await _adminService.fetchProdutos();
        _produtosFiltrados = List.from(_produtos);
        _categorias = [];
        _marcas = [];
        // Reseta filtros ao carregar a aba
        _filtroCategoriaIds = {};
        _filtroMarcaIds = {};
        _filtroUnidadeIds = {};
        _filtroEstoque = null;
      }
      else if (tab == 1) _categorias = await _adminService.fetchCategorias().then((l) => l.map((c) => {'id': c.id, 'nome': c.nome, 'icone': c.icone}).toList());
      else if (tab == 2) _marcas = await _adminService.fetchMarcas();
      else if (tab == 3) {}
      else if (tab == 4) { _posts = await _adminService.fetchPosts(); }
      else if (tab == 5) {}
      else if (tab == 6) {}
      else if (tab == 7) {}
    } catch (e) {
      debugPrint('Erro carregar tab: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _buscar(String q) async {
    setState(() => _loading = true);
    try { _produtos = await _adminService.fetchProdutos(search: q.isEmpty ? null : q); } catch (e) {
      debugPrint('Erro buscar: $e');
    }
    // Pesquisa nova reseta os filtros
    _filtroCategoriaIds = {};
    _filtroMarcaIds = {};
    _filtroUnidadeIds = {};
    _filtroEstoque = null;
    _produtosFiltrados = List.from(_produtos);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _deletarProduto(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir produto'),
        content: const Text('Tem certeza?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Excluir', style: TextStyle(color: ThemeColors.error(ctx)))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _adminService.deleteProduto(id);
      context.read<HomeProvider>().refresh();
      _loadTabData(0);
    } catch (e) {
      debugPrint('ERRO AO DELETAR: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mapErroAdmin(e))));
    }
  }

  Future<void> _confirmarExclusao(String tipo, int id, Future<void> Function() onDelete) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Excluir ${tipo == 'categoria' ? 'categoria' : 'marca'}'),
        content: Text('Tem certeza que deseja excluir esta ${tipo == 'categoria' ? 'categoria' : 'marca'}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Excluir', style: TextStyle(color: ThemeColors.error(ctx)))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await onDelete();
      if (tipo == 'categoria') _loadTabData(1); else _loadTabData(2);
      context.read<HomeProvider>().refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mapErroAdmin(e))));
    }
  }

  Future<void> _mostrarPickerCategoria({String? nomeAtual, String? iconeAtual, int? idEditando}) async {
    final nomeCtrl = TextEditingController(text: nomeAtual ?? '');
    String? iconeSelecionado = iconeAtual;
    final formKey = GlobalKey<FormState>();

    final resultado = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: AppSpacing.lg,
                right: AppSpacing.lg,
                top: AppSpacing.lg,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      idEditando != null ? 'Editar Categoria' : 'Nova Categoria',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: nomeCtrl,
                      decoration: InputDecoration(
                        labelText: 'Nome da categoria',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: ThemeColors.surface(context),
                      ),
                      autofocus: idEditando == null,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text('Escolha um ícone:', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: ThemeColors.secondaryText(context))),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: categoriaIcones.entries.map((entry) {
                        final isSelected = entry.key == iconeSelecionado;
                        return GestureDetector(
                          onTap: () => setSheetState(() => iconeSelecionado = entry.key),
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: isSelected ? ThemeColors.primary(context).withValues(alpha: 0.15) : ThemeColors.surfaceVariant(context),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected ? ThemeColors.primary(context) : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: Icon(entry.value, color: isSelected ? ThemeColors.primary(context) : ThemeColors.secondaryText(context), size: 28),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () {
                          final nome = nomeCtrl.text.trim();
                          if (nome.isEmpty) return;
                          Navigator.pop(ctx, {'nome': nome, 'icone': iconeSelecionado});
                        },
                        child: Text(idEditando != null ? 'Salvar' : 'Criar Categoria'),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (resultado == null) return;
    final nome = resultado['nome'] as String;
    final icone = resultado['icone'] as String?;

    try {
      if (idEditando != null) {
        await _adminService.updateCategoria(idEditando, nome, icone);
        _loadTabData(1);
      } else {
        await _adminService.insertCategoria(nome, icone);
        _loadTabData(1);
      }
      context.read<HomeProvider>().refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mapErroAdmin(e))));
    }
  }

  Future<void> _mostrarDialogMarca({String? nomeAtual, int? idEditando}) async {
    final nomeCtrl = TextEditingController(text: nomeAtual ?? '');
    final nome = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(idEditando != null ? 'Editar Marca' : 'Nova Marca'),
        content: TextField(
          controller: nomeCtrl,
          decoration: InputDecoration(
            labelText: 'Nome da marca',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: ThemeColors.surface(ctx),
          ),
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, nomeCtrl.text.trim()),
            child: Text('Salvar', style: TextStyle(color: ThemeColors.primary(ctx))),
          ),
        ],
      ),
    );
    if (nome == null || nome.isEmpty || nome == nomeAtual) return;
    try {
      if (idEditando != null) {
        await _adminService.updateMarca(idEditando, nome);
      } else {
        await _adminService.insertMarca(nome);
      }
      _loadTabData(2);
      context.read<HomeProvider>().refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mapErroAdmin(e))));
    }
  }

  Future<void> _editarItem(String tipo, int id, String nomeAtual, {String? iconeAtual}) async {
    if (tipo == 'categoria') {
      _mostrarPickerCategoria(nomeAtual: nomeAtual, iconeAtual: iconeAtual, idEditando: id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeColors.background(context),
      body: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // AppBar azul info
              Container(
                color: ThemeColors.info(context),
                padding: EdgeInsets.fromLTRB(AppSpacing.lg, MediaQuery.of(context).padding.top + AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
                child: SafeArea(
                  bottom: false,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () => context.pop(),
                            child: const Icon(Icons.arrow_back_rounded, color: AppColors.onInfo, size: 24),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Painel do Administrador',
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                      color: AppColors.onInfo, fontWeight: FontWeight.bold)),
                              if (context.read<AuthProvider>().user?.unidadeNome != null)
                                Text(context.read<AuthProvider>().user!.unidadeNome!,
                                    style: const TextStyle(color: AppColors.onInfo, fontSize: 11, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ],
                      ),
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: ThemeColors.surface(context),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          boxShadow: AppShadows.sm,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Image.asset('assets/logo.jpg', fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Icon(Icons.storefront_rounded, color: ThemeColors.primary(context), size: 20)),
                      ),
                    ],
                  ),
                ),
              ),
              Divider(height: 1, color: ThemeColors.divider(context)),
              // TabBar
              Container(
                color: ThemeColors.surface(context),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildTabItem('Produtos', Icons.inventory_2_rounded, 0, selected: true),
                      const SizedBox(width: AppSpacing.lg),
                      _buildTabItem('Categorias', Icons.category_rounded, 1),
                      const SizedBox(width: AppSpacing.lg),
                      _buildTabItem('Marcas', Icons.sell_rounded, 2),
                      const SizedBox(width: AppSpacing.lg),
                      _buildTabItem('Candidaturas', Icons.description_rounded, 3),
                      const SizedBox(width: AppSpacing.lg),
                      _buildTabItem('Posts', Icons.article_rounded, 4),
                      const SizedBox(width: AppSpacing.lg),
                      _buildTabItem('Lojas', Icons.store_mall_directory_rounded, 5),
                      const SizedBox(width: AppSpacing.lg),
                      _buildTabItem('Cupons', Icons.discount_rounded, 6),
                      const SizedBox(width: AppSpacing.lg),
                      _buildTabItem('Usuários', Icons.people_rounded, 7),
                      const SizedBox(width: AppSpacing.lg),
                      _buildTabItem('Verificação', Icons.cleaning_services_rounded, 8),
                      const SizedBox(width: AppSpacing.lg),
                      _buildTabItem('Pedidos', Icons.receipt_long_rounded, 9),
                      const SizedBox(width: AppSpacing.lg),
                      _buildTabItem('Assinaturas', Icons.card_membership_rounded, 10),
                    ],
                  ),
                ),
              ),
              // Content
              Expanded(
                child: _buildContent(),
              ),
            ],
          ),
          // FAB
          if (_tabCtrl.index == 0)
            Positioned(
              bottom: AppSpacing.lg,
              right: AppSpacing.lg,
              child: ElevatedButton.icon(
              onPressed: () async {
                final result = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const ProdutoFormScreen()));
                if (result == true) _loadTabData(0);
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Anunciar produto'),
              style: ElevatedButton.styleFrom(
                backgroundColor: ThemeColors.primary(context),
                foregroundColor: ThemeColors.onPrimary(context),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 8,
              ),
            ),
          ),
          ],
        ),
      );
    }

  Widget _buildTabItem(String label, IconData icon, int index, {bool selected = false}) {
    final isSelected = _tabCtrl.index == index;
    return GestureDetector(
      onTap: () => _tabCtrl.animateTo(index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: isSelected ? ThemeColors.primary(context) : Colors.transparent, width: 2),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isSelected ? ThemeColors.primary(context) : ThemeColors.secondaryText(context)),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600,
              color: isSelected ? ThemeColors.primary(context) : ThemeColors.secondaryText(context),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_tabCtrl.index == 0) return _buildProdutosTab();
    if (_tabCtrl.index == 1) return _buildCategoriasTab();
    if (_tabCtrl.index == 2) return _buildMarcasTab();
    if (_tabCtrl.index == 3) return _buildCandidaturasTab();
    if (_tabCtrl.index == 4) return _buildPostsTab();
    if (_tabCtrl.index == 5) return _buildUnidadesTab();
    if (_tabCtrl.index == 6) return _buildCuponsTab();
    if (_tabCtrl.index == 7) return const UsuariosTab();
    if (_tabCtrl.index == 8) return _buildVerificacaoLixoTab();
    if (_tabCtrl.index == 9) return const PedidosTab();
    if (_tabCtrl.index == 10) return const AssinaturasTab();
    return const SizedBox.shrink();
  }

  int get _filtrosAtivosCount => (_filtroCategoriaIds.isNotEmpty ? 1 : 0) + (_filtroMarcaIds.isNotEmpty ? 1 : 0) + (_filtroUnidadeIds.isNotEmpty ? 1 : 0) + (_filtroEstoque != null ? 1 : 0);

  /// Aplica todos os filtros ativos sobre a lista ORIGINAL de produtos.
  /// Nunca utiliza lista previamente filtrada.
  void _aplicarFiltros() {
    print('████ FILTROS: cats=$_filtroCategoriaIds marcas=$_filtroMarcaIds unidades=$_filtroUnidadeIds estoque=$_filtroEstoque');
    print('████ FILTROS: _produtos.length=${_produtos.length}');
    _produtosFiltrados = _produtos.where((p) {
      // Marca: OR entre selecionadas
      if (_filtroMarcaIds.isNotEmpty && (p.marcaId == null || !_filtroMarcaIds.contains(p.marcaId))) return false;
      // Categoria: OR entre selecionadas
      if (_filtroCategoriaIds.isNotEmpty && !_filtroCategoriaIds.contains(p.categoriaId)) return false;
      // Unidade: OR entre selecionadas
      if (_filtroUnidadeIds.isNotEmpty && (p.unidadeId == null || !_filtroUnidadeIds.contains(p.unidadeId))) return false;
      // Estoque
      if (_filtroEstoque == 'com_estoque' && (p.estoque <= 0)) return false;
      if (_filtroEstoque == 'sem_estoque' && (p.estoque > 0)) return false;
      if (_filtroEstoque == 'estoque_baixo' && (p.estoque <= 0 || p.estoque > 3)) return false;
      return true;
    }).toList();
    print('████ FILTROS: _produtosFiltrados.length=${_produtosFiltrados.length}');
    if (mounted) setState(() {});
  }

  /// Limpa TODOS os filtros e restaura a lista original
  void _resetarFiltros() {
    _filtroCategoriaIds = {};
    _filtroMarcaIds = {};
    _filtroUnidadeIds = {};
    _filtroEstoque = null;
    _produtosFiltrados = List.from(_produtos);
    if (mounted) setState(() {});
  }

  Future<void> _abrirDialogFiltros() async {
    // Carrega categorias, marcas e unidades da lista de produtos
    final cats = <Map<String, dynamic>>[];
    final brdsSet = <Map<String, dynamic>>{};
    final undsSet = <Map<String, dynamic>>{};
    for (final p in _produtos) {
      if (p.categoriaId != null && p.categoriaNome != null && !cats.any((c) => c['id'] == p.categoriaId)) {
        cats.add({'id': p.categoriaId, 'nome': p.categoriaNome});
      }
      if (p.marcaId != null && p.marcaNome != null && !brdsSet.any((b) => b['id'] == p.marcaId)) {
        brdsSet.add({'id': p.marcaId, 'nome': p.marcaNome});
      }
      if (p.unidadeId != null && p.unidadeNome != null && !undsSet.any((u) => u['id'] == p.unidadeId)) {
        undsSet.add({'id': p.unidadeId, 'nome': p.unidadeNome});
      }
    }
    cats.sort((a, b) => (a['nome'] as String).compareTo(b['nome'] as String));
    final marcas = brdsSet.toList()..sort((a, b) => (a['nome'] as String).compareTo(b['nome'] as String));
    var unidades = undsSet.toList()..sort((a, b) => (a['nome'] as String).compareTo(b['nome'] as String));
    // Busca foto_url de cada unidade
    for (var i = 0; i < unidades.length; i++) {
      try {
        final info = await Supabase.instance.client
            .from('unidades')
            .select('foto_url')
            .eq('id', unidades[i]['id'])
            .maybeSingle();
        if (info != null) unidades[i]['foto_url'] = info['foto_url'];
      } catch (_) {}
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        Set<int> tempCats = Set.from(_filtroCategoriaIds);
        Set<int> tempMarcas = Set.from(_filtroMarcaIds);
        Set<int> tempUnidades = Set.from(_filtroUnidadeIds);
        String? tempEstoque = _filtroEstoque;

        return StatefulBuilder(
          builder: (context, setInner) {
            return AlertDialog(
              title: const Text('Filtrar Produtos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text('${_produtos.length} ${_produtos.length == 1 ? 'produto' : 'produtos'} disponíveis',
                            style: TextStyle(fontSize: 12, color: ThemeColors.secondaryText(context))),
                      ),
                      // Categoria (chip style - referência do layout)
                      if (cats.isNotEmpty) ...[
                        Text('Categoria', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ThemeColors.secondaryText(context))),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8, runSpacing: 6,
                          children: cats.map((c) {
                            final isSel = tempCats.contains(c['id']);
                            return FilterChip(
                              label: Text(c['nome'] as String, style: TextStyle(
                                fontSize: 13,
                                color: isSel ? Colors.white : ThemeColors.primaryText(context),
                                fontWeight: isSel ? FontWeight.w600 : FontWeight.normal,
                              )),
                              selected: isSel,
                              onSelected: (v) => setInner(() { v ? tempCats.add(c['id'] as int) : tempCats.remove(c['id'] as int); }),
                              selectedColor: const Color(0xFFE50914),
                              checkmarkColor: Colors.white,
                              backgroundColor: ThemeColors.surfaceVariant(context),
                              side: BorderSide.none,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                      ],
                      // Marca (chip style)
                      if (marcas.isNotEmpty) ...[
                        Text('Marca', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ThemeColors.secondaryText(context))),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8, runSpacing: 6,
                          children: marcas.map((m) {
                            final isSel = tempMarcas.contains(m['id']);
                            return FilterChip(
                              label: Text(m['nome'] as String, style: TextStyle(
                                fontSize: 13,
                                color: isSel ? Colors.white : ThemeColors.primaryText(context),
                                fontWeight: isSel ? FontWeight.w600 : FontWeight.normal,
                              )),
                              selected: isSel,
                              onSelected: (v) => setInner(() { v ? tempMarcas.add(m['id'] as int) : tempMarcas.remove(m['id'] as int); }),
                              selectedColor: const Color(0xFFE50914),
                              checkmarkColor: Colors.white,
                              backgroundColor: ThemeColors.surfaceVariant(context),
                              side: BorderSide.none,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                      ],
                      // Unidade (cards horizontais - estilo do layout de referência)
                      if (unidades.isNotEmpty) ...[
                        Text('Unidade', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ThemeColors.secondaryText(context))),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 140,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: unidades.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 8),
                            itemBuilder: (context, i) {
                              final u = unidades[i];
                              final isSel = tempUnidades.contains(u['id']);
                              final fotoUrl = u['foto_url'] as String?;
                              return GestureDetector(
                                onTap: () => setInner(() { isSel ? tempUnidades.remove(u['id']) : tempUnidades.add(u['id'] as int); }),
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
                        const SizedBox(height: 16),
                      ],
                      // Estoque
                      Text('Estoque', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ThemeColors.secondaryText(context))),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildEstoqueChip('Com estoque', tempEstoque == 'com_estoque', () => setInner(() => tempEstoque = tempEstoque == 'com_estoque' ? null : 'com_estoque')),
                            const SizedBox(width: 8),
                            _buildEstoqueChip('Estoque baixo', tempEstoque == 'estoque_baixo', () => setInner(() => tempEstoque = tempEstoque == 'estoque_baixo' ? null : 'estoque_baixo')),
                            const SizedBox(width: 8),
                            _buildEstoqueChip('Sem estoque', tempEstoque == 'sem_estoque', () => setInner(() => tempEstoque = tempEstoque == 'sem_estoque' ? null : 'sem_estoque')),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, {'limpar': true}),
                  child: const Text('Limpar', style: TextStyle(color: Color(0xFFC6C6C6))),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, {
                    'categorias': tempCats,
                    'marcas': tempMarcas,
                    'unidades': tempUnidades,
                    'estoque': tempEstoque,
                  }),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE50914), foregroundColor: Colors.white),
                  child: const Text('Aplicar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) return;
    if (result['limpar'] == true) {
      _resetarFiltros();
    } else {
      setState(() {
        _filtroCategoriaIds = Set<int>.from(result['categorias'] as Set<int>);
        _filtroMarcaIds = Set<int>.from(result['marcas'] as Set<int>);
        _filtroUnidadeIds = Set<int>.from(result['unidades'] as Set<int>);
        _filtroEstoque = result['estoque'] as String?;
      });
      _aplicarFiltros();
    }
  }

  Widget _buildEstoqueChip(String label, bool selected, VoidCallback onTap) {
    Color chipColor;
    switch (label) {
      case 'Estoque baixo': chipColor = const Color(0xFFFFAD01); break;
      case 'Sem estoque': chipColor = const Color(0xFFF23D4F); break;
      default: chipColor = const Color(0xFFE50914);
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? chipColor.withValues(alpha: 0.1) : const Color(0xFF1F1F1F),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? chipColor : const Color(0xFFE0E0E0)),
        ),
        child: Text(label, style: TextStyle(
          fontSize: 13,
          color: selected ? chipColor : const Color(0xFFC6C6C6),
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        )),
      ),
    );
  }

  Widget _buildUnidadeFallback(String nome) {
    return Container(
      color: const Color(0xFF1F1F1F),
      child: Center(
        child: Text(
          nome.isNotEmpty ? nome[0].toUpperCase() : '?',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF9C9C9C)),
        ),
      ),
    );
  }

  Widget _buildProdutosTab() {
    return Column(
      children: [
        // Search
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 8, AppSpacing.lg, 8),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Buscar',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              filled: true,
              fillColor: ThemeColors.surface(context),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
            onChanged: (q) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 400), () => _buscar(q));
            },
          ),
        ),
        // Status row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${_produtosFiltrados.length} ${_produtosFiltrados.length == 1 ? 'produto' : 'produtos'}${_produtosFiltrados.length != _produtos.length ? ' de ${_produtos.length}' : ''}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: ThemeColors.secondaryText(context))),
              ActionChip(
                avatar: Icon(Icons.filter_list_rounded, size: 16, color: ThemeColors.primary(context)),
                label: Text(_filtrosAtivosCount > 0 ? 'Filtrar ($_filtrosAtivosCount)' : 'Filtrar', style: const TextStyle(fontSize: 12)),
                onPressed: _abrirDialogFiltros,
                backgroundColor: _filtrosAtivosCount > 0 ? ThemeColors.primary(context).withValues(alpha: 0.1) : ThemeColors.surface(context),
                side: BorderSide(color: _filtrosAtivosCount > 0 ? ThemeColors.primary(context) : ThemeColors.outline(context)),
              ),
            ],
          ),
        ),
        // List
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _produtosFiltrados.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off_rounded, size: 48, color: ThemeColors.hint(context)),
                          const SizedBox(height: 12),
                          Text('Nenhum produto encontrado', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text('Tente alterar os filtros ou a pesquisa.', style: TextStyle(color: ThemeColors.secondaryText(context))),
                          const SizedBox(height: 12),
                          TextButton.icon(
                            onPressed: _resetarFiltros,
                            icon: const Icon(Icons.clear_all_rounded, size: 18),
                            label: const Text('Limpar filtros'),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 120),
                      itemCount: _produtosFiltrados.length,
                      itemBuilder: (context, index) {
                        final p = _produtosFiltrados[index];
                        return AnimatedCardEntry(
                          index: index,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.sm),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: SizedBox(
                                      width: 56, height: 56,
                                      child: p.urlImagem.isNotEmpty
                                          ? CachedNetworkImage(imageUrl: p.urlImagem.first, fit: BoxFit.cover,
                                              errorWidget: (_, __, ___) => _imagePlaceholder(),
                                              placeholder: (_, __) => Container(color: Colors.white))
                                          : _imagePlaceholder(),
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(p.nome, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                                        const SizedBox(height: 2),
                                        Text(p.categoriaNome ?? 'Sem categoria',
                                            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: ThemeColors.secondaryText(context)), maxLines: 1),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            Container(
                                              width: 8, height: 8,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: p.estoque > 0 ? (p.estoque <= 3 ? const Color(0xFFFFAD01) : const Color(0xFF00A650)) : const Color(0xFFF23D4F),
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              p.estoque > 0 ? '${p.estoque} ${p.estoque == 1 ? 'unidade' : 'unidades'}${p.estoque <= 3 ? ' - estoque baixo' : ''}' : 'Sem estoque',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: p.estoque > 0 ? (p.estoque <= 3 ? const Color(0xFFFFAD01) : const Color(0xFF00A650)) : const Color(0xFFF23D4F),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (p.unidadeNome != null)
                                          Text(p.unidadeNome ?? '', style: TextStyle(fontSize: 10, color: ThemeColors.primary(context), fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        iconSize: 20,
                                        icon: Icon(Icons.edit_rounded, color: ThemeColors.info(context), size: 18),
                                        onPressed: () async {
                                          final result = await Navigator.push<bool>(
                                            context,
                                          MaterialPageRoute(builder: (_) => ProdutoFormScreen(produto: {
                                            'id': p.id, 'nome': p.nome, 'descricao': p.descricao,
                                            'preco': p.preco, 'categoria_id': p.categoriaId,
                                            'marca_id': p.marcaId, 'em_promocao': p.emPromocao,
                                            'url_imagem': p.urlImagem.isNotEmpty ? p.urlImagem : null, 'estoque': p.estoque,
                                            'unidade_id': p.unidadeId,
                                          })),
                                          );
                                          if (result == true) _loadTabData(0);
                                        },
                                      ),
                                      IconButton(
                                        iconSize: 20,
                                        icon: Icon(Icons.delete_rounded, color: ThemeColors.error(context), size: 18),
                                        onPressed: () => _deletarProduto(p.id),
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

  Widget _imagePlaceholder() {
    return Container(
      color: ThemeColors.surfaceVariant(context),
      child: Icon(Icons.image_outlined, color: ThemeColors.hint(context), size: 24),
    );
  }

  Widget _buildCategoriasTab() {
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
                    onPressed: () => _mostrarPickerCategoria(),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Nova Categoria'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ThemeColors.primary(context),
                      foregroundColor: ThemeColors.onPrimary(context),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _categorias.isEmpty
                    ? Center(child: Text('Nenhuma categoria', style: TextStyle(color: ThemeColors.secondaryText(context))))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                        itemCount: _categorias.length,
                        itemBuilder: (context, index) {
                          final c = _categorias[index];
                          final icone = resolverIconeCategoria(c['icone'] as String?, c['nome'] as String);
                          return AnimatedCardEntry(
                            index: index,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListTile(
                                leading: Icon(icone, color: ThemeColors.primary(context)),
                                title: Text(c['nome'] as String),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(Icons.edit_rounded, color: ThemeColors.info(context)),
                                      onPressed: () => _editarItem('categoria', c['id'] as int, c['nome'] as String, iconeAtual: c['icone'] as String?),
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.delete_outline_rounded, color: ThemeColors.error(context)),
                                      onPressed: () => _confirmarExclusao('categoria', c['id'] as int, () => _adminService.deleteCategoria(c['id'] as int)),
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

  Widget _buildMarcasTab() {
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
                    onPressed: () => _mostrarDialogMarca(),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Nova Marca'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ThemeColors.primary(context),
                      foregroundColor: ThemeColors.onPrimary(context),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _marcas.isEmpty
                    ? Center(child: Text('Nenhuma marca', style: TextStyle(color: ThemeColors.secondaryText(context))))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                        itemCount: _marcas.length,
                        itemBuilder: (context, index) {
                          final m = _marcas[index];
                          return AnimatedCardEntry(
                            index: index,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListTile(
                                leading: Icon(Icons.sell_rounded, color: ThemeColors.primary(context)),
                                title: Text(m['nome'] as String),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(Icons.edit_rounded, color: ThemeColors.info(context)),
                                      onPressed: () => _mostrarDialogMarca(nomeAtual: m['nome'] as String, idEditando: m['id'] as int),
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.delete_outline_rounded, color: ThemeColors.error(context)),
                                      onPressed: () => _confirmarExclusao('marca', m['id'] as int, () => _adminService.deleteMarca(m['id'] as int)),
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

  // ─── CANDIDATURAS TAB ───────────────────────────────

  Widget _buildCandidaturasTab() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _adminService.fetchCandidaturas(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Erro ao carregar: ${snapshot.error}', style: TextStyle(color: ThemeColors.error(context))));
        }
        final candidaturas = snapshot.data ?? [];
        if (candidaturas.isEmpty) {
          return Center(child: Text('Nenhuma candidatura recebida', style: TextStyle(color: ThemeColors.secondaryText(context))));
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
                  backgroundColor: ThemeColors.primary(context).withValues(alpha: 0.1),
                  child: Text(( (c['nome'] as String? ?? '').isEmpty ? '?' : (c['nome'] as String? ?? '?')[0] ).toUpperCase(),
                      style: TextStyle(color: ThemeColors.primary(context), fontWeight: FontWeight.bold)),
                ),
                title: Text(c['nome'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${c['email'] ?? ''}  •  ${c['telefone'] ?? ''}', style: TextStyle(fontSize: 12, color: ThemeColors.secondaryText(context))),
                    Text('Vaga: ${vagaTitulo ?? ''}', style: TextStyle(fontSize: 11, color: ThemeColors.hint(context))),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (c['url_curriculo'] != null)
                      IconButton(
                        icon: Icon(Icons.download_rounded, color: ThemeColors.primary(context)),
                        onPressed: () async {
                          final uri = Uri.tryParse(c['url_curriculo'] as String);
                          if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
                        },
                      ),
                    IconButton(
                      icon: Icon(Icons.delete_outline_rounded, color: ThemeColors.error(context)),
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Excluir candidatura'),
                            content: const Text('Tem certeza?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                              TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Excluir', style: TextStyle(color: ThemeColors.error(ctx)))),
                            ],
                          ),
                        );
                        if (confirm != true) return;
                        try {
                          await _adminService.deleteCandidatura('${c['id']}');
                          if (mounted) setState(() {});
                        } catch (e) {
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mapErroAdmin(e))));
                        }
                      },
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

  // ─── POSTS TAB ──────────────────────────────────────

  Widget _buildPostsTab() {
    final q = _postsSearchCtrl.text.toLowerCase();
    var posts = q.isEmpty ? _posts : _posts.where((p) =>
      (p['titulo'] as String? ?? '').toLowerCase().contains(q) ||
      (p['categoria'] as String? ?? '').toLowerCase().contains(q)
    ).toList();
    if (_postFiltroCategoria.isNotEmpty) {
      posts = posts.where((p) => (p['categoria'] as String? ?? '').toLowerCase() == _postFiltroCategoria.toLowerCase()).toList();
    }

    return Stack(
      children: [
        Column(
          children: [
            // Filtros de categoria
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, 8, AppSpacing.md, 0),
              child: SizedBox(
                height: 34,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _buildPostChip('Todas', _postFiltroCategoria.isEmpty, () => setState(() => _postFiltroCategoria = '')),
                    const SizedBox(width: 6),
                    _buildPostChip('Avisos', _postFiltroCategoria == 'avisos', () => setState(() => _postFiltroCategoria = 'avisos')),
                    const SizedBox(width: 6),
                    _buildPostChip('Eventos', _postFiltroCategoria == 'eventos', () => setState(() => _postFiltroCategoria = 'eventos')),
                    const SizedBox(width: 6),
                    _buildPostChip('Novidades', _postFiltroCategoria == 'novidades', () => setState(() => _postFiltroCategoria = 'novidades')),
                    const SizedBox(width: 6),
                    _buildPostChip('Vagas', _postFiltroCategoria == 'vagas', () => setState(() => _postFiltroCategoria = 'vagas')),
                  ],
                ),
              ),
            ),
            _buildPostsSearchBar(context),
            Expanded(
              child: _posts.isEmpty && q.isEmpty
                  ? Center(child: Text('Nenhum post', style: TextStyle(color: ThemeColors.secondaryText(context))))
                      : posts.isEmpty
                          ? Center(child: Text('Nenhum post encontrado', style: TextStyle(color: ThemeColors.secondaryText(context))))
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, 80),
                              itemCount: posts.length,
                              itemBuilder: (context, index) {
                                final p = posts[index];
                                final autor = p['perfis'] is Map ? (p['perfis'] as Map)['nome'] as String? : null;
                                final funcao = p['perfis'] is Map ? (p['perfis'] as Map)['funcao'] as String? : null;
                                final unidade = p['unidades'] is Map ? (p['unidades'] as Map)['nome'] as String? : null;
                                return AnimatedCardEntry(
                                  index: index,
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.surface,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(AppSpacing.sm),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(8),
                                            child: SizedBox(
                                              width: 56, height: 56,
                                              child: p['url_imagem'] != null && (p['url_imagem'] as String).isNotEmpty
                                                  ? CachedNetworkImage(imageUrl: p['url_imagem'] as String, fit: BoxFit.cover,
                                                      errorWidget: (_, __, ___) => _postMediaPlaceholder(p['url_youtube'] as String?))
                                                  : _postMediaPlaceholder(p['url_youtube'] as String?),
                                            ),
                                          ),
                                          const SizedBox(width: AppSpacing.sm),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Text(p['titulo'] as String? ?? '', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                                                  const SizedBox(height: 4),
                                                  Row(
                                                    children: [
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: _corCategoriaPost(p['categoria'] as String?).withValues(alpha: 0.15),
                                                          borderRadius: BorderRadius.circular(4),
                                                        ),
                                                        child: Text(p['categoria'] ?? '', style: TextStyle(fontSize: 9, color: _corCategoriaPost(p['categoria'] as String?), fontWeight: FontWeight.w700)),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Row(
                                                    children: [
                                                      Icon(Icons.person_rounded, size: 12, color: ThemeColors.secondaryText(context)),
                                                      const SizedBox(width: 4),
                                                      Text(autor ?? '', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: ThemeColors.secondaryText(context)), maxLines: 1, overflow: TextOverflow.ellipsis),
                                                      if (funcao != null && funcao != 'usuario') ...[
                                                        const SizedBox(width: 4),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                          decoration: BoxDecoration(
                                                            color: ThemeColors.secondaryText(context).withValues(alpha: 0.1),
                                                            borderRadius: BorderRadius.circular(3),
                                                          ),
                                                          child: Text(
                                                            funcao,
                                                            style: TextStyle(fontSize: 8, color: ThemeColors.secondaryText(context), fontWeight: FontWeight.w600),
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                  if (unidade != null) ...[
                                                    const SizedBox(height: 2),
                                                    Row(
                                                      children: [
                                                        Icon(Icons.store_rounded, size: 12, color: const Color(0xFFE50914)),
                                                        const SizedBox(width: 4),
                                                        Expanded(
                                                          child: Text(unidade, style: const TextStyle(fontSize: 11, color: Color(0xFFE50914), fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                              ],
                                            ),
                                          ),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                iconSize: 20,
                                                icon: Icon(Icons.chat_bubble_outline_rounded, color: ThemeColors.primary(context), size: 18),
                                                onPressed: () => _mostrarComentariosPost(p['id'] as String),
                                              ),
                                              IconButton(
                                                iconSize: 20,
                                                icon: Icon(Icons.edit_rounded, color: ThemeColors.info(context), size: 18),
                                                onPressed: () => _mostrarDialogPost(
                                                  idEditando: p['id'] as String,
                                                  tituloAtual: p['titulo'] as String?,
                                                  descricaoAtual: p['descricao'] as String?,
                                                  categoriaAtual: p['categoria'] as String?,
                                                  imagemAtual: p['url_imagem'] as String?,
                                                  youtubeAtual: p['url_youtube'] as String?,
                                                  unidadeIdAtual: p['unidade_id'] as int?,
                                                ),
                                              ),
                                              IconButton(
                                                iconSize: 20,
                                                icon: Icon(Icons.delete_outline_rounded, color: ThemeColors.error(context), size: 18),
                                                onPressed: () => _confirmarExclusaoPost(p['id'] as String),
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
        ),
        Positioned(
          bottom: 24,
          right: 24,
          child: FloatingActionButton.extended(
            onPressed: () => _mostrarDialogPost(),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Novo Post'),
            backgroundColor: ThemeColors.primary(context),
            foregroundColor: ThemeColors.onPrimary(context),
          ),
        ),
      ],
    );
  }

  Widget _buildPostChip(String label, bool selected, VoidCallback onTap) {
    final cor = label == 'Avisos'
        ? const Color(0xFFFFAD01)
        : label == 'Eventos'
            ? const Color(0xFFE50914)
            : label == 'Novidades'
                ? const Color(0xFF00A650)
                : label == 'Vagas'
                    ? const Color(0xFFF23D4F)
                    : const Color(0xFFC6C6C6);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? cor.withValues(alpha: 0.15) : const Color(0xFF1F1F1F),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: selected ? cor : const Color(0xFFC6C6C6))),
      ),
    );
  }

  Widget _buildPostsSearchBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 8, AppSpacing.md, 8),
      child: TextField(
        controller: _postsSearchCtrl,
        decoration: InputDecoration(
          hintText: 'Buscar',
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          filled: true,
          fillColor: ThemeColors.surface(context),
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Future<void> _confirmarExclusaoPost(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir post'),
        content: const Text('Tem certeza?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Excluir', style: TextStyle(color: ThemeColors.error(ctx)))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _adminService.deletePost(id);
      _posts = await _adminService.fetchPosts();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mapErroAdmin(e))));
    }
  }

  /// Abre a lista de comentários do post com opção de excluir (moderação).
  Future<void> _mostrarComentariosPost(String postId) async {
    List<Map<String, dynamic>> comentarios;
    try {
      comentarios = await _adminService.fetchComentariosPost(postId);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mapErroAdmin(e))));
      return;
    }
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 8, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Comentários (${comentarios.length})',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: ThemeColors.divider(context)),
                  Expanded(
                    child: comentarios.isEmpty
                        ? Center(
                            child: Text('Nenhum comentário',
                                style: TextStyle(color: ThemeColors.secondaryText(context))))
                        : ListView.builder(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            itemCount: comentarios.length,
                            itemBuilder: (context, i) {
                              final c = comentarios[i];
                              final perfil = c['perfis'] is Map ? (c['perfis'] as Map) : null;
                              final nome = perfil?['nome'] as String? ?? '';
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: ThemeColors.surface(context),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundColor: ThemeColors.primary(context).withValues(alpha: 0.1),
                                      child: Text(
                                        nome.isEmpty ? '?' : nome[0].toUpperCase(),
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: ThemeColors.primary(context),
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(nome,
                                              style: const TextStyle(
                                                  fontSize: 12, fontWeight: FontWeight.w600)),
                                          Text(c['texto'] as String? ?? '',
                                              style: const TextStyle(fontSize: 12)),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      iconSize: 20,
                                      icon: Icon(Icons.delete_outline_rounded,
                                          color: ThemeColors.error(context), size: 20),
                                      onPressed: () async {
                                        if (!await confirmarExclusao(context, titulo: 'Excluir comentário')) {
                                          return;
                                        }
                                        try {
                                          await _adminService.deleteComentario(c['id'] as String);
                                          comentarios.removeAt(i);
                                          setSheetState(() {});
                                        } catch (e) {
                                          if (mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(content: Text(mapErroAdmin(e))));
                                          }
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Mostra thumbnail de post ou ícone de vídeo quando não há imagem.
  Widget _postMediaPlaceholder(String? youtubeUrl) {
    if (youtubeUrl != null && youtubeUrl.isNotEmpty) {
      return Container(
        color: const Color(0xFF1F1F1F),
        child: const Icon(Icons.play_circle_outline_rounded, color: Color(0xFF9C9C9C), size: 28),
      );
    }
    return Container(
      color: const Color(0xFF1F1F1F),
      child: const Icon(Icons.article_outlined, color: Color(0xFF9C9C9C), size: 28),
    );
  }

  Color _corCategoriaPost(String? categoria) {
    switch (categoria?.toLowerCase()) {
      case 'avisos': return const Color(0xFFFFAD01);
      case 'eventos': return const Color(0xFFE50914);
      case 'novidades': return const Color(0xFF00A650);
      case 'vagas': return const Color(0xFFF23D4F);
      default: return const Color(0xFFC6C6C6);
    }
  }

  Future<void> _mostrarDialogPost({String? idEditando, String? tituloAtual, String? descricaoAtual, String? categoriaAtual, String? imagemAtual, String? youtubeAtual, int? unidadeIdAtual}) async {
    final tituloCtrl = TextEditingController(text: tituloAtual ?? '');
    final descricaoCtrl = TextEditingController(text: descricaoAtual ?? '');
    final youtubeCtrl = TextEditingController(text: youtubeAtual ?? '');
    bool isVideo = youtubeAtual != null && youtubeAtual.isNotEmpty;
    String? imagemUrl = imagemAtual;
    const categoriasPost = ['Avisos', 'Eventos', 'Novidades', 'Vagas'];
    String? categoriaSelecionada = categoriasPost.contains(categoriaAtual) ? categoriaAtual : null;
    bool salvando = false;
    String? erroUpload;

    // Carrega unidades
    final unidades = await Supabase.instance.client
        .from('unidades')
        .select('id, nome, bairro, foto_url')
        .order('nome');
    final unidadesList = (unidades as List).cast<Map<String, dynamic>>();
    int? postUnidadeId = unidadeIdAtual ?? context.read<AuthProvider>().user?.unidadeId;
    String? postUnidadeNome;
    if (postUnidadeId != null) {
      final u = unidadesList.firstWhere((u) => u['id'] == postUnidadeId, orElse: () => {'nome': '', 'bairro': ''});
      if (u['nome'] != '') postUnidadeNome = '${u['nome']} (${u['bairro'] ?? ''})';
    }

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 24, right: 24, top: 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          idEditando != null ? 'Editar Post' : 'Novo Post',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Título
                    TextField(
                      controller: tituloCtrl,
                      maxLength: 50,
                      decoration: InputDecoration(
                        labelText: 'Título',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: ThemeColors.surface(context),
                      ),
                      onChanged: (_) => setSheetState(() {}),
                    ),
                    const SizedBox(height: 12),
                    // Descrição
                    TextField(
                      controller: descricaoCtrl,
                      maxLines: 4,
                      maxLength: 2000,
                      decoration: InputDecoration(
                        labelText: 'Descrição',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: ThemeColors.surface(context),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Categoria (dropdown)
                    DropdownButtonFormField<String>(
                      value: categoriasPost.contains(categoriaSelecionada) ? categoriaSelecionada : null,
                      decoration: InputDecoration(
                        labelText: 'Categoria',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: ThemeColors.surface(context),
                      ),
                      items: categoriasPost.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      onChanged: (v) => setSheetState(() => categoriaSelecionada = v),
                    ),
                    const SizedBox(height: 16),
                    // Tipo de mídia: Imagem ou Vídeo
                    Row(
                      children: [
                        const Text('Tipo de mídia:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 12),
                        ChoiceChip(
                          label: const Text('Imagem', style: TextStyle(fontSize: 12)),
                          selected: !isVideo,
                          onSelected: (v) => setSheetState(() { isVideo = false; erroUpload = null; }),
                          selectedColor: ThemeColors.primary(context).withValues(alpha: 0.15),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('Vídeo', style: TextStyle(fontSize: 12)),
                          selected: isVideo,
                          onSelected: (v) => setSheetState(() => isVideo = true),
                          selectedColor: ThemeColors.primary(context).withValues(alpha: 0.15),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Upload imagem ou YouTube
                    if (!isVideo) ...[
                      // Preview da imagem
                      if (imagemUrl != null && imagemUrl!.isNotEmpty)
                        Container(
                          height: 120,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: const Color(0xFF1F1F1F),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              CachedNetworkImage(imageUrl: imagemUrl!, fit: BoxFit.cover),
                              Positioned(
                                top: 4, right: 4,
                                child: GestureDetector(
                                  onTap: () => setSheetState(() => imagemUrl = null),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(color: Color(0xFFF23D4F), shape: BoxShape.circle),
                                    child: const Icon(Icons.close_rounded, color: Colors.white, size: 16),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        GestureDetector(
                          onTap: () async {
                            final picker = ImagePicker();
                            final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
                            if (file == null) return;
                            setSheetState(() => salvando = true);
                            try {
                              final bytes = await file.readAsBytes();
                              final fileName = 'post_${DateTime.now().millisecondsSinceEpoch}.jpg';
                              await Supabase.instance.client.storage.from('Produtos').uploadBinary(
                                fileName, bytes,
                                fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
                              );
                              imagemUrl = Supabase.instance.client.storage.from('Produtos').getPublicUrl(fileName);
                              erroUpload = null;
                            } catch (e) {
                              erroUpload = 'Erro ao fazer upload: $e';
                            }
                            setSheetState(() => salvando = false);
                          },
                          child: Container(
                            height: 120,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE0E0E0), width: 1.5, strokeAlign: BorderSide.strokeAlignInside),
                              color: const Color(0xFFF9F9F9),
                            ),
                            child: Center(
                              child: salvando
                                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                                  : Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.add_photo_alternate_outlined, size: 36, color: const Color(0xFF9C9C9C)),
                                        const SizedBox(height: 4),
                                        Text('Adicionar foto', style: TextStyle(fontSize: 13, color: const Color(0xFF9C9C9C))),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                      if (erroUpload != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(erroUpload!, style: const TextStyle(fontSize: 11, color: Color(0xFFF23D4F))),
                        ),
                    ] else ...[
                      TextField(
                        controller: youtubeCtrl,
                        decoration: InputDecoration(
                          labelText: 'URL do YouTube',
                          hintText: 'https://youtube.com/watch?v=...',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: ThemeColors.surface(context),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    // Unidade (cards horizontais)
                    const Text('Unidade', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 100,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: unidadesList.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, i) {
                          final u = unidadesList[i];
                          final isSel = postUnidadeId == u['id'];
                          final fotoUrl = u['foto_url'] as String?;
                          return GestureDetector(
                            onTap: () => setSheetState(() {
                              postUnidadeId = u['id'] as int;
                              postUnidadeNome = '${u['nome']} (${u['bairro'] ?? ''})';
                            }),
                            child: Container(
                              width: 100,
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
                                              ? Image.network(fotoUrl, fit: BoxFit.cover)
                                              : Container(
                                                  color: const Color(0xFFF0F0F0),
                                                  child: Center(
                                                    child: Text(
                                                      (u['nome'] as String).isNotEmpty ? (u['nome'] as String)[0].toUpperCase() : '?',
                                                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Color(0xFFBBBBBB)),
                                                    ),
                                                  ),
                                                ),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                        child: Text(
                                          u['nome'] as String,
                                          textAlign: TextAlign.center,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 9,
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
                                      child: Icon(Icons.check_circle_rounded, size: 16, color: const Color(0xFFE50914)),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Ações
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
                            onPressed: salvando ? null : () {
                              final titulo = tituloCtrl.text.trim();
                              final descricao = descricaoCtrl.text.trim();
                              String? erro;
                              if (titulo.isEmpty) {
                                erro = 'Preencha o título.';
                              } else if (descricao.isEmpty) {
                                erro = 'Preencha a descrição.';
                              } else if (categoriaSelecionada == null) {
                                erro = 'Selecione uma categoria.';
                              } else if (postUnidadeId == null) {
                                erro = 'Selecione uma unidade.';
                              } else if (isVideo && youtubeCtrl.text.trim().isEmpty) {
                                erro = 'Informe a URL do YouTube.';
                              } else if (!isVideo && (imagemUrl == null || imagemUrl!.isEmpty)) {
                                erro = 'Adicione uma imagem.';
                              }
                              if (erro != null) {
                                setSheetState(() => erroUpload = erro);
                                return;
                              }
                              Navigator.pop(ctx, {
                                'titulo': titulo,
                                'descricao': descricao,
                                'categoria': categoriaSelecionada ?? '',
                                'url_imagem': isVideo ? '' : (imagemUrl ?? ''),
                                'url_youtube': isVideo ? youtubeCtrl.text.trim() : '',
                                'unidade_id': postUnidadeId,
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFE50914),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: salvando
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text('Salvar'),
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
        );
      },
    );

    if (result == null) return;
    try {
      if (idEditando != null) {
        await _adminService.updatePost(idEditando, result);
      } else {
        // Usa unidade selecionada no diálogo, ou fallback para a do usuário
        result['unidade_id'] = result['unidade_id'] ?? context.read<AuthProvider>().user?.unidadeId?.toString();
        await _adminService.insertPost(result);
      }
      _posts = await _adminService.fetchPosts();
      setState(() {});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mapErroAdmin(e))));
    }
  }

  // ─── UNIDADES TAB ───────────────────────────────────

  Widget _buildUnidadesTab() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: Supabase.instance.client.from('unidades').select().order('ordem'),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Erro ao carregar', style: TextStyle(color: ThemeColors.error(context))));
        }
        final unidades = (snapshot.data as List?) ?? [];
        if (unidades.isEmpty) {
          return Center(child: Text('Nenhuma unidade', style: TextStyle(color: ThemeColors.secondaryText(context))));
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final result = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(builder: (_) => const UnidadeFormScreen()),
                    );
                    if (result == true) setState(() {});
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Nova Unidade'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ThemeColors.primary(context),
                    foregroundColor: ThemeColors.onPrimary(context),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                itemCount: unidades.length,
                itemBuilder: (context, index) {
                  final u = unidades[index];
                  final aberto = _verificarAbertoAdmin(u);
                  final fotoUrl = u['foto_url'] as String?;
                  final nome = u['nome'] as String? ?? '';
                  final bairro = u['bairro'] as String?;
                  final endereco = u['endereco'] as String?;
                  final ativa = u['ativa'] == true;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: AnimatedCardEntry(
                      index: index,
                      child: GestureDetector(
                        onTap: () async {
                          final result = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(builder: (_) => UnidadeFormScreen(unidade: u)),
                          );
                          if (result == true) setState(() {});
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF2C2C2C)),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFE50914).withValues(alpha: 0.12),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Stack(
                                children: [
                                  Container(
                                    width: double.infinity,
                                    height: 160,
                                    color: const Color(0xFF1F1F1F),
                                    child: fotoUrl != null && fotoUrl.isNotEmpty
                                        ? Image.network(fotoUrl, fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => _buildUnidadeFallback(nome))
                                        : _buildUnidadeFallback(nome),
                                  ),
                                  Positioned(
                                    top: 12,
                                    right: 12,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(20),
                                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4)],
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 8, height: 8,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: aberto ? const Color(0xFF00A650) : const Color(0xFFF23D4F),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            aberto ? 'Aberto' : 'Fechado',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: aberto ? const Color(0xFF00A650) : const Color(0xFFF23D4F),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  // Botões de ação no topo esquerdo
                                  Positioned(
                                    top: 12,
                                    left: 12,
                                    child: Row(
                                      children: [
                                        Container(
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4)],
                                          ),
                                          child: IconButton(
                                            iconSize: 18,
                                            icon: Icon(Icons.edit_rounded, color: ThemeColors.info(context)),
                                            onPressed: () async {
                                              final result = await Navigator.push<bool>(
                                                context,
                                                MaterialPageRoute(builder: (_) => UnidadeFormScreen(unidade: u)),
                                              );
                                              if (result == true) setState(() {});
                                            },
                                          ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4)],
                                          ),
                                          child: IconButton(
                                            iconSize: 18,
                                            icon: Icon(Icons.delete_outline_rounded, color: ThemeColors.error(context)),
                                            onPressed: () => _confirmarExclusaoUnidade(u['id'] as int),
                                          ),
                                        ),
                                      ],
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
                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFFEDEDED)),
                                        maxLines: 1, overflow: TextOverflow.ellipsis),
                                    const SizedBox(height: 4),
                                    if (bairro != null && bairro.isNotEmpty) ...[
                                      Row(
                                        children: [
                                          Icon(Icons.location_on_rounded, size: 14, color: const Color(0xFFE50914)),
                                          const SizedBox(width: 6),
                                          Text(bairro,
                                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFFE50914)),
                                              maxLines: 1, overflow: TextOverflow.ellipsis),
                                        ],
                                      ),
                                    ],
                                    if (endereco != null && endereco.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(Icons.location_on_rounded, size: 14, color: const Color(0xFFE50914)),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(endereco,
                                                style: const TextStyle(fontSize: 12, color: Color(0xFFE50914)),
                                                maxLines: 1, overflow: TextOverflow.ellipsis),
                                          ),
                                        ],
                                      ),
                                    ],
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: ativa ? const Color(0xFF00A650).withValues(alpha: 0.15) : const Color(0xFFF23D4F).withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            ativa ? 'Ativa' : 'Inativa',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: ativa ? const Color(0xFF00A650) : const Color(0xFFF23D4F),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  /// Verifica se a unidade está aberta com base nos horários
  bool _verificarAbertoAdmin(Map<String, dynamic> u) {
    final dias = ['dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sab'];
    final hoje = dias[DateTime.now().weekday % 7];
    final chave = 'horario_$hoje';
    final horaStr = u[chave] as String?;
    if (horaStr == null || horaStr.isEmpty || horaStr == 'Fechado') return false;
    final partes = horaStr.split('-');
    if (partes.length != 2) return false;
    try {
      final agora = DateTime.now();
      final abertura = partes[0].split(':').map(int.parse).toList();
      final fechamento = partes[1].split(':').map(int.parse).toList();
      final agoraMin = agora.hour * 60 + agora.minute;
      final aberturaMin = abertura[0] * 60 + abertura[1];
      final fechamentoMin = fechamento[0] * 60 + fechamento[1];
      return agoraMin >= aberturaMin && agoraMin <= fechamentoMin;
    } catch (e) {
      return false;
    }
  }

  Future<void> _confirmarExclusaoUnidade(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir unidade'),
        content: const Text('Tem certeza?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Excluir', style: TextStyle(color: ThemeColors.error(ctx)))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await Supabase.instance.client.from('unidades').delete().eq('id', id);
      setState(() {});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mapErroAdmin(e))));
    }
  }

  // ─── CUPONS TAB ─────────────────────────────────────

  Widget _buildCuponsTab() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: Supabase.instance.client.from('cupons').select().order('codigo'),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Erro ao carregar', style: TextStyle(color: ThemeColors.error(context))));
        }
        final cupons = (snapshot.data as List?) ?? [];
        if (cupons.isEmpty) {
          return Center(child: Text('Nenhum cupom', style: TextStyle(color: ThemeColors.secondaryText(context))));
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () => _mostrarDialogCupom(),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Novo Cupom'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ThemeColors.primary(context),
                    foregroundColor: ThemeColors.onPrimary(context),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                itemCount: cupons.length,
                itemBuilder: (context, index) {
                  final c = cupons[index];
                  return AnimatedCardEntry(
                    index: index,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        title: Text(c['codigo'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Row(
                        children: [
                          Text(
                            c['tipo'] == 'percentual'
                                ? '${((c['valor'] as num?) ?? 0).toStringAsFixed(0)}% de desconto'
                                : 'R\$ ${c['valor'] ?? ''} de desconto',
                            style: TextStyle(fontSize: 12, color: ThemeColors.secondaryText(context)),
                          ),
                          const SizedBox(width: 8),
                          if ((c['valor_minimo'] as num? ?? 0) > 0)
                            Text('mín. R\$ ${c['valor_minimo']}', style: TextStyle(fontSize: 12, color: ThemeColors.hint(context))),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: c['ativo'] == true ? ThemeColors.success(context).withValues(alpha: 0.15) : ThemeColors.error(context).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              c['ativo'] == true ? 'Ativo' : 'Inativo',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: c['ativo'] == true ? ThemeColors.success(context) : ThemeColors.error(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(Icons.edit_rounded, color: ThemeColors.info(context)),
                            onPressed: () => _mostrarDialogCupom(
                              idEditando: c['id'] as int,
                              codigoAtual: c['codigo'] as String?,
                              tipoAtual: c['tipo'] as String?,
                              valorAtual: (c['valor'] as num?)?.toDouble(),
                              valorMinimoAtual: (c['valor_minimo'] as num?)?.toDouble(),
                              dataValidadeAtual: c['data_validade'] as String?,
                              usoMaximoAtual: c['uso_maximo'] as int?,
                              ativoAtual: c['ativo'] as bool?,
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_outline_rounded, color: ThemeColors.error(context)),
                            onPressed: () => _confirmarExclusaoCupom(c['id'] as int),
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
      },
    );
  }

  Future<void> _confirmarExclusaoCupom(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir cupom'),
        content: const Text('Tem certeza?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Excluir', style: TextStyle(color: ThemeColors.error(ctx)))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await Supabase.instance.client.from('cupons').delete().eq('id', id);
      setState(() {});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mapErroAdmin(e))));
    }
  }

  Future<void> _mostrarDialogCupom({
    int? idEditando,
    String? codigoAtual,
    String? tipoAtual,
    double? valorAtual,
    double? valorMinimoAtual,
    String? dataValidadeAtual,
    int? usoMaximoAtual,
    bool? ativoAtual,
  }) async {
    final codigoCtrl = TextEditingController(text: codigoAtual ?? '');
    final valorCtrl = TextEditingController(text: valorAtual?.toStringAsFixed(2) ?? '');
    final valorMinimoCtrl = TextEditingController(text: valorMinimoAtual?.toStringAsFixed(2) ?? '');
    final usoMaximoCtrl = TextEditingController(text: usoMaximoAtual?.toString() ?? '');
    String tipo = tipoAtual ?? 'percentual';
    bool ativo = ativoAtual ?? true;
    DateTime? dataValidade = dataValidadeAtual != null ? DateTime.tryParse(dataValidadeAtual) : null;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(idEditando != null ? 'Editar Cupom' : 'Novo Cupom'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: codigoCtrl, decoration: InputDecoration(labelText: 'Código', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), filled: true, fillColor: ThemeColors.surface(ctx))),
                  const SizedBox(height: AppSpacing.sm),
                  DropdownButtonFormField<String>(
                    value: tipo,
                    decoration: InputDecoration(labelText: 'Tipo', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), filled: true, fillColor: ThemeColors.surface(ctx)),
                    items: const [
                      DropdownMenuItem(value: 'percentual', child: Text('Percentual')),
                      DropdownMenuItem(value: 'fixo', child: Text('Fixo')),
                    ],
                    onChanged: (v) => setDialogState(() => tipo = v ?? 'percentual'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(controller: valorCtrl, decoration: InputDecoration(labelText: 'Valor', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), filled: true, fillColor: ThemeColors.surface(ctx)), keyboardType: TextInputType.number),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(controller: valorMinimoCtrl, decoration: InputDecoration(labelText: 'Valor Mínimo', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), filled: true, fillColor: ThemeColors.surface(ctx)), keyboardType: TextInputType.number),
                  const SizedBox(height: AppSpacing.sm),
                  ListTile(
                    title: Text(dataValidade != null ? 'Validade: ${dataValidade!.toLocal().toString().split(' ')[0]}' : 'Selecionar data de validade'),
                    trailing: const Icon(Icons.calendar_month_rounded),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: dataValidade ?? DateTime.now(),
                        firstDate: dataValidade ?? DateTime.now().subtract(const Duration(days: 365)),
                        lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                      );
                      if (picked != null) setDialogState(() => dataValidade = picked);
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(controller: usoMaximoCtrl, decoration: InputDecoration(labelText: 'Uso Máximo', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), filled: true, fillColor: ThemeColors.surface(ctx)), keyboardType: TextInputType.number),
                  const SizedBox(height: AppSpacing.sm),
                  SwitchListTile(
                    title: const Text('Ativo'),
                    value: ativo,
                    onChanged: (v) => setDialogState(() => ativo = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              TextButton(
                onPressed: () {
                  final codigo = codigoCtrl.text.trim().toUpperCase();
                  final valor = double.tryParse(valorCtrl.text.trim());
                  if (codigo.isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Informe o código do cupom')),
                    );
                    return;
                  }
                  if (valor == null || valor <= 0) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Informe um valor/porcentagem válido')),
                    );
                    return;
                  }
                  if (tipo == 'percentual' && valor > 100) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Percentual deve ser entre 1 e 100')),
                    );
                    return;
                  }
                  Navigator.pop(ctx, {
                    'codigo': codigo,
                    'tipo': tipo,
                    'valor': valor,
                    'valor_minimo': double.tryParse(valorMinimoCtrl.text.trim()),
                    'data_validade': dataValidade?.toIso8601String(),
                    'uso_maximo': int.tryParse(usoMaximoCtrl.text.trim()),
                    'ativo': ativo,
                  });
                },
                child: Text('Salvar', style: TextStyle(color: ThemeColors.primary(ctx))),
              ),
            ],
          );
        },
      ),
    );

    if (result == null) return;
    result.removeWhere((k, v) => v == null);
    try {
      if (idEditando != null) {
        await Supabase.instance.client.from('cupons').update(result).eq('id', idEditando);
      } else {
        await Supabase.instance.client.from('cupons').insert(result);
      }
      setState(() {});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mapErroAdmin(e))));
    }
  }

  Widget _buildVerificacaoLixoTab() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _verificarLixo(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Erro: ${snapshot.error}', style: TextStyle(color: ThemeColors.error(context))));
        }
        final orfaos = snapshot.data ?? [];
        if (orfaos.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_rounded, size: 64, color: ThemeColors.success(context)),
                const SizedBox(height: 16),
                const Text('Nenhuma imagem órfã encontrada', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                const Text('Todas as imagens no Storage estão vinculadas a produtos.', style: TextStyle(color: Color(0xFFC6C6C6))),
              ],
            ),
          );
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${orfaos.length} ${orfaos.length == 1 ? 'imagem órfã' : 'imagens órfãs'}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const Text('Imagens no Storage sem produto vinculado',
                          style: TextStyle(fontSize: 12, color: Color(0xFFC6C6C6))),
                    ],
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _limparTodasOrfas(orfaos),
                    icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                    label: const Text('Limpar tudo'),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF23D4F), foregroundColor: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 120),
                itemCount: orfaos.length,
                itemBuilder: (_, i) {
                  final o = orfaos[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          width: 48, height: 48,
                          child: Image.network(o['url'] as String, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(color: const Color(0xFF1F1F1F), child: Icon(Icons.broken_image_rounded, color: const Color(0xFF9C9C9C)))),
                        ),
                      ),
                      title: Text(o['nome'] as String, style: const TextStyle(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(o['url'] as String, style: const TextStyle(fontSize: 10, color: Color(0xFF9C9C9C)), maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: IconButton(
                        icon: Icon(Icons.delete_outline_rounded, color: ThemeColors.error(context), size: 20),
                        onPressed: () => _deletarOrfa(o),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _verificarLixo() async {
    final orfaos = <Map<String, dynamic>>[];
    try {
      // Lista arquivos do bucket Produtos
      final arquivos = await Supabase.instance.client.storage.from('Produtos').list();
      // Busca todas as URLs de imagem usadas nos produtos
      final prods = await _adminService.fetchProdutos();
      final urlsUsadas = <String>{};
      for (final p in prods) {
        for (final url in p.urlImagem) {
          final nome = url.split('/Produtos/').lastOrNull ?? url.split('/').last;
          urlsUsadas.add(nome);
        }
      }
      // Também protege fotos das unidades
      final unidades = await Supabase.instance.client.from('unidades').select('foto_url');
      if (unidades is List) {
        for (final u in unidades) {
          final url = (u as Map)['foto_url'] as String?;
          if (url != null && url.contains('/Produtos/')) {
            urlsUsadas.add(url.split('/Produtos/').last);
          }
        }
      }
      // Compara
      for (final f in arquivos) {
        if (!urlsUsadas.contains(f.name)) {
          orfaos.add({
            'nome': f.name,
            'url': Supabase.instance.client.storage.from('Produtos').getPublicUrl(f.name),
            'id': f.id,
          });
        }
      }
    } catch (e) {
      debugPrint('Erro verificação: $e');
    }
    return orfaos;
  }

  Future<void> _deletarOrfa(Map<String, dynamic> orfa) async {
    try {
      await Supabase.instance.client.storage.from('Produtos').remove([orfa['nome'] as String]);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao excluir: $e')));
    }
  }

  Future<void> _limparTodasOrfas(List<Map<String, dynamic>> orfaos) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limpar todas'),
        content: Text('Excluir ${orfaos.length} ${orfaos.length == 1 ? 'imagem órfã' : 'imagens órfãs'}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Excluir', style: TextStyle(color: ThemeColors.error(ctx)))),
        ],
      ),
    );
    if (confirm != true) return;
    for (final o in orfaos) {
      try {
        await Supabase.instance.client.storage.from('Produtos').remove([o['nome'] as String]);
      } catch (e) {
        debugPrint('Erro ao excluir ${o['nome']}: $e');
      }
    }
    if (mounted) setState(() {});
  }
}
