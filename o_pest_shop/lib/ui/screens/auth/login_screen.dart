import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/helpers/theme_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../providers/auth_provider.dart';
import '../../widgets/custom_text_field.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleLogin() {
    if (!_formKey.currentState!.validate()) return;
    final authProvider = context.read<AuthProvider>();
    authProvider.signIn(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeColors.surface(context),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              _buildLoginForm(),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.only(
        top: AppSpacing.xl,
        right: AppSpacing.lg,
        bottom: AppSpacing.xl,
        left: AppSpacing.lg,
      ),
      color: ThemeColors.primary(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.md),
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: ThemeColors.surface(context),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              boxShadow: AppShadows.sm,
            ),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Image.asset(
                'assets/logo.jpg',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.storefront_rounded,
                  color: ThemeColors.primary(context),
                  size: 48,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'O Pest - Shop',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: ThemeColors.onPrimary(context),
                  fontWeight: FontWeight.w900,
                ),
          ),
          Text(
            'A voz da quebrada pra todo Brasil',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: ThemeColors.onPrimary(context).withValues(alpha: 0.8),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginForm() {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          return Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (auth.error != null)
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    margin: const EdgeInsets.only(bottom: AppSpacing.md),
                    decoration: BoxDecoration(
                      color: ThemeColors.error(context).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: ThemeColors.error(context).withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: ThemeColors.error(context), size: 18),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            auth.error!,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: ThemeColors.error(context),
                                ),
                          ),
                        ),
                        GestureDetector(
                          onTap: auth.clearError,
                          child: Icon(Icons.close, color: ThemeColors.error(context), size: 16),
                        ),
                      ],
                    ),
                  ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Entrar',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Acesse sua conta para conferir novidades e ofertas',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: ThemeColors.secondaryText(context),
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                CustomTextField(
                  label: 'E-mail ou CPF',
                  hint: 'seu@email.com',
                  leadingIcon: Icons.person_outline_rounded,
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Informe seu email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                CustomTextField(
                  label: 'Senha',
                  hint: '••••••••',
                  leadingIcon: Icons.lock_outline_rounded,
                  trailingIcon:
                      _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                  obscureText: _obscurePassword,
                  controller: _passwordController,
                  onTrailingTap: () => setState(() => _obscurePassword = !_obscurePassword),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Informe sua senha';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {},
                      child: const Text('Esqueceu a senha?'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: auth.loading ? null : _handleLogin,
                    child: auth.loading
                        ? SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: ThemeColors.onPrimary(context),
                            ),
                          )
                        : const Text('Continuar'),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => context.push('/register'),
                    child: const Text('Criar conta'),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                _buildDividerWithText('ou entre com'),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.g_mobiledata_rounded, size: 24),
                        label: const Text('Google'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.apple, size: 24),
                        label: const Text('Apple'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDividerWithText(String text) {
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text(
            text,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: ThemeColors.secondaryText(context),
                ),
          ),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      color: AppColors.secondaryBackground,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildFeatureIcon(Icons.verified_rounded, 'Original'),
              const SizedBox(width: AppSpacing.lg),
              _buildFeatureIcon(Icons.speed_rounded, 'Envio Rápido'),
              const SizedBox(width: AppSpacing.lg),
              _buildFeatureIcon(Icons.health_and_safety_rounded, 'Qualidade'),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Ao continuar, você concorda com nossos Termos de Uso e Política de Privacidade.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: ThemeColors.secondaryText(context),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureIcon(IconData icon, String label) {
    return Column(
      children: [
        Icon(icon, color: ThemeColors.primary(context), size: 24),
        const SizedBox(height: AppSpacing.xs),
        Text(
          label,
          style: TextStyle(
            color: ThemeColors.secondaryText(context),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
