import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../animations/rising_fade_particle.dart';
import '../controllers/loading_page_controller.dart';

/// Full-screen loading UI: dark blue rounded container, particles,
/// centered fingerprint, progress % top-left, "DOWNLOADING RESOURCES..." bottom-right.
/// Pops when [loadFuture] completes and progress reaches 100%, then calls [onComplete].
class LoadingPage extends StatelessWidget {
  const LoadingPage({
    super.key,
    this.loadFuture,
    this.onComplete,
    this.progressListenable,
  });

  final Future<void>? loadFuture;
  final VoidCallback? onComplete;
  final ValueListenable<double>? progressListenable;

  static const String _particleAsset = 'assets/icons/square-particles-fx.svg';
  static const String _fingerprintAsset =
      'assets/images/HIRSLogo-default.png';

  @override
  Widget build(BuildContext context) {
    return GetBuilder<LoadingPageController>(
      init: LoadingPageController(
        loadFuture: loadFuture,
        progressListenable: progressListenable,
        onFinish: () {
          Navigator.of(context).pop();
          onComplete?.call();
        },
      ),
      builder: (controller) {
        final size = MediaQuery.sizeOf(context);
        final viewportW = size.width;
        final viewportH = size.height;
        final padding = EdgeInsets.symmetric(
          horizontal: viewportW * 0.02,
          vertical: viewportH * 0.02,
        );

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/images/Main BG.png'),
                fit: BoxFit.cover,
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: padding,
                child: Center(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 400),
                    builder: (context, value, child) => Opacity(
                      opacity: value,
                      child: child,
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final maxW = constraints.maxWidth;
                        final maxH = constraints.maxHeight;
                        final edgeInset = (viewportW * 0.02).clamp(12.0, 24.0).toDouble();
                        final availableW = (maxW - (edgeInset * 2)).clamp(0.0, maxW).toDouble();
                        final cardWByHeight = maxH * (16 / 9);
                        final cardW = cardWByHeight < availableW ? cardWByHeight : availableW;
                        final cardH = cardW * (9 / 16);

                        // Asymmetric radius matching HomePage card style:
                        // large top-left, small on the other three corners.
                        final radius = BorderRadius.only(
                          topLeft: Radius.circular(
                            (cardW * 0.08).clamp(36.0, 92.0),
                          ),
                          topRight: Radius.circular(
                            (cardW * 0.015).clamp(8.0, 20.0),
                          ),
                          bottomLeft: Radius.circular(
                            (cardW * 0.015).clamp(8.0, 20.0),
                          ),
                          bottomRight: Radius.circular(
                            (cardW * 0.015).clamp(8.0, 20.0),
                          ),
                        );

                        return SizedBox(
                          width: cardW,
                          height: cardH,
                          child: ClipPath(
                            clipper: _AsymmetricCardClipper(radius: radius),
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: Image.asset(
                                    'assets/images/cardmodified123.png',
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned.fill(
                                  child: LayoutBuilder(
                                    builder: (context, cardConstraints) {
                                      final cw = cardConstraints.maxWidth;
                                      final ch = cardConstraints.maxHeight;
                                      final ps = (cw * 0.045).clamp(20.0, 52.0);

                                      return Stack(
                                        children: [
                                          _particle(cw, ch, 0.08, 0.15, ps * 1.2, 0),
                                          _particle(cw, ch, 0.12, 0.08, ps * 0.5, 0.3),
                                          _particle(cw, ch, 0.18, 0.5, ps * 0.9, 0.6),
                                          _particle(cw, ch, 0.75, 0.45, ps * 1.1, 0.2),
                                          _particle(cw, ch, 0.5, 0.2, ps * 0.55, 0.5),
                                          _particle(cw, ch, 0.08, 0.7, ps * 1.0, 0.8),
                                          _particle(cw, ch, 0.28, 0.35, ps * 0.45, 0.15),
                                          _particle(cw, ch, 0.72, 0.3, ps * 0.9, 0.45),
                                          _particle(cw, ch, 0.38, 0.78, ps * 0.6, 0.7),
                                          _particle(cw, ch, 0.88, 0.6, ps * 1.15, 0.25),
                                          _particle(cw, ch, 0.05, 0.42, ps * 0.5, 0.9),
                                          _particle(cw, ch, 0.62, 0.48, ps * 0.75, 0.35),
                                          Center(
                                            child: Padding(
                                              padding: EdgeInsets.only(bottom: ch * 0.15),
                                              child: Image.asset(
                                                _fingerprintAsset,
                                                width: cw * 0.24,
                                                height: ch * 0.36,
                                                fit: BoxFit.contain,
                                              ),
                                            ),
                                          ),
                                          Positioned(
                                            left: cw * 0.07,
                                            top: ch * 0.015,
                                            child: _ProgressText(
                                              progress: controller.progress,
                                              fontSize: (cw * 0.055).clamp(28.0, 56.0),
                                            ),
                                          ),
                                          Positioned(
                                            right: cw * 0.028,
                                            bottom: ch * 0.03,
                                            child: _DownloadingLabel(
                                              fontSize: (cw * 0.022).clamp(12.0, 26.0),
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _particle(
    double w,
    double h,
    double fracLeft,
    double fracTop,
    double sizePx,
    double phase,
  ) {
    return Positioned(
      left: w * fracLeft - sizePx / 2,
      top: h * fracTop - sizePx / 2,
      width: sizePx,
      height: sizePx,
      child: RisingFadeParticle(
        size: sizePx,
        phase: phase,
        assetPath: _particleAsset,
      ),
    );
  }
}

class _ProgressText extends StatelessWidget {
  const _ProgressText({required this.progress, this.fontSize = 25});

  final int progress;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$progress%',
      style: const TextStyle(
        fontFamily: 'CEORUSE',
        fontSize: 35,
        fontWeight: FontWeight.bold,
        color: Colors.white,
        letterSpacing: 2,
      ).copyWith(fontSize: fontSize),
    );
  }
}

class _DownloadingLabel extends StatelessWidget {
  const _DownloadingLabel({this.fontSize = 50});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      'DOWNLOADING\nRESOURCES...',
      style: TextStyle(
        fontFamily: 'CEORUSE',
        fontSize: 50,
        fontWeight: FontWeight.bold,
        color: Colors.white.withValues(alpha: 0.95),
        letterSpacing: 2,
      ),
    );
  }
}

class _AsymmetricCardClipper extends CustomClipper<Path> {
  const _AsymmetricCardClipper({required this.radius});

  final BorderRadius radius;

  @override
  Path getClip(Size size) {
    final resolved = radius.resolve(TextDirection.ltr);
    final rrect = resolved.toRRect(Offset.zero & size);
    return Path()..addRRect(rrect);
  }

  @override
  bool shouldReclip(covariant _AsymmetricCardClipper oldClipper) {
    return oldClipper.radius != radius;
  }
}