part of '../views/loading_page.dart';

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
