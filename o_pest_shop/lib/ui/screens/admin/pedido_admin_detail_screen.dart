import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/helpers/pedido_status.dart';
import '../../../core/helpers/theme_colors.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../services/admin_service.dart';
import '../../../services/pagamento_service.dart';
import '../../widgets/comprovante_pagamento.dart';
import 'admin_utils.dart';

class PedidoAdminDetailScreen extends StatefulWidget {
  final int pedidoId;

  const PedidoAdminDetailScreen({super.key, required this.pedidoId});

  @override
  State<PedidoAdminDetailScreen> createState() =>
      _PedidoAdminDetailScreenState();
}

class _PedidoAdminDetailScreenState extends State<PedidoAdminDetailScreen> {
  final _service = AdminService();
  Map<String, dynamic>? _pedido;
  List<Map<String, dynamic>> _historico = [];
  List<Map<String, dynamic>> _auditoria = [];
  bool _loading = true;
  bool _processando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      final pedido = await _service.fetchPedidoDetalhe(widget.pedidoId);
      final historico = await _service.fetchPedidoHistorico(widget.pedidoId);
      List<Map<String, dynamic>> auditoria = [];
      try {
        auditoria = await _service.fetchPedidoAuditoria(widget.pedidoId);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _pedido = pedido;
        _historico = historico;
        _auditoria = auditoria;
      });
    } catch (e) {
      if (mounted) setState(() => _erro = mapErroAdmin(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  String get _status => _pedido?['status'] as String? ?? 'pendente';
  String get _tipoEntrega => _pedido?['tipo_entrega'] as String? ?? 'retirada';
  double get _total => (_pedido?['total'] as num?)?.toDouble() ?? 0;

  List<Map<String, dynamic>> get _itens =>
      ((_pedido?['pedido_itens'] as List?) ?? []).cast<Map<String, dynamic>>();

  String? _primeiraImagem(Map? produto) {
    final raw = produto?['url_imagem'];
    if (raw is List && raw.isNotEmpty) return raw.first.toString();
    if (raw is String && raw.isNotEmpty) return raw;
    return null;
  }

  Map<String, dynamic>? get _cliente {
    final raw = _pedido?['perfis'];
    return raw is Map ? raw.cast<String, dynamic>() : null;
  }

  Map<String, dynamic>? get _unidade {
    final raw = _pedido?['unidades'];
    return raw is Map ? raw.cast<String, dynamic>() : null;
  }

  Map<String, dynamic>? get _pagamento {
    final raw = _pedido?['pagamentos'];
    return raw is Map ? raw.cast<String, dynamic>() : null;
  }

  bool get _pagamentoAtivo {
    final status = _pagamento?['status'] as String? ?? '';
    return status == 'pago' || status == 'pendente' || status == 'em_analise';
  }

  bool get _podeCancelar {
    if (_pagamentoAtivo) return false;
    return const {
      'pendente',
      'pago',
      'em_preparo',
      'pronto_para_entrega',
    }.contains(_status);
  }

  Future<void> _confirmarPagamentoManual() async {
    final motivoCtrl = TextEditingController();
    final motivo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar pagamento manual'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Use apenas para pagamento recebido fora do gateway. '
              'O pedido será liberado e a ação ficará na auditoria.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: motivoCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Motivo / comprovante',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () {
              final texto = motivoCtrl.text.trim();
              if (texto.length < 5) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('Descreva o motivo (mínimo 5 caracteres).'),
                  ),
                );
                return;
              }
              Navigator.pop(ctx, texto);
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    motivoCtrl.dispose();
    if (motivo == null) return;

    await _executar(() async {
      await _service.confirmarPagamentoManual(widget.pedidoId, motivo);
    }, sucesso: 'Pagamento manual confirmado.');
  }

  Future<void> _estornarPagamento() async {
    final pagamento = _pagamento;
    final id = (pagamento?['id'] as num?)?.toInt();
    if (pagamento == null || id == null) return;

    final estorno = pagamento['status'] == 'pago';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(estorno ? 'Estornar pagamento' : 'Cancelar cobrança'),
        content: Text(
          '${estorno ? 'Estornar' : 'Cancelar'} '
          '${formatarMoeda(pagamento['valor'])} via '
          '${pagamento['metodo'] ?? 'gateway'}?\n\n'
          'O pedido será cancelado e o estoque/cupom devolvidos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Confirmar',
              style: TextStyle(
                color: Color(0xFFF23D4F),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await _executar(
      () => PagamentoService().cancelar(id),
      sucesso: estorno ? 'Estorno solicitado.' : 'Cobrança cancelada.',
    );
  }

  Future<void> _cancelarPedido() async {
    final motivoCtrl = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar pedido'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'O pedido será cancelado e o estoque/cupom devolvidos. '
              'Essa ação não pode ser desfeita.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: motivoCtrl,
              decoration: const InputDecoration(
                labelText: 'Motivo do cancelamento',
                hintText: 'Ex.: cliente pediu, endereço errado...',
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Cancelar pedido',
              style: TextStyle(color: Color(0xFFF23D4F)),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final motivo = motivoCtrl.text.trim();
    motivoCtrl.dispose();

    final etiquetaStatus = _pedido?['etiqueta_status'] as String?;
    if (etiquetaStatus != null &&
        !['cancelado', 'postado', 'em_transito', 'entregue'].contains(
          etiquetaStatus,
        )) {
      try {
        await _service.cancelarEtiqueta(widget.pedidoId);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Não foi possível cancelar a etiqueta. O pedido não foi '
                'cancelado para evitar custo de postagem: $e',
              ),
              backgroundColor: const Color(0xFFF23D4F),
            ),
          );
        }
        return;
      }
    }

    await _executar(
      () => _service.cancelarPedidoComMotivo(widget.pedidoId, motivo),
      sucesso: 'Pedido cancelado.',
    );
  }

  Future<void> _editarRastreio() async {
    final codigoCtrl = TextEditingController(
      text: _pedido?['codigo_rastreio'] as String? ?? '',
    );
    final urlCtrl = TextEditingController(
      text: _pedido?['url_rastreio'] as String? ?? '',
    );
    final salvar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rastreio da entrega'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: codigoCtrl,
              decoration: const InputDecoration(
                labelText: 'Código de rastreio',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlCtrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Link de rastreio (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    final codigo = codigoCtrl.text.trim();
    final url = urlCtrl.text.trim();
    codigoCtrl.dispose();
    urlCtrl.dispose();
    if (salvar != true) return;

    await _executar(
      () => _service.atualizarRastreio(
        widget.pedidoId,
        codigo.isEmpty ? null : codigo,
        url.isEmpty ? null : url,
      ),
      sucesso: 'Rastreio atualizado.',
    );
  }

  Map<String, dynamic>? get _envio {
    final bruto = _pedido?['envios'];
    if (bruto is Map) return bruto.cast<String, dynamic>();
    if (bruto is List && bruto.isNotEmpty && bruto.first is Map) {
      return (bruto.first as Map).cast<String, dynamic>();
    }
    return null;
  }

  String get _etiquetaStatus =>
      (_envio?['status'] as String?) ??
      (_pedido?['etiqueta_status'] as String?) ??
      '';

  List<Map<String, dynamic>> get _eventosEnvio {
    final bruto = _envio?['envio_eventos'];
    if (bruto is List) return bruto.cast<Map<String, dynamic>>();
    return [];
  }

  String _rotuloEnvio(String status) {
    switch (status) {
      case 'pendente':
      case 'prepostado':
        return 'Pré-postagem criada';
      case 'gerada':
        return 'Etiqueta gerada';
      case 'aguardando_postagem':
        return 'Aguardando postagem';
      case 'postado':
        return 'Postado';
      case 'em_transito':
        return 'Em trânsito';
      case 'entregue':
        return 'Entregue';
      case 'cancelado':
        return 'Cancelada';
      case 'problema':
        return 'Problema na entrega';
      default:
        return status.isEmpty ? 'Sem etiqueta' : status;
    }
  }

  bool get _podeGerarEtiqueta {
    if (_tipoEntrega != 'entrega') return false;
    final provider =
        (_pedido?['frete_provider'] ?? _unidade?['frete_modo'] ?? '')
            .toString()
            .toLowerCase();
    if (provider != 'correios') return false;
    if (!['pago', 'em_preparo', 'pronto_para_entrega'].contains(_status)) {
      return false;
    }
    return _etiquetaStatus.isEmpty || _etiquetaStatus == 'pendente';
  }

  Future<void> _gerarEtiqueta() async {
    await _executarEtiqueta(
      () => _service.gerarEtiqueta(widget.pedidoId),
      sucesso: 'Etiqueta gerada.',
      abrirPdf: true,
    );
  }

  Future<void> _imprimirEtiqueta() async {
    await _executarEtiqueta(
      () => _service.imprimirEtiqueta(widget.pedidoId),
      sucesso: 'Etiqueta pronta para impressão.',
      abrirPdf: true,
    );
  }

  Future<void> _sincronizarEnvio() async {
    await _executarEtiqueta(
      () => _service.sincronizarEnvio(widget.pedidoId),
      sucesso: 'Rastreio sincronizado.',
    );
  }

  Future<void> _simularEnvio() async {
    final status = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Simular evento dos Correios'),
        children: [
          for (final item in const [
            ('postado', 'Postado'),
            ('em_transito', 'Em trânsito'),
            ('entregue', 'Entregue'),
            ('problema', 'Problema na entrega'),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, item.$1),
              child: Text(item.$2),
            ),
        ],
      ),
    );
    if (status == null) return;
    await _executarEtiqueta(
      () => _service.simularEventoEnvio(widget.pedidoId, status),
      sucesso: 'Evento simulado.',
    );
  }

  Future<void> _cancelarEtiqueta() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar etiqueta'),
        content: const Text(
          'A pré-postagem será cancelada nos Correios. '
          'Use apenas se a etiqueta ainda não foi postada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Cancelar etiqueta',
              style: TextStyle(color: Color(0xFFF23D4F)),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _executarEtiqueta(
      () => _service.cancelarEtiqueta(widget.pedidoId),
      sucesso: 'Etiqueta cancelada.',
    );
  }

  Future<void> _executarEtiqueta(
    Future<Map<String, dynamic>> Function() acao, {
    required String sucesso,
    bool abrirPdf = false,
  }) async {
    if (_processando) return;
    setState(() => _processando = true);
    try {
      final resultado = await acao();
      final pdf = resultado['pdf_url'] as String?;
      final pendente = resultado['pendente'] == true;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              pendente
                  ? 'Etiqueta em processamento nos Correios. Tente imprimir em instantes.'
                  : sucesso,
            ),
          ),
        );
      }
      if (abrirPdf && pdf != null && pdf.isNotEmpty) {
        await _abrirUrl(pdf);
      }
      await _carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(mapErroAdmin(e))));
      }
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  Future<void> _editarNotaFiscal() async {
    final chaveCtrl = TextEditingController(
      text: _pedido?['nota_fiscal_chave'] as String? ?? '',
    );
    final numeroCtrl = TextEditingController(
      text: _pedido?['nota_fiscal_numero'] as String? ?? '',
    );
    final salvar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nota fiscal do pedido'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Obrigatória quando a loja é contribuinte do ICMS. '
              'A chave tem 44 dígitos.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: chaveCtrl,
              keyboardType: TextInputType.number,
              maxLength: 44,
              decoration: const InputDecoration(
                labelText: 'Chave da NF-e',
                border: OutlineInputBorder(),
              ),
            ),
            TextField(
              controller: numeroCtrl,
              keyboardType: TextInputType.number,
              maxLength: 12,
              decoration: const InputDecoration(
                labelText: 'Número da NF-e',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    final chave = chaveCtrl.text.trim();
    final numero = numeroCtrl.text.trim();
    chaveCtrl.dispose();
    numeroCtrl.dispose();
    if (salvar != true) return;

    await _executar(
      () => _service.atualizarNotaFiscalPedido(
        widget.pedidoId,
        chave.isEmpty ? null : chave,
        numero.isEmpty ? null : numero,
      ),
      sucesso: 'Nota fiscal atualizada.',
    );
  }

  Future<void> _resolverRevisao() async {
    final pagamento = _pagamento;
    final id = (pagamento?['id'] as num?)?.toInt();
    if (id == null) return;

    final resolucaoCtrl = TextEditingController();
    final resolucao = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resolver revisão manual'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              pagamento?['revisao_motivo'] as String? ??
                  'Descreva o que foi verificado.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: resolucaoCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Resolução',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () {
              final texto = resolucaoCtrl.text.trim();
              if (texto.length < 5) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Descreva a resolução (mínimo 5 caracteres).',
                    ),
                  ),
                );
                return;
              }
              Navigator.pop(ctx, texto);
            },
            child: const Text('Resolver'),
          ),
        ],
      ),
    );
    resolucaoCtrl.dispose();
    if (resolucao == null) return;

    await _executar(
      () => _service.resolverRevisaoPagamento(id, resolucao),
      sucesso: 'Revisão resolvida.',
    );
  }

  Future<void> _executar(
    Future<void> Function() acao, {
    required String sucesso,
  }) async {
    if (_processando) return;
    setState(() => _processando = true);
    try {
      await acao();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(sucesso)));
      }
      await _carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(mapErroAdmin(e))));
      }
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  Future<void> _abrirUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final cor = corStatusPedido(_status);
    return Scaffold(
      backgroundColor: ThemeColors.background(context),
      appBar: AppBar(
        backgroundColor: ThemeColors.surface(context),
        title: Text('Pedido #${widget.pedidoId}'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _loading ? null : _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _erro != null || _pedido == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  _erro ?? 'Pedido não encontrado.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.circle, size: 12, color: cor),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              rotuloStatusPedido(_status),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: cor,
                              ),
                            ),
                          ),
                          Text(
                            formatarMoeda(_total),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_tipoEntrega == 'entrega' ? 'Entrega' : 'Retirada'}'
                        ' • ${_unidade?['nome'] ?? 'Loja'}'
                        ' • ${formatarData(_pedido?['created_at'] as String?)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: ThemeColors.secondaryText(context),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (_status == 'pendente' && !_pagamentoAtivo)
                            OutlinedButton.icon(
                              onPressed: _processando
                                  ? null
                                  : _confirmarPagamentoManual,
                              icon: const Icon(
                                Icons.price_check_rounded,
                                size: 16,
                              ),
                              label: const Text('Pagamento manual'),
                            ),
                          if (_pagamentoAtivo)
                            OutlinedButton.icon(
                              onPressed: _processando
                                  ? null
                                  : _estornarPagamento,
                              icon: const Icon(Icons.undo_rounded, size: 16),
                              label: Text(
                                _pagamento?['status'] == 'pago'
                                    ? 'Estornar'
                                    : 'Cancelar cobrança',
                              ),
                            ),
                          OutlinedButton.icon(
                            onPressed: _processando ? null : _editarRastreio,
                            icon: const Icon(
                              Icons.local_shipping_rounded,
                              size: 16,
                            ),
                            label: const Text('Rastreio'),
                          ),
                          if (_podeCancelar)
                            OutlinedButton.icon(
                              onPressed: _processando ? null : _cancelarPedido,
                              icon: const Icon(Icons.cancel_rounded, size: 16),
                              label: const Text('Cancelar pedido'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _card(
                  titulo: 'Cliente',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _cliente?['nome'] as String? ??
                            _pedido?['comprador_nome'] as String? ??
                            'Cliente',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _cliente?['email'] as String? ??
                            _pedido?['comprador_email'] as String? ??
                            'Sem e-mail',
                        style: TextStyle(
                          fontSize: 12,
                          color: ThemeColors.secondaryText(context),
                        ),
                      ),
                      Text(
                        _cliente?['telefone'] as String? ??
                            _pedido?['comprador_telefone'] as String? ??
                            'Sem telefone',
                        style: TextStyle(
                          fontSize: 12,
                          color: ThemeColors.secondaryText(context),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _card(
                  titulo: 'Itens (${_itens.length})',
                  child: Column(
                    children: _itens.map((item) {
                      final produto = item['produtos'];
                      final nome = produto is Map
                          ? produto['nome'] as String? ?? 'Produto'
                          : 'Produto';
                      final imagem = _primeiraImagem(
                        produto is Map ? produto : null,
                      );
                      final quantidade =
                          (item['quantidade'] as num?)?.toInt() ?? 1;
                      final preco =
                          (item['preco_unitario'] as num?)?.toDouble() ?? 0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: SizedBox(
                                width: 40,
                                height: 40,
                                child: imagem != null
                                    ? CachedNetworkImage(
                                        imageUrl: imagem,
                                        fit: BoxFit.cover,
                                        errorWidget: (_, __, ___) =>
                                            _placeholderImagem(),
                                      )
                                    : _placeholderImagem(),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    nome,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (item['cor'] != null &&
                                      (item['cor'] as String).isNotEmpty)
                                    Text(
                                      'Cor: ${item['cor']}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: ThemeColors.secondaryText(
                                          context,
                                        ),
                                      ),
                                    ),
                                  Text(
                                    '$quantidade x ${formatarMoeda(preco)}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: ThemeColors.secondaryText(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              formatarMoeda(preco * quantidade),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _card(
                  titulo: 'Entrega',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _tipoEntrega == 'entrega'
                            ? 'Entrega'
                            : 'Retirada na unidade',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_pedido?['endereco_entrega'] != null &&
                          (_pedido?['endereco_entrega'] as String).isNotEmpty)
                        Text(
                          _pedido?['endereco_entrega'] as String,
                          style: TextStyle(
                            fontSize: 12,
                            color: ThemeColors.secondaryText(context),
                          ),
                        ),
                      if (_pedido?['distancia_km'] != null)
                        Text(
                          'Distância: ${(_pedido?['distancia_km'] as num).toStringAsFixed(1)} km'
                          ' • Frete: ${formatarMoeda(_pedido?['taxa_entrega'])}',
                          style: TextStyle(
                            fontSize: 12,
                            color: ThemeColors.secondaryText(context),
                          ),
                        ),
                      if ((_pedido?['codigo_rastreio'] as String?)
                                  ?.isNotEmpty ==
                              true ||
                          (_pedido?['url_rastreio'] as String?)?.isNotEmpty ==
                              true) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.local_shipping_rounded, size: 16),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _pedido?['codigo_rastreio'] as String? ??
                                    'Rastreio disponível',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if ((_pedido?['codigo_rastreio'] as String?)
                                    ?.isNotEmpty ==
                                true)
                              IconButton(
                                tooltip: 'Copiar código',
                                onPressed: () {
                                  Clipboard.setData(
                                    ClipboardData(
                                      text:
                                          _pedido?['codigo_rastreio'] as String,
                                    ),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Código de rastreio copiado.',
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.copy_rounded, size: 16),
                              ),
                            if ((_pedido?['url_rastreio'] as String?)
                                    ?.isNotEmpty ==
                                true)
                              IconButton(
                                tooltip: 'Abrir rastreio',
                                onPressed: () => _abrirUrl(
                                  _pedido?['url_rastreio'] as String,
                                ),
                                icon: const Icon(
                                  Icons.open_in_new_rounded,
                                  size: 16,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _card(
                  titulo: 'Envio / Etiqueta',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.local_shipping_rounded,
                            size: 18,
                            color: _etiquetaStatus.isEmpty
                                ? ThemeColors.hint(context)
                                : corStatusPedido(
                                    _etiquetaStatus == 'gerada'
                                        ? 'em_preparo'
                                        : _etiquetaStatus,
                                  ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _rotuloEnvio(_etiquetaStatus),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if ((_pedido?['frete_servico'] as String?)
                                  ?.isNotEmpty ==
                              true)
                            Text(
                              '${_pedido?['frete_servico']}'
                              '${(_pedido?['taxa_entrega'] as num?) != null ? ' • ${formatarMoeda(_pedido?['taxa_entrega'])}' : ''}',
                              style: TextStyle(
                                fontSize: 11,
                                color: ThemeColors.secondaryText(context),
                              ),
                            ),
                        ],
                      ),
                      if (_envio != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Serviço: ${_envio?['servico'] ?? _pedido?['frete_servico'] ?? 'Correios'}'
                          '${(_envio?['peso_kg'] as num?) != null ? ' • ${(_envio?['peso_kg'] as num).toStringAsFixed(2)} kg' : ''}'
                          '${(_envio?['comprimento_cm'] as num?) != null ? ' • ${(_envio?['comprimento_cm'] as num).toStringAsFixed(0)}x${(_envio?['largura_cm'] as num?)?.toStringAsFixed(0) ?? '?'}x${(_envio?['altura_cm'] as num?)?.toStringAsFixed(0) ?? '?'} cm' : ''}',
                          style: TextStyle(
                            fontSize: 11,
                            color: ThemeColors.secondaryText(context),
                          ),
                        ),
                        if ((_envio?['codigo_objeto'] as String?)?.isNotEmpty ==
                            true) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.qr_code_2_rounded, size: 16),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _envio?['codigo_objeto'] as String,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Copiar código',
                                onPressed: () {
                                  Clipboard.setData(
                                    ClipboardData(
                                      text: _envio?['codigo_objeto'] as String,
                                    ),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Código de rastreio copiado.',
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.copy_rounded, size: 16),
                              ),
                            ],
                          ),
                        ],
                        if ((_envio?['erro'] as String?)?.isNotEmpty == true)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              _envio?['erro'] as String,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.error,
                              ),
                            ),
                          ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (_podeGerarEtiqueta)
                            FilledButton.icon(
                              onPressed: _processando ? null : _gerarEtiqueta,
                              icon: const Icon(Icons.print_rounded, size: 16),
                              label: Text(
                                _etiquetaStatus == 'pendente'
                                    ? 'Tentar novamente'
                                    : 'Gerar etiqueta',
                              ),
                            ),
                          if (_envio != null &&
                              (_envio?['etiqueta_pdf_path'] != null ||
                                  _pedido?['etiqueta_pdf_path'] != null))
                            OutlinedButton.icon(
                              onPressed: _processando
                                  ? null
                                  : _imprimirEtiqueta,
                              icon: const Icon(
                                Icons.picture_as_pdf_rounded,
                                size: 16,
                              ),
                              label: const Text('Imprimir'),
                            ),
                          if (_envio != null)
                            OutlinedButton.icon(
                              onPressed: _processando
                                  ? null
                                  : _sincronizarEnvio,
                              icon: const Icon(Icons.sync_rounded, size: 16),
                              label: const Text('Sincronizar'),
                            ),
                          OutlinedButton.icon(
                            onPressed: _processando ? null : _editarNotaFiscal,
                            icon: const Icon(
                              Icons.receipt_long_rounded,
                              size: 16,
                            ),
                            label: const Text('NF-e'),
                          ),
                          if (_envio != null &&
                              ![
                                'cancelado',
                                'entregue',
                              ].contains(_etiquetaStatus))
                            OutlinedButton.icon(
                              onPressed: _processando
                                  ? null
                                  : _cancelarEtiqueta,
                              icon: const Icon(Icons.cancel_rounded, size: 16),
                              label: const Text('Cancelar etiqueta'),
                            ),
                          if (_envio != null)
                            OutlinedButton.icon(
                              onPressed: _processando ? null : _simularEnvio,
                              icon: const Icon(Icons.science_rounded, size: 16),
                              label: const Text('Simular evento'),
                            ),
                        ],
                      ),
                      if (_eventosEnvio.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const Divider(height: 16),
                        for (final evento in _eventosEnvio.take(4))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.circle,
                                  size: 6,
                                  color: Color(0xFF00A650),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '${evento['descricao'] ?? evento['codigo'] ?? 'Evento'}'
                                    '${evento['ocorrido_em'] != null ? ' • ${formatarDataHora(evento['ocorrido_em'] as String?)}' : ''}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: ThemeColors.secondaryText(context),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _card(
                  titulo: 'Pagamento',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_pagamento == null)
                        Text(
                          'Nenhuma cobrança vinculada.',
                          style: TextStyle(
                            fontSize: 12,
                            color: ThemeColors.secondaryText(context),
                          ),
                        )
                      else
                        ComprovantePagamento(
                          dados: _pagamento!,
                          compacto: true,
                        ),
                      if (_pagamento?['revisao_manual'] == true) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFF23D4F,
                            ).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(
                                0xFFF23D4F,
                              ).withValues(alpha: 0.4),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'REVISÃO MANUAL',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFFF23D4F),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _pagamento?['revisao_motivo'] as String? ??
                                    'Pagamento precisa de conferência.',
                                style: const TextStyle(fontSize: 12),
                              ),
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                onPressed: _processando
                                    ? null
                                    : _resolverRevisao,
                                icon: const Icon(
                                  Icons.check_circle_outline_rounded,
                                  size: 16,
                                ),
                                label: const Text('Resolver revisão'),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (_pagamento?['revisao_resolucao'] != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Resolvido em '
                          '${formatarDataHora(_pagamento?['revisao_resolvida_em'] as String?)}: '
                          '${_pagamento?['revisao_resolucao']}',
                          style: TextStyle(
                            fontSize: 11,
                            color: ThemeColors.secondaryText(context),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _card(
                  titulo: 'Histórico de status',
                  child: _historico.isEmpty
                      ? Text(
                          'Sem histórico registrado.',
                          style: TextStyle(
                            fontSize: 12,
                            color: ThemeColors.secondaryText(context),
                          ),
                        )
                      : Column(
                          children: _historico.map((h) {
                            final status = h['status'] as String? ?? '';
                            final ator = h['perfis'] is Map
                                ? (h['perfis'] as Map)['nome'] as String?
                                : null;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.circle,
                                    size: 10,
                                    color: corStatusPedido(status),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          rotuloStatusPedido(status),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        Text(
                                          '${formatarDataHora(h['criado_em'] as String?)}'
                                          '${ator != null && ator.isNotEmpty ? ' • $ator' : ''}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: ThemeColors.secondaryText(
                                              context,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                ),
                const SizedBox(height: AppSpacing.md),
                _card(
                  titulo: 'Auditoria',
                  child: _auditoria.isEmpty
                      ? Text(
                          'Sem ações administrativas registradas.',
                          style: TextStyle(
                            fontSize: 12,
                            color: ThemeColors.secondaryText(context),
                          ),
                        )
                      : Column(
                          children: _auditoria.map((a) {
                            final ator = a['perfis'] is Map
                                ? (a['perfis'] as Map)['nome'] as String?
                                : null;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.history_rounded, size: 14),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _resumoAuditoria(a),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          '${formatarDataHora(a['criado_em'] as String?)}'
                                          '${ator != null && ator.isNotEmpty ? ' • $ator' : ''}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: ThemeColors.secondaryText(
                                              context,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _card({String? titulo, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: ThemeColors.surface(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (titulo != null) ...[
            Text(
              titulo,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: ThemeColors.secondaryText(context),
              ),
            ),
            const SizedBox(height: 10),
          ],
          child,
        ],
      ),
    );
  }

  Widget _placeholderImagem() {
    return Container(
      color: ThemeColors.surfaceVariant(context),
      child: Icon(
        Icons.image_outlined,
        size: 18,
        color: ThemeColors.hint(context),
      ),
    );
  }

  String _resumoAuditoria(Map<String, dynamic> a) {
    final acao = a['acao'] as String? ?? 'ação';
    final detalhe = a['detalhe'];
    if (acao == 'status' && detalhe is Map) {
      return 'Status: ${rotuloStatusCurto(detalhe['de'] as String? ?? '')}'
          ' → ${rotuloStatusCurto(detalhe['para'] as String? ?? '')}';
    }
    if (acao == 'pagamento_manual' && detalhe is Map) {
      return 'Pagamento manual: ${detalhe['motivo'] ?? ''}';
    }
    if (acao == 'revisao_pagamento' && detalhe is Map) {
      return 'Revisão resolvida: ${detalhe['resolucao'] ?? ''}';
    }
    if (acao == 'rastreio' && detalhe is Map) {
      return 'Rastreio: ${detalhe['codigo'] ?? 'removido'}';
    }
    if (acao == 'cancelamento') return 'Pedido cancelado';
    return capitalizar(acao.replaceAll('_', ' '));
  }
}
