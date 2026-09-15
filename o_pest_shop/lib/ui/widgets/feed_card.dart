import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import '../../core/helpers/scale_helper.dart';
import '../../core/theme/app_colors.dart';
import '../../core/helpers/theme_colors.dart';
import '../../core/theme/app_spacing.dart';

class FeedCard extends StatefulWidget {
  final String postId;
  final String autor;
  final String? autorImagem;
  final String categoria;
  final String? imagemUrl;
  final String? youtubeUrl;
  final String titulo;
  final String? descricao;
  final int likeCount;
  final int commentCount;
  final bool likedByMe;
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onTap;
  final VoidCallback? onAutorTap;

  const FeedCard({
    super.key,
    required this.postId,
    required this.autor,
    this.autorImagem,
    required this.categoria,
    this.imagemUrl,
    this.youtubeUrl,
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
  State<FeedCard> createState() => _FeedCardState();
}

class _FeedCardState extends State<FeedCard> {
  bool _isImage = false;
  bool _isVideo = false;

  @override
  void initState() {
    super.initState();
    _isImage = widget.imagemUrl != null && widget.imagemUrl!.isNotEmpty;
    _isVideo = widget.youtubeUrl != null && widget.youtubeUrl!.isNotEmpty;
  }

  Color _badgeColor() {
    switch (widget.categoria.toLowerCase()) {
      case 'vaga':
      case 'emprego':
        return ThemeColors.success(context);
      case 'notícia':
      case 'noticia':
      case 'novidade':
        return ThemeColors.primary(context);
      case 'patrocinado':
      case 'anúncio':
      case 'anuncio':
      case 'ofertas':
        return ThemeColors.warning(context);
      default:
        return ThemeColors.primary(context);
    }
  }

  bool get _hasMedia => _isImage || _isVideo;

  String? _youtubeThumbnailUrl() {
    if (!_isVideo) return null;
    final videoId = YoutubePlayerController.convertUrlToId(widget.youtubeUrl!);
    if (videoId == null) return null;
    return 'https://img.youtube.com/vi/$videoId/hqdefault.jpg';
  }

  @override
  Widget build(BuildContext context) {
    final badgeColor = _badgeColor();
    Widget card = Container(
      margin: EdgeInsets.only(bottom: context.w(16).clamp(12.0, 20.0)),
      decoration: BoxDecoration(
        color: ThemeColors.surface(context),
        borderRadius: BorderRadius.circular(AppRadius.rMd(context)),
        boxShadow: [
          BoxShadow(
            color: ThemeColors.primary(context).withValues(alpha: 0.15),
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
          _buildHeader(badgeColor),
          _buildMedia(),
          _buildBody(),
          _buildActions(),
        ],
      ),
    );
    if (widget.onTap != null) {
      card = GestureDetector(onTap: widget.onTap, child: card);
    }
    return card;
  }

  Widget _buildHeader(Color badgeColor) {
    return Padding(
      padding: EdgeInsets.fromLTRB(context.w(12), context.w(12), context.w(12), 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: widget.onAutorTap,
            child: CircleAvatar(
              radius: context.w(18).clamp(14.0, 24.0),
              backgroundColor: ThemeColors.surfaceVariant(context),
              child: widget.autorImagem != null
                  ? ClipOval(
                      child: SizedBox(
                        width: context.w(18).clamp(14.0, 24.0) * 2,
                        height: context.w(18).clamp(14.0, 24.0) * 2,
                        child: CachedNetworkImage(
                            imageUrl: widget.autorImagem!,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Icon(
                                Icons.person_rounded,
                                color: ThemeColors.hint(context),
                                size: context.sp(18)),
                            placeholder: (_, __) => Container(color: Colors.white)),
                      ),
                    )
                  : Icon(Icons.person_rounded,
                      color: ThemeColors.hint(context), size: context.sp(18)),
            ),
          ),
          SizedBox(width: context.w(10).clamp(6.0, 14.0)),
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
            padding: EdgeInsets.symmetric(
                horizontal: context.w(8), vertical: context.h(3)),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(context.w(6)),
            ),
            child: Text(
              widget.categoria.toUpperCase(),
              style: TextStyle(
                  color: badgeColor,
                  fontSize: context.sp(10),
                  fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedia() {
    if (_isVideo) {
      final thumb = _youtubeThumbnailUrl();
      if (thumb != null) {
        return Padding(
          padding: EdgeInsets.fromLTRB(context.w(12), context.h(8), context.w(12), 0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.rMd(context)),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Hero(
                tag: 'post_${widget.postId}',
                flightShuttleBuilder: (_, animation, direction, fromHeroContext, toHeroContext) {
                  final child = (direction == HeroFlightDirection.push ? fromHeroContext : toHeroContext).widget;
                  return AnimatedBuilder(
                    animation: animation,
                    builder: (context, _) {
                      final t = animation.value;
                      final scale = 1.0 + (t - t * t) * 0.6;
                      return Transform.scale(scale: scale, child: child);
                    },
                  );
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: thumb,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                        color: ThemeColors.surfaceVariant(context),
                        child: const Icon(Icons.play_circle_outline, color: Colors.white70, size: 48),
                      ),
                      placeholder: (_, __) => Container(color: ThemeColors.surface(context)),
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
        );
      }
    }
    if (_isImage) {
      return Padding(
        padding: EdgeInsets.fromLTRB(context.w(12), context.h(8), context.w(12), 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.rMd(context)),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Hero(
              tag: 'post_${widget.postId}',
              flightShuttleBuilder: (_, animation, direction, fromHeroContext, toHeroContext) {
                final child = (direction == HeroFlightDirection.push ? fromHeroContext : toHeroContext).widget;
                return AnimatedBuilder(
                  animation: animation,
                  builder: (context, _) {
                    final t = animation.value;
                    final scale = 1.0 + (t - t * t) * 0.6;
                    return Transform.scale(scale: scale, child: child);
                  },
                );
              },
              child: CachedNetworkImage(
                imageUrl: widget.imagemUrl!,
                width: double.infinity,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  color: ThemeColors.surface(context),
                ),
                errorWidget: (_, __, ___) => Container(
                  color: ThemeColors.surface(context),
                  child: Center(
                    child: Icon(Icons.image_outlined,
                        color: ThemeColors.hint(context), size: context.sp(36)),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildBody() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          context.w(12), _hasMedia ? context.h(8) : context.h(12), context.w(12), 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.titulo,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          if (widget.descricao != null && widget.descricao!.isNotEmpty) ...[
            SizedBox(height: context.h(4)),
            Text(widget.descricao!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: ThemeColors.secondaryText(context)),
                maxLines: 3,
                overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          context.w(4), context.h(4), context.w(4), context.h(4)),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              widget.likedByMe
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: widget.likedByMe ? ThemeColors.error(context) : ThemeColors.hint(context),
              size: context.sp(20),
            ),
            onPressed: widget.onLike,
          ),
          Text('${widget.likeCount}',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: ThemeColors.secondaryText(context))),
          SizedBox(width: context.w(AppSpacing.md)),
          IconButton(
            icon: Icon(Icons.chat_bubble_outline_rounded,
                color: ThemeColors.hint(context), size: context.sp(20)),
            onPressed: widget.onComment,
          ),
          Text('${widget.commentCount}',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: ThemeColors.secondaryText(context))),
        ],
      ),
    );
  }
}
