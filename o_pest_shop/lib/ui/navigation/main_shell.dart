import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/app_config_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cart_provider.dart';
import '../../providers/feed_provider.dart';
import '../../providers/home_provider.dart';
import '../screens/home/home_screen.dart';
import '../screens/cart/cart_screen.dart';
import '../screens/feed/feed_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/unidades/unidades_screen.dart';
import '../widgets/login_required.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _currentIndex = 0;
  final Set<int> _visited = {0};
  GoRouterDelegate? _routerDelegate;
  HomeProvider? _homeProvider;
  bool _listenerAdicionado = false;

  List<Widget> _screens(bool isLoggedIn) => [
        const HomeScreen(),
        const FeedScreen(),
        const UnidadesScreen(),
        if (isLoggedIn)
          const CartScreen()
        else
          const LoginRequired(
            title: 'Seu carrinho',
            message: 'Entre para adicionar produtos e finalizar a compra.',
            icon: Icons.shopping_cart_outlined,
          ),
        if (isLoggedIn)
          const ProfileScreen()
        else
          const LoginRequired(
            title: 'Sua conta',
            message: 'Entre para ver seus pedidos, favoritos e endereços.',
            icon: Icons.person_outline_rounded,
          ),
      ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<AppConfigProvider>().load();
      _homeProvider?.loadIfStale();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _homeProvider ??= context.read<HomeProvider>();
    if (!_listenerAdicionado) {
      _routerDelegate = GoRouter.of(context).routerDelegate;
      _routerDelegate!.addListener(_onRouteChanged);
      _listenerAdicionado = true;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_listenerAdicionado) {
      _routerDelegate?.removeListener(_onRouteChanged);
      _listenerAdicionado = false;
    }
    super.dispose();
  }

  void _onRouteChanged() {
    if (!mounted) return;
    final location = _routerDelegate?.currentConfiguration.uri.toString() ?? '';
    if (location == '/') {
      _homeProvider?.loadIfStale();
    }
  }

  void _onTap(int index) {
    if (index == _currentIndex) return;

    final isLoggedIn = context.read<AuthProvider>().isAuthenticated;
    if (!isLoggedIn && (index == 3 || index == 4)) {
      context.push('/login');
      return;
    }

    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
    setState(() {
      _currentIndex = index;
      _visited.add(index);
    });
    if (index == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<HomeProvider>().loadIfStale();
      });
    }
    if (index == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<FeedProvider>().loadIfStale();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = context.watch<AuthProvider>().isAuthenticated;
    final config = context.watch<AppConfigProvider>();
    final screens = _screens(isLoggedIn);
    final items = [
      _NavItem(Icons.store_rounded, Icons.store_rounded, 'Início'),
      _NavItem(Icons.rss_feed_rounded, Icons.rss_feed_rounded, 'Feed'),
      _NavItem(Icons.store_mall_directory_rounded, Icons.store_mall_directory_rounded, 'Lojas'),
      _NavItem(Icons.shopping_cart_outlined, Icons.shopping_cart_rounded, 'Carrinho'),
      _NavItem(Icons.person_outline_rounded, Icons.person_rounded, 'Perfil'),
    ];

    return Scaffold(
      extendBody: true,
      body: Column(
        children: [
          if (config.manutencao)
            Container(
              width: double.infinity,
              color: const Color(0xFF7A1018),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SafeArea(
                bottom: false,
                child: Text(
                  config.mensagemManutencao ??
                      'Estamos em manutenção. Algumas funções podem ficar indisponíveis.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              // Só constrói a aba quando ela é aberta pela primeira vez.
              children: List.generate(
                screens.length,
                (i) => _visited.contains(i) ? screens[i] : const SizedBox.shrink(),
              ),
            ),
          ),
        ],
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
