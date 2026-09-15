import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../providers/favorito_provider.dart';
import '../../../providers/home_provider.dart';
import '../../widgets/product_card.dart';
import '../../widgets/animated_card_entry.dart';
import '../product/product_detail_screen.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FavoritoProvider>().loadFavoritos();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text('Favoritos',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                )),
        elevation: 0,
      ),
      body: Consumer2<FavoritoProvider, HomeProvider>(
        builder: (context, fav, home, _) {
          final ids = fav.favoritosIds;

          if (fav.loading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (ids.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.favorite_border_rounded,
                      color: AppColors.hint, size: 64),
                  const SizedBox(height: 16),
                  Text(
                    'Nenhum favorito ainda',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Toque no coração dos produtos\npara favoritá-los',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppColors.secondaryText),
                  ),
                ],
              ),
            );
          }

          final favoritos = home.produtos
              .where((p) => ids.contains(p.id))
              .toList();

          if (favoritos.isEmpty && home.loading == false) {
            return const Center(
              child: Text('Carregando produtos...'),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.sm),
            itemCount: favoritos.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final produto = favoritos[index];
              return AnimatedCardEntry(
                index: index,
                child: ProductCard(
                  produto: produto,
                  onTap: () => ProductDetailScreen.push(
                    context,
                    produto.id,
                    imageUrl: produto.urlImagem.isNotEmpty ? produto.urlImagem.first : null,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
