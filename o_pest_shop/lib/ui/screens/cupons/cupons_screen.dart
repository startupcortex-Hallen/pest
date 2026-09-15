import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../providers/cupom_provider.dart';

class CuponsScreen extends StatefulWidget {
  const CuponsScreen({super.key});

  @override
  State<CuponsScreen> createState() => _CuponsScreenState();
}

class _CuponsScreenState extends State<CuponsScreen> {
  final _codigoController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CupomProvider>().loadCupons();
    });
  }

  @override
  void dispose() {
    _codigoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text('Cupons',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: Consumer<CupomProvider>(
        builder: (context, cupom, _) {
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              _buildAplicarCupom(context, cupom),
              const SizedBox(height: AppSpacing.lg),
              if (cupom.cupomAplicado != null) ...[
                _buildCupomAtivo(context, cupom),
                const SizedBox(height: AppSpacing.lg),
              ],
              Text(
                'Cupons disponíveis',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppSpacing.md),
              if (cupom.loading)
                const Center(child: CircularProgressIndicator())
              else if (cupom.cuponsDisponiveis.isEmpty)
                _buildEmptyState()
              else
                ...cupom.cuponsDisponiveis.map(
                  (c) => _buildCupomCard(context, c.codigo, c.descricao),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAplicarCupom(BuildContext context, CupomProvider cupom) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tem um cupom?',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _codigoController,
                  decoration: InputDecoration(
                    hintText: 'Digite o código',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                  ),
                  textCapitalization: TextCapitalization.characters,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              ElevatedButton(
                onPressed: () async {
                  final erro = await cupom
                      .aplicarCupom(_codigoController.text.trim());
                  if (erro != null && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(erro)),
                    );
                  }
                },
                child: const Text('Aplicar'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCupomAtivo(BuildContext context, CupomProvider cupom) {
    final c = cupom.cupomAplicado!;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded,
              color: AppColors.success, size: 28),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.codigo,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                Text(c.descricao,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.secondaryText)),
              ],
            ),
          ),
          TextButton(
            onPressed: cupom.removerCupom,
            child: const Text('Remover'),
          ),
        ],
      ),
    );
  }

  Widget _buildCupomCard(BuildContext context, String codigo, String descricao) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(codigo,
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(descricao,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.hint),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          children: [
            const Icon(Icons.local_offer_outlined,
                color: AppColors.hint, size: 48),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Nenhum cupom disponível no momento',
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
}
