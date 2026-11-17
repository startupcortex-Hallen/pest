import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/helpers/scale_helper.dart';
import '../../core/helpers/theme_colors.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

class BannerCarousel extends StatefulWidget {
  final List<Map<String, dynamic>> banners;
  final ValueChanged<Map<String, dynamic>>? onTap;
  final Duration interval;

  const BannerCarousel({
    super.key,
    required this.banners,
    this.onTap,
    this.interval = const Duration(seconds: 5),
  });

  @override
  State<BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<BannerCarousel>
    with WidgetsBindingObserver {
  static const int _kLoopMultiplier = 1000;
  static const double _kViewportFraction = 0.9;
  static const Duration _kTransitionDuration = Duration(milliseconds: 650);
  static const Duration _kResumeDelay = Duration(seconds: 4);

  late PageController _pageController;
  Timer? _autoPlayTimer;
  Timer? _resumeTimer;
  int _currentIndex = 0;
  bool _isUserInteracting = false;
  bool _isAppInForeground = true;
  bool _reduceAnimations = false;

  bool get _canLoop => widget.banners.length > 1;

  int get _initialPage =>
      _canLoop ? widget.banners.length * (_kLoopMultiplier ~/ 2) : 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reduceAnimations != disableAnimations) {
      _reduceAnimations = disableAnimations;
      if (_reduceAnimations) {
        _stopAutoPlay();
      } else {
        _startAutoPlay();
      }
    }
  }

  @override
  void didUpdateWidget(covariant BannerCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameBanners(oldWidget.banners, widget.banners) ||
        oldWidget.interval != widget.interval) {
      _stopAutoPlay();
      _pageController.dispose();
      _initController();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final inForeground = state == AppLifecycleState.resumed;
    if (_isAppInForeground == inForeground) return;
    _isAppInForeground = inForeground;
    if (_isAppInForeground) {
      _scheduleAutoPlayResume();
    } else {
      _stopAutoPlay();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopAutoPlay();
    _pageController.dispose();
    super.dispose();
  }

  void _initController() {
    _currentIndex = 0;
    _pageController = PageController(
      viewportFraction: _kViewportFraction,
      initialPage: _initialPage,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startAutoPlay();
    });
  }

  bool _sameBanners(
    List<Map<String, dynamic>> a,
    List<Map<String, dynamic>> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i]['id'] != b[i]['id'] ||
          a[i]['imagem_url'] != b[i]['imagem_url'] ||
          a[i]['titulo'] != b[i]['titulo'] ||
          a[i]['link_url'] != b[i]['link_url']) {
        return false;
      }
    }
    return true;
  }

  void _startAutoPlay() {
    _autoPlayTimer?.cancel();
    _resumeTimer?.cancel();
    if (!_canLoop ||
        _reduceAnimations ||
        !_isAppInForeground ||
        _isUserInteracting) {
      return;
    }
    _autoPlayTimer = Timer.periodic(widget.interval, (_) {
      if (!mounted ||
          !_pageController.hasClients ||
          _isUserInteracting ||
          !_isAppInForeground ||
          _reduceAnimations) {
        return;
      }
      _pageController.nextPage(
        duration: _kTransitionDuration,
        curve: Curves.easeInOutCubic,
      );
    });
  }

  void _stopAutoPlay() {
    _autoPlayTimer?.cancel();
    _autoPlayTimer = null;
    _resumeTimer?.cancel();
    _resumeTimer = null;
  }

  void _pauseForInteraction() {
    _isUserInteracting = true;
    _stopAutoPlay();
  }

  void _scheduleAutoPlayResume() {
    _isUserInteracting = false;
    _autoPlayTimer?.cancel();
    _resumeTimer?.cancel();
    if (!_canLoop || _reduceAnimations || !_isAppInForeground) return;
    _resumeTimer = Timer(_kResumeDelay, () {
      if (mounted) _startAutoPlay();
    });
  }

  @override
  Widget build(BuildContext context) {
    final banners = widget.banners;
    if (banners.isEmpty) return const SizedBox.shrink();

    final cardHeight = context.h(184).clamp(156.0, 220.0);
    final totalItems = _canLoop ? banners.length * _kLoopMultiplier : 1;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: cardHeight,
              child: Listener(
                onPointerDown: (_) => _pauseForInteraction(),
                onPointerUp: (_) => _scheduleAutoPlayResume(),
                onPointerCancel: (_) => _scheduleAutoPlayResume(),
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is ScrollStartNotification &&
                        notification.dragDetails != null) {
                      _pauseForInteraction();
                    } else if (notification is ScrollEndNotification) {
                      _scheduleAutoPlayResume();
                    }
                    return false;
                  },
                  child: PageView.builder(
                    controller: _pageController,
                    physics: _canLoop
                        ? const BouncingScrollPhysics()
                        : const NeverScrollableScrollPhysics(),
                    itemCount: totalItems,
                    onPageChanged: (page) {
                      final next = page % banners.length;
                      if (_currentIndex != next && mounted) {
                        setState(() => _currentIndex = next);
                      }
                    },
                    itemBuilder: (context, index) {
                      final realIndex = index % banners.length;
                      final banner = banners[realIndex];
                      return _buildCubePage(
                        context,
                        index: index,
                        realIndex: realIndex,
                        total: banners.length,
                        banner: banner,
                      );
                    },
                  ),
                ),
              ),
            ),
            if (_canLoop) ...[
              const SizedBox(height: 12),
              _buildDotsIndicator(banners.length),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCubePage(
    BuildContext context, {
    required int index,
    required int realIndex,
    required int total,
    required Map<String, dynamic> banner,
  }) {
    return AnimatedBuilder(
      animation: _pageController,
      builder: (context, child) {
        double page = _initialPage.toDouble();
        if (_pageController.hasClients &&
            _pageController.position.hasContentDimensions) {
          page = _pageController.page ??
              _pageController.initialPage.toDouble();
        }
        final delta = (index - page).clamp(-1.0, 1.0);
        final absDelta = delta.abs();

        if (_reduceAnimations) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: child,
          );
        }

        // Rotação 3D estilo cubo com pivô na borda interna entre os cards
        final maxAngle = math.pi / 3.2; // ~56°
        final angle = delta * maxAngle;
        final scale = 1.0 - (0.07 * absDelta);
        final pivot =
            delta <= 0 ? Alignment.centerRight : Alignment.centerLeft;
        final shadeOpacity = (absDelta * 0.45).clamp(0.0, 0.45);

        final matrix = Matrix4.identity()
          ..setEntry(3, 2, 0.0015)
          ..rotateY(angle)
          ..scaleByDouble(scale, scale, 1.0, 1.0);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Transform(
            alignment: pivot,
            transform: matrix,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: (0.42 * (1.0 - absDelta * 0.5)).clamp(0.15, 0.45),
                    ),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    child!,
                    if (shadeOpacity > 0.01)
                      IgnorePointer(
                        child: ColoredBox(
                          color: Colors.black.withValues(alpha: shadeOpacity),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      child: _buildBannerCard(
        context,
        banner: banner,
        realIndex: realIndex,
        total: total,
      ),
    );
  }

  Widget _buildBannerCard(
    BuildContext context, {
    required Map<String, dynamic> banner,
    required int realIndex,
    required int total,
  }) {
    final titulo = (banner['titulo'] as String?)?.trim() ?? '';
    final imagemUrl = (banner['imagem_url'] as String?)?.trim() ?? '';
    final linkUrl = (banner['link_url'] as String?)?.trim() ?? '';
    final hasLink = linkUrl.isNotEmpty;
    final semanticsLabel = titulo.isNotEmpty
        ? 'Banner ${realIndex + 1} de $total: $titulo'
        : 'Banner ${realIndex + 1} de $total';

    return Semantics(
      label: semanticsLabel,
      button: hasLink || widget.onTap != null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Material(
          color: ThemeColors.surfaceVariant(context),
          child: InkWell(
            onTap: widget.onTap != null ? () => widget.onTap!(banner) : null,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (imagemUrl.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: imagemUrl,
                    fit: BoxFit.cover,
                    fadeInDuration: const Duration(milliseconds: 220),
                    placeholder: (_, _) => _buildImagePlaceholder(context),
                    errorWidget: (_, _, _) => _buildImageFallback(context),
                  )
                else
                  _buildImageFallback(context),
                // Gradiente escuro para leitura nítida do texto e selo
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.45, 1.0],
                        colors: [
                          Colors.black.withValues(alpha: 0.25),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.88),
                        ],
                      ),
                    ),
                  ),
                ),
                // Selo "DESTAQUE" no topo esquerdo
                Positioned(
                  top: 14,
                  left: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Text(
                      'DESTAQUE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),
                // Rodapé com título e CTA
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 14,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: titulo.isNotEmpty
                            ? Text(
                                titulo,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  height: 1.2,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              )
                            : const SizedBox.shrink(),
                      ),
                      if (hasLink) ...[
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(AppRadius.full),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.32),
                            ),
                          ),
                          child: const Text(
                            'Ver oferta →',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImagePlaceholder(BuildContext context) {
    return Container(
      color: ThemeColors.surfaceVariant(context),
      alignment: Alignment.center,
      child: SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.primary.withValues(alpha: 0.7),
        ),
      ),
    );
  }

  Widget _buildImageFallback(BuildContext context) {
    return Container(
      color: ThemeColors.surfaceVariant(context),
      alignment: Alignment.center,
      child: Icon(
        Icons.image_not_supported_rounded,
        color: ThemeColors.hint(context),
        size: 36,
      ),
    );
  }

  Widget _buildDotsIndicator(int count) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (index) {
        final isActive = index == _currentIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: isActive ? 22 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.primary
                : Colors.white.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
        );
      }),
    );
  }
}
