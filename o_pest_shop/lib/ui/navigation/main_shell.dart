import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/cart_provider.dart';
import '../../providers/feed_provider.dart';
import '../../providers/home_provider.dart';
import '../screens/home/home_screen.dart';
import '../screens/cart/cart_screen.dart';
import '../screens/feed/feed_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/unidades/unidades_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  final _screens = const [
    HomeScreen(),
    FeedScreen(),
    UnidadesScreen(),
    CartScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      GoRouter.of(context).routerDelegate.addListener(_onRouteChanged);
    });
  }

  @override
  void dispose() {
    try {
      GoRouter.of(context).routerDelegate.removeListener(_onRouteChanged);
    } catch (e) {
      debugPrint('Erro router: $e');
    }
    super.dispose();
  }

  void _onRouteChanged() {
    final location = GoRouterState.of(context).uri.toString();
    if (location == '/') {
      context.read<HomeProvider>().refresh();
    }
  }

  void _onTap(int index) {
    if (index == _currentIndex) return;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
    setState(() => _currentIndex = index);
    if (index == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<HomeProvider>().refresh();
      });
    }
    if (index == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<FeedProvider>().loadFeed();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = [
      _NavItem(Icons.store_rounded, Icons.store_rounded, 'Início'),
      _NavItem(Icons.rss_feed_rounded, Icons.rss_feed_rounded, 'Feed'),
      _NavItem(Icons.store_mall_directory_rounded, Icons.store_mall_directory_rounded, 'Lojas'),
      _NavItem(Icons.shopping_cart_outlined, Icons.shopping_cart_rounded, 'Carrinho'),
      _NavItem(Icons.person_outline_rounded, Icons.person_rounded, 'Perfil'),
    ];

    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: const Color(0xFF121212),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFFE50914).withValues(alpha: 0.35),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: List.generate(items.length, (i) {
              final item = items[i];
              final isSelected = i == _currentIndex;
              return Expanded(
                child: GestureDetector(
                  onTap: () => _onTap(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    margin: EdgeInsets.all(isSelected ? 6 : 0),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFE50914)
                          : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Icon(
                              item.activeIcon,
                              size: isSelected ? 24 : 22,
                              color: isSelected
                                  ? Colors.white
                                  : Colors.white60,
                            ),
                            if (i == 3)
                              Consumer<CartProvider>(
                                builder: (context, cart, _) {
                                  if (cart.totalItens <= 0) {
                                    return const SizedBox.shrink();
                                  }
                                  return Positioned(
                                    top: -8,
                                    right: -12,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      constraints: const BoxConstraints(minWidth: 16),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF23D4F),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: Colors.white, width: 1.5),
                                      ),
                                      child: Text(
                                        '${cart.totalItens}',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 9,
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.label,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.w400,
                            color: isSelected
                                ? Colors.white
                                : Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavItem(this.icon, this.activeIcon, this.label);
}
