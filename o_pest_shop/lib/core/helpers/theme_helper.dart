import 'package:flutter/material.dart';

class ThemeHelper {
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color surface(BuildContext context) =>
      Theme.of(context).colorScheme.surface;

  static Color primary(BuildContext context) =>
      Theme.of(context).colorScheme.primary;

  static Color onSurface(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface;

  static Color surfaceVariant(BuildContext context) =>
      Theme.of(context).colorScheme.surfaceContainerHighest;

  static Color onSurfaceVariant(BuildContext context) =>
      Theme.of(context).colorScheme.onSurfaceVariant;

  static Color secondaryText(BuildContext context) =>
      Theme.of(context).colorScheme.onSurfaceVariant;

  static Color hint(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5);

  static Color outline(BuildContext context) =>
      Theme.of(context).colorScheme.outline;
}
