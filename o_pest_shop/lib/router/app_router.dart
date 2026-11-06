import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../core/constants/auth_notifier.dart';
import '../providers/auth_provider.dart';
import '../ui/screens/splash/splash_screen.dart';
import '../ui/screens/auth/login_screen.dart';
import '../ui/screens/auth/register_screen.dart';
import '../ui/screens/auth/redefinir_senha_screen.dart';
import '../ui/screens/product/product_detail_screen.dart';
import '../ui/screens/search/search_results_screen.dart';
import '../ui/screens/cupons/cupons_screen.dart';
import '../ui/screens/cartoes/cartoes_screen.dart';
import '../ui/screens/profile/edit_personal_data_screen.dart';
import '../ui/screens/profile/enderecos_screen.dart';
import '../ui/screens/feed/feed_screen.dart';
import '../ui/screens/feed/post_detail_screen.dart';
import '../ui/screens/feed/aviso_detail_screen.dart';
import '../ui/screens/feed/novidade_detail_screen.dart';
import '../ui/screens/feed/evento_detail_screen.dart';
import '../ui/screens/feed/unidade_screen.dart';
import '../ui/screens/chat/chat_screen.dart';
import '../ui/screens/chat/central_atendimento_screen.dart';
import '../ui/screens/favorites/favorites_screen.dart';
import '../ui/screens/home/home_screen.dart';
import '../ui/screens/pedidos/pedidos_screen.dart';
import '../ui/screens/profile/profile_screen.dart';
import '../ui/screens/cart/cart_screen.dart';
import '../ui/screens/pedidos/pedidos_screen.dart';
import '../ui/screens/admin/admin_screen.dart';
import '../ui/screens/admin/pedido_admin_detail_screen.dart';
import '../ui/screens/entregador/area_entregador_screen.dart';
import '../ui/screens/pedidos/pedidos_loja_screen.dart';
import '../ui/navigation/main_shell.dart';

class AppRouter {
  AppRouter._();

  /// Catálogo/feed/lojas são públicos; carrinho, conta, pedidos e painéis
  /// continuam exigindo login.
  static bool _rotaPublica(String location) {
    if (location.isEmpty || location == '/' || location.startsWith('/?')) {
      return true;
    }
    const exatas = {
      '/login',
      '/register',
      '/redefinir-senha',
      '/busca',
    };
    if (exatas.contains(location)) return true;
    const prefixos = [
      '/busca?',
      '/produto/',
      '/categoria/',
      '/unidade/',
      '/post/',
      '/aviso/',
      '/novidade/',
      '/evento/',
    ];
    return prefixos.any(location.startsWith);
  }

  static final GoRouter router = GoRouter(
    refreshListenable: AuthRefreshNotifier.instance,
    initialLocation: '/splash',
    redirect: (context, state) {
      final auth = context.read<AuthProvider>();
      final isLoggedIn = auth.isAuthenticated;
      final location = state.uri.toString();

      if (location == '/splash') return null;

      final destino = state.uri.queryParameters['redirect'];
      if (destino != null &&
          destino.startsWith('/') &&
          !destino.startsWith('//') &&
          _rotaPublica(destino)) {
        return destino;
      }

      // Abriu o app pelo link de recuperação: manda direto para "Nova senha".
      if (PasswordRecoveryFlag.pending && isLoggedIn && location == '/') {
        return '/redefinir-senha';
      }

      if (isLoggedIn && (location == '/login' || location == '/register')) {
        return '/';
      }
      if (!isLoggedIn && !_rotaPublica(location)) {
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
        path: '/redefinir-senha',
        builder: (context, state) => const RedefinirSenhaScreen(),
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
        path: '/enderecos',
        builder: (context, state) => const EnderecosScreen(),
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
      GoRoute(path: '/chat/:id/:nome', builder: (_, s) => ChatScreen(
        unidadeId: int.tryParse(s.pathParameters['id'] ?? '') ?? 0,
        unidadeNome: Uri.decodeComponent(s.pathParameters['nome'] ?? ''),
      )),
      GoRoute(path: '/chat-conversa/:id/:nome', builder: (_, s) => ChatScreen(
        conversaId: int.tryParse(s.pathParameters['id'] ?? ''),
        unidadeId: 0,
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
          if (funcao != 'admin' && funcao != 'atendente' && funcao != 'gestor') {
            return const MainShell();
          }
          return const PedidosLojaScreen();
        },
      ),
      GoRoute(
        path: '/painel-loja',
        builder: (context, state) {
          final auth = context.read<AuthProvider>();
          final funcao = auth.user?.funcao;
          if (funcao != 'admin' && funcao != 'gestor' && funcao != 'atendente') {
            return const MainShell();
          }
          return const AdminScreen(modoParceiro: true);
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
      GoRoute(
        path: '/admin/pedidos/:id',
        builder: (context, state) {
          final auth = context.read<AuthProvider>();
          final funcao = auth.user?.funcao;
          if (funcao != 'admin' && funcao != 'atendente' && funcao != 'gestor') {
            return const MainShell();
          }
          final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          if (id <= 0) return const MainShell();
          return PedidoAdminDetailScreen(pedidoId: id);
        },
      ),
    ],
  );
}
