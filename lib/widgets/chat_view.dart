import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show mapEquals;

import '../chat/chat_message.dart';
import '../core/demo_config.dart';
import 'chat_action_card.dart';
import 'voice_prompt_overlay.dart';

/// Texts the cards send, kept next to the UI that sends them. The engine
/// understands both as a plain yes / no.
const String kConfirmText = 'Yes, go ahead';
const String kCancelText = 'No, cancel';

/// The conversation: bubbles, confirmation cards, typing indicator, quick
/// reply chips and the input box. Presentational only: it renders [state]
/// and reports what the customer sends through [onSend].
class ChatView extends StatefulWidget {
  final ChatState state;
  final ValueChanged<String> onSend;
  final ValueChanged<String>? onVoiceSend;

  const ChatView({
    super.key,
    required this.state,
    required this.onSend,
    this.onVoiceSend,
  });

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> with WidgetsBindingObserver {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() {
    _scrollToEnd();
  }

  @override
  void didUpdateWidget(ChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.state;
    final after = widget.state;
    if (before.messages.length != after.messages.length ||
        before.isTyping != after.isTyping) {
      _scrollToEnd();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_scroll.hasClients) return;
      await _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      // A long list is laid out lazily, so its extent grows while scrolling;
      // settle on the true end.
      if (mounted && _scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _submit([String? text]) {
    final value = (text ?? _input.text).trim();
    if (value.isEmpty || widget.state.isTyping) return;
    widget.onSend(value);
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    const colors = selectedDemoColors;
    final state = widget.state;
    final last = state.lastMessage;
    final chips = !state.isTyping && last != null && !last.isUser
        ? last.suggestions
        : const <String>[];

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            key: const Key('chat_list'),
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            itemCount: state.messages.length + (state.isTyping ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == state.messages.length) {
                return const TypingIndicator();
              }
              final message = state.messages[index];
              final action = message.action;
              final hasLaterMatchingCompletedAction =
                  action != null &&
                  message.actionStatus == ChatActionStatus.done &&
                  state.messages.skip(index + 1).any((later) {
                    final laterAction = later.action;
                    return later.actionStatus == ChatActionStatus.done &&
                        laterAction?.type == action.type &&
                        mapEquals(laterAction?.params, action.params);
                  });
              return ChatBubble(
                message: message,
                showActionCard: !hasLaterMatchingCompletedAction,
                actionsEnabled: !state.isTyping,
                onConfirm: () => _submit(kConfirmText),
                onCancel: () => _submit(kCancelText),
              );
            },
          ),
        ),
        if (chips.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView.separated(
              key: const Key('chat_suggestions'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: chips.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) => ActionChip(
                label: Text(
                  chips[index],
                  style: TextStyle(color: colors.textPrimary, fontSize: 12),
                ),
                backgroundColor: colors.surface,
                side: BorderSide(color: colors.border),
                onPressed: () => _submit(chips[index]),
              ),
            ),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('chat_input'),
                    controller: _input,
                    style: TextStyle(color: colors.textPrimary),
                    textInputAction: TextInputAction.send,
                    onSubmitted: _submit,
                    decoration: InputDecoration(
                      hintText: 'Ask about your money…',
                      hintStyle: TextStyle(color: colors.textMuted),
                      filled: true,
                      fillColor: colors.surface,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: colors.border),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _input,
                  builder: (context, value, _) {
                    final hasText = value.text.trim().isNotEmpty;
                    return IconButton(
                      key: const Key('chat_send'),
                      icon: Icon(
                        hasText ? Icons.send_rounded : Icons.mic_none_rounded,
                      ),
                      color: colors.accent,
                      tooltip: hasText ? 'Send message' : 'Voice input',
                      onPressed: state.isTyping
                          ? null
                          : () async {
                              final raw = _input.text;
                              final trimmed = raw.trim();
                              if (trimmed.isNotEmpty) {
                                _submit(trimmed);
                              } else if (raw.isEmpty) {
                                final query = await showVoicePrompt(
                                  context,
                                  onTranscript: (text) {
                                    _input.value = TextEditingValue(
                                      text: text,
                                      selection: TextSelection.collapsed(
                                        offset: text.length,
                                      ),
                                    );
                                  },
                                );
                                if (query != null && query.trim().isNotEmpty) {
                                  (widget.onVoiceSend ?? widget.onSend)(query);
                                }
                              } else {
                                _input.clear();
                              }
                            },
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final bool actionsEnabled;
  final bool showActionCard;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const ChatBubble({
    super.key,
    required this.message,
    required this.onConfirm,
    required this.onCancel,
    this.actionsEnabled = true,
    this.showActionCard = true,
  });

  @override
  Widget build(BuildContext context) {
    const colors = selectedDemoColors;
    final isUser = message.isUser;
    final width = MediaQuery.sizeOf(context).width;
    final action = message.action;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(maxWidth: width * 0.82),
        decoration: BoxDecoration(
          color: isUser
              ? colors.accent
              : message.isError
              ? const Color(0xFF7F1D1D)
              : colors.surface,
          border: isUser || message.isError
              ? null
              : Border.all(color: colors.subtleBorder),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.text,
              style: TextStyle(
                color: isUser || message.isError
                    ? Colors.white
                    : colors.textPrimary,
                fontSize: 14,
                height: 1.35,
              ),
            ),
            if (action != null && showActionCard)
              ChatActionCard(
                action: action,
                status: message.actionStatus ?? ChatActionStatus.proposed,
                enabled: actionsEnabled,
                onConfirm: onConfirm,
                onCancel: onCancel,
              ),
          ],
        ),
      ),
    );
  }
}

/// Three pulsing dots while the assistant is thinking.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const colors = selectedDemoColors;
    return Align(
      alignment: Alignment.centerLeft,
      heightFactor: 1,
      child: Container(
        key: const Key('typing_indicator'),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++)
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.textPrimary.withValues(alpha: _opacity(i)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Each dot brightens a third of a cycle after the previous one.
  double _opacity(int dot) {
    final phase = (_controller.value - dot / 3) % 1.0;
    return 0.3 + 0.7 * (1 - (phase * 2 - 1).abs());
  }
}
