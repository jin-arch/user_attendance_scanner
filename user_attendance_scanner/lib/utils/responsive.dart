import 'package:flutter/material.dart';

/// Clamped responsive sizing to avoid pixel overflow on small/large devices.
class R {
  R._();

  static Size sizeOf(BuildContext context) => MediaQuery.sizeOf(context);

  static bool isNarrow(BuildContext context) => sizeOf(context).width < 720;

  static double wp(
    BuildContext context,
    double fraction, {
    double min = 8,
    double max = 9999,
  }) {
    final value = sizeOf(context).width * fraction;
    return value.clamp(min, max);
  }

  static double hp(
    BuildContext context,
    double fraction, {
    double min = 8,
    double max = 9999,
  }) {
    final value = sizeOf(context).height * fraction;
    return value.clamp(min, max);
  }

  static double font(
    BuildContext context,
    double fraction, {
    double min = 10,
    double max = 28,
  }) =>
      wp(context, fraction, min: min, max: max);

  static EdgeInsets screenPadding(BuildContext context) {
    final s = wp(context, 0.02, min: 8, max: 24);
    return EdgeInsets.all(s);
  }

  /// Primary action button with safe text scaling.
  static Widget primaryButton({
    required BuildContext context,
    required String label,
    required VoidCallback? onTap,
    Color background = const Color(0xFF3E7DDD),
    bool isLoading = false,
  }) {
    final vertical = hp(context, 0.018, min: 12, max: 22);
    final radius = wp(context, 0.012, min: 8, max: 16);
    final fontSize = font(context, 0.014, min: 11, max: 16);

    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: vertical, horizontal: 12),
        decoration: BoxDecoration(
          color: isLoading ? Colors.grey : background,
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Center(
          child: isLoading
              ? SizedBox(
                  width: fontSize + 4,
                  height: fontSize + 4,
                  child: const CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      fontFamily: 'CEORUSE',
                      fontSize: fontSize,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
