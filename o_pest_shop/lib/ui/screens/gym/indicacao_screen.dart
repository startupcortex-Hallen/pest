import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/helpers/theme_colors.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/gym_service.dart';

class IndicacaoScreen extends StatefulWidget {
  const IndicacaoScreen({super.key});

  @override
  State<IndicacaoScreen> createState() => _IndicacaoScreenState();
}

class _IndicacaoScreenState extends State<IndicacaoScreen> {
  final _service = GymService();
  Map<String, dynamic>? _indicacao;
  bool _loading = true;
  int _totalPontos = 0;

  @override
  void initState() { super.initState(); _carregar(); }

  Future<void> _carregar() async {
    final userId = context.read<AuthProvider>().user?.id;
    if (userId == null) return;
    try {
      _indicacao = await _service.fetchIndicacao(userId);
      _totalPontos = context.read<AuthProvider>().user?.pontos ?? 0;
    } catch (e) { debugPrint('Erro indicacao: $e'); }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final codigo = user?.codigo ?? '';
    return Scaffold(
      backgroundColor: ThemeColors.background(context),
      appBar: AppBar(backgroundColor: ThemeColors.surface(context), leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => context.pop()), title: const Text('Indique e Ganhe')),
      body: _loading ? const Center(child: CircularProgressIndicator()) : ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [AppColors.primary, AppColors.primary.withValues(alpha: 0.7)]),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(children: [
              const Icon(Icons.card_giftcard_rounded, size: 48, color: Colors.white),
              const SizedBox(height: 12),
              const Text('Seu código de indicação', style: TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
                child: Text(codigo, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 4)),
              ),
              const SizedBox(height: 8),
              const Text('Compartilhe e ganhe pontos!', style: TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: _cardPonto('${_totalPontos}', 'Pontos', Icons.monetization_on_rounded, AppColors.warning)),
            const SizedBox(width: 12),
            Expanded(child: _cardPonto(_indicacao != null ? '1' : '0', 'Indicações', Icons.people_rounded, AppColors.success)),
          ]),
          const SizedBox(height: 24),
          const Text('Como funciona', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          _passo(1, 'Compartilhe seu código com amigos'),
          _passo(2, 'Eles se cadastram usando seu código'),
          _passo(3, 'Você ganha 50 pontos por indicação'),
          _passo(4, 'Troque pontos por descontos na mensalidade'),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity, height: 50,
            child: ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.share_rounded),
              label: const Text('Compartilhar Código'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardPonto(String valor, String label, IconData icone, Color cor) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: ThemeColors.surface(context), borderRadius: BorderRadius.circular(16)),
    child: Column(children: [
      Icon(icone, color: cor, size: 32),
      const SizedBox(height: 8),
      Text(valor, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: cor)),
      Text(label, style: TextStyle(fontSize: 12, color: ThemeColors.secondaryText(context))),
    ]),
  );

  Widget _passo(int n, String texto) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Container(width: 28, height: 28, decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
        child: Center(child: Text('$n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)))),
      const SizedBox(width: 12),
      Text(texto, style: TextStyle(color: ThemeColors.primaryText(context))),
    ]),
  );
}
