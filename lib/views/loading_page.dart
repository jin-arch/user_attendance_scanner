import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Full-screen loading UI: dark blue rounded container, particles,
/// centered fingerprint, progress % top-left, "DOWNLOADING RESOURCES..." bottom-right.
/// Pops when [loadFuture] completes and progress reaches 100%.
class LoadingPage extends StatefulWidget {
  const LoadingPage({
    super.key,
    required this.loadFuture,
  });

  final Future<void> loadFuture;

  @override
  State<LoadingPage> createState() => _LoadingPageState();
}

class _LoadingPageState extends State<LoadingPage>
    with SingleTickerProviderStateMixin {
  int _progress = 0;
  bool _loadComplete = false;
  late AnimationController _progressController;

  static const String _particleAsset = 'assets/icons/square-particles-fx.svg';
  static const String _fingerprintAsset =
      'assets/images/Finger Print Icon.png';

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..addListener(() {
        if (!mounted) return;
        setState(() {
          _progress = (_progressController.value * 100).round().clamp(0, 100);
        });
      });
    _progressController.forward();

    unawaited(_run());
  }

  Future<void> _run() async {
    try {
      await widget.loadFuture;
    } catch (e) {
      debugPrint('LoadingPage loadFuture error: $e');
    }
    if (!mounted) return;
    setState(() => _loadComplete = true);
    if (_progressController.value < 1.0) {
      _progressController.animateTo(1.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut);
    }
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;
    final padding = EdgeInsets.symmetric(
      horizontal: w * 0.04,
      vertical: h * 0.04,
    );
    final borderRadius = BorderRadius.circular(w * 0.04);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: padding,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 400),
            builder: (context, value, child) => Opacity(
              opacity: value,
              child: child,
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                border: Border.all(
                  color: const Color(0xFF4A90B8).withValues(alpha: 0.5),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 12,
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: borderRadius,
                child: Stack(
                  children: [
                    // Gradient background
                    Positioned.fill(
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0xFF1A3A52),
                              Color(0xFF234A6B),
                              Color(0xFF1A3A52),
                            ],
                            stops: [0.0, 0.5, 1.0],
                          ),
                        ),
                      ),
                    ),
                    // Particles
                    Positioned.fill(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final cw = constraints.maxWidth;
                          final ch = constraints.maxHeight;
                          final ps = (cw * 0.06).clamp(32.0, 56.0);
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
                            ],
                          );
                        },
                      ),
                    ),
                    // Fingerprint — center, slightly above middle
                    Center(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: h * 0.08),
                        child: Image.asset(
                          _fingerprintAsset,
                          width: w * 0.22,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    // Progress % — top-left
                    Positioned(
                      left: w * 0.04,
                      top: h * 0.04,
                      child: _ProgressText(progress: _progress),
                    ),
                    // "DOWNLOADING RESOURCES..." — bottom-right
                    Positioned(
                      right: w * 0.04,
                      bottom: h * 0.04,
                      child: const _DownloadingLabel(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
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
  const _ProgressText({required this.progress});

  final int progress;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$progress%',
      style: const TextStyle(
        fontFamily: 'CEORUSE',
        fontSize: 32,
        fontWeight: FontWeight.bold,
        color: Colors.white,
        letterSpacing: 2,
      ),
    );
  }
}

class _DownloadingLabel extends StatelessWidget {
  const _DownloadingLabel();

  @override
  Widget build(BuildContext context) {
    return Text(
      'DOWNLOADING RESOURCES...',
      style: TextStyle(
        fontFamily: 'CEORUSE',
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: Colors.white.withValues(alpha: 0.95),
        letterSpacing: 2,
      ),
    );
  }
}

class _RisingFadeParticle extends StatefulWidget {
  const _RisingFadeParticle({
    required this.size,
    required this.assetPath,
    this.phase = 0.0,
  });

  final double size;
  final String assetPath;
  final double phase;

  @override
  State<_RisingFadeParticle> createState() => _RisingFadeParticleState();
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
