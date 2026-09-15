import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/helpers/time_ago.dart';
import '../../../models/user_profile.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/theme_provider.dart';
import 'edit_personal_data_screen.dart';
import '../../widgets/animated_card_entry.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context, user, user?.nome ?? 'Usuário'),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPerfilNutricao(context),
                    const SizedBox(height: AppSpacing.lg),
                    _buildSuaCarna(context),
                    const SizedBox(height: AppSpacing.lg),
                    _buildSuporteElite(context),
                    const SizedBox(height: AppSpacing.lg),
                    _buildLogoutButton(context),
                    _buildFooter(context),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, UserProfile? user, String nome) {
    final isDark = context.watch<ThemeProvider>().isDark;
    return Container(
      height: 420,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [AppColors.darkPrimary, AppColors.darkPrimary.withValues(alpha: 0.6), AppColors.darkSurface]
              : [AppColors.primary, AppColors.primary.withValues(alpha: 0.6), AppColors.background],
        ),
      ),
      child: Stack(
        children: [
          // Titulo centralizado no topo
          Positioned(
            top: MediaQuery.of(context).padding.top + 8, left: 0, right: 0,
            child: Center(
              child: Text('O PEST - SHOP',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: isDark ? AppColors.darkOnSurface : AppColors.onPrimary)),
            ),
          ),
          // Avatar + nome + stats centralizados verticalmente
          Positioned(
            top: 0, left: 0, right: 0, bottom: 0,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 120, height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: isDark ? AppColors.darkAccent : AppColors.accent, width: 3),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: Container(
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.surfaceVariant),
                        child: ClipOval(
                          child: user?.avatarUrl?.isNotEmpty == true
                              ? CachedNetworkImage(
                                  imageUrl: user?.avatarUrl ?? '',
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                  placeholder: (_, __) => const Icon(Icons.person_rounded, size: 60, color: AppColors.hint),
                                  errorWidget: (_, __, ___) => const Icon(Icons.person_rounded, size: 60, color: AppColors.hint),
                                )
                              : Image.asset('assets/logo.jpg', fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded, size: 60, color: AppColors.hint)),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0, right: 0,
                      child: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDark ? AppColors.darkAccent : AppColors.accent,
                          border: Border.all(color: isDark ? AppColors.darkPrimary : AppColors.primary, width: 3),
                        ),
                        child: GestureDetector(
                          onTap: () => _uploadFoto(context),
                          child: const Icon(Icons.add_a_photo_rounded, size: 18, color: AppColors.onSurface),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text(nome,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(user?.objetivo ?? 'Comunidade O Pest',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(width: AppSpacing.sm),
                    Container(width: 4, height: 4,
                      decoration: BoxDecoration(shape: BoxShape.circle,
                          color: isDark ? AppColors.darkOnPrimary : AppColors.primary)),
                    const SizedBox(width: AppSpacing.sm),
                    Text('ID: ${user?.codigo ?? (user != null && user.id.length > 6 ? user.id.substring(0, 6).toUpperCase() : user?.id ?? '')}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.7))),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                _buildStatsCard(context, isDark, user),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton(BuildContext context, IconData icon, {VoidCallback? onPressed}) {
    final isDark = context.watch<ThemeProvider>().isDark;
    return Container(
      decoration: BoxDecoration(
        color: (isDark
                ? AppColors.darkOnPrimary
                : AppColors.onPrimary)
            .withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
        child: IconButton(
        icon: Icon(icon,
            color: isDark
                ? AppColors.darkOnSurface
                : AppColors.onPrimary,
            size: 24),
        onPressed: onPressed ?? () {},
      ),
    );
  }

  Widget _buildStatsCard(BuildContext context, bool isDark, UserProfile? user) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: (isDark
                    ? AppColors.darkOnPrimary
                    : AppColors.onPrimary)
                .withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: (isDark
                      ? AppColors.darkOnPrimary
                      : AppColors.onPrimary)
                  .withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              _buildStatItem(context, '${user?.pontos ?? 0}', 'PONTOS'),
              _buildStatDivider(isDark),
              _buildStatItem(context, 'R\$ ${user?.pontos ?? 0}', 'INVESTIDO'),
              _buildStatDivider(isDark),
              _buildStatItem(context, '0', 'ASSINATURAS'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(BuildContext context, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(
                  color: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.color
                      ?.withValues(alpha: 0.7),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatDivider(bool isDark) {
    return Container(
      width: 1,
      height: 30,
      color: (isDark ? AppColors.darkOnPrimary : AppColors.onPrimary)
          .withValues(alpha: 0.2),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context)
          .textTheme
          .labelSmall
          ?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w800),
    );
  }

  Widget _buildProfileOption(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    String? badge,
    Color? iconBgColor,
    Color? iconColor,
    VoidCallback? onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: iconBgColor ??
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: iconColor ?? Theme.of(context).colorScheme.primary,
            size: 22,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
            ),
            if (badge != null) _buildBadge(badge),
          ],
        ),
        subtitle: Text(subtitle,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.secondaryText)),
        trailing: const Icon(Icons.chevron_right_rounded,
            color: AppColors.hint),
        onTap: onTap,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      ),
    );
  }

  Widget _buildToggleSetting(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    String? badge,
    Color? iconBgColor,
    Color? iconColor,
    ValueChanged<bool>? onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: iconBgColor ??
                Theme.of(context).colorScheme.secondary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: iconColor ?? AppColors.secondaryText,
            size: 22,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
            ),
            if (badge != null) _buildBadge(badge),
          ],
        ),
        subtitle: Text(subtitle,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.secondaryText)),
        trailing: Switch(
          value: value,
          onChanged: onChanged,
          activeColor: Theme.of(context).colorScheme.primary,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      ),
    );
  }

  Widget _buildBadge(String texto) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_rounded, size: 10, color: AppColors.error),
          const SizedBox(width: 3),
          Text(texto,
              style: const TextStyle(fontSize: 9, color: AppColors.error, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
        ],
      ),
    );
  }

  Future<void> _uploadFoto(BuildContext context) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (file == null) return;

    final userId = context.read<AuthProvider>().user?.id;
    if (userId == null) return;

    try {
      // Deleta avatar antigo se existir
      final user = context.read<AuthProvider>().user;
      if (user?.avatarUrl != null && user!.avatarUrl!.contains('/fotos_perfil/')) {
        final oldFile = user.avatarUrl!.split('/fotos_perfil/').last;
        await Supabase.instance.client.storage.from('fotos_perfil').remove([oldFile]);
      }

      final bytes = await file.readAsBytes();
      final fileName = 'avatar_${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await Supabase.instance.client.storage.from('fotos_perfil').uploadBinary(
        fileName, bytes,
        fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
      );

      final url = Supabase.instance.client.storage.from('fotos_perfil').getPublicUrl(fileName);

      await Supabase.instance.client.from('perfis').update({
        'avatar_url': url,
      }).eq('id', userId);

      if (context.mounted) await context.read<AuthProvider>().refreshProfile();
    } catch (e) {
      debugPrint('Erro upload foto: $e');
    }
  }

  Widget _buildPerfilNutricao(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, 'PERFIL & CONTA'),
        const SizedBox(height: AppSpacing.md),
        AnimatedCardEntry(
          index: 0,
          child: _buildProfileOption(
            context,
            icon: Icons.person_outline_rounded,
            title: 'Dados Pessoais',
            subtitle: 'Nome completo, CPF e contato',
            onTap: () => context.push('/editar-dados'),
          ),
        ),
        const SizedBox(height: 12),
        AnimatedCardEntry(
          index: 1,
          child: _buildProfileOption(
            context,
            icon: Icons.shopping_bag_rounded,
            title: 'Histórico de Compras',
            subtitle: 'Tudo que você já comprou',
            iconBgColor: AppColors.accent.withValues(alpha: 0.1),
            iconColor: AppColors.primaryText,
          ),
        ),
        const SizedBox(height: 12),
        AnimatedCardEntry(
          index: 2,
          child: _buildProfileOption(
            context,
            icon: Icons.favorite_rounded,
            title: 'Favoritos',
            subtitle: 'Produtos salvos',
            iconBgColor: AppColors.error.withValues(alpha: 0.1),
            iconColor: AppColors.error,
            onTap: () => context.push('/favoritos'),
          ),
        ),
      ],
    );
  }

  Widget _buildSuaCarna(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, 'TIPO DE PAGAMENTO'),
        const SizedBox(height: AppSpacing.md),
        AnimatedCardEntry(
          index: 0,
          child: _buildProfileOption(
            context,
            icon: Icons.card_membership_rounded,
            title: 'Assinatura Ativa',
            subtitle: 'Plano O Pest - membros da comunidade',
            badge: 'EM BREVE',
            onTap: () => context.push('/assinaturas'),
          ),
        ),
        const SizedBox(height: 12),
        AnimatedCardEntry(
          index: 1,
          child: _buildProfileOption(
            context,
            icon: Icons.credit_card_rounded,
            title: 'Método de Pagamento',
            subtitle: 'Cartão de crédito',
            iconBgColor:
                Theme.of(context).colorScheme.secondary.withValues(alpha: 0.1),
            iconColor: AppColors.secondaryText,
          ),
        ),
        const SizedBox(height: 12),
        AnimatedCardEntry(
          index: 2,
          child: _buildPixToggle(context),
        ),
      ],
    );
  }

  Widget _buildPixToggle(BuildContext context) {
    final pixAtivo = ValueNotifier<bool>(true);
    return ValueListenableBuilder<bool>(
      valueListenable: pixAtivo,
      builder: (context, value, _) {
        return _buildToggleSetting(
          context,
          icon: Icons.qr_code_rounded,
          title: 'Pix',
          subtitle: value ? 'Ativado como método principal' : 'Desativado',
          value: value,
          iconBgColor: AppColors.success.withValues(alpha: 0.1),
          iconColor: AppColors.success,
          onChanged: (v) => pixAtivo.value = v,
        );
      },
    );
  }

  Widget _buildSuporteElite(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, 'SUPORTE'),
        const SizedBox(height: AppSpacing.md),
        AnimatedCardEntry(
          index: 0,
          child: _buildProfileOption(
            context,
            icon: Icons.help_outline_rounded,
            title: 'Central de Ajuda',
            subtitle: 'FAQ e trocas em até 30 dias',
          ),
        ),
      ],
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.xl),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          onPressed: () async {
            final auth = context.read<AuthProvider>();
            await auth.signOut();
            if (context.mounted) context.go('/login');
          },
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Encerrar Sessão'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Text(
        'Desenvolvido por Cortex Startup',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.secondaryText,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
