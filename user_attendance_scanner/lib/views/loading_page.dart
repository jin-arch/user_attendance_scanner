import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';

import '../controllers/loading_page_controller.dart';
part '../animations/loading_rising_fade_particle_widget.dart';

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
  static const String _fingerprintAsset = 'assets/images/HIRSLogo-default.png';

  @override
  Widget build(BuildContext context) {
    return GetBuilder<LoadingPageController>(
        init: LoadingPageController(
          loadFuture: loadFuture,
          progressListenable: progressListenable,
          onFinish: () {
            Get.back<void>();
            onComplete?.call();
          },
        ),
      global: false,
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
                    builder: (context, value, child) =>
                        Opacity(opacity: value, child: child),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final maxW = constraints.maxWidth;
                        final maxH = constraints.maxHeight;
                        final cardWByHeight = maxH * (16 / 9);
                        final cardW = cardWByHeight < maxW
                            ? cardWByHeight
                            : maxW;
                        final cardH = cardW * (9 / 16);
                        final radius = BorderRadius.circular(
                          (cardW * 0.08).clamp(36.0, 92.0),
                        );

                        return SizedBox(
                          width: cardW,
                          height: cardH,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: radius,
                              image: const DecorationImage(
                                image: AssetImage(
                                  'assets/images/cardmodified123.png',
                                ),
                                fit: BoxFit.cover,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: radius,
                              clipBehavior: Clip.antiAlias,
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: LayoutBuilder(
                                      builder: (context, cardConstraints) {
                                        final cw = cardConstraints.maxWidth;
                                        final ch = cardConstraints.maxHeight;
                                        final ps = (cw * 0.045).clamp(
                                          20.0,
                                          52.0,
                                        );

                                        return Stack(
                                          children: [
                                            _particle(
                                              cw,
                                              ch,
                                              0.08,
                                              0.15,
                                              ps * 1.2,
                                              0,
                                            ),
                                            _particle(
                                              cw,
                                              ch,
                                              0.12,
                                              0.08,
                                              ps * 0.5,
                                              0.3,
                                            ),
                                            _particle(
                                              cw,
                                              ch,
                                              0.18,
                                              0.5,
                                              ps * 0.9,
                                              0.6,
                                            ),
                                            _particle(
                                              cw,
                                              ch,
                                              0.75,
                                              0.45,
                                              ps * 1.1,
                                              0.2,
                                            ),
                                            _particle(
                                              cw,
                                              ch,
                                              0.5,
                                              0.2,
                                              ps * 0.55,
                                              0.5,
                                            ),
                                            _particle(
                                              cw,
                                              ch,
                                              0.08,
                                              0.7,
                                              ps * 1.0,
                                              0.8,
                                            ),
                                            _particle(
                                              cw,
                                              ch,
                                              0.28,
                                              0.35,
                                              ps * 0.45,
                                              0.15,
                                            ),
                                            _particle(
                                              cw,
                                              ch,
                                              0.72,
                                              0.3,
                                              ps * 0.9,
                                              0.45,
                                            ),
                                            _particle(
                                              cw,
                                              ch,
                                              0.38,
                                              0.78,
                                              ps * 0.6,
                                              0.7,
                                            ),
                                            _particle(
                                              cw,
                                              ch,
                                              0.88,
                                              0.6,
                                              ps * 1.15,
                                              0.25,
                                            ),
                                            _particle(
                                              cw,
                                              ch,
                                              0.05,
                                              0.42,
                                              ps * 0.5,
                                              0.9,
                                            ),
                                            _particle(
                                              cw,
                                              ch,
                                              0.62,
                                              0.48,
                                              ps * 0.75,
                                              0.35,
                                            ),
                                            Center(
                                              child: Padding(
                                                padding: EdgeInsets.only(
                                                  bottom: ch * 0.05,
                                                ),
                                                child: Image.asset(
                                                  _fingerprintAsset,
                                                  width: cw * 0.24,
                                                  height: ch * 0.36,
                                                  fit: BoxFit.contain,
                                                ),
                                              ),
                                            ),
                                            Positioned(
                                              left: cw * 0.1,
                                              top: ch * 0.02,
                                              child: _ProgressText(
                                                progress: controller.progress,
                                                fontSize: (cw * 0.055).clamp(
                                                  28.0,
                                                  56.0,
                                                ),
                                              ),
                                            ),
                                            Positioned(
                                              right: cw * 0.038,
                                              bottom: ch * 0.04,
                                              child: _DownloadingLabel(
                                                fontSize: (cw * 0.022).clamp(
                                                  12.0,
                                                  26.0,
                                                ),
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
      child: _RisingFadeParticle(
        size: sizePx,
        phase: phase,
        assetPath: _particleAsset,
      ),
    );
  }
}

class _ProgressText extends StatelessWidget {
  const _ProgressText({required this.progress, this.fontSize = 32});

  final int progress;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$progress%',
      style: const TextStyle(
        fontFamily: 'CEORUSE',
        fontSize: 40,
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
        fontSize: 52,
        fontWeight: FontWeight.bold,
        color: Colors.white.withValues(alpha: 0.95),
        letterSpacing: 2,
      ),
    );
  }
}

class _RisingFadeParticleState extends State<_RisingFadeParticle>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _opacity;
  Animation<double>? _translateY;
  Animation<double>? _scale;

  static const double _riseDistance = 48.0;
  static const Duration _duration = Duration(milliseconds: 2600);

  @override
  void initState() {
    super.initState();
    final c = AnimationController(vsync: this, duration: _duration);
    final curve = CurvedAnimation(parent: c, curve: Curves.easeOut);
    _controller = c;
    _opacity = Tween<double>(begin: 0.7, end: 0.0).animate(curve);
    _translateY = Tween<double>(begin: 0.0, end: -_riseDistance).animate(curve);
    _scale = Tween<double>(begin: 1.0, end: 0.8).animate(curve);
    c.value = widget.phase;
    c.repeat();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final opacity = _opacity;
    final translateY = _translateY;
    final scale = _scale;
    if (c == null || opacity == null || translateY == null || scale == null) {
      return const SizedBox.shrink();
    }
    return AnimatedBuilder(
      animation: c,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, translateY.value),
          child: Opacity(
            opacity: opacity.value,
            child: Transform.scale(
              scale: scale.value,
              alignment: Alignment.center,
              child: SvgPicture.asset(
                widget.assetPath,
                width: widget.size,
                height: widget.size,
                fit: BoxFit.contain,
                colorFilter: const ColorFilter.mode(
                  Color(0xFF5FCFFF),
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
