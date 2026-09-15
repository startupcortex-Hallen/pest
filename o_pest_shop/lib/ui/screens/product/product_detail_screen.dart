import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/produto.dart';
import '../../../providers/cart_provider.dart';
import '../../../providers/favorito_provider.dart';
import '../../../services/produto_service.dart';
import '../../widgets/featured_card.dart';

class ProductDetailScreen extends StatefulWidget {
  final int produtoId;

  const ProductDetailScreen({super.key, required this.produtoId});

  static void push(BuildContext context, int produtoId, {String? imageUrl}) {
    // Pré-carrega a imagem do card antes da navegação para o voo de entrada
    // aterrissar sem spinner/piscar. A imagem já está no cache (veio do card),
    // então o custo é praticamente zero.
    final url = imageUrl;
    if (url != null && url.isNotEmpty) {
      precacheImage(CachedNetworkImageProvider(url), context);
    }
    Navigator.of(context).push<dynamic>(
      PageRouteBuilder<dynamic>(
        pageBuilder: (_, __, ___) => ProductDetailScreen(produtoId: produtoId),
        transitionsBuilder: (_, Animation<double> animation, __, Widget child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 900),
        reverseTransitionDuration: const Duration(milliseconds: 700),
      ),
    );
  }

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen>
    with SingleTickerProviderStateMixin {
  Produto? _produto;
  bool _loading = true;
  final _pageController = PageController();
  int _currentPage = 0;
  int _quantidade = 1;
  List<Produto> _recomendados = [];
  bool _descExpandida = false;
  String? _corSelecionada;
  late AnimationController _slideCtrl;
  late Animation<Offset> _slideAnim;
  final _shareBoundaryKey = GlobalKey();
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _slideCtrl.forward();
    });
    _loadProduto();
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadProduto() async {
    try {
      final service = ProdutoService();
      final produto = await service.fetchProdutoById(widget.produtoId);
if (mounted) {
        setState(() {
          _produto = produto;
          _loading = false;
          if (produto != null && produto.cores.isNotEmpty && _corSelecionada == null) {
            _corSelecionada = produto.cores.first;
          }
        });
        if (produto != null) _loadRecomendados(produto);
      }
    } catch (e) {
      debugPrint('Erro ao carregar produto: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

Future<void> _loadRecomendados(Produto produto) async {
    try {
      final res = await Supabase.instance.client
          .from('produtos')
          .select('*, categorias(nome), marcas(nome), unidades(nome)')
          .eq('categoria_id', produto.categoriaId)
          .neq('id', produto.id)
          .order('id')
          .limit(10);
      var lista = res is List ? res : [];
      if (lista.isEmpty) {
        final res2 = await Supabase.instance.client
            .from('produtos')
            .select('*, categorias(nome), marcas(nome), unidades(nome)')
            .neq('id', produto.id)
            .order('id')
            .limit(10);
        lista = res2 is List ? res2 : [];
      }
      if (mounted) {
        setState(() {
          _recomendados = lista.map((j) => Produto.fromJson(j as Map<String, dynamic>)).toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _compartilhar() async {
    if (_sharing || _produto == null) return;
    setState(() => _sharing = true);
    try {
      await Future.delayed(const Duration(milliseconds: 100));
      final boundary = _shareBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('Boundary não encontrado');
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('Falha ao gerar imagem');
      await Share.shareXFiles(
        [
          XFile.fromData(
            byteData.buffer.asUint8List(),
            name: 'produto_${_produto!.id}.png',
            mimeType: 'image/png',
          ),
        ],
        text: 'Confira ${_produto!.nome} no O Pest - Shop!',
      );
    } catch (e) {
      debugPrint('Erro ao compartilhar: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível compartilhar')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  void _abrirMeiosPagamento() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Meios de pagamento', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildPagamentoItem(Icons.credit_card_rounded, 'Cartão de crédito', 'Até ${_produto?.parcelas ?? 12}x sem juros'),
            const Divider(height: 24),
            _buildPagamentoItem(Icons.pix_rounded, 'Pix', 'À vista com 5% de desconto'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar', style: TextStyle(color: Color(0xFFE50914))),
          ),
        ],
      ),
    );
  }

  Widget _buildPagamentoItem(IconData icon, String titulo, String subtitulo) {
    return Row(
      children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFE50914).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: const Color(0xFFE50914), size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(subtitulo, style: const TextStyle(fontSize: 12, color: Color(0xFFC6C6C6))),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _produto == null
              ? const Center(child: Text('Produto não encontrado'))
              : Stack(
                  children: [
                    SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 120),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          RepaintBoundary(
                            key: _shareBoundaryKey,
                            child: _buildImageSection(_produto!),
                          ),
                          SlideTransition(
                            position: _slideAnim,
                            child: _buildContentSection(_produto!),
                          ),
                          if (_recomendados.isNotEmpty)
                            SlideTransition(
                              position: _slideAnim,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
                                    child: Text('Recomendados', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFFEDEDED))),
                                  ),
                                  SizedBox(
                                    height: 220,
                                    child: ListView.separated(
                                      scrollDirection: Axis.horizontal,
                                      clipBehavior: Clip.none,
                                      padding: const EdgeInsets.only(left: 24, right: 24),
                                      itemCount: _recomendados.length,
                                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                                      itemBuilder: (context, index) {
                                        final r = _recomendados[index];
                                        return FeaturedCard(
                                          produto: r,
                                          onTap: () => ProductDetailScreen.push(
                                            context,
                                            r.id,
                                            imageUrl: r.urlImagem.isNotEmpty ? r.urlImagem.first : null,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 50),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: SlideTransition(
                        position: _slideAnim,
                        child: _buildBottomBar(),
                      ),
                    ),
                    // Barra "Ver carrinho" — padrão das grandes lojas
                    Positioned(
                      bottom: MediaQuery.of(context).padding.bottom + 108,
                      left: 0,
                      right: 0,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: Consumer<CartProvider>(
                          builder: (context, cart, _) {
                            if (cart.totalItens <= 0) return const SizedBox.shrink();
                            return SafeArea(
                              top: false,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                                child: GestureDetector(
                                  onTap: () => context.go('/carrinho'),
                                  child: Container(
                                    height: 46,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE50914),
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFFE50914).withValues(alpha: 0.35),
                                          blurRadius: 12,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.shopping_cart_rounded, size: 18, color: Colors.white),
                                        const SizedBox(width: 8),
                                        Text(
                                          '${cart.totalItens} ${cart.totalItens == 1 ? 'item' : 'itens'} no carrinho — Ver carrinho',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
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
                    ),
                  ],
                ),
    );
  }

  Widget _buildImageSection(Produto produto) {
    final imagens = produto.urlImagem;
    return Container(
      height: 264,
      color: Colors.white,
      padding: const EdgeInsets.only(top: 16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imagens.isNotEmpty)
            PageView.builder(
              controller: _pageController,
              itemCount: imagens.length,
              onPageChanged: (i) => setState(() => _currentPage = i),
              itemBuilder: (_, i) {
                Widget img = Container(
                  color: Colors.white,
                  child: CachedNetworkImage(
                    imageUrl: imagens[i],
                    fit: BoxFit.contain,
                    placeholder: (_, __) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    errorWidget: (_, __, ___) => const Icon(Icons.image_outlined, size: 64, color: Color(0xFF9C9C9C)),
                  ),
                );
                if (i == 0) {
                  img = Hero(tag: 'produto_${produto.id}', child: img);
                }
                return img;
              },
            )
          else
            Container(
              color: Colors.white,
              child: const Icon(Icons.image_outlined, size: 64, color: Color(0xFF9C9C9C)),
            ),
          Positioned(
            top: 48,
            left: 20,
child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => context.pop(),
              ),
            ),
          ),
          Positioned(
            top: 48,
            right: 20,
            child: Row(
              children: [
Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: Consumer<FavoritoProvider>(
                    builder: (context, fav, _) {
                      final isFav = fav.isFavorito(widget.produtoId);
                      return IconButton(
                        icon: Icon(
                          isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          color: isFav ? const Color(0xFFF23D4F) : Colors.white,
                        ),
                        onPressed: () => fav.toggle(widget.produtoId),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: _sharing
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.share_rounded, color: Colors.white),
                    onPressed: _compartilhar,
                  ),
                ),
              ],
            ),
          ),
          if (imagens.length > 1)
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(imagens.length, (i) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _currentPage ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _currentPage ? const Color(0xFFE50914) : const Color(0xFF9C9C9C),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ),
          if (produto.estoque <= 0)
            Positioned.fill(
              child: GestureDetector(
                onTap: _mostrarDialogEsgotado,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.45),
                  alignment: Alignment.center,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'ESGOTADO',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFF23D4F),
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Dialog exibido ao tocar no "ESGOTADO" — oferece salvar como preferido
  /// para avisar quando o produto voltar ao estoque.
  Future<void> _mostrarDialogEsgotado() async {
    final produto = _produto;
    if (produto == null) return;
    final fav = context.read<FavoritoProvider>();
    final isFav = fav.isFavorito(produto.id);
    final messenger = ScaffoldMessenger.of(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error_outline_rounded, color: Color(0xFFF23D4F)),
            SizedBox(width: 8),
            Text('Produto esgotado', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ],
        ),
        content: Text(
          '"${produto.nome}" está sem estoque no momento.\n\nSalve como preferido e avisaremos quando ele voltar.',
          style: const TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!isFav) await fav.toggle(produto.id);
              Navigator.pop(ctx);
              messenger.showSnackBar(SnackBar(
                content: Text(
                  isFav
                      ? 'Produto já está nos seus favoritos.'
                      : 'Salvo nos favoritos — avisaremos quando voltar ao estoque.',
                ),
              ));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF23D4F),
              foregroundColor: Colors.white,
            ),
            child: Text(isFav ? 'Já está nos favoritos' : 'Salvar como preferido'),
          ),
        ],
      ),
    );
  }

Widget _buildContentSection(Produto produto) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF141414),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            (produto.categoriaNome ?? 'PRODUTO').toUpperCase(),
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFFC6C6C6), letterSpacing: 1),
          ),
          const SizedBox(height: 4),
          Text(
            produto.nome,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Color(0xFFF5F5F5)),
          ),
          if (produto.cores.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: produto.cores.map((c) {
                return _buildColorChip(
                  c,
                  selected: _corSelecionada == c,
                  onTap: () => setState(() => _corSelecionada = c),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (produto.temDesconto)
                      Text(
                        'R\$ ${produto.preco.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 14, color: Color(0xFF9C9C9C), decoration: TextDecoration.lineThrough),
                      ),
Text(
                      'R\$ ${produto.precoAtual.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFFF5F5F5)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'em ${produto.parcelas}x R\$ ${(produto.precoAtual / produto.parcelas).toStringAsFixed(2)} sem juros',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFFEDEDED)),
                    ),
                    const SizedBox(height: 2),
GestureDetector(
                      onTap: _abrirMeiosPagamento,
                      child: const Text(
                        'Ver os meios de pagamento',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFE50914)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(
                          produto.estoque <= 0 ? Icons.error_outline_rounded : Icons.inventory_2_outlined,
                          size: 16,
                          color: produto.estoque <= 0
                              ? const Color(0xFFF23D4F)
                              : const Color(0xFF00C660),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          produto.estoque <= 0
                              ? 'Esgotado'
                              : '${produto.estoque} ${produto.estoque == 1 ? 'unidade' : 'unidades'} em estoque',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: produto.estoque <= 0
                                ? const Color(0xFFF23D4F)
                                : const Color(0xFF00C660),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _buildQuantitySelector(),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFF2C2C2C)),
          const SizedBox(height: 16),
          if (produto.freteGratis) ...[
            Row(
              children: [
                const Icon(Icons.local_shipping_outlined, size: 18, color: Color(0xFF00A650)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text('Frete grátis', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF00A650))),
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            color: const Color(0xFF00A650),
                            child: const Text('FULL', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: Colors.white)),
                          ),
                        ],
                      ),
                      Text(
                        'Chega hoje em ${produto.unidadeNome ?? 'Loja Parceira'}',
                        style: const TextStyle(fontSize: 12, color: Color(0xFFC6C6C6)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFF2C2C2C)),
            const SizedBox(height: 16),
          ],
const Text('Descrição', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFFEDEDED))),
          const SizedBox(height: 8),
          Text(
            produto.descricao.isNotEmpty
                ? produto.descricao
                : 'Produto original e de alta qualidade, direto da quebrada.',
            maxLines: _descExpandida ? null : 3,
            overflow: _descExpandida ? null : TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, color: Color(0xFFC6C6C6), height: 1.5),
          ),
          if (produto.descricao.length > 120) ...[
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () => setState(() => _descExpandida = !_descExpandida),
              child: Text(
                _descExpandida ? 'Mostrar menos' : 'Ler mais',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFE50914)),
              ),
            ),
          ],
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFF2C2C2C)),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildColorChip(String nome, {bool selected = false, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF33E50914) : const Color(0xFF1F1F1F),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? const Color(0xFFE50914) : const Color(0xFF2C2C2C),
            width: selected ? 1.5 : 1,
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
                color: _corDe(nome),
                border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              nome,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? const Color(0xFFF5F5F5) : const Color(0xFFC6C6C6),
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 4),
              const Icon(Icons.check_rounded, size: 12, color: Color(0xFFF5F5F5)),
            ],
          ],
        ),
      ),
    );
  }

  Color _corDe(String nome) {
    final n = nome.toLowerCase();
    if (n.contains('preto')) return const Color(0xFF111111);
    if (n.contains('branco')) return const Color(0xFFF5F5F5);
    if (n.contains('vermelho') || n.contains('vinho')) return const Color(0xFFE50914);
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

  bool _deveEscolherCor() {
    final p = _produto;
    return p != null && p.cores.isNotEmpty;
  }

  Widget _buildQuantitySelector() {
    final esgotado = (_produto?.estoque ?? 0) <= 0;
    return Container(
      width: 110,
      height: 36,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE0E0E0)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: esgotado
                  ? null
                  : () => setState(() { if (_quantidade > 1) _quantidade--; }),
              child: Center(
                child: Icon(Icons.remove_rounded,
                    size: 18,
                    color: esgotado ? const Color(0xFF9C9C9C) : const Color(0xFFEDEDED)),
              ),
            ),
          ),
          Container(
            width: 1,
            color: const Color(0xFFE0E0E0),
          ),
          Expanded(
            child: Center(child: Text('$_quantidade', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
          ),
          Container(
            width: 1,
            color: const Color(0xFFE0E0E0),
          ),
          Expanded(
            child: GestureDetector(
              onTap: esgotado
                  ? null
                  : () => setState(() => _quantidade++),
              child: Container(
                decoration: BoxDecoration(
                  color: esgotado ? const Color(0xFF9C9C9C) : const Color(0xFFE50914),
                  borderRadius: BorderRadius.only(
                    topRight: Radius.circular(5),
                    bottomRight: Radius.circular(5),
                  ),
                ),
                child: const Center(child: Icon(Icons.add_rounded, size: 18, color: Colors.white)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final produto = _produto!;
    final esgotado = produto.estoque <= 0;
    return Container(
        height: 100,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF0A0A0A),
          border: const Border(top: BorderSide(color: Color(0xFF2C2C2C))),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: esgotado
                      ? OutlinedButton.icon(
                          onPressed: _mostrarDialogEsgotado,
                          icon: const Icon(Icons.error_outline_rounded, size: 18),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFF23D4F),
                            side: const BorderSide(color: Color(0xFFF23D4F)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                          ),
                          label: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Esgotado', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                          ),
                        )
                      : OutlinedButton(
                          onPressed: () async {
                            if (_deveEscolherCor() && _corSelecionada == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Selecione uma cor antes de adicionar.'),
                                  backgroundColor: Color(0xFFF23D4F),
                                ),
                              );
                              return;
                            }
                            final ok = await context
                                .read<CartProvider>()
                                .adicionar(widget.produtoId, quantidade: _quantidade, cor: _corSelecionada);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(ok
                                    ? 'Adicionado ao carrinho'
                                    : 'Não foi possível adicionar ao carrinho. Tente novamente.'),
                                backgroundColor: ok
                                    ? null
                                    : const Color(0xFFF23D4F),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFE50914),
                            side: const BorderSide(color: Color(0xFFE50914)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                          ),
                          child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Adicionar ao carrinho', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: esgotado
                      ? ElevatedButton.icon(
                          onPressed: () async {
                            final fav = context.read<FavoritoProvider>();
                            final jaFav = fav.isFavorito(widget.produtoId);
                            if (!jaFav) await fav.toggle(widget.produtoId);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(
                                  jaFav
                                      ? 'Produto já está nos seus favoritos.'
                                      : 'Salvo nos favoritos — avisaremos quando voltar ao estoque.',
                                ),
                              ));
                            }
                          },
                          icon: Consumer<FavoritoProvider>(
                            builder: (context, fav, _) => Icon(
                              fav.isFavorito(widget.produtoId)
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              size: 18,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF23D4F),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                          ),
                          label: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Salvar como preferido', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                          ),
                        )
                      : ElevatedButton(
                          onPressed: () async {
                            if (_deveEscolherCor() && _corSelecionada == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Selecione uma cor antes de comprar.'),
                                  backgroundColor: Color(0xFFF23D4F),
                                ),
                              );
                              return;
                            }
                            // Soma à quantidade já existente no carrinho (se houver)
                            final ok = await context.read<CartProvider>().adicionar(
                                  widget.produtoId,
                                  quantidade: _quantidade,
                                  cor: _corSelecionada,
                                );
                            // Só vai para o checkout se adicionou de verdade
                            if (!ok) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Não foi possível adicionar ao carrinho. Tente novamente.'),
                                    backgroundColor: Color(0xFFF23D4F),
                                  ),
                                );
                              }
                              return;
                            }
                            // Vai direto para o checkout/carrinho
                            context.go('/carrinho');
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE50914),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                          ),
                          child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Comprar agora', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
    );
  }
}
