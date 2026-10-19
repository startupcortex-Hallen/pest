import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/helpers/theme_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../models/pagamento.dart';

/// Comprovante de pagamento (PagBank) — usado no detalhe do pedido (cliente)
/// e na aba Pedidos do painel admin. Mostra método, status, IDs da transação,
/// dados do PIX/boleto/cartão e permite copiar o comprovante em texto.
class ComprovantePagamento extends StatelessWidget {
  final Map<String, dynamic> dados;
  final bool compacto;

  const ComprovantePagamento({
    super.key,
    required this.dados,
    this.compacto = false,
  });

  Color _corStatus(String status) {
    switch (status) {
      case 'pago':
        return const Color(0xFF00A650);
      case 'em_analise':
        return const Color(0xFFF2A33C);
      case 'recusado':
      case 'expirado':
      case 'cancelado':
      case 'estornado':
        return const Color(0xFFF23D4F);
      default:
        return const Color(0xFF0084FF);
    }
  }

  IconData _iconeMetodo(String metodo) {
    switch (metodo) {
      case 'pix':
        return Icons.qr_code_2_rounded;
      case 'credito':
        return Icons.credit_card_rounded;
      case 'debito':
        return Icons.credit_card_outlined;
      case 'boleto':
        return Icons.receipt_rounded;
      default:
        return Icons.payments_rounded;
    }
  }

  String _formatarDataHora(DateTime? data) {
    if (data == null) return '—';
    String d(int v) => v.toString().padLeft(2, '0');
    return '${d(data.day)}/${d(data.month)}/${data.year} às ${d(data.hour)}:${d(data.minute)}';
  }

  String _textoComprovante(Pagamento p) {
    final linhas = <String>[
      '===== COMPROVANTE DE PAGAMENTO =====',
      'O Pest Shop • PagBank',
      'Cobrança: ${p.identificador}',
      'Forma: ${p.metodoRotulo}',
      'Valor: R\$ ${p.valor.toStringAsFixed(2)}',
      'Status: ${p.statusRotulo}',
      if (p.pagoEm != null) 'Pago em: ${_formatarDataHora(p.pagoEm)}',
      if (p.metodo == 'pix' && p.pixE2eId != null) 'E2E PIX: ${p.pixE2eId}',
      if (p.metodo == 'boleto' && p.boletoLinhaDigitavel != null)
        'Linha digitável: ${p.boletoLinhaDigitavel}',
      if (p.metodo == 'boleto' && p.boletoVencimento != null)
        'Vencimento: ${p.boletoVencimento}',
      if (p.cartaoLast4 != null)
        'Cartão: ${p.cartaoBandeira ?? ''} •••• ${p.cartaoLast4} (${p.parcelas}x)',
      if (p.cartaoAutorizacao != null) 'Autorização: ${p.cartaoAutorizacao}',
      if (p.motivoRecusa != null) 'Motivo: ${p.motivoRecusa}',
      '====================================',
    ];
    return linhas.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final p = Pagamento.fromJson(dados);
    final cor = _corStatus(p.status);
    return Container(
      padding: EdgeInsets.all(compacto ? AppSpacing.sm : AppSpacing.md),
      decoration: BoxDecoration(
        color: ThemeColors.surface(context),
        borderRadius: BorderRadius.circular(compacto ? 10 : 16),
        border: Border.all(color: cor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_iconeMetodo(p.metodo), size: compacto ? 16 : 20, color: cor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  p.metodoRotulo,
                  style: TextStyle(
                    fontSize: compacto ? 12 : 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  p.statusRotulo,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: cor,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: compacto ? 6 : 10),
          _linha(context, 'Valor', 'R\$ ${p.valor.toStringAsFixed(2)}', bold: true),
          if (p.pagoEm != null) _linha(context, 'Pago em', _formatarDataHora(p.pagoEm)),
          if (p.metodo == 'pix') ...[
            if (p.pixE2eId != null) _linha(context, 'E2E PIX', p.pixE2eId!),
            if (p.pixCopiaCola != null)
              _linha(
                context,
                'PIX copia e cola',
                p.pixCopiaCola!.length > 24
                    ? '${p.pixCopiaCola!.substring(0, 24)}...'
                    : p.pixCopiaCola!,
              ),
          ],
          if (p.metodo == 'boleto') ...[
            if (p.boletoLinhaDigitavel != null)
              _linha(context, 'Linha digitável', p.boletoLinhaDigitavel!),
            if (p.boletoVencimento != null)
              _linha(context, 'Vencimento', p.boletoVencimento!),
          ],
          if (p.metodo == 'credito' || p.metodo == 'debito') ...[
            if (p.cartaoLast4 != null)
              _linha(
                context,
                'Cartão',
                '${p.cartaoBandeira ?? 'Cartão'} •••• ${p.cartaoLast4}'
                    '${p.metodo == 'credito' ? ' • ${p.parcelas}x' : ' • à vista'}',
              ),
            if (p.cartaoAutorizacao != null)
              _linha(context, 'Autorização', p.cartaoAutorizacao!),
          ],
          if (p.gatewayChargeId != null) _linha(context, 'Transação', p.gatewayChargeId!),
          if (p.motivoRecusa != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Motivo: ${p.motivoRecusa}',
                style: const TextStyle(fontSize: 11, color: Color(0xFFF23D4F)),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (p.boletoPdfUrl != null)
                Expanded(
                  child: SizedBox(
                    height: 34,
                    child: OutlinedButton.icon(
                      onPressed: () => launchUrl(
                        Uri.parse(p.boletoPdfUrl!),
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Icons.picture_as_pdf_rounded, size: 14),
                      label: const Text('Abrir boleto', style: TextStyle(fontSize: 11)),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        foregroundColor: cor,
                        side: BorderSide(color: cor),
                      ),
                    ),
                  ),
                ),
              if (p.boletoPdfUrl != null) const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: _textoComprovante(p)));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Comprovante copiado!'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy_rounded, size: 14),
                    label: const Text('Copiar comprovante', style: TextStyle(fontSize: 11)),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      foregroundColor: ThemeColors.primaryText(context),
                      side: BorderSide(color: ThemeColors.outline(context)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _linha(BuildContext context, String label, String valor, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 86,
            child: Text(
              label,
              style: TextStyle(fontSize: 11, color: ThemeColors.secondaryText(context)),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: TextStyle(
                fontSize: 11,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
              ),
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
