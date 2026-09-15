import 'package:flutter/material.dart';
import '../helpers/scale_helper.dart';

class AppSpacing {
  AppSpacing._();

  static const double none = 0;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
  static const double xxxl = 64;

  static double wSm(BuildContext c) => ScaleHelper.w(c, sm);
  static double wMd(BuildContext c) => ScaleHelper.w(c, md);
  static double wLg(BuildContext c) => ScaleHelper.w(c, lg);
  static double wXl(BuildContext c) => ScaleHelper.w(c, xl);

  static double hSm(BuildContext c) => ScaleHelper.h(c, sm);
  static double hMd(BuildContext c) => ScaleHelper.h(c, md);
  static double hLg(BuildContext c) => ScaleHelper.h(c, lg);
  static double hXl(BuildContext c) => ScaleHelper.h(c, xl);
}

class AppRadius {
  AppRadius._();

  static const double none = 0;
  static const double xs = 2;
  static const double sm = 4;
  static const double md = 8;
  static const double lg = 12;
  static const double xl = 20;
  static const double xxl = 32;
  static const double full = 9999;

  static double rMd(BuildContext c) => ScaleHelper.w(c, md);
  static double rLg(BuildContext c) => ScaleHelper.w(c, lg);
  static double rXl(BuildContext c) => ScaleHelper.w(c, xl);
  static double rSm(BuildContext c) => ScaleHelper.w(c, sm);
}

class AppShadows {
  AppShadows._();

  static List<BoxShadow> none = const [];
  static List<BoxShadow> xs = [
    BoxShadow(
      color: Color(0x0D000000),
      offset: Offset(0, 1),
      blurRadius: 2,
    ),
  ];
  static List<BoxShadow> sm = [
    BoxShadow(
      color: Color(0x14000000),
      offset: Offset(0, 2),
      blurRadius: 4,
    ),
  ];
  static List<BoxShadow> md = [
    BoxShadow(
      color: Color(0x1A000000),
      offset: Offset(0, 4),
      blurRadius: 8,
    ),
  ];
  static List<BoxShadow> lg = [
    BoxShadow(
      color: Color(0x21000000),
      offset: Offset(0, 8),
      blurRadius: 16,
    ),
  ];
  static List<BoxShadow> xl = [
    BoxShadow(
      color: Color(0x29000000),
      offset: Offset(0, 12),
      blurRadius: 24,
    ),
  ];
  static List<BoxShadow> xxl = [
    BoxShadow(
      color: Color(0x33000000),
      offset: Offset(0, 20),
      blurRadius: 40,
    ),
  ];
}
