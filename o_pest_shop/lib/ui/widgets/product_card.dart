import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../models/produto.dart';

class ProductCard extends StatelessWidget {
  final Produto produto;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const ProductCard({super.key, required this.produto, this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final emEstoque = produto.estoque > 0;
    final estoqueBaixo = produto.estoque > 0 && produto.estoque <= 3;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.15),
              blurRadius: 4,
              spreadRadius: 1,
              offset: const Offset(4, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: SizedBox(
                width: 100,
                height: 100,
                child: Stack(
                  children: [
                    Hero(
                      tag: 'produto_${produto.id}',
                      flightShuttleBuilder: (_, animation, direction, fromHeroContext, toHeroContext) {
                        // ENTRADA (push): voo limpo com Image puro (sem spinner/placeholder).
                        if (direction == HeroFlightDirection.push) {
                          return AnimatedBuilder(
                            animation: animation,
                            builder: (context, _) {
                              final t = animation.value;
                              final scale = 1.0 + (t - t * t) * 0.6;
                              return Transform.scale(
                                scale: scale,
                                child: Image(
                                  image: CachedNetworkImageProvider(produto.urlImagem.isNotEmpty
                                      ? produto.urlImagem.first
                                      : ''),
                                  fit: BoxFit.contain,
                                  gaplessPlayback: true,
                                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                                ),
                              );
                            },
                          );
                        }
                        // SAÍDA (pop): mantém o comportamento atual intacto.
                        final child = (direction == HeroFlightDirection.push ? fromHeroContext : toHeroContext).widget;
                        return AnimatedBuilder(
                          animation: animation,
                          builder: (context, _) {
                            final t = animation.value;
                            final scale = 1.0 + (t - t * t) * 0.6;
                            return Transform.scale(scale: scale, child: child);
                          },
                        );
                      },
                      child: produto.urlImagem.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: produto.urlImagem.first,
                              fit: BoxFit.contain,
                              placeholder: (_, __) => Container(
                                color: Colors.white,
                                child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                              ),
                              errorWidget: (_, __, ___) => Container(
                                color: Colors.white,
                                child: const Icon(Icons.image_outlined, color: AppColors.hint),
                              ),
                            )
                          : Container(
                              color: Colors.white,
                              child: const Icon(Icons.image_outlined, color: AppColors.hint),
                            ),
                    ),
                    if (!emEstoque)
                      Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Esgotado',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFF23D4F),
                              letterSpacing: 0.3,
                            ),
                          ),
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
                    produto.nome,
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      if (produto.temDesconto) ...[
                        Text(
                          'R\$ ${produto.preco.toStringAsFixed(2)}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppColors.hint,
                                decoration: TextDecoration.lineThrough,
                              ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                          ),
                          child: Text(
                            '${((1 - produto.precoAtual / produto.preco) * 100).round()}% OFF',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: AppColors.success,
                                ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'R\$ ${produto.precoAtual.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  if (produto.unidadeNome != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      produto.unidadeNome!,
                      style: TextStyle(
                        fontSize: 10,
                        color: const Color(0xFFE50914),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 8, height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: !emEstoque
                              ? const Color(0xFFF23D4F)
                              : estoqueBaixo
                                  ? const Color(0xFFFFAD01)
                                  : const Color(0xFF00A650),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        !emEstoque
                            ? 'Sem estoque'
                            : estoqueBaixo
                                ? 'Estoque baixo'
                                : 'Em estoque',
                        style: TextStyle(
                          fontSize: 10,
                          color: !emEstoque
                              ? const Color(0xFFF23D4F)
                              : estoqueBaixo
                                  ? const Color(0xFFFFAD01)
                                  : const Color(0xFF00A650),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  if (produto.freteGratis) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.local_shipping_outlined,
                            size: 14, color: AppColors.success),
                        const SizedBox(width: 4),
                        Text(
                          'Frete grátis',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: AppColors.success,
                              ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
