import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/cartao_credito.dart';
import '../../../providers/cartao_provider.dart';

/// Cartões salvos com segurança no gateway (PagBank).
///
/// O cartão é salvo automaticamente ao pagar com crédito marcando
/// "Salvar cartão" — nunca guardamos número/CVV no nosso banco.
class CartoesScreen extends StatefulWidget {
  const CartoesScreen({super.key});

  @override
  State<CartoesScreen> createState() => _CartoesScreenState();
}

class _CartoesScreenState extends State<CartoesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CartaoProvider>().loadCartoes();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text('Cartões',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: Consumer<CartaoProvider>(
        builder: (context, cartaoProv, _) {
          if (cartaoProv.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (cartaoProv.cartoes.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.credit_card_outlined,
                        color: AppColors.hint, size: 64),
                    const SizedBox(height: 16),
                    Text(
                      'Nenhum cartão salvo',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Ao pagar com cartão de crédito, marque "Salvar cartão" — '
                      'os dados são guardados com segurança no gateway, nunca no nosso banco.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.secondaryText),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: cartaoProv.cartoes.length,
            itemBuilder: (context, index) {
              final cartao = cartaoProv.cartoes[index];
              return _buildCartaoCard(context, cartaoProv, cartao);
            },
          );
        },
      ),
    );
  }

  Widget _buildCartaoCard(
      BuildContext context, CartaoProvider prov, CartaoCredito cartao) {
    final utilizavel = cartao.gatewayCardId != null;
    final digitos = cartao.numeroMascarado.replaceAll(RegExp(r'[^0-9]'), '');
    final final4 = digitos.length >= 4
        ? digitos.substring(digitos.length - 4)
        : digitos.padLeft(4, '0');
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary,
            AppColors.primary.withValues(alpha: 0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  cartao.apelido,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!utilizavel)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.onPrimary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text('Reativar no pagamento',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: AppColors.onPrimary)),
                )
              else if (cartao.padrao)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.onPrimary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text('Padrão',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: AppColors.onPrimary)),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            utilizavel ? cartao.numeroMascarado : '•••• •••• •••• $final4',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(color: AppColors.onPrimary, letterSpacing: 2),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  cartao.titular,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.onPrimary.withValues(alpha: 0.8)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Row(
                children: [
                  Text(
                    '${cartao.mesValidade.toString().padLeft(2, '0')}/${cartao.anoValidade}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.onPrimary.withValues(alpha: 0.8)),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  GestureDetector(
                    onTap: () => prov.removerCartao(cartao.id),
                    child: Icon(Icons.delete_outline_rounded,
                        color: AppColors.onPrimary.withValues(alpha: 0.7), size: 20),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
