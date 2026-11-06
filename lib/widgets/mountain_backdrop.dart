import 'package:flutter/material.dart';

class MountainBackdrop extends StatelessWidget {
  const MountainBackdrop({
    super.key,
    this.backdropKey = const ValueKey('mountain-backdrop'),
  });

  final Key backdropKey;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          key: backdropKey,
          painter: const _MountainBackdropPainter(),
        ),
      ),
    );
  }
}

class _MountainBackdropPainter extends CustomPainter {
  const _MountainBackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bounds = Offset.zero & size;

    final distant = Path()
      ..moveTo(-size.width * 0.1, size.height * 0.76)
      ..cubicTo(
        size.width * 0.15,
        size.height * 0.68,
        size.width * 0.23,
        size.height * 0.72,
        size.width * 0.42,
        size.height * 0.78,
      )
      ..cubicTo(
        size.width * 0.64,
        size.height * 0.86,
        size.width * 0.78,
        size.height * 0.68,
        size.width * 1.12,
        size.height * 0.61,
      )
      ..lineTo(size.width * 1.12, size.height)
      ..lineTo(-size.width * 0.1, size.height)
      ..close();
    canvas.drawPath(
      distant,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x4D579BE0), Color(0x52245A9A), Color(0x1F0A1F42)],
        ).createShader(bounds),
    );

    final middle = Path()
      ..moveTo(-size.width * 0.1, size.height * 0.84)
      ..cubicTo(
        size.width * 0.12,
        size.height * 0.77,
        size.width * 0.27,
        size.height * 0.8,
        size.width * 0.48,
        size.height * 0.87,
      )
      ..cubicTo(
        size.width * 0.72,
        size.height * 0.95,
        size.width * 0.86,
        size.height * 0.75,
        size.width * 1.12,
        size.height * 0.7,
      )
      ..lineTo(size.width * 1.12, size.height)
      ..lineTo(-size.width * 0.1, size.height)
      ..close();
    canvas.drawPath(
      middle,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x752E72B8), Color(0x99143D70), Color(0x5206142E)],
        ).createShader(bounds),
    );

    final foreground = Path()
      ..moveTo(-size.width * 0.1, size.height * 0.94)
      ..cubicTo(
        size.width * 0.18,
        size.height * 0.86,
        size.width * 0.35,
        size.height * 0.91,
        size.width * 0.55,
        size.height * 0.96,
      )
      ..cubicTo(
        size.width * 0.78,
        size.height * 1.02,
        size.width * 0.93,
        size.height * 0.9,
        size.width * 1.12,
        size.height * 0.86,
      )
      ..lineTo(size.width * 1.12, size.height)
      ..lineTo(-size.width * 0.1, size.height)
      ..close();
    canvas.drawPath(
      foreground,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xA3174878), Color(0xE00A1F42)],
        ).createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(_MountainBackdropPainter oldDelegate) => false;
}
