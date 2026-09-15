import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/cartao_credito.dart';
import '../../../providers/cartao_provider.dart';

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

  void _showAdicionarDialog() {
    final apelidoCtrl = TextEditingController();
    final numeroCtrl = TextEditingController();
    final titularCtrl = TextEditingController();
    final mesCtrl = TextEditingController();
    final anoCtl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Adicionar Cartão'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: apelidoCtrl,
                decoration: const InputDecoration(
                    labelText: 'Apelido', hintText: 'Meu cartão'),
              ),
              TextField(
                controller: titularCtrl,
                decoration: const InputDecoration(
                    labelText: 'Titular', hintText: 'Nome no cartão'),
              ),
              TextField(
                controller: numeroCtrl,
                decoration: const InputDecoration(
                    labelText: 'Número',
                    hintText: '****.****.****.1234'),
                maxLength: 19,
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: mesCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Mês', hintText: '12'),
                      keyboardType: TextInputType.number,
                      maxLength: 2,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: TextField(
                      controller: anoCtl,
                      decoration:
                          const InputDecoration(labelText: 'Ano', hintText: '2028'),
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final provider = context.read<CartaoProvider>();
              final cartao = CartaoCredito(
                id: 0,
                userId: provider.userId ?? '',
                apelido: apelidoCtrl.text,
                numeroMascarado: numeroCtrl.text,
                bandeira: _detectBandeira(numeroCtrl.text),
                titular: titularCtrl.text,
                mesValidade: int.tryParse(mesCtrl.text) ?? 1,
                anoValidade: int.tryParse(anoCtl.text) ?? 2030,
              );
              final erro = await provider.adicionarCartao(cartao);
              if (ctx.mounted) Navigator.pop(ctx);
              if (erro != null && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(erro)),
                );
              }
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  String _detectBandeira(String numero) {
    final n = numero.replaceAll(RegExp(r'\D'), '');
    if (n.startsWith('4')) return 'Visa';
    if (n.startsWith('5')) return 'Master';
    if (RegExp(r'^3[47]').hasMatch(n)) return 'Amex';
    if (RegExp(r'^(636368|438935|504175|451416|636297)').hasMatch(n)) {
      return 'Elo';
    }
    return 'Outra';
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
      floatingActionButton: FloatingActionButton(
        onPressed: _showAdicionarDialog,
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add_rounded, color: AppColors.onPrimary),
      ),
      body: Consumer<CartaoProvider>(
        builder: (context, cartaoProv, _) {
          if (cartaoProv.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (cartaoProv.cartoes.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.credit_card_outlined,
                      color: AppColors.hint, size: 64),
                  const SizedBox(height: 16),
                  Text(
                    'Nenhum cartão salvo',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Adicione um cartão para agilizar suas compras',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppColors.secondaryText),
                  ),
                ],
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
              Text(
                cartao.apelido,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.bold),
              ),
              if (cartao.padrao)
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
            cartao.numeroMascarado,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(color: AppColors.onPrimary, letterSpacing: 2),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                cartao.titular,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.onPrimary.withValues(alpha: 0.8)),
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
