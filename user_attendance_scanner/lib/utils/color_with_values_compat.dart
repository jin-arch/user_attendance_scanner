import 'package:flutter/material.dart';

/// Compatibility shim for older Flutter versions that don't have `Color.withValues`.
///
/// This project uses `color.withValues(alpha: x)` in multiple places.
/// On older SDKs, use `withOpacity` instead.
extension ColorWithValuesCompat on Color {
  Color withValues({double? alpha}) {
    if (alpha == null) return this;
    final int a = (alpha * 255).round().clamp(0, 255).toInt();
    return withAlpha(a);
  }
}
