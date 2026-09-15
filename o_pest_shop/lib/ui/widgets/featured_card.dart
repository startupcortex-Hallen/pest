import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../core/helpers/scale_helper.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../models/produto.dart';

class FeaturedCard extends StatelessWidget {
  final Produto produto;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const FeaturedCard({super.key, required this.produto, this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: context.w(160).clamp(130.0, 200.0),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.rMd(context)),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.25),
              blurRadius: 4,
              spreadRadius: 1,
              offset: const Offset(4, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    width: double.infinity,
                    color: Colors.white,
                    child: Hero(
                      tag: 'produto_${produto.id}',
                      flightShuttleBuilder: (_, animation, direction, fromHeroContext, toHeroContext) {
                        // ENTRADA (push): voo limpo com Image puro (sem spinner/placeholder) —
                        // usa o mesmo cache da imagem do card para nunca piscar.
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
                            return Transform.scale(
                              scale: scale,
                              child: child,
                            );
                          },
                        );
                      },
                      child: produto.urlImagem.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: produto.urlImagem.first,
                              fit: BoxFit.contain,
                              placeholder: (_, __) => const Center(
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              errorWidget: (_, __, ___) => const Icon(
                                Icons.image_outlined,
                                color: AppColors.hint,
                              ),
                            )
                          : const Icon(Icons.image_outlined, color: AppColors.hint),
                    ),
                  ),
                  if (produto.estoque <= 0)
                    Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Esgotado',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFF23D4F),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.all(context.w(AppSpacing.sm)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: context.h(4).clamp(2.0, 6.0)),
                  Text(
                    produto.nome,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  SizedBox(height: context.h(4).clamp(2.0, 6.0)),
                  if (produto.temDesconto) ...[
                    Text(
                      'R\$ ${produto.preco.toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.secondaryText,
                            decoration: TextDecoration.lineThrough,
                            fontWeight: FontWeight.w400,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'R\$ ${produto.precoAtual.toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.error,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ] else
                    Text(
                      'R\$ ${produto.precoAtual.toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (produto.unidadeNome != null) ...[
                    SizedBox(height: context.h(2)),
                    Text(
                      produto.unidadeNome!,
                      style: TextStyle(
                        fontSize: context.sp(9),
                        color: const Color(0xFFE50914),
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
