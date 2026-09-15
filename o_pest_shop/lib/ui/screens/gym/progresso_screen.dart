import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/helpers/theme_colors.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/gym_service.dart';

class ProgressoScreen extends StatefulWidget {
  const ProgressoScreen({super.key});

  @override
  State<ProgressoScreen> createState() => _ProgressoScreenState();
}

class _ProgressoScreenState extends State<ProgressoScreen> {
  final _service = GymService();
  List<Map<String, dynamic>> _fotos = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _carregar(); }

  Future<void> _carregar() async {
    final userId = context.read<AuthProvider>().user?.id;
    if (userId == null) return;
    try { _fotos = await _service.fetchProgressoFotos(userId); } catch (e) { debugPrint('Erro progresso: $e'); }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _adicionarFoto() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (file == null) return;
    final userId = context.read<AuthProvider>().user?.id;
    if (userId == null) return;
    try {
      final bytes = await file.readAsBytes();
      final fileName = 'progresso_${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await Supabase.instance.client.storage.from('fotos_perfil').uploadBinary(fileName, bytes, fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true));
      final url = Supabase.instance.client.storage.from('fotos_perfil').getPublicUrl(fileName);
      await Supabase.instance.client.from('progresso_fotos').insert({'user_id': userId, 'foto_url': url});
      _carregar();
    } catch (e) { debugPrint('Erro upload: $e'); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeColors.background(context),
      appBar: AppBar(backgroundColor: ThemeColors.surface(context), leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => context.pop()), title: const Text('Meu Progresso')),
      floatingActionButton: FloatingActionButton(onPressed: _adicionarFoto, child: const Icon(Icons.camera_alt_rounded)),
      body: _loading ? const Center(child: CircularProgressIndicator()) : GridView.builder(
        padding: const EdgeInsets.all(AppSpacing.lg),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12),
        itemCount: _fotos.length + 1,
        itemBuilder: (_, i) {
          if (i == 0) return GestureDetector(
            onTap: _adicionarFoto,
            child: Container(
              decoration: BoxDecoration(
                color: ThemeColors.surfaceVariant(context), borderRadius: BorderRadius.circular(16),
                border: Border.all(color: ThemeColors.outline(context), width: 2, strokeAlign: BorderSide.strokeAlignInside),
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.add_photo_alternate_rounded, size: 48, color: ThemeColors.hint(context)),
                const SizedBox(height: 8),
                Text('Nova Foto', style: TextStyle(color: ThemeColors.secondaryText(context), fontWeight: FontWeight.w600)),
              ]),
            ),
          );
          final f = _fotos[i - 1];
          return ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(fit: StackFit.expand, children: [
              Image.network(f['foto_url'] as String? ?? '', fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: ThemeColors.surfaceVariant(context))),
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black54])),
                  child: Text(f['data'] as String? ?? '', style: const TextStyle(color: Colors.white, fontSize: 11), textAlign: TextAlign.center),
                ),
              ),
            ]),
          );
        },
      ),
    );
  }
}
