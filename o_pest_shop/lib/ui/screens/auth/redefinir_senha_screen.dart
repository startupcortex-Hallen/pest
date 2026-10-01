import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/auth_notifier.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/helpers/theme_colors.dart';
import '../../../providers/auth_provider.dart';
import '../../widgets/custom_text_field.dart';

/// Tela aberta quando o usuário chega pelo link de recuperação de senha.
/// O Supabase já restaura a sessão nesse momento; aqui só definimos a nova senha.
class RedefinirSenhaScreen extends StatefulWidget {
  const RedefinirSenhaScreen({super.key});

  @override
  State<RedefinirSenhaScreen> createState() => _RedefinirSenhaScreenState();
}

class _RedefinirSenhaScreenState extends State<RedefinirSenhaScreen> {
  final _formKey = GlobalKey<FormState>();
  final _senhaCtrl = TextEditingController();
  final _confirmaCtrl = TextEditingController();
  bool _obscure = true;
  bool _saving = false;

  @override
  void dispose() {
    _senhaCtrl.dispose();
    _confirmaCtrl.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final erro = await context.read<AuthProvider>().changePassword(_senhaCtrl.text);

    if (!mounted) return;
    setState(() => _saving = false);

    if (erro != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(erro), backgroundColor: AppColors.error),
      );
      return;
    }

    PasswordRecoveryFlag.pending = false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Senha alterada com sucesso!'),
        backgroundColor: AppColors.success,
      ),
    );
    context.go('/');
  }

  void _irParaLoja() {
    PasswordRecoveryFlag.pending = false;
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeColors.surface(context),
      appBar: AppBar(
        backgroundColor: ThemeColors.surface(context),
        elevation: 0,
        title: Text(
          'Nova senha',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Defina sua nova senha',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Você abriu o app pelo link de recuperação. Escolha uma nova senha para continuar acessando sua conta.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: ThemeColors.secondaryText(context),
                      ),
                ),
                const SizedBox(height: AppSpacing.lg),
                CustomTextField(
                  label: 'Nova senha',
                  hint: 'Mínimo 6 caracteres',
                  leadingIcon: Icons.lock_outline_rounded,
                  trailingIcon:
                      _obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                  obscureText: _obscure,
                  controller: _senhaCtrl,
                  onTrailingTap: () => setState(() => _obscure = !_obscure),
                  validator: (value) {
                    if (value == null || value.length < 6) {
                      return 'A senha deve ter no mínimo 6 caracteres';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                CustomTextField(
                  label: 'Confirmar nova senha',
                  hint: 'Repita a senha',
                  leadingIcon: Icons.lock_reset_rounded,
                  obscureText: _obscure,
                  controller: _confirmaCtrl,
                  validator: (value) {
                    if (value != _senhaCtrl.text) {
                      return 'As senhas não conferem';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _salvar,
                    child: _saving
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.onPrimary,
                            ),
                          )
                        : const Text('Salvar nova senha'),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextButton(
                  onPressed: _irParaLoja,
                  child: const Text('Agora não, ir para a loja'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
