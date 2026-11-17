import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/helpers/streaming_format.dart';
import '../../../core/helpers/theme_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/streaming_models.dart';

class StreamingNetworkImage extends StatelessWidget {
  final String? url;
  final BoxFit fit;
  final IconData fallbackIcon;
  final int? memCacheWidth;
  final Alignment alignment;

  const StreamingNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.fallbackIcon = Icons.movie_outlined,
    this.memCacheWidth,
    this.alignment = Alignment.center,
  });

  @override
  Widget build(BuildContext context) {
    final endereco = url?.trim();
    if (endereco == null || endereco.isEmpty) {
      return _fallback(context);
    }
    return CachedNetworkImage(
      imageUrl: endereco,
      fit: fit,
      alignment: alignment,
      memCacheWidth: memCacheWidth,
      fadeInDuration: const Duration(milliseconds: 250),
      placeholder: (_, __) => Container(
        color: ThemeColors.surfaceVariant(context),
        child: const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      errorWidget: (_, __, ___) => _fallback(context),
    );
  }

  Widget _fallback(BuildContext context) {
    return Container(
      color: ThemeColors.surfaceVariant(context),
      alignment: Alignment.center,
      child: Icon(fallbackIcon, color: ThemeColors.hint(context), size: 34),
    );
  }
}

class StreamingSectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const StreamingSectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
        10,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              child: Text(
                actionLabel!,
                style: TextStyle(
                  color: ThemeColors.primary(context),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class StreamingProgressBar extends StatelessWidget {
  final double percentual;
  final double height;

  const StreamingProgressBar({
    super.key,
    required this.percentual,
    this.height = 4,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: percentual.clamp(0, 1),
        minHeight: height,
        backgroundColor: Colors.white24,
        valueColor: AlwaysStoppedAnimation<Color>(ThemeColors.primary(context)),
      ),
    );
  }
}

class StreamingBadge extends StatelessWidget {
  final String label;
  final Color? color;

  const StreamingBadge({super.key, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final cor = color ?? ThemeColors.primary(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cor.withValues(alpha: 0.45), width: 0.7),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: cor,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class StreamingPosterCard extends StatelessWidget {
  final StreamingSeries series;
  final VoidCallback onTap;
  final bool isFavorite;
  final VoidCallback? onFavorite;
  final bool showDescription;
  final bool bloqueado;

  const StreamingPosterCard({
    super.key,
    required this.series,
    required this.onTap,
    this.isFavorite = false,
    this.onFavorite,
    this.showDescription = true,
    this.bloqueado = false,
  });

  @override
  Widget build(BuildContext context) {
    final texto = series.descricaoCurta;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: StreamingNetworkImage(
                    url: series.coverUrl ?? series.bannerUrl,
                    memCacheWidth: 400,
                    fallbackIcon: Icons.movie_filter_outlined,
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(12),
                    ),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(8, 24, 8, 7),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.85),
                          ],
                        ),
                      ),
                      child: Row(
                        children: [
                          if (series.seasonsCount > 0) ...[
                            Icon(
                              Icons.video_library_outlined,
                              size: 11,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '${series.seasonsCount}T',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                          const Spacer(),
                          Icon(
                            bloqueado
                                ? Icons.lock_rounded
                                : Icons.play_circle_fill_rounded,
                            size: 20,
                            color: bloqueado
                                ? Colors.white
                                : ThemeColors.primary(context),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (onFavorite != null)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: GestureDetector(
                      onTap: onFavorite,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isFavorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: isFavorite
                              ? ThemeColors.primary(context)
                              : Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                if (bloqueado)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: StreamingBadge(
                      label: 'EXCLUSIVO',
                      color: ThemeColors.primary(context),
                    ),
                  )
                else if (series.isFeatured)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: StreamingBadge(
                      label: 'DESTAQUE',
                      color: ThemeColors.primary(context),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            series.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          if (showDescription && texto.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              texto,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: ThemeColors.secondaryText(context),
              ),
            ),
          ],
          if (series.category != null && series.category!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              series.category!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: ThemeColors.primary(context),
                fontWeight: FontWeight.w700,
                fontSize: 9,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class StreamingContinueCard extends StatelessWidget {
  final ContinueWatchingItem item;
  final VoidCallback onTap;

  const StreamingContinueCard({
    super.key,
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final episodio = item.episode;
    final progresso = item.progress;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 232,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: ThemeColors.surface(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: ThemeColors.outline(context).withValues(alpha: 0.6),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  StreamingNetworkImage(
                    url: episodio.thumbnailEfetiva,
                    memCacheWidth: 600,
                    fallbackIcon: Icons.play_circle_outline_rounded,
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.55),
                        ],
                      ),
                    ),
                  ),
                  Center(
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: StreamingProgressBar(
                      percentual: progresso.percentual,
                      height: 3,
                    ),
                  ),
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        formatarPercentual(progresso.percentual),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.series.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'T${item.season.seasonNumber} • EP ${episodio.episodeNumber}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: ThemeColors.primary(context),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        Icons.play_arrow_rounded,
                        size: 12,
                        color: ThemeColors.primary(context),
                      ),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(
                          episodio.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: ThemeColors.secondaryText(context),
                              ),
                        ),
                      ),
                      Text(
                        'CONTINUAR',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: ThemeColors.primary(context),
                          fontWeight: FontWeight.w800,
                          fontSize: 8,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StreamingLatestEpisodeCard extends StatelessWidget {
  final StreamingEpisode episode;
  final VoidCallback onTap;

  const StreamingLatestEpisodeCard({
    super.key,
    required this.episode,
    required this.onTap,
  });

  bool get _novo {
    final data = episode.publishedAt ?? episode.createdAt;
    if (data == null) return false;
    return DateTime.now().difference(data.toLocal()).inDays <= 14;
  }

  @override
  Widget build(BuildContext context) {
    final duracao = formatarDuracaoSegundos(episode.durationSeconds);
    final data = formatarDataStreaming(
      episode.publishedAt ?? episode.createdAt,
    );
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 236,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: ThemeColors.surface(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: ThemeColors.outline(context).withValues(alpha: 0.55),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  StreamingNetworkImage(
                    url: episode.thumbnailEfetiva,
                    memCacheWidth: 600,
                    fallbackIcon: Icons.play_circle_outline_rounded,
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.45),
                        ],
                      ),
                    ),
                  ),
                  Center(
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                  if (_novo)
                    Positioned(
                      left: 6,
                      top: 6,
                      child: StreamingBadge(
                        label: 'NOVO',
                        color: ThemeColors.primary(context),
                      ),
                    ),
                  if (duracao.isNotEmpty)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          duracao,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (episode.seriesTitle != null)
                    Text(
                      episode.seriesTitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: ThemeColors.primary(context),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    episode.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      'T${episode.seasonNumber ?? 1} • EP ${episode.episodeNumber}',
                      if (data.isNotEmpty) data,
                    ].join('  •  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: ThemeColors.secondaryText(context),
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StreamingEmptyState extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  const StreamingEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.movie_filter_outlined,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 62, color: ThemeColors.hint(context)),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: ThemeColors.secondaryText(context),
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class StreamingErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const StreamingErrorState({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return StreamingEmptyState(
      title: 'Não foi possível carregar',
      message: message,
      icon: Icons.wifi_off_rounded,
      actionLabel: 'Tentar novamente',
      onAction: onRetry,
    );
  }
}

class StreamingInfoChip extends StatelessWidget {
  final String label;
  final IconData? icon;

  const StreamingInfoChip({super.key, required this.label, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: ThemeColors.surfaceVariant(context),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: ThemeColors.secondaryText(context)),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: ThemeColors.secondaryText(context),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
