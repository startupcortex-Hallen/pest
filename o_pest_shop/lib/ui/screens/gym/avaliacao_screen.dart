import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/helpers/theme_colors.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/aula.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/gym_service.dart';

class AvaliacaoScreen extends StatefulWidget {
  const AvaliacaoScreen({super.key});

  @override
  State<AvaliacaoScreen> createState() => _AvaliacaoScreenState();
}

class _AvaliacaoScreenState extends State<AvaliacaoScreen> {
  final _service = GymService();
  List<Avaliacao> _avaliacoes = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _carregar(); }

  Future<void> _carregar() async {
    final userId = context.read<AuthProvider>().user?.id;
    if (userId == null) return;
    try {
      _avaliacoes = (await _service.fetchAvaliacoes(userId)).map((j) => Avaliacao.fromJson(j)).toList();
    } catch (e) { debugPrint('Erro avaliacao: $e'); }
    if (mounted) setState(() => _loading = false);
  }

  void _novaAvaliacao() {
    final pesoCtrl = TextEditingController(); final alturaCtrl = TextEditingController();
    final gorduraCtrl = TextEditingController(); final muscularCtrl = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Nova Avaliação'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: pesoCtrl, decoration: const InputDecoration(labelText: 'Peso (kg)', border: OutlineInputBorder()), keyboardType: TextInputType.number),
        const SizedBox(height: 8),
        TextField(controller: alturaCtrl, decoration: const InputDecoration(labelText: 'Altura (m)', border: OutlineInputBorder()), keyboardType: TextInputType.number),
        const SizedBox(height: 8),
        TextField(controller: gorduraCtrl, decoration: const InputDecoration(labelText: '% Gordura', border: OutlineInputBorder()), keyboardType: TextInputType.number),
        const SizedBox(height: 8),
        TextField(controller: muscularCtrl, decoration: const InputDecoration(labelText: 'Massa Muscular (kg)', border: OutlineInputBorder()), keyboardType: TextInputType.number),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        TextButton(onPressed: () async {
          final userId = context.read<AuthProvider>().user?.id;
          if (userId == null) return;
          await _service.salvarAvaliacao({
            'user_id': userId, 'unidade_id': context.read<AuthProvider>().user?.unidadeId ?? 1,
            'peso': double.tryParse(pesoCtrl.text.replaceAll(',', '.')),
            'altura': double.tryParse(alturaCtrl.text.replaceAll(',', '.')),
            'percentual_gordura': double.tryParse(gorduraCtrl.text.replaceAll(',', '.')),
            'massa_muscular': double.tryParse(muscularCtrl.text.replaceAll(',', '.')),
          });
          if (ctx.mounted) Navigator.pop(ctx);
          _carregar();
        }, child: const Text('Salvar', style: TextStyle(color: AppColors.primary))),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final ultima = _avaliacoes.isNotEmpty ? _avaliacoes.first : null;
    return Scaffold(
      backgroundColor: ThemeColors.background(context),
      appBar: AppBar(backgroundColor: ThemeColors.surface(context), leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => context.pop()), title: const Text('Avaliação Física')),
      floatingActionButton: FloatingActionButton(onPressed: _novaAvaliacao, child: const Icon(Icons.add_rounded)),
      body: _loading ? const Center(child: CircularProgressIndicator()) : ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          if (ultima != null) ...[
            const Text('Última Avaliação', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: ThemeColors.surface(context), borderRadius: BorderRadius.circular(16)),
              child: Column(children: [
                _medida('Peso', '${ultima.peso?.toStringAsFixed(1) ?? '-'} kg'),
                _medida('Altura', '${ultima.altura?.toStringAsFixed(2) ?? '-'} m'),
                _medida('% Gordura', '${ultima.percentualGordura?.toStringAsFixed(1) ?? '-'}%'),
                _medida('Massa Muscular', '${ultima.massaMuscular?.toStringAsFixed(1) ?? '-'} kg'),
                if (ultima.imc != null) _medida('IMC', ultima.imc!.toStringAsFixed(1)),
              ]),
            ),
          ] else const Text('Nenhuma avaliação cadastrada'),
          const SizedBox(height: 24),
          const Text('Histórico', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          ..._avaliacoes.map((a) => Container(
            margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: ThemeColors.surface(context), borderRadius: BorderRadius.circular(12)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(a.dataAvaliacao.length >= 10 ? a.dataAvaliacao.substring(0, 10) : a.dataAvaliacao, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('${a.peso?.toStringAsFixed(1) ?? '-'} kg  |  ${a.percentualGordura?.toStringAsFixed(1) ?? '-'}%'),
            ]),
          )),
        ],
      ),
    );
  }

  Widget _medida(String label, String valor) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: TextStyle(color: ThemeColors.secondaryText(context))),
      Text(valor, style: const TextStyle(fontWeight: FontWeight.w600)),
    ]),
  );
}
