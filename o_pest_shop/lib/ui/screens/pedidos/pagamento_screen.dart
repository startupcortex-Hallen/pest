import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/helpers/theme_colors.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/cartao_provider.dart';
import '../../../services/checkout_service.dart';

/// Tela de pagamento — PIX (copia e cola) ou Cartão de crédito (simulado).
/// Segue o padrão dos grandes apps: escolha da forma de pagamento,
/// passos claros e confirmação explícita.
class PagamentoScreen extends StatefulWidget {
  final List<PedidoCriado> pedidos;
  final double total;

  const PagamentoScreen({super.key, required this.pedidos, required this.total});

  @override
  State<PagamentoScreen> createState() => _PagamentoScreenState();
}

class _PagamentoScreenState extends State<PagamentoScreen> {
  final _checkoutService = CheckoutService();
  bool _confirmando = false;
  final Set<int> _copiados = {};
  String _metodo = 'pix';
  int? _cartaoSelecionado;
  int _parcelas = 1;
  static const _opcoesParcelas = [1, 2, 3, 6, 12];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CartaoProvider>().loadCartoes();
    });
  }

  Future<void> _copiarPix(int pedidoId, String? pix) async {
    if (pix == null || pix.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: pix));
    if (mounted) {
      setState(() => _copiados.add(pedidoId));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Código PIX copiado!'), duration: Duration(seconds: 2)),
      );
    }
  }

  Future<void> _adicionarCartao() async {
    await context.push('/cartoes');
    if (mounted) context.read<CartaoProvider>().loadCartoes();
  }

  Future<void> _confirmarPagamento() async {
    if (_metodo == 'cartao' && _cartaoSelecionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione um cartão para pagar.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    final userId = context.read<AuthProvider>().user?.id;
    if (userId == null) return;
    setState(() => _confirmando = true);
    String? transacao;
    try {
      if (_metodo == 'cartao') {
        // Autorização SIMULADA no servidor: valida validade/permissões,
        // grava a transação e aprova (o trigger avança para "em preparo").
        for (final p in widget.pedidos) {
          final r = await _checkoutService.processarPagamentoCartao(
            pedidoId: p.id,
            cartaoId: _cartaoSelecionado!,
            parcelas: _parcelas,
          );
          if (r['aprovado'] != true) {
            throw StateError(r['motivo'] as String? ?? 'Pagamento recusado.');
          }
          transacao = r['transacao_id'] as String? ?? transacao;
        }
      } else {
        for (final p in widget.pedidos) {
          await _checkoutService.confirmarPagamento(
            userId: userId,
            pedidoId: p.id,
            metodo: 'pix',
          );
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              transacao != null && transacao.length >= 8
                  ? 'Pagamento aprovado! Transação #${transacao.substring(0, 8)}.'
                  : 'Pagamento confirmado! Seu pedido está sendo processado.',
            ),
            backgroundColor: AppColors.success,
          ),
        );
        context.go('/pedidos');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _confirmando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is StateError ? e.message : 'Erro ao confirmar o pagamento. Tente novamente.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeColors.background(context),
      appBar: AppBar(
        backgroundColor: ThemeColors.surface(context),
        title: const Text('Pagamento', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          // Cabeçalho de sucesso
          const Icon(Icons.check_circle_rounded, size: 64, color: Color(0xFF00A650)),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Pedido realizado!',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            widget.pedidos.length > 1
                ? 'Seu pedido foi dividido em ${widget.pedidos.length} lojas parceiras.'
                : 'Escolha a forma de pagamento para confirmar sua compra.',
            textAlign: TextAlign.center,
            style: TextStyle(color: ThemeColors.secondaryText(context), fontSize: 13),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Forma de pagamento
          const Text('Forma de pagamento',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _buildMetodoCard(
                  metodo: 'pix',
                  icon: Icons.qr_code_2_rounded,
                  titulo: 'PIX',
                  subtitulo: 'Pagamento instantâneo',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetodoCard(
                  metodo: 'cartao',
                  icon: Icons.credit_card_rounded,
                  titulo: 'Cartão',
                  subtitulo: 'Crédito em até 12x',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          if (_metodo == 'pix') ...[
            // Passos do PIX
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: ThemeColors.surface(context),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Passo(numero: '1', texto: 'Copie o código PIX de cada unidade'),
                  _Passo(numero: '2', texto: 'Pague no app do seu banco'),
                  _Passo(numero: '3', texto: 'Volte aqui e toque em "Já paguei"'),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            ...widget.pedidos.map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: _buildPixCard(p),
                )),
          ] else ...[
            _buildCartaoSection(),
            const SizedBox(height: AppSpacing.md),
            // Parcelas
            const Text('Parcelas',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: _opcoesParcelas.map((p) {
                final sel = _parcelas == p;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _parcelas = p),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: sel
                            ? const Color(0xFFE50914).withValues(alpha: 0.12)
                            : ThemeColors.surface(context),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: sel ? const Color(0xFFE50914) : ThemeColors.outline(context),
                          width: sel ? 1.5 : 1,
                        ),
                      ),
                      child: Text(
                        '${p}x',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                          color: sel ? const Color(0xFFE50914) : ThemeColors.primaryText(context),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            Text(
              _parcelas > 1
                  ? '${_parcelas}x de R\$ ${(widget.total / _parcelas).toStringAsFixed(2)} sem juros'
                  : 'Pagamento à vista',
              style: const TextStyle(fontSize: 12, color: Color(0xFFC6C6C6)),
            ),
          ],

          const SizedBox(height: AppSpacing.sm),
          // Total geral
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: ThemeColors.surface(context),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total a pagar',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                Text(
                  'R\$ ${widget.total.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Confirmação
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _confirmando ? null : _confirmarPagamento,
              icon: _confirmando
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(_metodo == 'pix' ? Icons.verified_rounded : Icons.lock_rounded, size: 20),
              label: Text(
                _metodo == 'pix' ? 'Já paguei' : 'Confirmar pagamento',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00A650),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Continuar comprando
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: () => context.go('/'),
              icon: const Icon(Icons.shopping_bag_outlined, size: 18),
              label: const Text('Continuar comprando', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFE50914),
                side: const BorderSide(color: Color(0xFFE50914)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 44,
            child: TextButton(
              onPressed: () => context.go('/pedidos'),
              child: const Text('Pagar depois — ver meus pedidos', style: TextStyle(fontSize: 13)),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }

  Widget _buildMetodoCard({
    required String metodo,
    required IconData icon,
    required String titulo,
    required String subtitulo,
  }) {
    final sel = _metodo == metodo;
    return GestureDetector(
      onTap: () => setState(() => _metodo = metodo),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: ThemeColors.surface(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: sel ? const Color(0xFFE50914) : ThemeColors.outline(context),
            width: sel ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 28, color: sel ? const Color(0xFFE50914) : ThemeColors.hint(context)),
            const SizedBox(height: 8),
            Text(titulo,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: sel ? const Color(0xFFE50914) : ThemeColors.primaryText(context),
                )),
            Text(subtitulo,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, color: ThemeColors.secondaryText(context))),
          ],
        ),
      ),
    );
  }

  // ─── PIX ────────────────────────────────────────────

  Widget _buildPixCard(PedidoCriado p) {
    final copiado = _copiados.contains(p.id);
    final pix = p.pixCopiaCola;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: ThemeColors.surface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE50914).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.store_rounded, size: 18, color: Color(0xFFE50914)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(p.unidadeNome,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              Text('R\$ ${p.total.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 4),
          Text('${p.itensCount} ${p.itensCount == 1 ? 'item' : 'itens'} • Pedido #${p.id}',
              style: TextStyle(fontSize: 11, color: ThemeColors.secondaryText(context))),
          const SizedBox(height: AppSpacing.md),
          if (pix != null && pix.isNotEmpty) ...[
            Text('PIX copia e cola',
                style: TextStyle(fontSize: 11, color: ThemeColors.secondaryText(context), fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ThemeColors.surfaceVariant(context),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                pix,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: copiado
                  ? ElevatedButton.icon(
                      onPressed: () => _copiarPix(p.id, pix),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Copiado!'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00A650),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    )
                  : OutlinedButton.icon(
                      onPressed: () => _copiarPix(p.id, pix),
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Copiar código PIX'),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFE50914),
                        side: const BorderSide(color: Color(0xFFE50914)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
            ),
          ] else
            Text('PIX não configurado para esta unidade. Entre em contato pelo atendimento.',
                style: TextStyle(fontSize: 12, color: ThemeColors.error(context))),
        ],
      ),
    );
  }

  // ─── CARTÃO ─────────────────────────────────────────

  Widget _buildCartaoSection() {
    return Consumer<CartaoProvider>(
      builder: (context, cartao, _) {
        if (cartao.loading) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        // Cartão "fantasma": o selecionado foi removido na tela /cartoes
        final selecaoValida = _cartaoSelecionado != null &&
            cartao.cartoes.any((c) => c.id == _cartaoSelecionado);
        if (_cartaoSelecionado != null && !selecaoValida) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _cartaoSelecionado = null);
          });
        }
        if (cartao.cartoes.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: ThemeColors.surface(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: ThemeColors.outline(context)),
            ),
            child: Column(
              children: [
                const Icon(Icons.credit_card_off_rounded, size: 40, color: Color(0xFF9C9C9C)),
                const SizedBox(height: 8),
                const Text('Nenhum cartão salvo',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('Adicione um cartão para pagar com crédito.',
                    style: TextStyle(fontSize: 12, color: ThemeColors.secondaryText(context))),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _adicionarCartao,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Adicionar cartão'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE50914),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...cartao.cartoes.map((c) {
              final sel = _cartaoSelecionado == c.id;
              return GestureDetector(
                onTap: () => setState(() => _cartaoSelecionado = c.id),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: ThemeColors.surface(context),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: sel ? const Color(0xFFE50914) : ThemeColors.outline(context),
                      width: sel ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        sel ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                        size: 20,
                        color: sel ? const Color(0xFFE50914) : ThemeColors.hint(context),
                      ),
                      const SizedBox(width: 12),
                      Icon(Icons.credit_card_rounded, size: 24, color: const Color(0xFFE50914)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${c.bandeiraIcon} • ${c.apelido}',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                            Text(c.numeroMascarado,
                                style: TextStyle(fontSize: 12, color: ThemeColors.secondaryText(context))),
                            Text('Validade ${c.mesValidade.toString().padLeft(2, '0')}/${c.anoValidade}',
                                style: TextStyle(fontSize: 11, color: ThemeColors.hint(context))),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _adicionarCartao,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Adicionar novo cartão'),
                style: TextButton.styleFrom(foregroundColor: const Color(0xFFE50914)),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Pagamento simulado — não há cobrança real. Integre um gateway '
              '(Mercado Pago, Pagar.me, Stripe) para autorizar de verdade.',
              style: TextStyle(fontSize: 11, color: ThemeColors.hint(context)),
            ),
          ],
        );
      },
    );
  }
}

class _Passo extends StatelessWidget {
  final String numero;
  final String texto;
  const _Passo({required this.numero, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(
              color: Color(0xFFE50914),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(numero,
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(texto, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
