import 'dart:math';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_service.dart';

class StreamingStorage {
  StreamingStorage._();

  static const bucket = 'streaming';
  static const int limiteBytes = 10 * 1024 * 1024;

  static Future<String?> escolherEEnviarImagem({required String pasta}) async {
    final picker = ImagePicker();
    final arquivo = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
      maxWidth: 2200,
      maxHeight: 2200,
    );
    if (arquivo == null) return null;

    final bytes = await arquivo.readAsBytes();
    if (bytes.lengthInBytes > limiteBytes) {
      throw Exception('A imagem deve ter no máximo 10 MB.');
    }

    final tipo = _detectarTipo(bytes);
    if (tipo == null) {
      throw Exception('Formato não aceito. Envie uma imagem JPG, PNG ou WebP.');
    }

    final sufixo = Random().nextInt(999999).toString().padLeft(6, '0');
    final nome =
        '${DateTime.now().millisecondsSinceEpoch}_$sufixo.${tipo.extensao}';
    final caminho = '${pasta.replaceAll(RegExp(r'/+$'), '')}/$nome';

    final client = SupabaseService.instance.client;
    await client.storage
        .from(bucket)
        .uploadBinary(
          caminho,
          bytes,
          fileOptions: FileOptions(contentType: tipo.mime, upsert: true),
        );

    return client.storage.from(bucket).getPublicUrl(caminho);
  }

  static Future<void> removerImagem(String? url) async {
    final caminho = caminhoDoBucket(url);
    if (caminho == null) return;
    try {
      await SupabaseService.instance.client.storage.from(bucket).remove([
        caminho,
      ]);
    } catch (_) {}
  }

  static String? caminhoDoBucket(String? url) {
    if (url == null || url.isEmpty) return null;
    final marcador = '/$bucket/';
    final indice = url.indexOf(marcador);
    if (indice == -1) return null;
    final caminho = url.substring(indice + marcador.length);
    if (caminho.isEmpty) return null;
    return caminho;
  }

  static _TipoImagem? _detectarTipo(List<int> bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return const _TipoImagem('jpg', 'image/jpeg');
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return const _TipoImagem('png', 'image/png');
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return const _TipoImagem('webp', 'image/webp');
    }
    return null;
  }
}

class _TipoImagem {
  final String extensao;
  final String mime;

  const _TipoImagem(this.extensao, this.mime);
}
