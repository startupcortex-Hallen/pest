import 'package:flutter/material.dart';
import '../../core/helpers/scale_helper.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

class AppTopBar extends StatelessWidget {
  final VoidCallback? onMenuTap;
  final Widget? middleWidget;
  final Widget? bottomWidget;

  const AppTopBar({
    super.key,
    this.onMenuTap,
    this.middleWidget,
    this.bottomWidget,
  });

  factory AppTopBar.withSearch({
    required VoidCallback onMenuTap,
    required VoidCallback onSearchTap,
    Widget? bottomWidget,
  }) {
    return AppTopBar(
      onMenuTap: onMenuTap,
      middleWidget: _SearchBar(onTap: onSearchTap),
      bottomWidget: bottomWidget,
    );
  }

  factory AppTopBar.withTitle({
    required VoidCallback onMenuTap,
    required String title,
    required String subtitle,
    Widget? bottomWidget,
  }) {
    return AppTopBar(
      onMenuTap: onMenuTap,
      middleWidget: _TitleBlock(title: title, subtitle: subtitle),
      bottomWidget: bottomWidget,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.only(
        bottomLeft: Radius.circular(AppRadius.rXl(context)),
        bottomRight: Radius.circular(AppRadius.rXl(context)),
      ),
      child: Container(
        color: const Color(0xFF0A0A0A),
        child: SafeArea(
          bottom: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                    context.w(AppSpacing.sm), context.w(AppSpacing.lg), AppSpacing.md, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.menu_rounded,
                          color: AppColors.onPrimary,
                          size: context.sp(20).clamp(18.0, 30.0)),
                      onPressed: onMenuTap,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    SizedBox(width: context.w(AppSpacing.sm)),
                    Expanded(child: middleWidget ?? const SizedBox()),
                    SizedBox(width: context.w(AppSpacing.sm)),
                    SizedBox(
                      width: context.w(64).clamp(48.0, 80.0),
                      height: context.w(64).clamp(48.0, 80.0),
                      child: Image.asset(
                        'assets/logo.jpg',
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.storefront_rounded,
                          color: AppColors.onPrimary,
                          size: context.sp(32).clamp(28.0, 44.0),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (bottomWidget != null) ...[
                SizedBox(height: context.h(AppSpacing.sm)),
                bottomWidget!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final VoidCallback onTap;
  const _SearchBar({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: context.h(40).clamp(32.0, 52.0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.full),
        child: Row(
          children: [
            SizedBox(width: context.w(AppSpacing.md)),
            Icon(Icons.search_rounded, color: AppColors.hint,
                size: context.sp(18).clamp(16.0, 24.0)),
            SizedBox(width: context.w(AppSpacing.sm)),
            Flexible(
              child: Text(
                'Buscar produtos, novidades e mais',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.hint),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  final String title;
  final String subtitle;
  const _TitleBlock({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .headlineMedium
              ?.copyWith(
                  fontSize: context.sp(22),
                  color: AppColors.onPrimary, fontWeight: FontWeight.w900),
        ),
        Text(
          subtitle,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: AppColors.onPrimary.withValues(alpha: 0.8)),
        ),
      ],
    );
  }
}
