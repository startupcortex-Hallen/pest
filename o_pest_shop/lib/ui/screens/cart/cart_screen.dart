import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/helpers/theme_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/cart_item.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/cart_provider.dart';
import '../../../providers/cupom_provider.dart';
import '../../../services/checkout_service.dart';
import '../../widgets/animated_card_entry.dart';
import '../pedidos/pagamento_screen.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final _cupomCtrl = TextEditingController();
  final _cepCtrl = TextEditingController();
  final _ruaCtrl = TextEditingController();
  final _numeroCtrl = TextEditingController();
  final _complementoCtrl = TextEditingController();
  final _bairroCtrl = TextEditingController();
  final _cidadeCtrl = TextEditingController();
  final _ufCtrl = TextEditingController();
  final _cepMask = MaskTextInputFormatter(
    mask: '#####-###',
    filter: {'#': RegExp(r'[0-9]')},
  );
  bool _aplicandoCupom = false;
  bool _finalizando = false;
  bool _buscandoCep = false;
  String _tipoEntrega = 'retirada';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CartProvider>().loadCart();
      context.read<CupomProvider>().loadCupons();
    });
  }

  @override
  void dispose() {
    _cupomCtrl.dispose();
    _cepCtrl.dispose();
    _ruaCtrl.dispose();
    _numeroCtrl.dispose();
    _complementoCtrl.dispose();
    _bairroCtrl.dispose();
    _cidadeCtrl.dispose();
    _ufCtrl.dispose();
    super.dispose();
  }

  /// Busca o CEP no ViaCEP (grátis, sem chave) e preenche os campos.
  Future<void> _buscarCep() async {
    final cep = _cepCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (cep.length != 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Digite um CEP válido com 8 dígitos.'), backgroundColor: AppColors.error),
      );
      return;
    }
    setState(() => _buscandoCep = true);
    try {
      final res = await http.get(Uri.parse('https://viacep.com.br/ws/$cep/json/'));
      final json = jsonDecode(utf8.decode(res.bodyBytes));
      if (json is Map && json['erro'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('CEP não encontrado.'), backgroundColor: AppColors.error),
          );
        }
        return;
      }
      final dados = json as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _ruaCtrl.text = dados['logradouro'] as String? ?? '';
          _bairroCtrl.text = dados['bairro'] as String? ?? '';
          _cidadeCtrl.text = dados['localidade'] as String? ?? '';
          _ufCtrl.text = dados['uf'] as String? ?? '';
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível buscar o CEP. Verifique sua conexão.'), backgroundColor: AppColors.error),
        );
      }
    }
    if (mounted) setState(() => _buscandoCep = false);
  }

  /// Monta o endereço completo no MESMO padrão usado pelo mapa das unidades.
  String get _enderecoFormatado {
    final cep = _cepCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    final rua = _ruaCtrl.text.trim();
    final numero = _numeroCtrl.text.trim();
    final complemento = _complementoCtrl.text.trim();
    final bairro = _bairroCtrl.text.trim();
    final cidade = _cidadeCtrl.text.trim();
    final uf = _ufCtrl.text.trim().toUpperCase();
    final partes = <String>[
      if (rua.isNotEmpty) '$rua${numero.isNotEmpty ? ', $numero' : ''}',
      if (complemento.isNotEmpty) complemento,
      if (bairro.isNotEmpty) bairro,
      if (cidade.isNotEmpty || uf.isNotEmpty)
        '${cidade}${uf.isNotEmpty ? ' - $uf' : ''}',
    ];
    final endereco = partes.join(', ');
    final comCep = cep.length == 8 ? '$endereco, CEP $cep' : endereco;
    return comCep;
  }

  Future<void> _aplicarCupom(CupomProvider cupom) async {
    final codigo = _cupomCtrl.text.trim();
    if (codigo.isEmpty) return;
    setState(() => _aplicandoCupom = true);
    final erro = await cupom.aplicarCupom(codigo);
    if (!mounted) return;
    setState(() => _aplicandoCupom = false);
    if (erro != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(erro), backgroundColor: AppColors.error),
      );
      return;
    }
    final aplicado = cupom.cupomAplicado;
    final subtotal = context.read<CartProvider>().total;
    if (aplicado != null && subtotal < aplicado.valorMinimo) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Este cupom exige um valor mínimo de R\$ ${aplicado.valorMinimo.toStringAsFixed(2)}.'),
          backgroundColor: AppColors.error,
        ),
      );
      cupom.removerCupom();
      return;
    }
    _cupomCtrl.clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cupom ${aplicado?.codigo} aplicado!'), backgroundColor: AppColors.success),
      );
    }
  }

  /// Valida estoque de todos os itens antes de finalizar.
  /// Retorna false se houver itens indisponíveis (dialog oferece remoção).
  Future<bool> _validarEstoque(CartProvider cart) async {
    final esgotados = cart.itensEsgotados;
    final acimaEstoque = cart.items
        .where((i) => !i.esgotado && i.quantidade > (i.produtoEstoque ?? 0))
        .toList();
    if (esgotados.isEmpty && acimaEstoque.isEmpty) return true;

    final nomes = <String>[
      ...esgotados.map((i) => '${i.produtoNome ?? 'Produto'} (esgotado)'),
      ...acimaEstoque.map((i) => '${i.produtoNome ?? 'Produto'} (restam apenas ${i.produtoEstoque})'),
    ];

    final remover = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Itens indisponíveis', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Alguns itens do seu carrinho não estão disponíveis na quantidade desejada:'),
            const SizedBox(height: 12),
            ...nomes.map((n) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, size: 16, color: Color(0xFFF23D4F)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(n, style: const TextStyle(fontSize: 13))),
                    ],
                  ),
                )),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF23D4F), foregroundColor: Colors.white),
            child: const Text('Remover itens indisponíveis'),
          ),
        ],
      ),
    );

    if (remover != true) return false;
    for (final i in esgotados) {
      await cart.remover(i.id);
    }
    for (final i in acimaEstoque) {
      await cart.atualizarQuantidade(i.id, i.produtoEstoque ?? 1);
    }
    return false;
  }

  Future<void> _finalizarCompra(CartProvider cart, CupomProvider cupom) async {
    if (cart.items.isEmpty || _finalizando) return;

    if (!await _validarEstoque(cart)) return;

    final cep = _cepCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (_tipoEntrega == 'entrega') {
      final faltando = <String>[
        if (cep.length != 8) 'CEP',
        if (_ruaCtrl.text.trim().isEmpty) 'Rua',
        if (_numeroCtrl.text.trim().isEmpty) 'Número',
        if (_bairroCtrl.text.trim().isEmpty) 'Bairro',
        if (_cidadeCtrl.text.trim().isEmpty) 'Cidade',
        if (_ufCtrl.text.trim().isEmpty) 'UF',
      ];
      if (faltando.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Preencha para a entrega: ${faltando.join(', ')}.'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
    }

    final subtotal = cart.total;
    final descontoCupom = cupom.cupomAplicado != null
        ? subtotal - cupom.calcularDesconto(subtotal)
        : 0.0;
    final total = subtotal - descontoCupom;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar pedido', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _linhaConfirm('Itens', '${cart.items.length} ${cart.items.length == 1 ? 'produto' : 'produtos'}'),
            _linhaConfirm('Subtotal', 'R\$ ${subtotal.toStringAsFixed(2)}'),
            if (cart.economia > 0)
              _linhaConfirm('Desconto nos itens', '-R\$ ${cart.economia.toStringAsFixed(2)}', cor: const Color(0xFF00A650)),
            if (descontoCupom > 0)
              _linhaConfirm('Cupom ${cupom.cupomAplicado?.codigo}', '-R\$ ${descontoCupom.toStringAsFixed(2)}', cor: const Color(0xFF00A650)),
            const Divider(height: 24),
            _linhaConfirm('Total', 'R\$ ${total.toStringAsFixed(2)}', bold: true),
            const SizedBox(height: 8),
            const Text(
              'Você será direcionado para o pagamento via PIX da unidade.',
              style: TextStyle(fontSize: 12, color: Color(0xFFC6C6C6)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE50914), foregroundColor: Colors.white),
            child: const Text('Confirmar pedido'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _finalizando = true);
    try {
      final userId = context.read<AuthProvider>().user?.id;
      if (userId == null) return;

      final service = CheckoutService();
      final pedidos = await service.finalizar(
        userId: userId,
        itens: cart.items,
        cupomDescontoTotal: descontoCupom,
        cupomId: cupom.cupomAplicado?.id,
        tipoEntrega: _tipoEntrega,
        enderecoEntrega: _tipoEntrega == 'entrega' ? _enderecoFormatado : null,
        cepEntrega: _tipoEntrega == 'entrega' && cep.length == 8 ? cep : null,
      );

      // Limpa a UI (carrinho + cupom) sem nunca falhar o fluxo: os pedidos já
      // foram criados de forma atômica no banco. Se a limpeza falhar aqui
      // (rede), não pode virar "erro ao finalizar" nem permitir pedido duplicado.
      try {
        await cart.limpar();
      } catch (_) {}
      cupom.removerCupom();
      if (!mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PagamentoScreen(pedidos: pedidos, total: total),
        ),
      );
    } catch (e) {
      if (mounted) {
        final msg = e is StateError
            ? e.message
            : 'Erro ao finalizar a compra. Tente novamente.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _finalizando = false);
    }
  }

  Widget _linhaConfirm(String label, String valor, {Color? cor, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(fontSize: 13, color: cor ?? const Color(0xFFEDEDED), fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
          Text(valor,
              style: TextStyle(fontSize: 13, color: cor ?? const Color(0xFFEDEDED), fontWeight: bold ? FontWeight.w700 : FontWeight.w600)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeColors.background(context),
      appBar: AppBar(
        backgroundColor: ThemeColors.surface(context),
        leading: context.canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => context.pop(),
              )
            : null,
        title: Text('Carrinho',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: Consumer<CartProvider>(
        builder: (context, cart, _) {
          if (cart.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (cart.error != null && cart.items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off_rounded, color: ThemeColors.hint(context), size: 64),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    child: Text(cart.error!,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  const SizedBox(height: 8),
                  Text('Verifique sua conexão e tente de novo',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: ThemeColors.secondaryText(context))),
                  const SizedBox(height: AppSpacing.lg),
                  ElevatedButton(
                    onPressed: () => context.read<CartProvider>().loadCart(),
                    child: const Text('Tentar novamente'),
                  ),
                ],
              ),
            );
          }
          if (cart.items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shopping_cart_outlined, color: ThemeColors.hint(context), size: 64),
                  const SizedBox(height: 16),
                  Text('Carrinho vazio',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('Adicione produtos para começar',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: ThemeColors.secondaryText(context))),
                  const SizedBox(height: AppSpacing.lg),
                  ElevatedButton(
                    onPressed: () => context.go('/'),
                    child: const Text('Continuar comprando'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                    onPressed: () => context.go('/pedidos'),
                    child: const Text('Ver meus pedidos'),
                  ),
                ],
              ),
            );
          }

          final cupom = context.watch<CupomProvider>();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => context.go('/'),
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    label: const Text('Continuar comprando'),
                    style: TextButton.styleFrom(foregroundColor: const Color(0xFFE50914)),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.sm, 0, AppSpacing.sm, 0),
                  itemCount: cart.items.length,
                  itemBuilder: (context, index) {
                    final item = cart.items[index];
                    return AnimatedCardEntry(
                      index: index,
                      child: _buildCartItem(context, cart, item, cupom),
                    );
                  },
                ),
              ),
              // Resumo em área rolável: com o teclado aberto (campo de cupom)
              // o espaço diminui — sem isso ocorre "bottom overflowed".
              Flexible(
                child: SingleChildScrollView(
                  child: _buildResumo(context, cart, cupom),
                ),
              ),
              _buildBottomBar(context, cart, cupom),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCartItem(BuildContext context, CartProvider cart, CartItem item,
      CupomProvider cupom) {
    final esgotado = item.esgotado;
    final emPromo = item.temPromocao;
    final estoqueBaixo = !esgotado && (item.produtoEstoque ?? 0) <= 5;
    final estoque = item.produtoEstoque ?? 0;
    final percentualOff = emPromo && (item.produtoPreco ?? 0) > 0
        ? (((item.produtoPreco! - item.precoAtual) / item.produtoPreco!) * 100).round()
        : 0;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: ThemeColors.surface(context),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: esgotado ? Border.all(color: const Color(0xFFF23D4F).withValues(alpha: 0.4)) : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: SizedBox(
              width: 80,
              height: 80,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  item.produtoImagem != null
                      ? CachedNetworkImage(
                          imageUrl: item.produtoImagem!,
                          fit: BoxFit.contain,
                          placeholder: (_, __) => Container(
                            color: Colors.white,
                            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: Colors.white,
                            child: Icon(Icons.image_outlined, color: ThemeColors.hint(context)),
                          ),
                        )
                      : Container(
                          color: Colors.white,
                          child: Icon(Icons.image_outlined, color: ThemeColors.hint(context)),
                        ),
                  if (esgotado)
                    Container(
                      color: Colors.black.withValues(alpha: 0.45),
                      alignment: Alignment.center,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('ESGOTADO',
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFFF23D4F), letterSpacing: 0.5)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.produtoNome ?? 'Produto',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.cor != null && item.cor!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _corDe(item.cor!),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text('Cor: ${item.cor}',
                          style: TextStyle(fontSize: 11, color: ThemeColors.secondaryText(context), fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
                const SizedBox(height: 4),
                if (emPromo) ...[
                  Row(
                    children: [
                      Text(
                        'R\$ ${(item.produtoPreco ?? 0).toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF9C9C9C), decoration: TextDecoration.lineThrough),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00A650).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('-$percentualOff%',
                            style: const TextStyle(fontSize: 10, color: Color(0xFF00A650), fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ],
                Text(
                  'R\$ ${item.precoAtual.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: emPromo ? const Color(0xFF00A650) : null,
                      ),
                ),
                // Cupom percentual aplicado ao produto (evidência no item)
                if (cupom.cupomAplicado != null &&
                    cupom.cupomAplicado!.tipo == 'percentual' &&
                    !esgotado) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00A650).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '-${cupom.cupomAplicado!.valor.toInt()}% cupom ${cupom.cupomAplicado!.codigo}',
                          style: const TextStyle(
                              fontSize: 10, color: Color(0xFF00A650), fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 2),
                if (esgotado)
                  const Text('Sem estoque no momento',
                      style: TextStyle(fontSize: 11, color: Color(0xFFF23D4F), fontWeight: FontWeight.w600))
                else if (estoqueBaixo)
                  Text('Restam apenas $estoque ${estoque == 1 ? 'unidade' : 'unidades'}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFFFFAD01), fontWeight: FontWeight.w600))
                else
                  Text('Em estoque',
                      style: TextStyle(fontSize: 11, color: ThemeColors.success(context), fontWeight: FontWeight.w600)),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    _buildQuantityButton(
                      icon: Icons.remove_rounded,
                      onTap: esgotado ? null : () => cart.atualizarQuantidade(item.id, item.quantidade - 1),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text('${item.quantidade}',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(width: AppSpacing.sm),
                    _buildQuantityButton(
                      icon: Icons.add_rounded,
                      onTap: esgotado
                          ? null
                          : () {
                              if (item.quantidade >= estoque) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Estoque máximo disponível: $estoque'),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                                return;
                              }
                              cart.atualizarQuantidade(item.id, item.quantidade + 1);
                            },
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Subtotal da linha (qtd × preço)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Subtotal',
                        style: TextStyle(fontSize: 11, color: ThemeColors.secondaryText(context))),
                    Text(
                      'R\$ ${item.total.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline_rounded, color: ThemeColors.error(context), size: 20),
            onPressed: () => cart.remover(item.id),
          ),
        ],
      ),
    );
  }

  Color _corDe(String nome) {
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

  Widget _buildQuantityButton({
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: onTap == null ? ThemeColors.surfaceVariant(context).withValues(alpha: 0.5) : ThemeColors.surfaceVariant(context),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Icon(icon, size: 18, color: onTap == null ? ThemeColors.hint(context) : ThemeColors.primaryText(context)),
      ),
    );
  }

  // ─── RESUMO (cupom + totais) ────────────────────────

  Widget _buildResumo(BuildContext context, CartProvider cart, CupomProvider cupom) {
    final subtotal = cart.total;
    final economiaItens = cart.economia;
    final descontoCupom = cupom.cupomAplicado != null
        ? subtotal - cupom.calcularDesconto(subtotal)
        : 0.0;
    final freteGratis = cart.items.every((i) => i.produtoFreteGratis);
    final total = subtotal - descontoCupom;
    final economiaTotal = economiaItens + descontoCupom;
    final temEsgotado = cart.itensEsgotados.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: ThemeColors.surface(context),
        border: Border(top: BorderSide(color: ThemeColors.divider(context))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Entrega / Retirada
          const Text('Receber em', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildTipoEntregaOption(
                  tipo: 'retirada',
                  icon: Icons.storefront_rounded,
                  label: 'Retirada na unidade',
                  subtitulo: 'Grátis',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildTipoEntregaOption(
                  tipo: 'entrega',
                  icon: Icons.delivery_dining_rounded,
                  label: 'Entrega',
                  subtitulo: 'Ver previsão',
                ),
              ),
            ],
          ),
          if (_tipoEntrega == 'entrega') ...[
            const SizedBox(height: 8),
            // CEP com busca automática
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _cepCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [_cepMask],
                    decoration: InputDecoration(
                      labelText: 'CEP',
                      hintText: '00000-000',
                      prefixIcon: const Icon(Icons.location_on_outlined, size: 18),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      filled: true,
                      fillColor: ThemeColors.surfaceVariant(context),
                    ),
                    onSubmitted: (_) => _buscarCep(),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _buscandoCep ? null : _buscarCep,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE50914),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    child: _buscandoCep
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Buscar', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _ruaCtrl,
                    decoration: _campoEndereco('Rua'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _numeroCtrl,
                    decoration: _campoEndereco('Número'),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _complementoCtrl,
              decoration: _campoEndereco('Complemento (opcional)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _bairroCtrl,
              decoration: _campoEndereco('Bairro'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _cidadeCtrl,
                    decoration: _campoEndereco('Cidade'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _ufCtrl,
                    decoration: _campoEndereco('UF'),
                    maxLength: 2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Ao informar o CEP, os campos são preenchidos automaticamente (ViaCEP — gratuito).',
              style: TextStyle(fontSize: 10, color: ThemeColors.hint(context)),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          // Cupom
          if (cupom.cupomAplicado == null) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _cupomCtrl,
                    decoration: InputDecoration(
                      hintText: 'Cupom de desconto',
                      prefixIcon: const Icon(Icons.discount_rounded, size: 18),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      filled: true,
                      fillColor: ThemeColors.surfaceVariant(context),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      isDense: true,
                    ),
                    textCapitalization: TextCapitalization.characters,
                    onSubmitted: (_) => _aplicarCupom(cupom),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 44,
                  child: ElevatedButton(
                    onPressed: _aplicandoCupom ? null : () => _aplicarCupom(cupom),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE50914),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: _aplicandoCupom
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Aplicar', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF00A650).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.discount_rounded, size: 18, color: Color(0xFF00A650)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      cupom.cupomAplicado!.descricao,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF00A650)),
                    ),
                  ),
                  GestureDetector(
                    onTap: cupom.removerCupom,
                    child: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF00A650)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (temEsgotado) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF23D4F).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.error_outline_rounded, size: 18, color: Color(0xFFF23D4F)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Há itens esgotados no carrinho. Finalize a compra para revisá-los.',
                      style: TextStyle(fontSize: 12, color: Color(0xFFF23D4F), fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          _linhaResumo(context, 'Subtotal', 'R\$ ${subtotal.toStringAsFixed(2)}'),
          if (economiaItens > 0)
            _linhaResumo(context, 'Desconto nos itens', '-R\$ ${economiaItens.toStringAsFixed(2)}', cor: const Color(0xFF00A650)),
          if (descontoCupom > 0)
            _linhaResumo(context, 'Cupom ${cupom.cupomAplicado?.codigo}', '-R\$ ${descontoCupom.toStringAsFixed(2)}', cor: const Color(0xFF00A650)),
          _linhaResumo(context, 'Entrega', freteGratis ? 'Grátis' : 'Retirada na unidade'),
          if (economiaTotal > 0)
            _linhaResumo(context, 'Você economizou', 'R\$ ${economiaTotal.toStringAsFixed(2)}',
                cor: const Color(0xFF00A650), bold: true),
          const Divider(height: 20),
          _linhaResumo(context, 'Total', 'R\$ ${total.toStringAsFixed(2)}', bold: true, grande: true),
        ],
      ),
    );
  }

  InputDecoration _campoEndereco(String label) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      filled: true,
      fillColor: ThemeColors.surfaceVariant(context),
      isDense: true,
    );
  }

  Widget _buildTipoEntregaOption({
    required String tipo,
    required IconData icon,
    required String label,
    required String subtitulo,
  }) {
    final sel = _tipoEntrega == tipo;
    return GestureDetector(
      onTap: () => setState(() => _tipoEntrega = tipo),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: ThemeColors.surfaceVariant(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: sel ? const Color(0xFFE50914) : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: sel ? const Color(0xFFE50914) : ThemeColors.hint(context)),
            const SizedBox(height: 4),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                  color: sel ? const Color(0xFFE50914) : ThemeColors.primaryText(context),
                )),
            Text(subtitulo,
                style: TextStyle(fontSize: 10, color: ThemeColors.secondaryText(context))),
          ],
        ),
      ),
    );
  }

  Widget _linhaResumo(BuildContext context, String label, String valor,
      {Color? cor, bool bold = false, bool grande = false}) {
    final style = grande
        ? Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: cor)
        : TextStyle(
            fontSize: 13,
            color: cor ?? ThemeColors.primaryText(context),
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: grande ? 15 : 13, color: cor ?? ThemeColors.secondaryText(context), fontWeight: bold ? FontWeight.w600 : FontWeight.w400)),
          Text(valor, style: style),
        ],
      ),
    );
  }

  // ─── BOTTOM BAR ─────────────────────────────────────

  Widget _buildBottomBar(BuildContext context, CartProvider cart, CupomProvider cupom) {
    final subtotal = cart.total;
    final descontoCupom = cupom.cupomAplicado != null
        ? subtotal - cupom.calcularDesconto(subtotal)
        : 0.0;
    final total = subtotal - descontoCupom;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: ThemeColors.surface(context),
        border: Border(top: BorderSide(color: ThemeColors.divider(context))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Total',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: ThemeColors.secondaryText(context))),
                  Text(
                    'R\$ ${total.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: (_finalizando || cart.items.isEmpty) ? null : () => _finalizarCompra(cart, cupom),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE50914),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                ),
                child: _finalizando
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Finalizar Compra', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
