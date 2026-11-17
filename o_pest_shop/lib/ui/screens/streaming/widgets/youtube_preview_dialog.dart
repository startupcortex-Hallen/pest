import 'dart:async';

import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

import '../../../../core/theme/app_colors.dart';

class YoutubePreviewDialog extends StatefulWidget {
  final String videoId;
  final String titulo;

  const YoutubePreviewDialog({
    super.key,
    required this.videoId,
    this.titulo = 'Pré-visualização',
  });

  @override
  State<YoutubePreviewDialog> createState() => _YoutubePreviewDialogState();
}

class _YoutubePreviewDialogState extends State<YoutubePreviewDialog> {
  late final YoutubePlayerController _controller;
  StreamSubscription<YoutubePlayerValue>? _subscription;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController.fromVideoId(
      videoId: widget.videoId,
      autoPlay: true,
      params: const YoutubePlayerParams(
        showControls: true,
        enableCaption: false,
        strictRelatedVideos: true,
        videoStateUpdateInterval: 500,
      ),
    );
    _subscription = _controller.stream.listen((value) {
      if (!mounted) return;
      if (value.hasError) {
        debugPrint('Erro do player YouTube: ${value.error}');
        setState(() => _erro = _mensagemErro(value.error));
      }
    });
  }

  String _mensagemErro(YoutubeError erro) {
    switch (erro) {
      case YoutubeError.videoNotFound:
      case YoutubeError.cannotFindVideo:
      case YoutubeError.invalidParam:
        return 'Vídeo não encontrado, privado ou removido do YouTube.';
      case YoutubeError.notEmbeddable:
      case YoutubeError.sameAsNotEmbeddable:
      case YoutubeError.sameAsNotEmbeddable2:
        return 'Este vídeo não está disponível para reprodução incorporada. '
            'Pode ser restrito por idade, região ou pelas configurações do canal.';
      case YoutubeError.html5Error:
        return 'O player do YouTube não conseguiu reproduzir este vídeo.';
      default:
        return 'Não foi possível reproduzir este vídeo agora.';
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    unawaited(_controller.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.titulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            AspectRatio(
              aspectRatio: 16 / 9,
              child: _erro != null
                  ? Container(
                      color: AppColors.surface,
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: AppColors.error,
                            size: 38,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _erro!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    )
                  : YoutubePlayer(controller: _controller),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Text(
                'A reprodução depende das permissões de incorporação do YouTube.',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
