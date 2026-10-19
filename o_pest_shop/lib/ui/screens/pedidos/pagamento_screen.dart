import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/helpers/cpf.dart';
import '../../../core/helpers/pagbank_js.dart';
import '../../../core/helpers/pedido_status.dart';
import '../../../core/helpers/theme_colors.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/cartao_credito.dart';
import '../../../models/pagamento.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/cartao_provider.dart';
import '../../../services/checkout_service.dart';
import '../../../services/pagamento_service.dart';

/// Pagamento real (PagBank) — PIX, cartão de crédito, cartão de débito (3DS)
/// e boleto. Uma única cobrança cobre todos os pedidos do carrinho.
///
/// O status é confirmado pelo webhook do gateway; esta tela acompanha ao vivo
/// por polling (`consultar`). O cliente NUNCA confirma o pagamento sozinho.
class PagamentoScreen extends StatefulWidget {
  final List<PedidoCriado> pedidos;
  final double total;

  const PagamentoScreen({super.key, required this.pedidos, required this.total});

  @override
  State<PagamentoScreen> createState() => _PagamentoScreenState();
}

class _PagamentoScreenState extends State<PagamentoScreen> {
  final _service = PagamentoService();

  String _metodo = 'pix';
  bool _processando = false;
  Pagamento? _pagamento;
  String? _erro;
  Timer? _poll;
  Timer? _contagem;
  Duration _restante = Duration.zero;

  bool _pixCopiado = false;
  bool _boletoCopiado = false;

  // Cartão novo
  final _numeroCtrl = TextEditingController();
  final _nomeCtrl = TextEditingController();
  final _cpfCtrl = TextEditingController();
  final _validadeCtrl = TextEditingController();
  final _cvvCtrl = TextEditingController();
  final _cvvSalvoCtrl = TextEditingController();
  bool _salvarCartao = false;
  int _parcelas = 1;
  int? _cartaoSalvoId;

  static const _opcoesParcelas = [1, 2, 3, 4, 5, 6, 10, 12];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      final cpf = auth.user?.cpf ?? '';
      if (cpf.isNotEmpty) _cpfCtrl.text = cpf;
      final nome = auth.user?.nome ?? '';
      if (nome.isNotEmpty) _nomeCtrl.text = nome;
      context.read<CartaoProvider>().loadCartoes();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _contagem?.cancel();
    _numeroCtrl.dispose();
    _nomeCtrl.dispose();
    _cpfCtrl.dispose();
    _validadeCtrl.dispose();
    _cvvCtrl.dispose();
    _cvvSalvoCtrl.dispose();
    super.dispose();
  }

  List<int> get _pedidoIds => widget.pedidos.map((p) => p.id).toList();

  String _somenteDigitos(String v) => v.replaceAll(RegExp(r'[^0-9]'), '');

  // ─── Criação da cobrança ─────────────────────────────────────

  Future<void> _gerarCobranca() async {
    if (_processando) return;
    setState(() {
      _processando = true;
      _erro = null;
    });
    try {
      Map<String, dynamic>? cartao;
      String? tresdsId;

      if (_metodo == 'credito' || _metodo == 'debito') {
        final dadosCartao = await _dadosCartaoParaCobranca();
        cartao = dadosCartao.$1;
        tresdsId = dadosCartao.$2;
      }

      final pagamento = await _service.criar(
        pedidoIds: _pedidoIds,
        metodo: _metodo,
        parcelas: _metodo == 'credito' ? _parcelas : 1,
        cartao: cartao,
        tresdsId: tresdsId,
      );

      if (!mounted) return;
      setState(() => _pagamento = pagamento);

      if (pagamento.pago) {
        _aoConfirmarPagamento();
      } else if (pagamento.recusado) {
        setState(() => _erro = pagamento.motivoRecusa ?? 'Pagamento recusado pela operadora.');
      } else {
        _iniciarAcompanhamento();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _erro = e is StateError ? e.message : 'Não foi possível gerar o pagamento. Tente novamente.');
      }
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  /// Valida os dados, roda o 3DS (obrigatório em crédito e débito) e
  /// criptografa o cartão no navegador com a chave pública do PagBank.
  Future<(Map<String, dynamic>, String?)> _dadosCartaoParaCobranca() async {
    if (!PagBankJs.disponivel) {
      throw StateError(
        'Pagamento com cartão está disponível na versão web do app. '
        'Use PIX ou boleto por aqui.',
      );
    }

    final cartoes = context.read<CartaoProvider>().cartoes;
    final salvos = cartoes.where((c) => c.gatewayCardId != null).toList();

    // Cartão salvo (crédito) + CVV + 3DS
    if (_metodo == 'credito' && _cartaoSalvoId != null) {
      final cartao = salvos.firstWhere((c) => c.id == _cartaoSalvoId);
      final cvv = _somenteDigitos(_cvvSalvoCtrl.text);
      if (cvv.length < 3) {
        throw StateError('Informe o CVV do cartão salvo.');
      }
      final tresdsId = await _autenticar3ds(
        tipo: 'CREDIT_CARD',
        cardId: cartao.gatewayCardId,
        nome: cartao.titular,
      );
      return (
        {
          'card_id': cartao.gatewayCardId,
          'security_code': cvv,
          'holder_nome': cartao.titular,
        },
        tresdsId,
      );
    }

    if (!PagBankJs.disponivel) {
      throw StateError(
        'Pagamento com cartão está disponível na versão web do app. '
        'Use PIX ou boleto por aqui.',
      );
    }

    final numero = _somenteDigitos(_numeroCtrl.text);
    final nome = _nomeCtrl.text.trim();
    final cpf = _somenteDigitos(_cpfCtrl.text);
    final validade = _somenteDigitos(_validadeCtrl.text);
    final cvv = _somenteDigitos(_cvvCtrl.text);

    if (numero.length < 13) throw StateError('Número do cartão incompleto.');
    if (nome.split(' ').where((p) => p.isNotEmpty).length < 2) {
      throw StateError('Informe o nome completo do titular.');
    }
    if (!cpfValido(cpf)) throw StateError('CPF do titular inválido.');
    if (validade.length != 4) throw StateError('Validade inválida (use MM/AA).');
    if (cvv.length < 3) throw StateError('CVV inválido.');

    final mes = validade.substring(0, 2);
    final ano = '20${validade.substring(2)}';

    // 3DS obrigatório em crédito E débito (proteção contra cartão clonado).
    final tresdsId = await _autenticar3ds(
      tipo: _metodo == 'debito' ? 'DEBIT_CARD' : 'CREDIT_CARD',
      numero: numero,
      mes: mes,
      ano: ano,
      nome: nome,
    );

    final chave = await _service.chavePublica();
    final encrypted = await PagBankJs.criptografarCartao(
      publicKey: chave,
      holder: nome,
      number: numero,
      expMonth: mes,
      expYear: ano,
      securityCode: cvv,
    );

    return (
      {
        'encrypted': encrypted,
        'holder_nome': nome,
        'holder_cpf': cpf,
        'last4': numero.substring(numero.length - 4),
        'salvar': _metodo == 'credito' && _salvarCartao,
      },
      tresdsId,
    );
  }

  Future<String> _autenticar3ds({
    required String tipo,
    String? numero,
    String? mes,
    String? ano,
    String? nome,
    String? cardId,
  }) async {
    final sessao = await _service.sessao3ds();
    final auth = context.read<AuthProvider>().user;
    final telefone = _somenteDigitos(auth?.telefone ?? '');
    final nomeTitular = nome ?? auth?.nome ?? 'Cliente';

    final card = cardId != null
        ? <String, dynamic>{'id': cardId}
        : <String, dynamic>{
            'number': numero,
            'expMonth': mes,
            'expYear': ano,
            'holder': {'name': nomeTitular},
          };

    final request = <String, dynamic>{
      'data': {
        'customer': {
          'name': nomeTitular,
          'email': auth?.email ?? '',
          if (telefone.length >= 10)
            'phones': [
              {
                'country': '55',
                'area': telefone.substring(0, 2),
                'number': telefone.substring(2),
                'type': 'MOBILE',
              },
            ],
        },
        'paymentMethod': {
          'type': tipo,
          'installments': tipo == 'DEBIT_CARD' ? 1 : _parcelas,
          'card': card,
        },
        'amount': {
          'value': (widget.total * 100).round(),
          'currency': 'BRL',
        },
        'billingAddress': _enderecoPadrao3ds(),
        'shippingAddress': _enderecoPadrao3ds(),
        'dataOnly': false,
      },
    };

    final resultado = await PagBankJs.autenticar3ds(
      session: sessao['session'] ?? '',
      env: sessao['env'] ?? 'SANDBOX',
      request: request,
    );

    final status = resultado['status'] ?? '';
    final id3ds = resultado['id'] ?? '';
    if (status == 'AUTH_FLOW_COMPLETED' && id3ds.isNotEmpty) {
      return id3ds;
    }
    if (status == 'CHANGE_PAYMENT_METHOD') {
      throw StateError('Autenticação negada pelo banco. Tente outro cartão.');
    }
    if (status == 'AUTH_NOT_SUPPORTED') {
      throw StateError(
        'Este cartão não é elegível à autenticação 3DS, obrigatória para compras '
        'com cartão. Use outro cartão ou pague com PIX/boleto.',
      );
    }
    throw StateError('Não foi possível autenticar o cartão (3DS). Tente novamente.');
  }

  Map<String, dynamic> _enderecoPadrao3ds() => {
        'street': 'Av. Paulista',
        'number': '1000',
        'complement': '',
        'regionCode': 'SP',
        'country': 'BRA',
        'city': 'São Paulo',
        'postalCode': '01310100',
      };

  // ─── Acompanhamento do status (webhook + polling) ────────────

  void _iniciarAcompanhamento() {
    _poll?.cancel();
    _contagem?.cancel();

    final expira = _pagamento?.expiraEm;
    if (expira != null) {
      _restante = expira.difference(DateTime.now());
      _contagem = Timer.periodic(const Duration(seconds: 1), (_) {
        final restante = expira.difference(DateTime.now());
        if (mounted) setState(() => _restante = restante.isNegative ? Duration.zero : restante);
      });
    }

    if (_pagamento == null || !_pagamento!.pendente) return;
    _poll = Timer.periodic(const Duration(seconds: 5), (_) async {
      final atual = _pagamento;
      if (atual == null || !atual.pendente) return;
      try {
        final atualizado = await _service.consultar(atual.id);
        if (!mounted) return;
        setState(() => _pagamento = atualizado);
        if (atualizado.pago) {
          _aoConfirmarPagamento();
        } else if (atualizado.recusado || atualizado.expirado) {
          _poll?.cancel();
          _contagem?.cancel();
        }
      } catch (_) {
        // silencioso — tenta no próximo ciclo
      }
    });
  }

  void _aoConfirmarPagamento() {
    _poll?.cancel();
    _contagem?.cancel();
    context.read<CartaoProvider>().loadCartoes();
  }

  Future<void> _copiar(String texto, {bool pix = false}) async {
    await Clipboard.setData(ClipboardData(text: texto));
    if (!mounted) return;
    setState(() {
      if (pix) {
        _pixCopiado = true;
      } else {
        _boletoCopiado = true;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(pix ? 'Código PIX copiado!' : 'Linha digitável copiada!')),
    );
  }

  void _trocarFormaPagamento() {
    _poll?.cancel();
    _contagem?.cancel();
    setState(() {
      _pagamento = null;
      _erro = null;
      _pixCopiado = false;
      _boletoCopiado = false;
    });
  }

  // ─── UI ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final finalizado = _pagamento?.pago ?? false;
    return Scaffold(
      backgroundColor: ThemeColors.background(context),
      appBar: AppBar(
        backgroundColor: ThemeColors.surface(context),
        title: const Text('Pagamento', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: finalizado
          ? _buildSucesso(_pagamento!)
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                _buildCabecalho(),
                const SizedBox(height: AppSpacing.lg),
                if (_pagamento == null) ..._buildEscolha() else ..._buildAcompanhamento(_pagamento!),
              ],
            ),
    );
  }

  Widget _buildCabecalho() {
    return Column(
      children: [
        Icon(
          _pagamento == null ? Icons.lock_rounded : Icons.hourglass_top_rounded,
          size: 44,
          color: const Color(0xFFE50914),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          _pagamento == null ? 'Escolha a forma de pagamento' : 'Aguardando confirmação',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          widget.pedidos.length > 1
              ? 'Uma única cobrança para os ${widget.pedidos.length} pedidos das lojas parceiras.'
              : 'Pedido #${widget.pedidos.first.id}',
          textAlign: TextAlign.center,
          style: TextStyle(color: ThemeColors.secondaryText(context), fontSize: 12),
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: ThemeColors.surface(context),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total a pagar', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              Text(
                'R\$ ${widget.total.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildEscolha() {
    return [
      Row(
        children: [
          Expanded(child: _metodoCard('pix', Icons.qr_code_2_rounded, 'PIX', 'Aprovação na hora')),
          const SizedBox(width: 8),
          Expanded(child: _metodoCard('credito', Icons.credit_card_rounded, 'Crédito', 'Em até 12x')),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(child: _metodoCard('debito', Icons.credit_card_outlined, 'Débito', 'À vista com 3DS')),
          const SizedBox(width: 8),
          Expanded(child: _metodoCard('boleto', Icons.receipt_rounded, 'Boleto', 'Vence em 3 dias')),
        ],
      ),
      const SizedBox(height: AppSpacing.lg),
      if (_metodo == 'credito') _buildCartaoSection(permiteSalvar: true),
      if (_metodo == 'debito') ...[
        _buildCartaoSection(permiteSalvar: false),
        const SizedBox(height: 8),
        Text(
          'Para sua segurança, todo pagamento com cartão passa pela autenticação 3DS do seu banco — uma janela de confirmação será aberta.',
          style: TextStyle(fontSize: 11, color: ThemeColors.hint(context)),
        ),
      ],
      if (_metodo == 'pix')
        _buildAviso(
          Icons.qr_code_2_rounded,
          'O QR Code é gerado na hora e vale por 30 minutos. A confirmação é automática após o pagamento.',
        ),
      if (_metodo == 'boleto')
        _buildAviso(
          Icons.receipt_rounded,
          'O boleto é registrado na hora e vence em 3 dias. O pedido é liberado após a compensação bancária (1 a 2 dias úteis).',
        ),
      if (_erro != null) ...[
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_erro!, style: const TextStyle(fontSize: 12, color: AppColors.error)),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: AppSpacing.lg),
      SizedBox(
        height: 52,
        child: ElevatedButton.icon(
          onPressed: _processando ? null : _gerarCobranca,
          icon: _processando
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.lock_rounded, size: 20),
          label: Text(
            _rotuloBotao(),
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
      SizedBox(
        height: 44,
        child: TextButton(
          onPressed: () => context.go('/pedidos'),
          child: const Text('Pagar depois — ver meus pedidos', style: TextStyle(fontSize: 13)),
        ),
      ),
    ];
  }

  String _rotuloBotao() {
    switch (_metodo) {
      case 'pix':
        return 'Gerar QR Code PIX';
      case 'credito':
        return 'Pagar com crédito';
      case 'debito':
        return 'Pagar com débito';
      case 'boleto':
        return 'Gerar boleto';
      default:
        return 'Gerar pagamento';
    }
  }

  Widget _metodoCard(String metodo, IconData icon, String titulo, String subtitulo) {
    final sel = _metodo == metodo;
    final indisponivel =
        (metodo == 'credito' || metodo == 'debito') && !PagBankJs.disponivel;
    return GestureDetector(
      onTap: _processando
          ? null
          : () {
              if (indisponivel) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Pagamento com cartão está disponível na versão web. '
                      'No app, use PIX ou boleto.',
                    ),
                  ),
                );
                return;
              }
              setState(() => _metodo = metodo);
            },
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: ThemeColors.surface(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: sel ? const Color(0xFFE50914) : ThemeColors.outline(context),
            width: sel ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon,
                size: 24,
                color: indisponivel
                    ? ThemeColors.hint(context).withValues(alpha: 0.5)
                    : sel
                        ? const Color(0xFFE50914)
                        : ThemeColors.hint(context)),
            const SizedBox(height: 6),
            Text(
              titulo,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: indisponivel
                    ? ThemeColors.hint(context)
                    : sel
                        ? const Color(0xFFE50914)
                        : ThemeColors.primaryText(context),
              ),
            ),
            Text(
              indisponivel ? 'Somente no site' : subtitulo,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 9, color: ThemeColors.secondaryText(context)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAviso(IconData icon, String texto) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: ThemeColors.surface(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: ThemeColors.hint(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(texto, style: TextStyle(fontSize: 12, color: ThemeColors.secondaryText(context))),
          ),
        ],
      ),
    );
  }

  // ─── Cartão (form + salvos) ──────────────────────────────────

  Widget _buildCartaoSection({required bool permiteSalvar}) {
    return Consumer<CartaoProvider>(
      builder: (context, cartaoProvider, _) {
        final salvos = cartaoProvider.cartoes.where((c) => c.gatewayCardId != null).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (permiteSalvar && salvos.isNotEmpty) ...[
              Text('Cartões salvos', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ThemeColors.secondaryText(context))),
              const SizedBox(height: 6),
              ...salvos.map(_cartaoSalvoTile),
              const SizedBox(height: 6),
            ],
            if (_cartaoSalvoId != null) ...[
              TextField(
                controller: _cvvSalvoCtrl,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: const InputDecoration(
                  labelText: 'CVV do cartão salvo',
                  counterText: '',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 6),
            ],
            if (!(permiteSalvar && _cartaoSalvoId != null)) ...[
              if (permiteSalvar && salvos.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => setState(() => _cartaoSalvoId = null),
                    child: const Text('Usar um cartão novo', style: TextStyle(fontSize: 12)),
                  ),
                ),
              TextField(
                controller: _numeroCtrl,
                keyboardType: TextInputType.number,
                maxLength: 19,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Número do cartão',
                  counterText: '',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nomeCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nome impresso no cartão',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _cpfCtrl,
                keyboardType: TextInputType.number,
                maxLength: 11,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'CPF do titular',
                  counterText: '',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _validadeCtrl,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Validade (MMAA)',
                        counterText: '',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _cvvCtrl,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      obscureText: true,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'CVV',
                        counterText: '',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (_metodo == 'credito') ...[
              const SizedBox(height: 10),
              Text('Parcelas', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ThemeColors.secondaryText(context))),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _opcoesParcelas.map((p) {
                  final sel = _parcelas == p;
                  return GestureDetector(
                    onTap: () => setState(() => _parcelas = p),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: sel
                            ? const Color(0xFFE50914).withValues(alpha: 0.12)
                            : ThemeColors.surface(context),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: sel ? const Color(0xFFE50914) : ThemeColors.outline(context),
                        ),
                      ),
                      child: Text(
                        '${p}x${p > 1 ? ' de R\$ ${(widget.total / p).toStringAsFixed(2)}' : ''}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                          color: sel ? const Color(0xFFE50914) : ThemeColors.primaryText(context),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              if (_cartaoSalvoId == null) ...[
                const SizedBox(height: 6),
                CheckboxListTile(
                  value: _salvarCartao,
                  onChanged: (v) => setState(() => _salvarCartao = v ?? false),
                  title: const Text('Salvar cartão para a próxima compra', style: TextStyle(fontSize: 12)),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ],
            ],
          ],
        );
      },
    );
  }

  Widget _cartaoSalvoTile(CartaoCredito c) {
    final sel = _cartaoSalvoId == c.id;
    return GestureDetector(
      onTap: () => setState(() => _cartaoSalvoId = c.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: ThemeColors.surface(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: sel ? const Color(0xFFE50914) : ThemeColors.outline(context),
            width: sel ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              sel ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              size: 18,
              color: sel ? const Color(0xFFE50914) : ThemeColors.hint(context),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.credit_card_rounded, size: 20, color: Color(0xFFE50914)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${c.bandeiraIcon} • ${c.numeroMascarado}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Acompanhamento (PIX / boleto / cartão em análise) ───────

  List<Widget> _buildAcompanhamento(Pagamento p) {
    if (p.recusado || p.expirado) {
      return [
        _buildAvisoResultado(p),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: _trocarFormaPagamento,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE50914),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Tentar novamente', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 44,
          child: TextButton(
            onPressed: () => context.go('/pedidos'),
            child: const Text('Ver meus pedidos', style: TextStyle(fontSize: 13)),
          ),
        ),
      ];
    }

    switch (p.metodo) {
      case 'pix':
        return _buildPix(p);
      case 'boleto':
        return _buildBoleto(p);
      default:
        return [
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 12),
          Text(
            'Processando pagamento no cartão...',
            textAlign: TextAlign.center,
            style: TextStyle(color: ThemeColors.secondaryText(context), fontSize: 13),
          ),
        ];
    }
  }

  Widget _buildAvisoResultado(Pagamento p) {
    final cor = const Color(0xFFF23D4F);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(p.recusado ? Icons.credit_card_off_rounded : Icons.timer_off_rounded, color: cor, size: 32),
          const SizedBox(height: 8),
          Text(
            p.recusado ? 'Pagamento recusado' : 'Cobrança expirada',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          if (p.motivoRecusa != null) ...[
            const SizedBox(height: 4),
            Text(p.motivoRecusa!, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: ThemeColors.secondaryText(context))),
          ],
        ],
      ),
    );
  }

  Widget _buildContagem() {
    if (_restante <= Duration.zero) {
      return Text(
        'Código expirado — gere um novo pagamento.',
        style: TextStyle(fontSize: 12, color: AppColors.error.withValues(alpha: 0.9)),
      );
    }
    final m = _restante.inMinutes.toString().padLeft(2, '0');
    final s = (_restante.inSeconds % 60).toString().padLeft(2, '0');
    return Text(
      'Expira em $m:$s',
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFF2A33C)),
    );
  }

  List<Widget> _buildPix(Pagamento p) {
    final expirado = _restante <= Duration.zero && p.expiraEm != null;
    return [
      Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: ThemeColors.surface(context),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.qr_code_2_rounded, size: 20, color: Color(0xFFE50914)),
                    const SizedBox(width: 6),
                    Text('PIX • R\$ ${p.valor.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  ],
                ),
                if (p.expiraEm != null && !expirado) _buildContagem(),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (p.pixQrImageUrl != null && !expirado)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Image.network(
                  p.pixQrImageUrl!,
                  width: 200,
                  height: 200,
                  errorBuilder: (_, __, ___) => SizedBox(
                    width: 200,
                    height: 120,
                    child: Center(
                      child: Text(
                        'Use o código copia e cola abaixo',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            if (p.pixCopiaCola != null && p.pixCopiaCola!.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: ThemeColors.surfaceVariant(context),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  p.pixCopiaCola!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: expirado ? null : () => _copiar(p.pixCopiaCola!, pix: true),
                  icon: Icon(_pixCopiado ? Icons.check_rounded : Icons.copy_rounded, size: 18),
                  label: Text(_pixCopiado ? 'Código copiado!' : 'Copiar código PIX'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _pixCopiado ? const Color(0xFF00A650) : const Color(0xFFE50914),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: ThemeColors.surface(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Aguardando o pagamento — a confirmação é automática. Pode deixar esta tela aberta.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      _botaoTrocarForma(),
    ];
  }

  List<Widget> _buildBoleto(Pagamento p) {
    final vencido = _restante <= Duration.zero && p.expiraEm != null;
    return [
      Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: ThemeColors.surface(context),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Boleto • R\$ ${p.valor.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                if (p.boletoVencimento != null)
                  Text('Vence em ${p.boletoVencimento!.split('-').reversed.join('/')}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFF2A33C))),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (p.boletoLinhaDigitavel != null) ...[
              Text('Linha digitável', style: TextStyle(fontSize: 11, color: ThemeColors.secondaryText(context), fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: ThemeColors.surfaceVariant(context),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SelectableText(
                  p.boletoLinhaDigitavel!,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: () => _copiar(p.boletoLinhaDigitavel!),
                  icon: Icon(_boletoCopiado ? Icons.check_rounded : Icons.copy_rounded, size: 18),
                  label: Text(_boletoCopiado ? 'Linha copiada!' : 'Copiar linha digitável'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFE50914),
                    side: const BorderSide(color: Color(0xFFE50914)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
            if (p.boletoPdfUrl != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: () => launchUrl(Uri.parse(p.boletoPdfUrl!), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                  label: const Text('Abrir boleto (PDF)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE50914),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: ThemeColors.surface(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Aguardando o pagamento do boleto. O pedido é liberado após a compensação (1 a 2 dias úteis).',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      if (!vencido) _botaoTrocarForma(),
    ];
  }

  Widget _botaoTrocarForma() {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: TextButton(
        onPressed: () => context.go('/pedidos'),
        child: const Text('Pagar depois — ver meus pedidos', style: TextStyle(fontSize: 13)),
      ),
    );
  }

  // ─── Sucesso ─────────────────────────────────────────────────

  Widget _buildSucesso(Pagamento p) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        const SizedBox(height: 24),
        const Icon(Icons.check_circle_rounded, size: 72, color: Color(0xFF00A650)),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Pagamento aprovado!',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          p.metodo == 'boleto'
              ? 'Boleto registrado! O pedido será liberado após a compensação.'
              : 'Seu pedido já está sendo processado pela loja.',
          textAlign: TextAlign.center,
          style: TextStyle(color: ThemeColors.secondaryText(context), fontSize: 13),
        ),
        const SizedBox(height: AppSpacing.lg),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: ThemeColors.surface(context),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              _linhaResumo('Forma', p.metodoRotulo),
              _linhaResumo('Valor', 'R\$ ${p.valor.toStringAsFixed(2)}'),
              if (p.pagoEm != null)
                _linhaResumo(
                  'Confirmado',
                  formatarDataHora(p.pagoEm!.toIso8601String()),
                ),
              if (p.cartaoLast4 != null)
                _linhaResumo(
                  'Cartão',
                  '${p.cartaoBandeira ?? ''} •••• ${p.cartaoLast4} • ${p.parcelas}x'
                      .replaceAll('  ', ' '),
                ),
              if (p.metodo == 'credito' && _salvarCartao)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Cartão salvo para a próxima compra.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF00A650)),
                  ),
                ),
              if (p.identificador != '—')
                _linhaResumo('Transação', p.identificador),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            onPressed: () => context.go('/pedidos'),
            icon: const Icon(Icons.receipt_long_rounded, size: 20),
            label: const Text('Ver meus pedidos', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE50914),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
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
      ],
    );
  }

  Widget _linhaResumo(String label, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: ThemeColors.secondaryText(context))),
          Text(valor, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
