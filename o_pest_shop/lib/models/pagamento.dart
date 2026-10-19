/// Cobrança única do carrinho (PIX, crédito, débito ou boleto) criada no
/// gateway (PagBank). Cobre N pedidos — um por unidade do marketplace.
class Pagamento {
  final int id;
  final String userId;
  final String metodo;
  final double valor;
  final String status;
  final String? gatewayOrderId;
  final String? gatewayChargeId;

  final String? pixCopiaCola;
  final String? pixQrImageUrl;
  final String? pixE2eId;

  final String? boletoLinhaDigitavel;
  final String? boletoCodigoBarras;
  final String? boletoPdfUrl;
  final String? boletoVencimento;

  final String? cartaoBandeira;
  final String? cartaoLast4;
  final String? cartaoAutorizacao;
  final int parcelas;

  final String? motivoRecusa;
  final DateTime? expiraEm;
  final DateTime? pagoEm;
  final DateTime? createdAt;

  Pagamento({
    required this.id,
    required this.userId,
    required this.metodo,
    required this.valor,
    required this.status,
    this.gatewayOrderId,
    this.gatewayChargeId,
    this.pixCopiaCola,
    this.pixQrImageUrl,
    this.pixE2eId,
    this.boletoLinhaDigitavel,
    this.boletoCodigoBarras,
    this.boletoPdfUrl,
    this.boletoVencimento,
    this.cartaoBandeira,
    this.cartaoLast4,
    this.cartaoAutorizacao,
    this.parcelas = 1,
    this.motivoRecusa,
    this.expiraEm,
    this.pagoEm,
    this.createdAt,
  });

  String get metodoRotulo {
    switch (metodo) {
      case 'pix':
        return 'PIX';
      case 'credito':
        return 'Cartão de crédito';
      case 'debito':
        return 'Cartão de débito';
      case 'boleto':
        return 'Boleto';
      default:
        return metodo;
    }
  }

  String get statusRotulo {
    switch (status) {
      case 'pendente':
        return 'Aguardando pagamento';
      case 'em_analise':
        return 'Em análise';
      case 'pago':
        return 'Pago';
      case 'recusado':
        return 'Recusado';
      case 'expirado':
        return 'Expirado';
      case 'cancelado':
        return 'Cancelado';
      case 'estornado':
        return 'Estornado';
      default:
        return status;
    }
  }

  bool get pago => status == 'pago';
  bool get pendente => status == 'pendente' || status == 'em_analise';
  bool get recusado => status == 'recusado';
  bool get expirado => status == 'expirado' || status == 'cancelado';

  /// Identificador do comprovante exibido para cliente e admin.
  String get identificador {
    final id = gatewayChargeId ?? gatewayOrderId;
    if (id == null || id.isEmpty) return '#$id'.replaceFirst('#null', '—');
    return id;
  }

  factory Pagamento.fromJson(Map<String, dynamic> json) {
    double paraDouble(dynamic v) => (v as num?)?.toDouble() ?? 0;
    DateTime? paraData(dynamic v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
    return Pagamento(
      id: (json['id'] as num).toInt(),
      userId: json['user_id'] as String? ?? '',
      metodo: json['metodo'] as String? ?? 'pix',
      valor: paraDouble(json['valor']),
      status: json['status'] as String? ?? 'pendente',
      gatewayOrderId: json['gateway_order_id'] as String?,
      gatewayChargeId: json['gateway_charge_id'] as String?,
      pixCopiaCola: json['pix_copia_cola'] as String?,
      pixQrImageUrl: json['pix_qr_image_url'] as String?,
      pixE2eId: json['pix_e2e_id'] as String?,
      boletoLinhaDigitavel: json['boleto_linha_digitavel'] as String?,
      boletoCodigoBarras: json['boleto_codigo_barras'] as String?,
      boletoPdfUrl: json['boleto_pdf_url'] as String?,
      boletoVencimento: json['boleto_vencimento'] as String?,
      cartaoBandeira: json['cartao_bandeira'] as String?,
      cartaoLast4: json['cartao_last4'] as String?,
      cartaoAutorizacao: json['cartao_autorizacao'] as String?,
      parcelas: (json['parcelas'] as num?)?.toInt() ?? 1,
      motivoRecusa: json['motivo_recusa'] as String?,
      expiraEm: paraData(json['expira_em']),
      pagoEm: paraData(json['pago_em']),
      createdAt: paraData(json['created_at']),
    );
  }
}
