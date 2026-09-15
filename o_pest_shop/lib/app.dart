import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/cart_provider.dart';
import 'providers/cartao_provider.dart';
import 'providers/cupom_provider.dart';
import 'providers/favorito_provider.dart';
import 'providers/feed_provider.dart';
import 'providers/home_provider.dart';
import 'providers/theme_provider.dart';
import 'router/app_router.dart';
import 'services/auth_service.dart';
import 'services/cart_service.dart';
import 'services/cartao_service.dart';
import 'services/cupom_service.dart';
import 'services/favorito_service.dart';
import 'services/feed_service.dart';
import 'services/produto_service.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ThemeProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => AuthProvider(AuthService()),
        ),
        ChangeNotifierProvider(
          create: (_) => HomeProvider(ProdutoService()),
        ),
        ChangeNotifierProvider(
          create: (_) => FavoritoProvider(FavoritoService(), AuthService()),
        ),
        ChangeNotifierProvider(
          create: (_) => CartProvider(CartService(), AuthService()),
        ),
        ChangeNotifierProvider(
          create: (_) => CupomProvider(CupomService()),
        ),
        ChangeNotifierProvider(
          create: (_) => CartaoProvider(CartaoService(), AuthService()),
        ),
        ChangeNotifierProvider(
          create: (_) => FeedProvider(FeedService(), AuthService()),
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, theme, _) {
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: const SystemUiOverlayStyle(
              statusBarColor: Color(0xFF0A0A0A),
              statusBarIconBrightness: Brightness.light,
              systemNavigationBarColor: Colors.black,
              systemNavigationBarIconBrightness: Brightness.light,
            ),
            child: MaterialApp.router(
              title: 'O Pest - Shop',
              theme: AppTheme.darkTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: ThemeMode.dark,
              routerConfig: AppRouter.router,
              debugShowCheckedModeBanner: false,
            ),
          );
        },
      ),
    );
  }
}
