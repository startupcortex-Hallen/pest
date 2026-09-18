import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/produto.dart';
import '../../../providers/home_provider.dart';
import '../../../services/produto_service.dart';
import '../../widgets/product_card.dart';
import '../product/product_detail_screen.dart';

class SearchResultsScreen extends StatefulWidget {
  final String? initialQuery;
  const SearchResultsScreen({super.key, this.initialQuery});

  @override
  State<SearchResultsScreen> createState() => _SearchResultsScreenState();
}

class _SearchResultsScreenState extends State<SearchResultsScreen> {
  final _searchCtrl = TextEditingController();
  final _produtoService = ProdutoService();
  Timer? _debounce;

  String _query = '';
  List<Produto> _results = [];
  bool _loading = false;
  bool _hasMore = true;
  int? _lastId;
  String? _error;

  // Filtros
  Set<int> _filtroCategoriaIds = {};
  Set<int> _filtroMarcaIds = {};
  Set<int> _filtroUnidadeIds = {};
  String? _filtroEstoque;
  double _precoMin = 0;
  double _precoMax = 1000;

  // Ordenação
  String _sortBy = 'relevancia'; // relevancia, menor_preco, maior_preco, estoque

  // Dados para filtros
  List<Map<String, dynamic>> _categorias = [];
  List<Map<String, dynamic>> _marcas = [];
  List<Map<String, dynamic>> _unidades = [];
  int? _categoriaSelecionada;

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = widget.initialQuery ?? '';
    _query = widget.initialQuery ?? '';
    _carregarDadosFiltros();
    _buscar();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _carregarDadosFiltros() async {
    try {
      final cats = await _produtoService.fetchCategorias();
      final marcas = await Supabase.instance.client.from('marcas').select('id, nome').order('nome');
      final unidades = await Supabase.instance.client.from('unidades').select('id, nome, foto_url').order('nome');
      if (!mounted) return;
      setState(() {
        _categorias = cats.map((c) => {'id': c.id, 'nome': c.nome}).toList();
        _marcas = (marcas as List).cast<Map<String, dynamic>>();
        _unidades = (unidades as List).cast<Map<String, dynamic>>();
      });
    } catch (_) {}
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      setState(() => _query = v.toLowerCase().trim());
      _resetarBusca();
      _buscar();
    });
  }

  void _resetarBusca() {
    _results = [];
    _lastId = null;
    _hasMore = true;
    _error = null;
  }

  Future<void> _buscar({bool loadMore = false}) async {
    if (_loading || (!_hasMore && loadMore)) return;
    if (!loadMore) setState(() => _loading = true);

    try {
      // Busca no backend apenas com termo textual e categoria única
      final novos = await _produtoService.fetchProdutos(
        search: _query.isNotEmpty ? _query : (_filtroCategoriaIds.isNotEmpty || _categoriaSelecionada != null ? null : null),
        lastId: loadMore ? _lastId : null,
        categoriaId: _filtroCategoriaIds.isNotEmpty ? null : _categoriaSelecionada,
      );

      List<Produto> filtrados = novos;

      // Filtros locais (multi-select via Set)
      if (_filtroCategoriaIds.isNotEmpty) {
        filtrados = filtrados.where((p) => _filtroCategoriaIds.contains(p.categoriaId)).toList();
      }
      if (_filtroMarcaIds.isNotEmpty) {
        filtrados = filtrados.where((p) => p.marcaId != null && _filtroMarcaIds.contains(p.marcaId)).toList();
      }
      if (_filtroUnidadeIds.isNotEmpty) {
        filtrados = filtrados.where((p) => p.unidadeId != null && _filtroUnidadeIds.contains(p.unidadeId)).toList();
      }

      // Filtro de estoque local
      if (_filtroEstoque == 'com_estoque') {
        filtrados = filtrados.where((p) => p.estoque > 0).toList();
      } else if (_filtroEstoque == 'sem_estoque') {
        filtrados = filtrados.where((p) => p.estoque <= 0).toList();
      } else if (_filtroEstoque == 'estoque_baixo') {
        filtrados = filtrados.where((p) => p.estoque > 0 && p.estoque <= 3).toList();
      }

      // Filtro de preço local
      filtrados = filtrados.where((p) {
        final preco = p.precoAtual;
        return preco >= _precoMin && preco <= _precoMax;
      }).toList();

      // Ordenação
      if (_sortBy == 'menor_preco') {
        filtrados.sort((a, b) => a.precoAtual.compareTo(b.precoAtual));
      } else if (_sortBy == 'maior_preco') {
        filtrados.sort((a, b) => b.precoAtual.compareTo(a.precoAtual));
      } else if (_sortBy == 'estoque') {
        filtrados.sort((a, b) {
          int prio(Produto p) {
            if (p.estoque <= 0) return 2;
            if (p.estoque <= 3) return 1;
            return 0;
          }
          return prio(a).compareTo(prio(b));
        });
      }

      if (!mounted) return;
      setState(() {
        if (loadMore) {
          _results = [..._results, ...filtrados];
        } else {
          _results = filtrados;
        }
        _hasMore = novos.length == ProdutoService.pageSize;
        if (novos.isNotEmpty) _lastId = novos.last.id;
        _loading = false;
      });

    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Erro ao buscar produtos';
        _loading = false;
      });
    }
  }

  void _abrirDialogFiltros() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setInner) {
          Set<int> tempCats = Set.from(_filtroCategoriaIds);
          Set<int> tempMarcas = Set.from(_filtroMarcaIds);
          Set<int> tempUnidades = Set.from(_filtroUnidadeIds);
          String? tempEstoque = _filtroEstoque;
          double tempPrecoMin = _precoMin;
          double tempPrecoMax = _precoMax;

          return AlertDialog(
            title: const Text('Filtrar Produtos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_categorias.isNotEmpty) ...[
                      Text('Categoria', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFFC6C6C6))),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8, runSpacing: 6,
                        children: _categorias.map((c) => FilterChip(
                          label: Text(c['nome'] as String, style: TextStyle(fontSize: 13, color: tempCats.contains(c['id']) ? Colors.white : const Color(0xFFEDEDED))),
                          selected: tempCats.contains(c['id']),
                          onSelected: (v) => setInner(() { v ? tempCats.add(c['id'] as int) : tempCats.remove(c['id'] as int); }),
                          selectedColor: const Color(0xFFE50914),
                          checkmarkColor: Colors.white,
                          backgroundColor: const Color(0xFF1F1F1F),
                          side: BorderSide.none,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        )).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_marcas.isNotEmpty) ...[
                      Text('Marca', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFFC6C6C6))),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8, runSpacing: 6,
                        children: _marcas.map((m) => FilterChip(
                          label: Text(m['nome'] as String, style: TextStyle(fontSize: 13, color: tempMarcas.contains(m['id']) ? Colors.white : const Color(0xFFEDEDED))),
                          selected: tempMarcas.contains(m['id']),
                          onSelected: (v) => setInner(() { v ? tempMarcas.add(m['id'] as int) : tempMarcas.remove(m['id'] as int); }),
                          selectedColor: const Color(0xFFE50914),
                          checkmarkColor: Colors.white,
                          backgroundColor: const Color(0xFF1F1F1F),
                          side: BorderSide.none,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        )).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_unidades.isNotEmpty) ...[
                      Text('Unidade', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFFC6C6C6))),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 120,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _unidades.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, i) {
                            final u = _unidades[i];
                            final isSel = tempUnidades.contains(u['id']);
                            final fotoUrl = u['foto_url'] as String?;
                            return GestureDetector(
                              onTap: () => setInner(() { isSel ? tempUnidades.remove(u['id']) : tempUnidades.add(u['id'] as int); }),
                              child: Container(
                                width: 100,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: isSel ? const Color(0xFFE50914) : const Color(0xFF2C2C2C), width: isSel ? 2 : 1),
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
                                                : Center(child: Icon(Icons.store_rounded, size: 28, color: const Color(0xFFBBBBBB))),
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                          child: Text(u['nome'] as String, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                                            style: TextStyle(fontSize: 9, color: isSel ? const Color(0xFFE50914) : const Color(0xFFEDEDED), fontWeight: isSel ? FontWeight.w600 : FontWeight.normal)),
                                        ),
                                      ],
                                    ),
                                    if (isSel)
                                      Positioned(top: 4, right: 4, child: Icon(Icons.check_circle_rounded, size: 16, color: const Color(0xFFE50914))),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Text('Estoque', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFFC6C6C6))),
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
                    const SizedBox(height: 16),
                    Text('Faixa de Preço', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFFC6C6C6))),
                    const SizedBox(height: 4),
                    Text('R\$ ${tempPrecoMin.toStringAsFixed(0)} — R\$ ${tempPrecoMax.toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 12, color: Color(0xFFE50914), fontWeight: FontWeight.w600)),
                    RangeSlider(
                      values: RangeValues(tempPrecoMin, tempPrecoMax),
                      min: 0,
                      max: 1000,
                      divisions: 40,
                      labels: RangeLabels('R\$ ${tempPrecoMin.toStringAsFixed(0)}', 'R\$ ${tempPrecoMax.toStringAsFixed(0)}'),
                      activeColor: const Color(0xFFE50914),
                      onChanged: (v) => setInner(() { tempPrecoMin = v.start; tempPrecoMax = v.end; }),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, {'limpar': true}), child: const Text('Limpar', style: TextStyle(color: Color(0xFFC6C6C6)))),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, {'categorias': tempCats, 'marcas': tempMarcas, 'unidades': tempUnidades, 'estoque': tempEstoque, 'preco_min': tempPrecoMin, 'preco_max': tempPrecoMax}),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE50914), foregroundColor: Colors.white),
                child: const Text('Aplicar'),
              ),
            ],
          );
        },
      ),
    );

    if (result == null) return;
    if (result['limpar'] == true) {
      setState(() {
        _filtroCategoriaIds.clear();
        _filtroMarcaIds.clear();
        _filtroUnidadeIds.clear();
        _filtroEstoque = null;
        _precoMin = 0;
        _precoMax = 1000;
        _categoriaSelecionada = null;
      });
    } else {
      setState(() {
        _filtroCategoriaIds = Set<int>.from(result['categorias'] as Set<int>);
        _filtroMarcaIds = Set<int>.from(result['marcas'] as Set<int>);
        _filtroUnidadeIds = Set<int>.from(result['unidades'] as Set<int>);
        _filtroEstoque = result['estoque'] as String?;
        _precoMin = (result['preco_min'] as num?)?.toDouble() ?? 0;
        _precoMax = (result['preco_max'] as num?)?.toDouble() ?? 1000;
        _categoriaSelecionada = null;
      });
    }
    _resetarBusca();
    _buscar();
  }

  Widget _buildEstoqueChip(String label, bool selected, VoidCallback onTap) {
    final color = label == 'Com estoque'
        ? const Color(0xFF00A650)
        : label == 'Estoque baixo'
            ? const Color(0xFFFFAD01)
            : const Color(0xFFF23D4F);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.15) : const Color(0xFF1F1F1F),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? color : const Color(0xFFE0E0E0)),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: selected ? color : const Color(0xFFC6C6C6))),
      ),
    );
  }

  int get _filtrosAtivosCount {
    int count = 0;
    if (_filtroCategoriaIds.isNotEmpty) count++;
    if (_filtroMarcaIds.isNotEmpty) count++;
    if (_filtroUnidadeIds.isNotEmpty) count++;
    if (_filtroEstoque != null) count++;
    if (_precoMin > 0 || _precoMax < 1000) count++;
    return count;
  }

  void _mostrarQuickView(Produto p) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                height: 200,
                color: Colors.white,
                child: p.urlImagem.isNotEmpty
                    ? PageView.builder(
                        itemCount: p.urlImagem.length,
                        itemBuilder: (context, i) {
                          Widget img = Container(
                            color: Colors.white,
                            child: CachedNetworkImage(
                              imageUrl: p.urlImagem[i],
                              fit: BoxFit.contain,
                              useOldImageOnUrlChange: true,
                              fadeInDuration: Duration.zero,
                              fadeOutDuration: Duration.zero,
                              placeholder: (_, __) => const SizedBox.shrink(),
                              errorWidget: (_, __, ___) => const Icon(Icons.image_outlined, size: 48, color: Color(0xFF9C9C9C)),
                            ),
                          );
                          if (i == 0) {
                            img = Hero(tag: 'produto_${p.id}', child: img);
                          }
                          return img;
                        },
                      )
                    : const Icon(Icons.image_outlined, size: 48, color: Color(0xFF9C9C9C)),
              ),
            ),
            if (p.urlImagem.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(p.urlImagem.length, (i) => Container(
                    width: 6, height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == 0 ? const Color(0xFFE50914) : const Color(0xFF9C9C9C),
                    ),
                  )),
                ),
              ),
            const SizedBox(height: 16),
            Text(p.nome, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            if (p.temDesconto)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('R\$ ${p.preco.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 14, color: Color(0xFF9C9C9C), decoration: TextDecoration.lineThrough)),
                  const SizedBox(width: 8),
                  Text('R\$ ${p.precoAtual.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFFF23D4F))),
                ],
              )
            else
              Text('R\$ ${p.precoAtual.toStringAsFixed(2)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  ProductDetailScreen.push(
                    context,
                    p.id,
                    imageUrl: p.urlImagem.isNotEmpty ? p.urlImagem.first : null,
                  );
                  Future.delayed(const Duration(milliseconds: 1000), () {
                    if (ctx.mounted) Navigator.pop(ctx);
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE50914),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Ver detalhes'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtrosAtivos = _filtrosAtivosCount;

    return Scaffold(
      backgroundColor: const Color(0xFF1F1F1F),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(80),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          color: const Color(0xFFE50914),
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Buscar na AH ACADEMIAS',
                      prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF9C9C9C), size: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    style: const TextStyle(color: Color(0xFFEDEDED)),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.asset(
                    'assets/logo.jpg',
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(Icons.storefront_rounded, color: Color(0xFFE50914)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Barra de filtros e ordenação
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Colors.white,
            child: Column(
              children: [
                Row(
                  children: [
                    // Categorias como chips horizontais
                    Expanded(
                      child: SizedBox(
                        height: 34,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            _buildChip('Todos', _categoriaSelecionada == null, () => setState(() { _categoriaSelecionada = null; _filtroCategoriaIds.clear(); _resetarBusca(); _buscar(); })),
                            ..._categorias.map((c) => _buildChip(c['nome'] as String, _categoriaSelecionada == c['id'], () {
                              setState(() { _categoriaSelecionada = c['id'] as int; _filtroCategoriaIds.clear(); });
                              _resetarBusca();
                              _buscar();
                            })),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ActionChip(
                      avatar: Icon(Icons.filter_list_rounded, size: 16, color: filtrosAtivos > 0 ? const Color(0xFFE50914) : const Color(0xFFC6C6C6)),
                      label: Text(filtrosAtivos > 0 ? 'Filtrar ($filtrosAtivos)' : 'Filtrar', style: TextStyle(fontSize: 11, color: filtrosAtivos > 0 ? const Color(0xFFE50914) : const Color(0xFFC6C6C6))),
                      onPressed: _abrirDialogFiltros,
                      backgroundColor: filtrosAtivos > 0 ? const Color(0xFFE50914).withValues(alpha: 0.08) : const Color(0xFF1F1F1F),
                      side: BorderSide(color: filtrosAtivos > 0 ? const Color(0xFFE50914) : const Color(0xFFE0E0E0)),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Ordenação
                Row(
                  children: [
                    const Icon(Icons.sort_rounded, size: 14, color: Color(0xFF9C9C9C)),
                    const SizedBox(width: 4),
                    _buildSortChip('Relevância', _sortBy == 'relevancia', () => setState(() { _sortBy = 'relevancia'; _ordenar(); })),
                    const SizedBox(width: 4),
                    _buildSortChip('Menor preço', _sortBy == 'menor_preco', () => setState(() { _sortBy = 'menor_preco'; _ordenar(); })),
                    const SizedBox(width: 4),
                    _buildSortChip('Maior preço', _sortBy == 'maior_preco', () => setState(() { _sortBy = 'maior_preco'; _ordenar(); })),
                    const SizedBox(width: 4),
                    _buildSortChip('Estoque', _sortBy == 'estoque', () => setState(() { _sortBy = 'estoque'; _ordenar(); })),
                  ],
                ),
              ],
            ),
          ),
          // Contador de resultados
          if (_results.isNotEmpty || _query.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                _query.isEmpty
                    ? '${_results.length} ${_results.length == 1 ? 'produto' : 'produtos'}'
                    : '${_results.length} ${_results.length == 1 ? 'resultado' : 'resultados'} para "${_searchCtrl.text}"',
                style: const TextStyle(fontSize: 12, color: Color(0xFFC6C6C6)),
              ),
            ),
          // Lista de resultados
          Expanded(
            child: _buildResults(),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFE50914) : const Color(0xFF1F1F1F),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: selected ? Colors.white : const Color(0xFFC6C6C6))),
        ),
      ),
    );
  }

  Widget _buildSortChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE50914).withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: selected ? const Color(0xFFE50914) : const Color(0xFF9C9C9C))),
      ),
    );
  }

  void _ordenar() {
    if (_results.isEmpty) return;
    setState(() {
      if (_sortBy == 'menor_preco') {
        _results.sort((a, b) => a.precoAtual.compareTo(b.precoAtual));
      } else if (_sortBy == 'maior_preco') {
        _results.sort((a, b) => b.precoAtual.compareTo(a.precoAtual));
      } else if (_sortBy == 'estoque') {
        _results.sort((a, b) {
          int prio(Produto p) {
            if (p.estoque <= 0) return 2;
            if (p.estoque <= 3) return 1;
            return 0;
          }
          return prio(a).compareTo(prio(b));
        });
      }
    });
  }

  Widget _buildResults() {
    if (_loading && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 48, color: Color(0xFF9C9C9C)),
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Color(0xFFC6C6C6))),
            const SizedBox(height: 8),
            TextButton(onPressed: () { _resetarBusca(); _buscar(); }, child: const Text('Tentar novamente')),
          ],
        ),
      );
    }

    if (_results.isEmpty && _query.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off_rounded, size: 64, color: Color(0xFF9C9C9C)),
            const SizedBox(height: 12),
            const Text('Nenhum produto encontrado', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFFEDEDED))),
            const SizedBox(height: 4),
            Text('Tente alterar os filtros ou a pesquisa.', style: TextStyle(fontSize: 13, color: const Color(0xFF9C9C9C))),
            if (_filtrosAtivosCount > 0) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  setState(() {
                    _filtroCategoriaIds.clear();
                    _filtroMarcaIds.clear();
                    _filtroUnidadeIds.clear();
                    _filtroEstoque = null;
                    _precoMin = 0;
                    _precoMax = 1000;
                    _categoriaSelecionada = null;
                  });
                  _resetarBusca();
                  _buscar();
                },
                child: const Text('Limpar filtros'),
              ),
            ],
          ],
        ),
      );
    }

    if (_results.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_rounded, size: 64, color: Color(0xFF9C9C9C)),
            SizedBox(height: 12),
            Text('Faça uma busca', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFFEDEDED))),
            SizedBox(height: 4),
            Text('Digite o nome de um produto acima.', style: TextStyle(fontSize: 13, color: Color(0xFF9C9C9C))),
          ],
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (scrollInfo) {
        if (!_hasMore || _loading) return false;
        if (scrollInfo.metrics.pixels >= scrollInfo.metrics.maxScrollExtent - 200) {
          _buscar(loadMore: true);
        }
        return false;
      },
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.sm),
        itemCount: _results.length + (_hasMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          if (index >= _results.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          final produto = _results[index];
          return ProductCard(
            produto: produto,
            onTap: () => ProductDetailScreen.push(
              context,
              produto.id,
              imageUrl: produto.urlImagem.isNotEmpty ? produto.urlImagem.first : null,
            ),
            onLongPress: () => _mostrarQuickView(produto),
          );
        },
      ),
    );
  }
}
