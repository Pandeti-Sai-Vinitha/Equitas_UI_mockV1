import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/demo_config.dart';

/// Soft 3D orb used as the ambient hero on the menuless home canvas.
class GlowingOrb extends StatefulWidget {
  const GlowingOrb({super.key, required this.diameter});

  final double diameter;

  @override
  State<GlowingOrb> createState() => _GlowingOrbState();
}

class _GlowingOrbState extends State<GlowingOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduceMotion = false;
  bool _hasResolvedMotionPreference = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_hasResolvedMotionPreference && reduceMotion == _reduceMotion) return;
    _hasResolvedMotionPreference = true;
    _reduceMotion = reduceMotion;
    if (reduceMotion) {
      _controller
        ..stop()
        ..value = 0.5;
    } else {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const colors = selectedDemoColors;
    final accent = colors.accent;
    final deep = colors.background;
    final mid = Color.lerp(accent, deep, 0.35)!;
    final glow = Color.lerp(accent, Colors.white, 0.35)!;

    return SizedBox.square(
      dimension: widget.diameter,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final phase = _reduceMotion ? 0.5 : _controller.value;
            final wave = math.sin(phase * math.pi * 2);
            final pulse = 0.94 + ((wave + 1) * 0.045);
            final highlightX = -0.42 + (phase * 0.72);
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0018)
                ..rotateX(
                  _reduceMotion ? 0 : math.cos(phase * math.pi * 2) * 0.06,
                )
                ..rotateY(_reduceMotion ? 0 : wave * 0.09)
                ..scaleByDouble(pulse, pulse, 1, 1),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: glow.withValues(alpha: 0.22 + ((wave + 1) * 0.12)),
                      blurRadius:
                          widget.diameter * (0.32 + ((wave + 1) * 0.08)),
                      spreadRadius: widget.diameter * 0.055,
                    ),
                    BoxShadow(
                      color: accent.withValues(
                        alpha: 0.28 + ((wave + 1) * 0.1),
                      ),
                      blurRadius: widget.diameter * 0.2,
                      spreadRadius: 1,
                    ),
                  ],
                  gradient: RadialGradient(
                    center: Alignment(highlightX, -0.34),
                    radius: 0.92,
                    colors: [
                      glow,
                      glow,
                      accent,
                      mid,
                      accent,
                      deep,
                      deep,
                    ],
                    stops: const [0, 0.12, 0.29, 0.48, 0.67, 0.84, 1],
                  ),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: Alignment(highlightX, -0.34),
                      radius: 0.58,
                      colors: [
                        glow.withValues(alpha: 0.38 + ((wave + 1) * 0.08)),
                        accent.withValues(alpha: 0.16),
                        deep.withValues(alpha: 0.08),
                        deep.withValues(alpha: 0),
                      ],
                      stops: const [0, 0.23, 0.44, 1],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Pulsing orb shown while a single query is being answered.
class ThinkingOrb extends StatefulWidget {
  const ThinkingOrb({super.key});

  @override
  State<ThinkingOrb> createState() => _ThinkingOrbState();
}

class _ThinkingOrbState extends State<ThinkingOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const colors = selectedDemoColors;
    final accent = colors.accent;
    final glow = Color.lerp(accent, Colors.white, 0.45)!;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final pulse = 0.88 + (_controller.value * 0.18);
        return Transform.rotate(
          angle: _controller.value * 2 * math.pi,
          child: Transform.scale(
            scale: pulse,
            child: Container(
              key: const ValueKey('thinking-orb'),
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.42),
                    blurRadius: 48 + (14 * _controller.value),
                    spreadRadius: 8,
                  ),
                  BoxShadow(
                    color: accent.withValues(alpha: 0.5),
                    blurRadius: 26,
                    spreadRadius: 1,
                  ),
                ],
                gradient: RadialGradient(
                  center: Alignment(-0.35 + (_controller.value * 0.55), -0.3),
                  colors: [
                    Colors.white,
                    glow,
                    accent,
                    Color.lerp(accent, colors.background, 0.35)!,
                    colors.background.withValues(alpha: 0),
                  ],
                  stops: const [0, 0.17, 0.43, 0.68, 1],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
