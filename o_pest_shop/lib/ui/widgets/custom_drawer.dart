import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/helpers/scale_helper.dart';
import '../../core/helpers/theme_colors.dart';
import '../../providers/auth_provider.dart';

class CustomDrawer extends StatelessWidget {
  const CustomDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final funcao = user?.funcao ?? 'usuario';

    return Drawer(
      child: Container(
        color: ThemeColors.surface(context),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _buildHeader(context, user?.nome ?? 'Usuário',
                  user?.email ?? ''),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _DrawerItem(
                      icon: Icons.admin_panel_settings_rounded,
                      label: 'Área do Admin',
                      visible: funcao == 'admin',
                      onTap: () {
                        Navigator.pop(context);
                        context.push('/admin');
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.support_agent_rounded,
                      label: 'Central de Atendimento',
                      visible: funcao == 'admin' || funcao == 'atendente',
                      onTap: () {
                        Navigator.pop(context);
                        context.push('/central-atendimento');
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.receipt_long_rounded,
                      label: 'Meus Pedidos',
                      visible: true,
                      onTap: () {
                        Navigator.pop(context);
                        context.push('/pedidos');
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.favorite_rounded,
                      label: 'Favoritos',
                      visible: true,
                      onTap: () {
                        Navigator.pop(context);
                        context.push('/favoritos');
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.delivery_dining_rounded,
                      label: 'Área do Entregador',
                      visible: funcao == 'admin' || funcao == 'entregador',
                      onTap: () {
                        Navigator.pop(context);
                        context.push('/area-entregador');
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.storefront_rounded,
                      label: 'Pedidos da Loja',
                      visible: funcao == 'admin' || funcao == 'atendente',
                      onTap: () {
                        Navigator.pop(context);
                        context.push('/pedidos-loja');
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.medical_services_rounded,
                      label: 'Área do Nutricionista',
                      visible: false,
                      onTap: () {
                        Navigator.pop(context);
                        context.push('/area-profissional');
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.fitness_center_rounded,
                      label: 'Área do Personal',
                      visible: false,
                      onTap: () {
                        Navigator.pop(context);
                        context.push('/area-profissional');
                      },
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: context.w(16)),
                      child: const Divider(),
                    ),
                    _DrawerItem(
                      icon: Icons.logout_rounded,
                      label: 'Sair',
                      visible: true,
                      color: ThemeColors.error(context),
                      onTap: () async {
                        Navigator.pop(context);
                        final auth = context.read<AuthProvider>();
                        await auth.signOut();
                        if (context.mounted) context.go('/login');
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, String nome, String email) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
          context.w(16), context.h(48), context.w(16), context.h(24)),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [ThemeColors.primary(context), ThemeColors.primary(context).withValues(alpha: 0.7)],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(context.w(24)),
          bottomRight: Radius.circular(context.w(24)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: context.w(32).clamp(24.0, 40.0),
            backgroundColor: Colors.white.withValues(alpha: 0.2),
            child: Text(
              nome.isNotEmpty ? nome[0].toUpperCase() : 'U',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: context.sp(26),
                  fontWeight: FontWeight.bold),
            ),
          ),
          SizedBox(height: context.h(12)),
          Text(
            nome,
            style: TextStyle(
              color: Colors.white,
              fontSize: context.sp(16),
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: context.h(4)),
          Text(
            email,
            style: TextStyle(
              color: Colors.white70,
              fontSize: context.sp(12),
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool visible;
  final Color? color;
  final VoidCallback? onTap;

  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.visible,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return ListTile(
      leading: Icon(icon, color: color ?? ThemeColors.primary(context),
          size: context.sp(22)),
      title: Text(
        label,
        style: TextStyle(
          color: color ?? ThemeColors.primaryText(context),
          fontSize: context.sp(14),
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap,
      dense: true,
    );
  }
}
