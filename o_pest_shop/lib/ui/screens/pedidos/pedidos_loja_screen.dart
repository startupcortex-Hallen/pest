import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/helpers/theme_colors.dart';
import '../admin/tabs/pedidos_tab.dart';

/// Pedidos da unidade para admin e atendente — mesmo widget da aba do admin.
class PedidosLojaScreen extends StatelessWidget {
  const PedidosLojaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeColors.background(context),
      appBar: AppBar(
        backgroundColor: ThemeColors.surface(context),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
        title: const Text('Pedidos da Loja',
            style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: const PedidosTab(),
    );
  }
}
