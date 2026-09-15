import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../core/constants/auth_notifier.dart';
import '../providers/auth_provider.dart';
import '../ui/screens/splash/splash_screen.dart';
import '../ui/screens/auth/login_screen.dart';
import '../ui/screens/auth/register_screen.dart';
import '../ui/screens/product/product_detail_screen.dart';
import '../ui/screens/search/search_results_screen.dart';
import '../ui/screens/cupons/cupons_screen.dart';
import '../ui/screens/cartoes/cartoes_screen.dart';
import '../ui/screens/profile/edit_personal_data_screen.dart';
import '../ui/screens/feed/feed_screen.dart';
import '../ui/screens/feed/post_detail_screen.dart';
import '../ui/screens/feed/aviso_detail_screen.dart';
import '../ui/screens/feed/novidade_detail_screen.dart';
import '../ui/screens/feed/evento_detail_screen.dart';
import '../ui/screens/feed/vaga_detail_screen.dart';
import '../ui/screens/feed/unidade_screen.dart';
import '../ui/screens/chat/chat_screen.dart';
import '../ui/screens/chat/central_atendimento_screen.dart';
import '../ui/screens/favorites/favorites_screen.dart';
import '../ui/screens/home/home_screen.dart';
import '../ui/screens/pedidos/pedidos_screen.dart';
import '../ui/screens/profile/assinaturas_screen.dart';
import '../ui/screens/profile/profile_screen.dart';
import '../ui/screens/cart/cart_screen.dart';
import '../ui/screens/pedidos/pedidos_screen.dart';
import '../ui/screens/admin/admin_screen.dart';
import '../ui/screens/entregador/area_entregador_screen.dart';
import '../ui/screens/pedidos/pedidos_loja_screen.dart';
import '../ui/navigation/main_shell.dart';

class AppRouter {
  AppRouter._();

  static final GoRouter router = GoRouter(
    refreshListenable: AuthRefreshNotifier.instance,
    initialLocation: '/splash',
    redirect: (context, state) {
      final auth = context.read<AuthProvider>();
      final isLoggedIn = auth.isAuthenticated;
      final location = state.uri.toString();

      if (location == '/splash') return null;

      if (isLoggedIn && (location == '/login' || location == '/register')) {
        return '/';
      }
      if (!isLoggedIn && location != '/login' && location != '/register') {
        return '/login';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const MainShell(),
      ),
      GoRoute(
        path: '/busca',
        builder: (context, state) {
          final query = state.uri.queryParameters['q'] ?? '';
          return SearchResultsScreen(initialQuery: query);
        },
      ),
      GoRoute(
        path: '/categoria/:id',
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '');
          return MainShell();
        },
      ),
      GoRoute(
        path: '/produto/:id',
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '');
          if (id == null) return const MainShell();
          return ProductDetailScreen(produtoId: id);
        },
      ),
      GoRoute(
        path: '/favoritos',
        builder: (context, state) => const FavoritesScreen(),
      ),
      GoRoute(
        path: '/perfil',
        builder: (context, state) => ProfileScreen(),
      ),
      GoRoute(
        path: '/carrinho',
        builder: (context, state) => const CartScreen(),
      ),
      GoRoute(
        path: '/cupons',
        builder: (context, state) => const CuponsScreen(),
      ),
      GoRoute(
        path: '/cartoes',
        builder: (context, state) => const CartoesScreen(),
      ),
      GoRoute(
        path: '/editar-dados',
        builder: (context, state) => const EditPersonalDataScreen(),
      ),
      GoRoute(
        path: '/post/:id',
        builder: (context, state) {
          final postId = state.pathParameters['id'] ?? '';
          return PostDetailScreen(postId: postId);
        },
      ),
      GoRoute(
        path: '/aviso/:id',
        builder: (context, state) {
          final postId = state.pathParameters['id'] ?? '';
          return AvisoDetailScreen(postId: postId);
        },
      ),
      GoRoute(
        path: '/novidade/:id',
        builder: (context, state) {
          final postId = state.pathParameters['id'] ?? '';
          return NovidadeDetailScreen(postId: postId);
        },
      ),
      GoRoute(
        path: '/evento/:id',
        builder: (context, state) {
          final postId = state.pathParameters['id'] ?? '';
          return EventoDetailScreen(postId: postId);
        },
      ),
      GoRoute(
        path: '/vaga/:id',
        builder: (context, state) {
          final vagaId = state.pathParameters['id'] ?? '';
          return VagaDetailScreen(postId: vagaId);
        },
      ),
      GoRoute(
        path: '/unidade/:id',
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          return UnidadeScreen(unidadeId: id);
        },
      ),
      GoRoute(
        path: '/pedidos',
        builder: (context, state) => const PedidosScreen(),
      ),
      GoRoute(
        path: '/assinaturas',
        builder: (context, state) => const AssinaturasScreen(),
      ),
      GoRoute(path: '/chat/:id/:nome', builder: (_, s) => ChatScreen(
        unidadeId: int.tryParse(s.pathParameters['id'] ?? '') ?? 0,
        unidadeNome: Uri.decodeComponent(s.pathParameters['nome'] ?? ''),
      )),
      GoRoute(path: '/central-atendimento', builder: (_, s) => const CentralAtendimentoScreen()),
      GoRoute(
        path: '/area-entregador',
        builder: (context, state) {
          final auth = context.read<AuthProvider>();
          final funcao = auth.user?.funcao;
          if (funcao != 'admin' && funcao != 'entregador') {
            return const MainShell();
          }
          return const AreaEntregadorScreen();
        },
      ),
      GoRoute(
        path: '/pedidos-loja',
        builder: (context, state) {
          final auth = context.read<AuthProvider>();
          final funcao = auth.user?.funcao;
          if (funcao != 'admin' && funcao != 'atendente') {
            return const MainShell();
          }
          return const PedidosLojaScreen();
        },
      ),
      GoRoute(
        path: '/admin',
        builder: (context, state) {
          final auth = context.read<AuthProvider>();
          if (auth.user?.funcao != 'admin') return const MainShell();
          return const AdminScreen();
        },
      ),
    ],
  );
}
