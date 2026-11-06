import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../chat/chat_models.dart';
import '../core/demo_config.dart';

class TransactionProcessingOverlay extends StatelessWidget {
  const TransactionProcessingOverlay({super.key, this.actionType});

  final ChatActionType? actionType;

  @override
  Widget build(BuildContext context) {
    const colors = selectedDemoColors;
    return AbsorbPointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: ColoredBox(
                color: colors.background.withValues(alpha: 0.62),
              ),
            ),
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 390),
              child: TransactionProcessingAnimation(actionType: actionType),
            ),
          ),
        ],
      ),
    );
  }
}

class TransactionProcessingAnimation extends StatefulWidget {
  const TransactionProcessingAnimation({super.key, this.actionType});

  final ChatActionType? actionType;

  @override
  State<TransactionProcessingAnimation> createState() =>
      _TransactionProcessingAnimationState();
}

class _TransactionProcessingAnimationState
    extends State<TransactionProcessingAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
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
    return SizedBox(
      width: double.infinity,
      height: 300,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final progress = Curves.easeInOutCubic.transform(_controller.value);
          if (widget.actionType == ChatActionType.lockCard ||
              widget.actionType == ChatActionType.unlockCard ||
              widget.actionType == ChatActionType.updateDebitLimit) {
            final isLockingCard = widget.actionType == ChatActionType.lockCard;
            final isUnlockingCard =
                widget.actionType == ChatActionType.unlockCard;
            return _CardActionProcessing(
              progress: progress,
              title: isLockingCard
                  ? 'Securing your debit card'
                  : isUnlockingCard
                  ? 'Unlocking your debit card'
                  : 'Updating your debit card limit',
              icon: isLockingCard
                  ? Icons.lock_rounded
                  : isUnlockingCard
                  ? Icons.lock_open_rounded
                  : Icons.trending_up_rounded,
            );
          }
          final bob = math.sin(_controller.value * math.pi * 4) * 5;
          return Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                top: 28,
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0015)
                    ..rotateY((1 - progress) * -0.12)
                    ..translateByDouble(0.0, -bob, 0.0, 1.0),
                  child: Container(
                    width: 54,
                    height: 62,
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: colors.accent.withValues(alpha: 0.7),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: colors.accent.withValues(alpha: 0.15),
                          blurRadius: 18,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.receipt_long_rounded,
                      size: 31,
                      color: colors.accent,
                    ),
                  ),
                ),
              ),
              _MovingMoney(
                progress: progress,
                start: const Offset(-58, -26),
                end: const Offset(34, 50),
                rotation: -0.32,
                color: const Color(0xFF34D399),
              ),
              _MovingMoney(
                progress: Curves.easeInOut.transform(
                  ((_controller.value + 0.18) * 1.05).clamp(0.0, 1.0),
                ),
                start: const Offset(52, -2),
                end: const Offset(-28, 62),
                rotation: 0.28,
                color: colors.accent,
              ),
              _MovingMoney(
                progress: Curves.easeInOut.transform(
                  ((_controller.value - 0.08) * 1.12).clamp(0.0, 1.0),
                ),
                start: const Offset(-38, 42),
                end: const Offset(5, 76),
                rotation: 0.12,
                color: const Color(0xFF34D399),
              ),
              Positioned(
                bottom: 76,
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0015)
                    ..rotateX(0.1)
                    ..translateByDouble(0.0, bob, 0.0, 1.0),
                  child: Container(
                    width: 112,
                    height: 58,
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: colors.accent.withValues(alpha: 0.75),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.account_balance_wallet_rounded,
                      size: 35,
                      color: colors.accent,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 28,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Processing your transaction',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _ProcessingDots(progress: _controller.value),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CardActionProcessing extends StatelessWidget {
  const _CardActionProcessing({
    required this.progress,
    required this.title,
    required this.icon,
  });

  final double progress;
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    const colors = selectedDemoColors;
    final pulse = 0.94 + (math.sin(progress * math.pi * 6).abs() * 0.08);
    return SizedBox(
      width: double.infinity,
      height: 300,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colors.accent.withValues(alpha: 0.28),
                    width: 2,
                  ),
                ),
              ),
              Transform.scale(
                scale: pulse,
                child: Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: colors.accent.withValues(alpha: 0.75),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: colors.accent.withValues(alpha: 0.18),
                        blurRadius: 20,
                      ),
                    ],
                  ),
                  child: Icon(icon, size: 38, color: colors.accent),
                ),
              ),
              Positioned(
                right: 2,
                bottom: 3,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: colors.background,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.accent, width: 1.5),
                  ),
                  child: Icon(
                    Icons.credit_card_rounded,
                    size: 17,
                    color: colors.accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          _ProcessingDots(progress: progress),
        ],
      ),
    );
  }
}

class _MovingMoney extends StatelessWidget {
  const _MovingMoney({
    required this.progress,
    required this.start,
    required this.end,
    required this.rotation,
    required this.color,
  });

  final double progress;
  final Offset start;
  final Offset end;
  final double rotation;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final position = Offset.lerp(start, end, progress)!;
    final opacity = (math.sin(progress * math.pi) * 1.4).clamp(0.2, 1.0);
    return Transform.translate(
      offset: position,
      child: Opacity(
        opacity: opacity,
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0018)
            ..rotateY(math.sin(progress * math.pi) * 0.65)
            ..rotateZ(rotation * (1 - progress)),
          child: Container(
            width: 46,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: color, width: 1.4),
            ),
            child: Icon(Icons.currency_rupee_rounded, size: 17, color: color),
          ),
        ),
      ),
    );
  }
}

class _ProcessingDots extends StatelessWidget {
  const _ProcessingDots({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    const colors = selectedDemoColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(4, (index) {
        final phase = (progress * 2 - (index * 0.15)) % 1;
        final scale = 0.7 + (math.sin(phase * math.pi * 2) + 1) * 0.15;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: colors.accent.withValues(alpha: 0.55 + (scale * 0.4)),
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      }),
    );
  }
}
