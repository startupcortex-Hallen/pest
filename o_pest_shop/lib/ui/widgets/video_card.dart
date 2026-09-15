import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import '../../core/helpers/scale_helper.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

class VideoCard extends StatefulWidget {
  final String autor;
  final String? autorImagem;
  final String categoria;
  final String youtubeUrl;
  final String titulo;
  final String? descricao;
  final int likeCount;
  final int commentCount;
  final bool likedByMe;
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onTap;
  final VoidCallback? onAutorTap;

  const VideoCard({
    super.key,
    required this.autor,
    this.autorImagem,
    required this.categoria,
    required this.youtubeUrl,
    required this.titulo,
    this.descricao,
    this.likeCount = 0,
    this.commentCount = 0,
    this.likedByMe = false,
    this.onLike,
    this.onComment,
    this.onTap,
    this.onAutorTap,
  });

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard> {
  String? _thumbUrl;

  @override
  void initState() {
    super.initState();
    final videoId = YoutubePlayerController.convertUrlToId(widget.youtubeUrl);
    if (videoId != null) {
      _thumbUrl = 'https://img.youtube.com/vi/$videoId/hqdefault.jpg';
    }
  }

  Color _badgeColor() {
    switch (widget.categoria.toLowerCase()) {
      case 'vaga':
      case 'emprego':
        return AppColors.success;
      case 'notícia':
      case 'noticia':
      case 'novidade':
        return AppColors.primary;
      case 'patrocinado':
      case 'anúncio':
      case 'anuncio':
      case 'ofertas':
        return AppColors.warning;
      default:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final badgeColor = _badgeColor();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.15),
            blurRadius: 4,
            spreadRadius: 1,
            offset: const Offset(4, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                CircleAvatar(
                  radius: context.w(18).clamp(14.0, 24.0),
                  backgroundColor: AppColors.surfaceVariant,
                  child: widget.autorImagem != null
                      ? ClipOval(
                          child: SizedBox(
                            width: context.w(18).clamp(14.0, 24.0) * 2,
                            height: context.w(18).clamp(14.0, 24.0) * 2,
                            child: Image.network(widget.autorImagem!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Icon(
                                    Icons.person_rounded,
                                    color: AppColors.hint,
                                    size: context.sp(18))),
                          ),
                        )
                      : Icon(Icons.person_rounded,
                          color: AppColors.hint, size: context.sp(18)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: widget.onAutorTap,
                    child: Text(widget.autor,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    widget.categoria.toUpperCase(),
                    style: TextStyle(
                        color: badgeColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          // Thumbnail + Play button
          if (_thumbUrl != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        _thumbUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: AppColors.surfaceVariant,
                          child: const Icon(Icons.play_circle_outline, color: Colors.white70, size: 48),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.3)],
                            begin: Alignment.center,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                      Center(
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Título
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Text(widget.titulo,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
          if (widget.descricao != null && widget.descricao!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Text(widget.descricao!,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.secondaryText),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis),
            ),
          // Ações
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    widget.likedByMe
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: widget.likedByMe ? AppColors.error : AppColors.hint,
                    size: 20,
                  ),
                  onPressed: widget.onLike,
                ),
                Text('${widget.likeCount}',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: AppColors.secondaryText)),
                const SizedBox(width: AppSpacing.md),
                IconButton(
                  icon: const Icon(Icons.chat_bubble_outline_rounded,
                      color: AppColors.hint, size: 20),
                  onPressed: widget.onComment,
                ),
                Text('${widget.commentCount}',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: AppColors.secondaryText)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
