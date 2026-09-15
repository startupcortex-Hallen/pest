import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class ThemeColors {
  static Color background(BuildContext c) =>
      Theme.of(c).scaffoldBackgroundColor;
  static Color surface(BuildContext c) =>
      Theme.of(c).colorScheme.surface;
  static Color primary(BuildContext c) =>
      Theme.of(c).colorScheme.primary;
  static Color onPrimary(BuildContext c) =>
      Theme.of(c).colorScheme.onPrimary;
  static Color secondary(BuildContext c) =>
      Theme.of(c).colorScheme.secondary;
  static Color error(BuildContext c) =>
      Theme.of(c).colorScheme.error;
  static Color onError(BuildContext c) =>
      Theme.of(c).colorScheme.onError;
  static Color surfaceVariant(BuildContext c) =>
      Theme.of(c).colorScheme.surfaceContainerHighest;
  static Color onSurfaceVariant(BuildContext c) =>
      Theme.of(c).colorScheme.onSurfaceVariant;
  static Color outline(BuildContext c) =>
      Theme.of(c).colorScheme.outline;
  static Color hint(BuildContext c) =>
      Theme.of(c).colorScheme.onSurface.withValues(alpha: 0.5);
  static Color divider(BuildContext c) =>
      Theme.of(c).dividerTheme.color ?? AppColors.darkDivider;
  static Color primaryText(BuildContext c) =>
      Theme.of(c).textTheme.bodyLarge?.color ?? AppColors.primaryText;
  static Color secondaryText(BuildContext c) =>
      Theme.of(c).colorScheme.onSurfaceVariant;
  static Color success(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark
          ? AppColors.darkSuccess
          : AppColors.success;
  static Color warning(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark
          ? AppColors.darkWarning
          : AppColors.warning;
  static Color info(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark
          ? AppColors.darkInfo
          : AppColors.info;
  static Color accent(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark
          ? AppColors.darkAccent
          : AppColors.accent;
}
