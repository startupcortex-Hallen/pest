import 'package:url_launcher/url_launcher.dart';

/// Abre o endereço no Google Maps usando o MESMO padrão das unidades
/// (maps/dir) — consistente em todo o app e imune a erros de URL.
Future<void> abrirMapa(String endereco) async {
  if (endereco.trim().isEmpty) return;
  final uri = Uri.parse(
    'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(endereco.trim())}',
  );
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
