import 'dart:ui';

// TODO 下面的代码其实没有意义
const int _opacity08 = 20;
const int _opacity10 = 25;
const int _opacity15 = 38;
const int _opacity20 = 51;
const int _opacity40 = 102;
const int _opacity60 = 153;
const int _opacity80 = 204;

extension ColorExtension on Color {
  Color opacity(double opacity) {
    return withAlpha((opacity * 255).toInt());
  }

  /// Flutter 废弃了 withOpacity，但实际上，UI 中还是使用比例来表示透明度
  /// 但是我不希望会有代码上的警告
  /// Flutter 不能从
  /// ```dart
  /// Color withOpacity(double opacity) {
  ///   assert(opacity >= 0.0 && opacity <= 1.0);
  ///   return withAlpha((255.0 * opacity).round());
  /// }
  /// ```
  /// 改成
  /// ```dart
  /// Color withOpacity(double o) {
  ///   return Color.from(
  ///     alpha: o,
  ///     red: r,
  ///     green: g,
  ///     blue: b,
  ///     colorSpace: colorSpace,
  ///   );
  /// }
  /// ```
  /// 的原因大概是，这会改变原本代码中得到的值
  Color withOpacityExact(double o) {
    return Color.from(alpha: o, red: r, green: g, blue: b, colorSpace: colorSpace);
  }

  @Deprecated('Use withOpacityExact(double o) instead')
  Color get opacity08 {
    return withAlpha(_opacity08);
  }

  @Deprecated('Use withOpacityExact(double o) instead')
  Color get opacity10 {
    return withAlpha(_opacity10);
  }

  @Deprecated('Use withOpacityExact(double o) instead')
  Color get opacity15 {
    return withAlpha(_opacity15);
  }

  @Deprecated('Use withOpacityExact(double o) instead')
  Color get opacity20 {
    return withAlpha(_opacity20);
  }

  @Deprecated('Use withOpacityExact(double o) instead')
  Color get opacity40 {
    return withAlpha(_opacity40);
  }

  @Deprecated('Use withOpacityExact(double o) instead')
  Color get opacity60 {
    return withAlpha(_opacity60);
  }

  @Deprecated('Use withOpacityExact(double o) instead')
  Color get opacity80 {
    return withAlpha(_opacity80);
  }
}
