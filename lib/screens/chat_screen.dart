import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../chat/chat_message.dart';
import '../chat/chat_models.dart';
import '../chat/intent_classifier.dart';
import '../core/demo_config.dart';
import '../core/text_to_speech.dart';
import '../state/chat_notifier.dart';
import '../state/persona_notifier.dart';
import '../state/providers.dart';
import '../widgets/chat_view.dart';
import '../widgets/mountain_backdrop.dart';
import '../widgets/transaction_processing_animation.dart';

/// The AI chat for the selected persona. [initialPrompt] is sent as soon as
/// the conversation is ready, which is how the home screen's quick-action
/// tiles start a chat.
class ChatScreen extends ConsumerStatefulWidget {
  final String? initialPrompt;

  const ChatScreen({super.key, this.initialPrompt});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  bool _isVerifyingMpin = false;
  bool _speakNextResponse = false;

  @override
  void initState() {
    super.initState();
    final prompt = widget.initialPrompt;
    if (prompt != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final personaId = ref.read(personaProvider).selectedPersona.id;
        ref.read(chatProvider(personaId).notifier).send(prompt);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const colors = selectedDemoColors;
    final persona = ref.watch(
      personaProvider.select((state) => state.selectedPersona),
    );
    final chat = ref.watch(chatProvider(persona.id));
    final processingActionType = chat.messages
        .where((message) => message.actionStatus == ChatActionStatus.running)
        .lastOrNull
        ?.action
        ?.type;
    ref.listen(chatProvider(persona.id), (previous, next) {
      if (_speakNextResponse && !next.isTyping) {
        final previousIds = previous?.messages
            .map((message) => message.id)
            .toSet();
        final response = next.messages
            .where(
              (message) =>
                  !message.isUser &&
                  !(previousIds?.contains(message.id) ?? false),
            )
            .lastOrNull;
        if (response != null) {
          _speakNextResponse = false;
          if (!response.isError) {
            unawaited(TextToSpeech.speak(response.text));
          }
        }
      }

      final prompt = widget.initialPrompt;
      if (prompt == null) return;
      final expectedIntent = persona.microActions
          .where((action) => action['prompt'] == prompt)
          .map((action) => action['intent'])
          .firstOrNull;
      final expectedActionType = switch (expectedIntent) {
        'PAY_BILL' => ChatActionType.payBill,
        'LOCK_CARD' =>
          next.messages.any(
                (message) =>
                    message.actionStatus == ChatActionStatus.done &&
                    message.action?.type == ChatActionType.unlockCard,
              )
              ? ChatActionType.unlockCard
              : ChatActionType.lockCard,
        'NEED_CREDIT' => ChatActionType.activateCredit,
        _ => null,
      };
      final completedMatchingAction =
          expectedActionType != null &&
          next.messages.any(
            (message) =>
                message.actionStatus == ChatActionStatus.done &&
                message.action?.type == expectedActionType &&
                !(previous?.messages.any(
                      (oldMessage) =>
                          oldMessage.id == message.id &&
                          oldMessage.actionStatus == ChatActionStatus.done,
                    ) ??
                    false),
          );
      if (completedMatchingAction) {
        ref
            .read(completedMicroActionsProvider.notifier)
            .update((completed) => {...completed, '${persona.id}:$prompt'});
      }
    });

    return Scaffold(
      backgroundColor: colors.background,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: IconThemeData(color: colors.textPrimary),
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: colors.accent,
              child: Icon(Icons.auto_awesome, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Banking Assistant',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
                Text(
                  'Helping ${persona.name}',
                  style: TextStyle(fontSize: 11, color: colors.textSecondary),
                ),
              ],
            ),
          ],
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          SafeArea(
            child: Stack(
              fit: StackFit.expand,
              children: [
                const MountainBackdrop(),
                ChatView(
                  state: chat,
                  onSend: _sendChatMessage,
                  onVoiceSend: (text) {
                    _speakNextResponse = true;
                    _sendChatMessage(text);
                  },
                ),
              ],
            ),
          ),
          if (chat.isProcessingTransaction)
            Positioned.fill(
              child: TransactionProcessingOverlay(
                key: const ValueKey('transaction-processing-overlay'),
                actionType: chat.pending?.action?.type ?? processingActionType,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _sendChatMessage(String text) async {
    if (_isVerifyingMpin) return;

    final personaId = ref.read(personaProvider).selectedPersona.id;
    final notifier = ref.read(chatProvider(personaId).notifier);
    final chat = ref.read(chatProvider(personaId));
    final isConfirmation =
        chat.pending?.awaiting == ChatAwaiting.confirm &&
        IntentClassifier.isAffirmative(IntentClassifier.normalize(text));

    if (!isConfirmation) {
      await notifier.send(text);
      return;
    }

    setState(() => _isVerifyingMpin = true);
    try {
      final mpin = await _requestMpin();
      if (!mounted || mpin == null) return;
      await notifier.send(text, mpin: mpin);
    } finally {
      if (mounted) setState(() => _isVerifyingMpin = false);
    }
  }

  Future<String?> _requestMpin() async {
    return showDialog<String>(
      context: context,
      builder: (_) => const MpinVerificationDialog(),
    );
  }
}

class MpinVerificationDialog extends StatefulWidget {
  const MpinVerificationDialog({super.key});

  @override
  State<MpinVerificationDialog> createState() => _MpinVerificationDialogState();
}

class _MpinVerificationDialogState extends State<MpinVerificationDialog> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  void _verify() {
    if (_controller.text.trim().isEmpty) return;
    Navigator.of(context).pop(_controller.text);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const colors = selectedDemoColors;
    return AlertDialog(
      key: const Key('mpin_dialog'),
      backgroundColor: colors.surface,
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      title: Text(
        'Enter your ${demoMpin.length}-digit MPIN to verify',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: colors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.normal,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 4),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, _) => GestureDetector(
              key: const Key('mpin_boxes'),
              onTap: () => _focusNode.requestFocus(),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var index = 0; index < demoMpin.length; index++)
                        Container(
                          key: ValueKey('mpin_digit_box_$index'),
                          width: 42,
                          height: 48,
                          margin: EdgeInsets.only(
                            right: index == demoMpin.length - 1 ? 0 : 8,
                          ),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: colors.background,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                              color: index < value.text.length
                                  ? colors.accent.withValues(alpha: 0.8)
                                  : colors.border,
                              width: 1,
                            ),
                          ),
                          child: index < value.text.length
                              ? Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: colors.accent,
                                    shape: BoxShape.circle,
                                  ),
                                )
                              : null,
                        ),
                    ],
                  ),
                  Positioned.fill(
                    child: TextField(
                      key: const Key('mpin_input'),
                      controller: _controller,
                      focusNode: _focusNode,
                      autofocus: false,
                      showCursor: false,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      maxLength: demoMpin.length,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(
                        color: Colors.transparent,
                        fontSize: 1,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        counterText: '',
                        contentPadding: EdgeInsets.zero,
                      ),
                      onSubmitted: (_) => _verify(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      actions: [
        Row(
          children: [
            Expanded(
              child: TextButton(
                key: const Key('mpin_cancel'),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: colors.textSecondary),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, value, _) => FilledButton(
                  key: const Key('mpin_verify'),
                  onPressed: value.text.trim().isEmpty ? null : _verify,
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.accent,
                  ),
                  child: const Text('Verify'),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
