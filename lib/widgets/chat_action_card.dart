import 'package:flutter/material.dart';

import '../chat/chat_message.dart';
import '../chat/chat_models.dart';
import '../core/demo_config.dart';

/// The confirmation card under an assistant message: what will happen, and
/// Confirm / Cancel while it is still waiting for an answer.
class ChatActionCard extends StatelessWidget {
  final ChatAction action;
  final ChatActionStatus status;

  /// False while the assistant is busy, so a card cannot be answered twice.
  final bool enabled;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const ChatActionCard({
    super.key,
    required this.action,
    required this.status,
    required this.onConfirm,
    required this.onCancel,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    const colors = selectedDemoColors;
    final accent = _accent(action.type);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_icon(action.type), color: accent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  action.title,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              _StatusBadge(status: status),
            ],
          ),
          const SizedBox(height: 10),
          for (final detail in action.details)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    detail.label,
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      detail.value,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (status == ChatActionStatus.proposed && enabled) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('card_cancel'),
                    onPressed: onCancel,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.textSecondary,
                      side: BorderSide(color: colors.border),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    key: const Key('card_confirm'),
                    onPressed: onConfirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(action.confirmLabel),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static Color _accent(ChatActionType type) {
    return switch (type) {
      ChatActionType.openFd => const Color(0xFF10B981),
      ChatActionType.activateCredit => const Color(0xFFF59E0B),
      ChatActionType.payBill => selectedDemoColors.accent,
      ChatActionType.updateDebitLimit => const Color(0xFF38BDF8),
      ChatActionType.lockCard => const Color(0xFFEF4444),
      ChatActionType.unlockCard => const Color(0xFF10B981),
    };
  }

  static IconData _icon(ChatActionType type) {
    return switch (type) {
      ChatActionType.openFd => Icons.savings_outlined,
      ChatActionType.activateCredit => Icons.account_balance_wallet_outlined,
      ChatActionType.payBill => Icons.send_rounded,
      ChatActionType.updateDebitLimit => Icons.credit_card_outlined,
      ChatActionType.lockCard => Icons.lock_outline,
      ChatActionType.unlockCard => Icons.lock_open_rounded,
    };
  }
}

class _StatusBadge extends StatelessWidget {
  final ChatActionStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      ChatActionStatus.proposed => ('Awaiting you', const Color(0xFF94A3B8)),
      ChatActionStatus.running => ('Working…', Colors.amber),
      ChatActionStatus.done => ('Done', const Color(0xFF10B981)),
      ChatActionStatus.failed => ('Failed', const Color(0xFFEF4444)),
      ChatActionStatus.cancelled => ('Cancelled', const Color(0xFF64748B)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
