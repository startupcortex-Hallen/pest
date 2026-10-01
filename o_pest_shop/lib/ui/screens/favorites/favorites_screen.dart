import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/produto.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/favorito_service.dart';
import '../../widgets/animated_card_entry.dart';
import '../../widgets/app_states.dart';
import '../../widgets/product_card.dart';
import '../product/product_detail_screen.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final _service = FavoritoService();
  late Future<List<Produto>> _future;

  @override
  void initState() {
    super.initState();
    _future = _carregar();
  }

  Future<List<Produto>> _carregar() {
    final userId = context.read<AuthProvider>().user?.id;
    if (userId == null) return Future.value(const []);
    return _service.fetchProdutosFavoritos(userId);
  }

  Future<void> _recarregar() async {
    setState(() => _future = _carregar());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text('Favoritos',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: FutureBuilder<List<Produto>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppSkeletonList(itemCount: 6, itemHeight: 96);
          }

          if (snapshot.hasError) {
            return AppErrorState(
              message: 'Não foi possível carregar seus favoritos.',
              onRetry: _recarregar,
            );
          }

          final favoritos = snapshot.data ?? [];
          if (favoritos.isEmpty) {
            return const AppEmptyState(
              icon: Icons.favorite_border_rounded,
              title: 'Nenhum favorito ainda',
              message: 'Toque no coração dos produtos\npara favoritá-los',
            );
          }

          return RefreshIndicator(
            onRefresh: _recarregar,
            child: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.sm),
              itemCount: favoritos.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                final produto = favoritos[index];
                return AnimatedCardEntry(
                  index: index,
                  child: ProductCard(
                    produto: produto,
                    onTap: () => ProductDetailScreen.push(
                      context,
                      produto.id,
                      imageUrl: produto.urlImagem.isNotEmpty
                          ? produto.urlImagem.first
                          : null,
                    ).then((_) {
                      if (mounted) _recarregar();
                    }),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
