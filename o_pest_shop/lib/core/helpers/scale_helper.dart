import 'package:flutter/material.dart';

class ScaleHelper {
  ScaleHelper._();

  static const double _baseWidth = 390;
  static const double _baseHeight = 844;
  static const double _minScale = 0.75;
  static const double _maxScale = 1.25;

  static double scaleW(BuildContext c) =>
      (MediaQuery.of(c).size.width / _baseWidth).clamp(_minScale, _maxScale);

  static double scaleH(BuildContext c) =>
      (MediaQuery.of(c).size.height / _baseHeight).clamp(_minScale, _maxScale);

  static double w(BuildContext c, double v) => v * scaleW(c);

  static double h(BuildContext c, double v) => v * scaleH(c);

  static double sp(BuildContext c, double v) =>
      v * scaleW(c) * MediaQuery.of(c).textScaleFactor;

  static double clamp(double value, double min, double max) =>
      value.clamp(min, max);
}

extension ResponsiveContext on BuildContext {
  double get scaleW => ScaleHelper.scaleW(this);
  double get scaleH => ScaleHelper.scaleH(this);
  double w(double v) => ScaleHelper.w(this, v);
  double h(double v) => ScaleHelper.h(this, v);
  double sp(double v) => ScaleHelper.sp(this, v);
}
