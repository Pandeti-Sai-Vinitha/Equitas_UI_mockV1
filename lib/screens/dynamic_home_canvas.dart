import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../chat/chat_message.dart';
import '../chat/chat_models.dart';
import '../chat/intent_classifier.dart';
import '../core/exceptions.dart';
import '../core/format.dart';
import '../core/demo_config.dart';
import '../core/text_to_speech.dart';
import '../domain/models.dart';
import '../state/booking_notifier.dart';
import '../state/chat_notifier.dart';
import '../state/credit_line_notifier.dart';
import '../state/persona_notifier.dart';
import '../state/providers.dart';
import '../widgets/chat_action_card.dart';
import '../widgets/chat_view.dart';
import '../widgets/demo_control_panel_drawer.dart';
import '../widgets/mountain_backdrop.dart';
import '../widgets/transaction_processing_animation.dart';
import '../widgets/voice_prompt_overlay.dart';
import 'chat_screen.dart';

class _ConversationRecord {
  const _ConversationRecord({
    required this.query,
    required this.response,
    required this.createdAt,
  });

  final String query;
  final String response;
  final DateTime createdAt;
}

Set<String> _receiptWords(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .split(' ')
    .map((word) => word == 'eb' ? 'electricity' : word)
    .where(
      (word) =>
          word.length > 1 &&
          !const {
            'a',
            'an',
            'and',
            'bill',
            'do',
            'for',
            'i',
            'my',
            'pay',
            'the',
            'to',
          }.contains(word),
    )
    .toSet();

class DynamicHomeCanvas extends ConsumerStatefulWidget {
  const DynamicHomeCanvas({super.key});

  @override
  ConsumerState<DynamicHomeCanvas> createState() => _DynamicHomeCanvasState();
}

class _DynamicHomeCanvasState extends ConsumerState<DynamicHomeCanvas> {
  static const _salariedPersonaId = 'p_salaried_01';

  final _queryController = TextEditingController();
  final _pageController = PageController(initialPage: 1);
  final List<_ConversationRecord> _conversations = [];
  bool _isVerifyingMpin = false;
  bool _isHomePage = true;
  bool _speakNextResponse = false;
  String? _activeQuery;
  int _activeQueryMessageStart = 0;

  @override
  void dispose() {
    _queryController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  String get _greetingSalutation {
    final hour = DateTime.now().hour;
    return hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';
  }

  bool get _isQueryActive => _activeQuery != null;

  void _shootQuery(String prompt) {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty) return;
    _archiveActiveQueryIfNeeded();
    final personaId = ref.read(personaProvider).selectedPersona.id;
    final messageStart = ref.read(chatProvider(personaId)).messages.length;
    setState(() {
      _activeQuery = trimmed;
      _activeQueryMessageStart = messageStart;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(chatProvider(personaId).notifier)
          .send(trimmed, startNewQuery: true);
    });
  }

  void _submitComposer([String? text]) {
    final query = (text ?? _queryController.text).trim();
    if (query.isEmpty) return;
    _queryController.clear();
    if (_isQueryActive) {
      final personaId = ref.read(personaProvider).selectedPersona.id;
      final chat = ref.read(chatProvider(personaId));
      if (chat.pending == null) {
        _shootQuery(query);
        return;
      }
      final nextIntent = const IntentClassifier().classify(
        IntentClassifier.normalize(query),
      );
      if (nextIntent.intent != ChatIntent.fallback &&
          nextIntent.intent != chat.pending!.intent &&
          nextIntent.intent != ChatIntent.cancel) {
        _shootQuery(query);
        return;
      }
      _sendFollowUp(query);
      return;
    }
    _shootQuery(query);
  }

  void _submitVoiceQuery(String query) {
    _speakNextResponse = true;
    _submitComposer(query);
  }

  Future<void> _sendFollowUp(String text) async {
    await _sendWithOptionalMpin(text);
  }

  void _archiveActiveQueryIfNeeded() {
    if (_activeQuery == null) return;
    final personaId = ref.read(personaProvider).selectedPersona.id;
    final chat = ref.read(chatProvider(personaId));
    final last = chat.lastMessage;
    if (last != null && !last.isUser && last.text.trim().isNotEmpty) {
      _conversations.add(
        _ConversationRecord(
          query: _activeQuery!,
          response: last.text,
          createdAt: DateTime.now(),
        ),
      );
    }
  }

  void _closeQuery() {
    _archiveActiveQueryIfNeeded();
    setState(() {
      _activeQuery = null;
    });
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        1,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _sendWithOptionalMpin(String text) async {
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
      final mpin = await showDialog<String>(
        context: context,
        builder: (_) => const MpinVerificationDialog(),
      );
      if (!mounted || mpin == null) return;
      await notifier.send(text, mpin: mpin);
    } finally {
      if (mounted) setState(() => _isVerifyingMpin = false);
    }
  }

  bool _matchesMicroAction(
    Map<String, dynamic> microAction,
    ChatAction completedAction,
  ) {
    final expectedType = switch (microAction['intent']) {
      'PAY_BILL' => ChatActionType.payBill,
      'LOCK_CARD' =>
        completedAction.type == ChatActionType.unlockCard
            ? ChatActionType.unlockCard
            : ChatActionType.lockCard,
      'NEED_CREDIT' => ChatActionType.activateCredit,
      _ => null,
    };
    if (expectedType != completedAction.type) return false;
    if (completedAction.type != ChatActionType.payBill) return true;

    const ignoredWords = {
      'a',
      'an',
      'and',
      'bill',
      'can',
      'do',
      'for',
      'i',
      'my',
      'pay',
      'please',
      'the',
      'to',
    };
    Set<String> words(String text) => text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .split(' ')
        .where((word) => word.length > 1 && !ignoredWords.contains(word))
        .toSet();

    final prompt = microAction['prompt'];
    if (prompt is! String) return false;
    final promptWords = words(prompt);
    final actionWords = words(
      [
        completedAction.params['payee'],
        completedAction.params['category'],
        completedAction.title,
        for (final detail in completedAction.details) detail.value,
      ].whereType<String>().join(' '),
    );
    return promptWords.intersection(actionWords).isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    const colors = selectedDemoColors;
    final personaState = ref.watch(personaProvider);
    final persona = personaState.selectedPersona;
    final persistedCompletedPrompts = <String>{
      for (final microAction in persona.microActions)
        if (microAction['prompt'] case final String prompt)
          if (microAction['intent'] == 'LOCK_CARD' && persona.cardLocked)
            '${persona.id}:$prompt'
          else if (microAction['intent'] == 'PAY_BILL' &&
              persona.recentTransactions.any((transaction) {
                if (transaction.type != TransactionType.debit ||
                    !transaction.id.startsWith('t_PAY_')) {
                  return false;
                }
                final now = DateTime.now();
                if (transaction.date.year != now.year ||
                    transaction.date.month != now.month) {
                  return false;
                }
                return _matchesMicroAction(
                  microAction,
                  ChatAction(
                    type: ChatActionType.payBill,
                    title: 'Payment',
                    confirmLabel: 'Paid',
                    params: {
                      'payee': transaction.description,
                      'category': transaction.category,
                    },
                    details: const [],
                  ),
                );
              }))
            '${persona.id}:$prompt',
    };
    final recommendations = ref.watch(recommendationsProvider);
    final bookingState = ref.watch(fdBookingProvider);
    final creditState = ref.watch(creditLineProvider);
    final chat = ref.watch(chatProvider(persona.id));
    ChatMessage? activeAssistant;
    ChatMessage? latestActionMessage;
    final queryMessages = chat.messages
        .skip(_activeQueryMessageStart)
        .toList()
        .reversed;
    for (final message in queryMessages) {
      if (message.isUser) continue;
      activeAssistant ??= message;
      if (message.action != null) {
        latestActionMessage ??= message;
      }
      if (latestActionMessage != null) break;
    }
    final resolvedAssistant = activeAssistant;
    final showAssistant =
        _isQueryActive && resolvedAssistant != null && !chat.isTyping;
    final suggestions = showAssistant
        ? resolvedAssistant.suggestions
        : const <String>[];

    ref.listen(personaProvider, (previous, next) {
      if (next.isLoading) return;
      if (next.selectedPersona.id != _salariedPersonaId) {
        ref.read(personaProvider.notifier).selectPersona(_salariedPersonaId);
      }
    });

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

      final newlyCompletedActions = next.messages.where(
        (message) =>
            message.actionStatus == ChatActionStatus.done &&
            message.action != null &&
            !(previous?.messages.any(
                  (oldMessage) =>
                      oldMessage.id == message.id &&
                      oldMessage.actionStatus == ChatActionStatus.done,
                ) ??
                false),
      );
      if (newlyCompletedActions.isEmpty) return;

      final completedPrompts = <String>{
        for (final microAction in persona.microActions)
          if (microAction['prompt'] case final String prompt)
            if (newlyCompletedActions.any(
              (message) =>
                  message.action!.type != ChatActionType.unlockCard &&
                  _matchesMicroAction(microAction, message.action!),
            ))
              '${persona.id}:$prompt',
      };
      final unlockedPrompts = <String>{
        for (final microAction in persona.microActions)
          if (microAction['intent'] == 'LOCK_CARD')
            if (newlyCompletedActions.any(
              (message) => message.action?.type == ChatActionType.unlockCard,
            ))
              if (microAction['prompt'] case final String prompt)
                '${persona.id}:$prompt',
      };
      if (completedPrompts.isNotEmpty || unlockedPrompts.isNotEmpty) {
        ref
            .read(completedMicroActionsProvider.notifier)
            .update(
              (completed) => {...completed}
                ..removeAll(unlockedPrompts)
                ..addAll(completedPrompts),
            );
      }
    });

    return Scaffold(
      backgroundColor: colors.background,
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colors.background,
                  Color.lerp(colors.background, colors.accent, 0.08)!,
                  colors.background,
                ],
              ),
            ),
          ),
          const MountainBackdrop(),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      PageView(
                        key: const ValueKey('banking-pages'),
                        controller: _pageController,
                        onPageChanged: (page) {
                          setState(() => _isHomePage = page == 1);
                        },
                        reverse: true,
                        physics: _isQueryActive
                            ? const NeverScrollableScrollPhysics()
                            : const BouncingScrollPhysics(),
                        children: [
                          _ConversationsPage(conversations: _conversations),
                          if (_isQueryActive)
                            const SizedBox.expand()
                          else
                            _HomePage(
                              greeting:
                                  '$_greetingSalutation, ${persona.name.split(' ').first}!',
                              persona: persona,
                              personaState: personaState,
                              recommendations: recommendations,
                              bookingState: bookingState,
                              creditState: creditState,
                              completedPrompts: {
                                ...ref.watch(completedMicroActionsProvider),
                                ...persistedCompletedPrompts,
                              },
                              onRecommendationPrompt: _shootQuery,
                              onMicroAction: _shootQuery,
                            ),
                        ],
                      ),
                      if (_isQueryActive)
                        Positioned.fill(
                          child: _QueryResponsePane(
                            query: _activeQuery!,
                            persona: persona,
                            pending: chat.pending,
                            isThinking: chat.isTyping || !showAssistant,
                            message: showAssistant ? resolvedAssistant : null,
                            actionMessage: showAssistant
                                ? latestActionMessage
                                : null,
                            onCancelQuery: _closeQuery,
                            onConfirm: () =>
                                _sendWithOptionalMpin(kConfirmText),
                            onCancel: () => _sendWithOptionalMpin(kCancelText),
                            onSelectPayee: _submitComposer,
                          ),
                        ),
                      if (_isHomePage)
                        Positioned(
                          top: 8,
                          left: 27,
                          right: 27,
                          child: Row(
                            children: [
                              GestureDetector(
                                onTap: _isQueryActive ? _closeQuery : null,
                                onLongPress: () => resetDemo(context, ref),
                                child: CircleAvatar(
                                  key: const ValueKey('home-profile-avatar'),
                                  radius: 18,
                                  backgroundColor: colors.accent,
                                  child: Text(
                                    persona.name[0],
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                              ),
                              const Spacer(),
                              if (!_isQueryActive)
                                _HomeAccountSummary(
                                  summary: persona.financialSummary,
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                if (suggestions.isNotEmpty &&
                    !(showAssistant &&
                        chat.pending?.awaiting == ChatAwaiting.payee))
                  SizedBox(
                    height: 44,
                    child:
                        showAssistant &&
                            resolvedAssistant.intent ==
                                ChatIntent.failedTransactions
                        ? Padding(
                            key: const Key('failed-transaction-suggestions'),
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Row(
                              children: [
                                for (
                                  var index = 0;
                                  index < suggestions.length;
                                  index++
                                ) ...[
                                  if (index > 0)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      child: Text(
                                        '|',
                                        style: TextStyle(
                                          color: colors.textMuted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  Expanded(
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: InkWell(
                                        onTap: () =>
                                            _submitComposer(suggestions[index]),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 8,
                                          ),
                                          child: Text(
                                            suggestions[index],
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: colors.textPrimary,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          )
                        : ListView.separated(
                            key: const Key('chat_suggestions'),
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: suggestions.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, index) => ActionChip(
                              label: Text(
                                suggestions[index],
                                style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: 12,
                                ),
                              ),
                              backgroundColor: colors.surface,
                              side: BorderSide(color: colors.border),
                              onPressed: () =>
                                  _submitComposer(suggestions[index]),
                            ),
                          ),
                  ),
                _StaticComposer(
                  controller: _queryController,
                  onSubmitted: _submitComposer,
                  onVoiceSubmitted: _submitVoiceQuery,
                  onSend: () => _submitComposer(),
                  onOpenHistory: () {
                    if (_isQueryActive) return;
                    _pageController.animateToPage(
                      0,
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutCubic,
                    );
                  },
                ),
              ],
            ),
          ),
          if (chat.isProcessingTransaction)
            Positioned.fill(
              child: TransactionProcessingOverlay(
                key: const ValueKey('transaction-processing-overlay'),
                actionType:
                    chat.pending?.action?.type ??
                    latestActionMessage?.action?.type,
              ),
            ),
        ],
      ),
    );
  }
}

class _HomePage extends StatelessWidget {
  const _HomePage({
    required this.greeting,
    required this.persona,
    required this.personaState,
    required this.recommendations,
    required this.bookingState,
    required this.creditState,
    required this.completedPrompts,
    required this.onRecommendationPrompt,
    required this.onMicroAction,
  });

  final String greeting;
  final Persona persona;
  final PersonaState personaState;
  final AsyncValue<List<ProductRecommendation>> recommendations;
  final FDBookingState bookingState;
  final CreditLineState creditState;
  final Set<String> completedPrompts;
  final ValueChanged<String> onRecommendationPrompt;
  final ValueChanged<String> onMicroAction;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final hasCompletedFd = bookingState.bookings.any(
          (booking) => booking.personaId == persona.id,
        );
        final completedPayments = <String, BankTransaction>{};
        for (final action in persona.microActions) {
          final prompt = action['prompt'];
          if (action['intent'] != 'PAY_BILL' || prompt is! String) continue;
          final promptWords = _receiptWords(prompt);
          final matches =
              persona.recentTransactions.where((transaction) {
                if (transaction.type != TransactionType.debit ||
                    !transaction.id.startsWith('t_PAY_')) {
                  return false;
                }
                final transactionWords = _receiptWords(
                  '${transaction.description} ${transaction.category}',
                );
                return promptWords.intersection(transactionWords).isNotEmpty;
              }).toList()..sort(
                (first, second) => (second.createdAt ?? second.date).compareTo(
                  first.createdAt ?? first.date,
                ),
              );
          if (matches.isNotEmpty) {
            completedPayments['${persona.id}:$prompt'] = matches.first;
          }
        }
        bool recommendationIsComplete(ProductRecommendation recommendation) {
          if (recommendation.category == ProductCategory.investment) {
            return hasCompletedFd;
          }
          return creditState.status == CreditActivationStatus.success &&
              creditState.result?.personaId == persona.id;
        }

        final allActionsComplete = persona.microActions.every((action) {
          final prompt = action['prompt'];
          if (prompt is! String) return false;
          return completedPrompts.contains('${persona.id}:$prompt') ||
              completedPayments.containsKey('${persona.id}:$prompt');
        });
        final showSpendingPrompt = hasCompletedFd;
        final contentTopOffset =
            (constraints.maxHeight * (showSpendingPrompt ? 0.48 : 0.31))
                .clamp(showSpendingPrompt ? 280.0 : 165.0, 400.0)
                .toDouble();
        return Stack(
          fit: StackFit.expand,
          children: [
            SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(27, 8, 27, 20),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 44),
                    if (personaState.errorMessage != null)
                      _InlineError(message: personaState.errorMessage!),
                    if (bookingState.errorMessage != null)
                      _InlineError(message: bookingState.errorMessage!),
                    if (creditState.errorMessage != null)
                      _InlineError(message: creditState.errorMessage!),
                    if (personaState.isLoading ||
                        bookingState.isLoadingBookings)
                      const LinearProgressIndicator(),
                    SizedBox(height: contentTopOffset),
                    _HomeGreeting(
                      greeting: greeting,
                      multiline: showSpendingPrompt,
                    ),
                    const SizedBox(height: 14),
                    if (showSpendingPrompt)
                      _HomeSpendingPrompt(
                        onTap: () =>
                            onMicroAction('How much I spent in this month'),
                        multiline: true,
                      )
                    else ...[
                      const SizedBox(height: 4),
                      ...recommendations.when(
                        data: (items) => items
                            .where((recommendation) {
                              return !recommendationIsComplete(recommendation);
                            })
                            .map<Widget>(
                              (rec) => _AmbientAgenticBanner(
                                recommendation: rec,
                                personaId: persona.id,
                                onOpenPrompt: onRecommendationPrompt,
                              ),
                            )
                            .toList(),
                        loading: () => const [
                          Center(child: CircularProgressIndicator()),
                        ],
                        error: (error, stackTrace) => [
                          _InlineError(
                            message:
                                'Failed to load recommendations: ${describeError(error)}',
                          ),
                        ],
                      ),
                    ],
                    if (!hasCompletedFd) ...[
                      const SizedBox(height: 4),
                      _HomeFinancialMetrics(summary: persona.financialSummary),
                    ],
                    if (!allActionsComplete) ...[
                      const SizedBox(height: 8),
                      _HomeSuggestedActions(
                        actions: persona.microActions,
                        personaId: persona.id,
                        completedPrompts: completedPrompts,
                        completedPayments: completedPayments,
                        onTap: onMicroAction,
                      ),
                    ],
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ConversationsPage extends StatelessWidget {
  const _ConversationsPage({required this.conversations});

  final List<_ConversationRecord> conversations;

  @override
  Widget build(BuildContext context) {
    const colors = selectedDemoColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(25, 12, 25, 0),
          child: Text(
            'Conversations',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(25, 0, 25, 22),
            children: [
              if (conversations.isEmpty)
                Padding(
                  key: const ValueKey('conversation-history-empty'),
                  padding: const EdgeInsets.only(top: 115),
                  child: Column(
                    children: [
                      Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 34,
                        color: colors.textMuted,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Your conversations will appear here',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Ask a question to get started.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: colors.textMuted),
                      ),
                    ],
                  ),
                )
              else
                for (final conversation in conversations.reversed)
                  _ConversationCard(conversation: conversation),
            ],
          ),
        ),
      ],
    );
  }
}

class _ConversationCard extends StatelessWidget {
  const _ConversationCard({required this.conversation});

  final _ConversationRecord conversation;

  @override
  Widget build(BuildContext context) {
    const colors = selectedDemoColors;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(15, 13, 12, 13),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            conversation.query,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            conversation.response,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              height: 1.3,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            conversation.createdAt.toLocal().toString().split('.').first,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _QueryResponsePane extends StatelessWidget {
  const _QueryResponsePane({
    required this.query,
    required this.persona,
    required this.pending,
    required this.isThinking,
    required this.message,
    required this.actionMessage,
    required this.onCancelQuery,
    required this.onConfirm,
    required this.onCancel,
    required this.onSelectPayee,
  });

  final String query;
  final Persona persona;
  final ChatPending? pending;
  final bool isThinking;
  final ChatMessage? message;
  final ChatMessage? actionMessage;
  final VoidCallback onCancelQuery;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final ValueChanged<String> onSelectPayee;

  @override
  Widget build(BuildContext context) {
    const colors = selectedDemoColors;
    var horizontalDragDistance = 0.0;
    return GestureDetector(
      key: const ValueKey('query-swipe-to-home'),
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (details) {
        horizontalDragDistance += details.delta.dx;
      },
      onHorizontalDragEnd: (details) {
        if (horizontalDragDistance > 80 || (details.primaryVelocity ?? 0) > 0) {
          onCancelQuery();
        }
      },
      child: Material(
        color: Colors.transparent,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 58),
                Padding(
                  padding: const EdgeInsets.fromLTRB(27, 14, 27, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          query,
                          key: const ValueKey('submitted-query'),
                          style: TextStyle(
                            fontSize: 21,
                            height: 1.15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: isThinking
                      ? Padding(
                          key: ValueKey('response-thinking'),
                          padding: const EdgeInsets.fromLTRB(27, 16, 27, 16),
                          child: const Align(
                            alignment: Alignment.topLeft,
                            child: TypingIndicator(),
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: SingleChildScrollView(
                            key: const Key('chat_list'),
                            padding: const EdgeInsets.fromLTRB(27, 0, 27, 16),
                            child: TweenAnimationBuilder<double>(
                              key: const ValueKey('response-3d-entrance'),
                              tween: Tween(begin: 0, end: 1),
                              duration: const Duration(milliseconds: 800),
                              curve: Curves.easeOutCubic,
                              builder: (context, progress, child) => Opacity(
                                opacity: progress.clamp(0, 1),
                                child: Transform(
                                  alignment: Alignment.center,
                                  transform: Matrix4.identity()
                                    ..setEntry(3, 2, 0.0015)
                                    ..rotateY((1 - progress) * -0.16)
                                    ..rotateX((1 - progress) * 0.05)
                                    ..scaleByDouble(
                                      0.96 + (progress * 0.04),
                                      0.96 + (progress * 0.04),
                                      1,
                                      1,
                                    ),
                                  child: child,
                                ),
                              ),
                              child: _SingleAnswer(
                                message: message!,
                                persona: persona,
                                pending: pending,
                                ticketReference: message!.ticketReference,
                                actionMessage: actionMessage,
                                onConfirm: onConfirm,
                                onCancel: onCancel,
                                onSelectPayee: onSelectPayee,
                              ),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SingleAnswer extends StatefulWidget {
  const _SingleAnswer({
    required this.message,
    required this.persona,
    required this.pending,
    required this.ticketReference,
    required this.actionMessage,
    required this.onConfirm,
    required this.onCancel,
    required this.onSelectPayee,
  });

  final ChatMessage message;
  final Persona persona;
  final ChatPending? pending;
  final String? ticketReference;
  final ChatMessage? actionMessage;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final ValueChanged<String> onSelectPayee;

  @override
  State<_SingleAnswer> createState() => _SingleAnswerState();
}

class _SingleAnswerState extends State<_SingleAnswer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _typingController;
  late List<RegExpMatch> _wordMatches;
  bool _showingTypedText = false;

  @override
  void initState() {
    super.initState();
    _typingController = AnimationController(vsync: this)
      ..addStatusListener(_onTypingStatus);
    _configureTyping();
  }

  @override
  void didUpdateWidget(covariant _SingleAnswer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id) {
      _configureTyping();
    }
  }

  void _onTypingStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      setState(() {});
    }
  }

  void _configureTyping() {
    final intent = widget.message.intent;
    _showingTypedText =
        widget.message.text.isNotEmpty &&
        intent != ChatIntent.failedTransactions &&
        intent != ChatIntent.spendInsight;
    _wordMatches = RegExp(r'\S+\s*').allMatches(widget.message.text).toList();
    if (!_showingTypedText || _wordMatches.isEmpty) {
      _typingController.duration = Duration.zero;
      _typingController.value = 1;
      return;
    }

    final durationMs = (_wordMatches.length * 75).clamp(750, 6000);
    _typingController
      ..duration = Duration(milliseconds: durationMs)
      ..value = 0
      ..forward();
  }

  @override
  void dispose() {
    _typingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const colors = selectedDemoColors;
    final message = widget.message;
    final actionMessage = widget.actionMessage;
    final actionSource = actionMessage?.action != null
        ? actionMessage!
        : message;
    final action = actionSource.action;
    final responseComplete =
        !_showingTypedText || _typingController.isCompleted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (message.intent == ChatIntent.failedTransactions)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              message.text,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        if (_showingTypedText)
          AnimatedBuilder(
            animation: _typingController,
            builder: (context, _) {
              final visibleWords =
                  (_typingController.value * _wordMatches.length).ceil().clamp(
                    0,
                    _wordMatches.length,
                  );
              final visibleText = visibleWords == 0
                  ? ''
                  : message.text.substring(
                      0,
                      _wordMatches[visibleWords - 1].end,
                    );
              return Text(
                visibleText,
                style: TextStyle(
                  color: message.isError
                      ? const Color(0xFFFF8A80)
                      : colors.textPrimary,
                  fontSize: 16,
                  height: 1.4,
                ),
              );
            },
          ),
        if (responseComplete && message.intent == ChatIntent.spendInsight)
          _MonthlySpendResult(persona: widget.persona, response: message.text),
        if (responseComplete && message.intent == ChatIntent.failedTransactions)
          _FailedTransactionsResult(ticketReference: widget.ticketReference),
        if (responseComplete &&
            widget.pending?.awaiting == ChatAwaiting.transferApproval)
          const _TransferReviewResult(),
        if (responseComplete && widget.pending?.awaiting == ChatAwaiting.payee)
          _PayeeSelectionResult(
            payees: widget.message.suggestions,
            onSelect: widget.onSelectPayee,
          ),
        if (responseComplete && action != null)
          ChatActionCard(
            action: action,
            status: actionSource.actionStatus ?? ChatActionStatus.proposed,
            enabled:
                (actionSource.actionStatus ?? ChatActionStatus.proposed) ==
                ChatActionStatus.proposed,
            onConfirm: widget.onConfirm,
            onCancel: widget.onCancel,
          ),
      ],
    );
  }
}

class _WordTypingText extends StatefulWidget {
  const _WordTypingText({super.key, required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  State<_WordTypingText> createState() => _WordTypingTextState();
}

class _WordTypingTextState extends State<_WordTypingText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late List<RegExpMatch> _words;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _startTyping();
  }

  @override
  void didUpdateWidget(covariant _WordTypingText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _startTyping();
  }

  void _startTyping() {
    _words = RegExp(r'\S+\s*').allMatches(widget.text).toList();
    final duration = (_words.length * 70).clamp(700, 4000);
    _controller
      ..duration = Duration(milliseconds: duration)
      ..value = 0
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final visibleWords = (_controller.value * _words.length).ceil().clamp(
          0,
          _words.length,
        );
        final visibleText = visibleWords == 0
            ? ''
            : widget.text.substring(0, _words[visibleWords - 1].end);
        return Text(visibleText, style: widget.style);
      },
    );
  }
}

class _MonthlySpendResult extends StatefulWidget {
  const _MonthlySpendResult({required this.persona, required this.response});

  final Persona persona;
  final String response;

  static const _colors = [
    Color(0xFF818CF8),
    Color(0xFF34D399),
    Color(0xFFFBBF24),
    Color(0xFFF472B6),
    Color(0xFF38BDF8),
    Color(0xFFFB7185),
  ];

  @override
  State<_MonthlySpendResult> createState() => _MonthlySpendResultState();
}

class _MonthlySpendResultState extends State<_MonthlySpendResult>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1550),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const colors = selectedDemoColors;
    final categories = [...widget.persona.spendByCategory]
      ..sort((left, right) => right.amount.compareTo(left.amount));
    final total = categories.fold<double>(0, (sum, item) => sum + item.amount);
    if (total <= 0 || categories.isEmpty) return const SizedBox.shrink();
    final insightStart = widget.response.indexOf('\n\n');
    final insight = insightStart < 0
        ? 'Your biggest spending category is '
              '${_spendCategoryLabel(categories.first.category)} at '
              '${formatMoney(categories.first.amount)}.'
        : widget.response.substring(insightStart).trim();

    return Container(
      key: const ValueKey('monthly-spending-result-card'),
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border.withValues(alpha: 0.75)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_rounded, color: colors.accent, size: 19),
              const SizedBox(width: 8),
              Text(
                'Monthly spending',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final progress = Curves.easeOutCubic.transform(
                  _controller.value,
                );
                return Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0012)
                    ..rotateX((1 - progress) * -0.18)
                    ..rotateY((1 - progress) * 0.12)
                    ..scaleByDouble(
                      0.88 + (progress * 0.12),
                      0.88 + (progress * 0.12),
                      1,
                      1,
                    ),
                  child: child,
                );
              },
              child: SizedBox(
                key: const ValueKey('spending-pie-chart'),
                width: 218,
                height: 218,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) => CustomPaint(
                    painter: _SpendingDonutPainter(
                      categories: categories,
                      colors: _MonthlySpendResult._colors,
                      progress: Curves.easeOutCubic.transform(
                        _controller.value,
                      ),
                      background: colors.background,
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'MONTHLY SPENDING',
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 9,
                              letterSpacing: 0.8,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            formatMoney(total),
                            key: const ValueKey('monthly-spending-chart-total'),
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (var index = 0; index < categories.length && index < 5; index++)
            _SpendCategoryLegend(
              label: _spendCategoryLabel(categories[index].category),
              amount: categories[index].amount,
              total: total,
              color: _MonthlySpendResult
                  ._colors[index % _MonthlySpendResult._colors.length],
            ),
          const SizedBox(height: 10),
          Container(
            key: const ValueKey('monthly-spending-insight'),
            width: double.infinity,
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: colors.background.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: colors.accent.withValues(alpha: 0.35)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 15,
                  color: colors.accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _WordTypingText(
                    key: const ValueKey('monthly-spending-insight-text'),
                    text: insight,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SpendCategoryLegend extends StatelessWidget {
  const _SpendCategoryLegend({
    required this.label,
    required this.amount,
    required this.total,
    required this.color,
  });

  final String label;
  final double amount;
  final double total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    const colors = selectedDemoColors;
    final fraction = (amount / total).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
          ),
          Text(
            formatMoney(amount),
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 34,
            child: Text(
              '${(fraction * 100).round()}%',
              textAlign: TextAlign.right,
              style: TextStyle(color: colors.textMuted, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpendingDonutPainter extends CustomPainter {
  const _SpendingDonutPainter({
    required this.categories,
    required this.colors,
    required this.progress,
    required this.background,
  });

  final List<SpendCategory> categories;
  final List<Color> colors;
  final double progress;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - 42) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const strokeWidth = 19.0;
    final total = categories.fold<double>(0, (sum, item) => sum + item.amount);
    final track = Paint()
      ..color = background.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center.translate(0, 5), radius, track);

    var startAngle = -math.pi / 2;
    for (var index = 0; index < categories.length && index < 5; index++) {
      final category = categories[index];
      final sweep = math.pi * 2 * category.amount / total;
      final visibleSweep = (sweep - 0.045).clamp(0.0, sweep) * progress;
      final color = colors[index % colors.length];
      final side = Paint()
        ..color = Color.lerp(background, color, 0.48)!
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      final top = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      for (var depth = 5; depth >= 1; depth--) {
        canvas.drawArc(
          rect.shift(Offset(0, depth.toDouble())),
          startAngle,
          visibleSweep,
          false,
          side,
        );
      }
      if (visibleSweep > 0) {
        canvas.drawArc(rect, startAngle, visibleSweep, false, top);
      }
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _SpendingDonutPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.categories != categories ||
      oldDelegate.colors != colors ||
      oldDelegate.background != background;
}

class _FailedTransactionsResult extends StatelessWidget {
  const _FailedTransactionsResult({required this.ticketReference});

  final String? ticketReference;

  /// Realistic declines for Ananya (₹1,85,000 balance / ₹20,000 buffer).
  /// Support ticket is raised only for card-expiration declines.
  static const _transactions = <_FailedTransaction>[
    _FailedTransaction(
      merchant: 'Amazon India',
      channel: 'UPI',
      time: '09:14 AM',
      amount: 275000,
      reason: 'Insufficient balance',
      explanation:
          'The available balance at the time was ₹1,85,000 — short of the '
          '₹2,75,000 attempted.',
    ),
    _FailedTransaction(
      merchant: 'Swiggy',
      channel: 'Card',
      time: '01:37 PM',
      amount: 621,
      reason: 'Card expired',
      explanation:
          'The debit card ending 4821 used for this payment has expired.',
      ticketRequired: true,
    ),
    _FailedTransaction(
      merchant: 'Netflix',
      channel: 'UPI Autopay',
      time: '08:52 PM',
      amount: 649,
      reason: 'Autopay mandate failed',
      explanation:
          'Your Netflix UPI Autopay mandate could not be completed. '
          'No card was charged.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    const colors = selectedDemoColors;
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    return Column(
      key: const ValueKey('failed-transactions-result-card'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          decoration: BoxDecoration(
            color: colors.surface.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: colors.accent.withValues(alpha: 0.55)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.only(left: 10),
                decoration: const BoxDecoration(
                  border: Border(
                    left: BorderSide(color: Color(0xFF60A5FA), width: 2),
                  ),
                ),
                child: Text(
                  'Yesterday · ${formatDate(yesterday)}',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              for (var index = 0; index < _transactions.length; index++) ...[
                _FailedTransactionRow(
                  transaction: _transactions[index],
                  ticketReference: ticketReference,
                ),
                if (index < _transactions.length - 1)
                  Divider(
                    height: 1,
                    color: colors.border.withValues(alpha: 0.65),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 11),
        Text(
          'No funds were debited. A support ticket is raised automatically '
          'only when a payment fails because the card has expired.',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 12,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _FailedTransaction {
  const _FailedTransaction({
    required this.merchant,
    required this.channel,
    required this.time,
    required this.amount,
    required this.reason,
    required this.explanation,
    this.ticketRequired = false,
  });

  final String merchant;
  final String channel;
  final String time;
  final int amount;
  final String reason;
  final String explanation;
  final bool ticketRequired;
}

class _FailedTransactionRow extends StatelessWidget {
  const _FailedTransactionRow({
    required this.transaction,
    required this.ticketReference,
  });

  final _FailedTransaction transaction;
  final String? ticketReference;

  @override
  Widget build(BuildContext context) {
    const colors = selectedDemoColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            key: ValueKey('failed-transaction-${transaction.merchant}'),
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF682756).withValues(alpha: 0.62),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              transaction.merchant[0],
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        transaction.merchant,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      formatMoney(transaction.amount),
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${transaction.time} · ${transaction.channel} · Declined',
                  style: TextStyle(color: colors.textSecondary, fontSize: 10),
                ),
                const SizedBox(height: 4),
                Text(
                  transaction.reason,
                  style: const TextStyle(
                    color: Color(0xFFFF8B9A),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  transaction.explanation,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 10,
                    height: 1.3,
                  ),
                ),
                if (transaction.ticketRequired) ...[
                  const SizedBox(height: 6),
                  Text(
                    ticketReference == null
                        ? 'Support ticket unavailable for this expired card.'
                        : 'Support ticket raised for expired card · '
                              'Reference: $ticketReference',
                    key: const ValueKey('failed-transactions-ticket'),
                    style: const TextStyle(
                      color: Color(0xFF6EE7B7),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TransferReviewResult extends StatelessWidget {
  const _TransferReviewResult();

  @override
  Widget build(BuildContext context) {
    const colors = selectedDemoColors;
    return Container(
      key: const ValueKey('transfer-risk-review-card'),
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFF78350F).withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFFBBF24).withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.shield_outlined, color: Color(0xFFFBBF24), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Security review required. This high-value transfer will not be '
              'sent unless you proceed, choose a recipient, and confirm with MPIN.',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PayeeSelectionResult extends StatelessWidget {
  const _PayeeSelectionResult({required this.payees, required this.onSelect});

  final List<String> payees;
  final ValueChanged<String> onSelect;

  static const _payeeProfiles = <String, _TransferPayeeProfile>{
    'Jada Winters': _TransferPayeeProfile(
      bank: 'HDFC Bank',
      accountSuffix: '4821',
      ifsc: 'HDFC0004821',
      lastPaid: '₹12,500 · 28 Oct',
      verified: true,
    ),
    'Priya Sharma': _TransferPayeeProfile(
      bank: 'ICICI Bank',
      accountSuffix: '1736',
      ifsc: 'ICIC0001736',
      lastPaid: '₹8,200 · 2 Nov',
      verified: true,
    ),
    'Arjun Mehta': _TransferPayeeProfile(
      bank: 'Axis Bank',
      accountSuffix: '9054',
      ifsc: 'UTIB0009054',
      lastPaid: '₹3,000 · 19 Oct',
      verified: true,
    ),
    'Maya Patel': _TransferPayeeProfile(
      bank: 'SBI',
      accountSuffix: '6280',
      ifsc: 'SBIN0006280',
      lastPaid: '₹15,000 · 31 Oct',
      verified: false,
    ),
  };

  @override
  Widget build(BuildContext context) {
    const colors = selectedDemoColors;
    return Container(
      key: const ValueKey('transfer-payee-selection-card'),
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border.withValues(alpha: 0.75)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Choose recipient',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'Saved bank accounts',
                      style: TextStyle(color: colors.textMuted, fontSize: 10),
                    ),
                  ],
                ),
              ),
              Text(
                '${payees.length} saved',
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < payees.length; index++) ...[
            if (index > 0)
              Divider(height: 1, color: colors.border.withValues(alpha: 0.65)),
            _TransferPayeeRow(
              key: ValueKey('transfer-payee-${payees[index]}'),
              name: payees[index],
              profile:
                  _payeeProfiles[payees[index]] ??
                  _TransferPayeeProfile(
                    bank: 'Linked bank',
                    accountSuffix: '${1000 + index}',
                    ifsc: 'BANK000${1000 + index}',
                    lastPaid: 'Recent recipient',
                  ),
              onTap: () => onSelect(payees[index]),
            ),
          ],
        ],
      ),
    );
  }
}

class _TransferPayeeProfile {
  const _TransferPayeeProfile({
    required this.bank,
    required this.accountSuffix,
    required this.ifsc,
    required this.lastPaid,
    this.verified = false,
  });

  final String bank;
  final String accountSuffix;
  final String ifsc;
  final String lastPaid;
  final bool verified;
}

class _TransferPayeeRow extends StatelessWidget {
  const _TransferPayeeRow({
    super.key,
    required this.name,
    required this.profile,
    required this.onTap,
  });

  final String name;
  final _TransferPayeeProfile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const colors = selectedDemoColors;
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
          child: Row(
            children: [
              Container(
                key: ValueKey('transfer-payee-avatar-$name'),
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: colors.accent.withValues(alpha: 0.24),
                  ),
                ),
                child: Text(
                  initial,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (profile.verified) ...[
                          const SizedBox(width: 7),
                          const Text(
                            'Verified',
                            style: TextStyle(
                              color: Color(0xFF6EE7B7),
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${profile.bank} · •••• ${profile.accountSuffix}',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'IFSC ${profile.ifsc} · Last paid ${profile.lastPaid}',
                      style: TextStyle(
                        color: colors.textMuted,
                        fontSize: 9,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_rounded,
                key: ValueKey('transfer-payee-arrow-$name'),
                color: colors.accent,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _spendCategoryLabel(String category) {
  return category
      .split('_')
      .map(
        (word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
      )
      .join(' ');
}

class _StaticComposer extends StatelessWidget {
  const _StaticComposer({
    required this.controller,
    required this.onSubmitted,
    required this.onVoiceSubmitted,
    required this.onSend,
    required this.onOpenHistory,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<String> onVoiceSubmitted;
  final VoidCallback onSend;
  final VoidCallback onOpenHistory;

  @override
  Widget build(BuildContext context) {
    const colors = selectedDemoColors;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
        child: Row(
          children: [
            IconButton(
              key: const Key('ask_ai_open_chat'),
              tooltip: 'Conversations',
              icon: Icon(Icons.forum_outlined, color: colors.accent),
              onPressed: onOpenHistory,
            ),
            Expanded(
              child: TextField(
                key: const Key('ask_ai'),
                controller: controller,
                textAlign: TextAlign.center,
                textInputAction: TextInputAction.send,
                onSubmitted: onSubmitted,
                style: TextStyle(color: colors.textPrimary, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Tap to type',
                  hintStyle: TextStyle(color: colors.textSecondary),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isCollapsed: true,
                ),
              ),
            ),
            const SizedBox(width: 4),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                final hasText = value.text.trim().isNotEmpty;
                return IconButton(
                  key: const Key('ask_ai_send'),
                  tooltip: hasText ? 'Send message' : 'Voice input',
                  icon: Icon(
                    hasText
                        ? Icons.arrow_forward_rounded
                        : Icons.mic_none_rounded,
                    color: colors.accent,
                  ),
                  onPressed: () async {
                    final raw = controller.text;
                    final trimmed = raw.trim();
                    if (trimmed.isNotEmpty) {
                      onSend();
                    } else if (raw.isEmpty) {
                      final query = await showVoicePrompt(
                        context,
                        onTranscript: (text) {
                          controller.value = TextEditingValue(
                            text: text,
                            selection: TextSelection.collapsed(
                              offset: text.length,
                            ),
                          );
                        },
                      );
                      if (query != null && query.trim().isNotEmpty) {
                        onVoiceSubmitted(query);
                      }
                    } else {
                      controller.clear();
                    }
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeGreeting extends StatelessWidget {
  final String greeting;
  final bool multiline;

  const _HomeGreeting({required this.greeting, this.multiline = false});

  @override
  Widget build(BuildContext context) {
    final colors = selectedDemoColors;

    return SizedBox(
      width: multiline ? 290 : double.infinity,
      key: const ValueKey('home-greeting'),
      child: Text(
        greeting,
        maxLines: 2,
        textAlign: TextAlign.left,
        style: TextStyle(
          color: colors.textPrimary,
          fontSize: 34,
          height: 0.99,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
      ),
    );
  }
}

class _HomeSpendingPrompt extends StatelessWidget {
  const _HomeSpendingPrompt({required this.onTap, this.multiline = false});

  final VoidCallback onTap;
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    const colors = selectedDemoColors;
    return InkWell(
      key: const Key('home-spending-prompt'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text.rich(
          key: const Key('home-spending-prompt-text'),
          TextSpan(
            children: [
              const TextSpan(text: 'Take a look at your spending this month'),
              const WidgetSpan(child: SizedBox(width: 8)),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Icon(
                  Icons.north_east_rounded,
                  key: const Key('home-spending-prompt-arrow'),
                  color: colors.textSecondary,
                  size: 18,
                ),
              ),
            ],
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 14,
              height: 1.35,
            ),
          ),
          maxLines: multiline ? 2 : 1,
        ),
      ),
    );
  }
}

class _AmbientAgenticBanner extends ConsumerWidget {
  final ProductRecommendation recommendation;
  final String personaId;
  final ValueChanged<String> onOpenPrompt;

  const _AmbientAgenticBanner({
    required this.recommendation,
    required this.personaId,
    required this.onOpenPrompt,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const colors = selectedDemoColors;
    final isInvestment = recommendation.category == ProductCategory.investment;
    final isBusy = isInvestment
        ? ref.watch(
            fdBookingProvider.select(
              (state) => state.status == FDBookingStatus.loading,
            ),
          )
        : ref.watch(
            creditLineProvider.select(
              (state) => state.status == CreditActivationStatus.loading,
            ),
          );
    final description = recommendation.description.replaceFirst(
      RegExp(r'[.!?]\s*$'),
      '',
    );
    final tenorMonths = (recommendation.metadata['defaultTenorMonths'] as num?)
        ?.toInt();
    final tenorText = tenorMonths != null
        ? '$tenorMonths months'
        : switch ((
            recommendation.metadata['minTenorMonths'] as num?,
            recommendation.metadata['maxTenorMonths'] as num?,
          )) {
            (final minimum?, final maximum?) =>
              '${minimum.toInt()}–${maximum.toInt()} months',
            (final minimum?, null) => '${minimum.toInt()}+ months',
            _ => 'a flexible term',
          };
    final linkText =
        '$description, so consider ${formatMoney(recommendation.recommendedAmount)} '
        'in ${recommendation.title} for $tenorText at '
        '${recommendation.expectedReturnOrInterestRate.toStringAsFixed(1)}% p.a.';
    return SizedBox(
      width: double.infinity,
      key: const Key('recommendation-text-section'),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: InkWell(
          key: const Key('recommendation-action'),
          onTap: isBusy
              ? null
              : () {
                  if (recommendation.actionType == ActionType.openFD) {
                    final tenor =
                        (recommendation.metadata['defaultTenorMonths'] as num?)
                            ?.toInt() ??
                        12;
                    onOpenPrompt(
                      'Create an FD of ${formatMoney(recommendation.recommendedAmount)} for $tenor months',
                    );
                  } else {
                    ref
                        .read(creditLineProvider.notifier)
                        .activate(
                          personaId: personaId,
                          recommendation: recommendation,
                        );
                  }
                },
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: linkText),
                  const TextSpan(text: '  '),
                  if (isBusy)
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.8,
                          color: colors.accent,
                        ),
                      ),
                    )
                  else
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Icon(
                        Icons.north_east_rounded,
                        key: const Key('recommendation-arrow'),
                        color: colors.textSecondary,
                        size: 17,
                      ),
                    ),
                ],
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              textAlign: TextAlign.left,
              softWrap: true,
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeAccountSummary extends StatelessWidget {
  const _HomeAccountSummary({required this.summary});

  final FinancialSummary summary;

  @override
  Widget build(BuildContext context) {
    final colors = selectedDemoColors;
    return SizedBox(
      key: const Key('home-account-summary'),
      width: 132,
      height: 40,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'CURRENT BALANCE',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 8,
              letterSpacing: 0.7,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            key: const Key('home-account-summary-value'),
            formatMoney(summary.currentBalance),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeFinancialMetrics extends StatelessWidget {
  const _HomeFinancialMetrics({required this.summary});

  final FinancialSummary summary;

  @override
  Widget build(BuildContext context) {
    const colors = selectedDemoColors;
    final metrics = [
      ('30-DAY INFLOW', summary.projectedIncome30D, const Color(0xFF10B981)),
      ('30-DAY OUTFLOW', summary.projectedSpend30D, const Color(0xFFEF4444)),
      ('SAFETY BUFFER', summary.minimumBuffer, const Color(0xFFFBBF24)),
    ];

    return Container(
      key: const Key('home-financial-metrics'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.textMuted.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          for (var index = 0; index < metrics.length; index++) ...[
            if (index > 0) const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    metrics[index].$1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textMuted,
                      fontSize: 8,
                      letterSpacing: 0.25,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatMoney(metrics[index].$2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: metrics[index].$3,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HomeSuggestedActions extends StatelessWidget {
  const _HomeSuggestedActions({
    required this.actions,
    required this.personaId,
    required this.completedPrompts,
    required this.completedPayments,
    required this.onTap,
  });

  final List<Map<String, dynamic>> actions;
  final String personaId;
  final Set<String> completedPrompts;
  final Map<String, BankTransaction> completedPayments;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    const colors = selectedDemoColors;
    final visibleActions = actions
        .where((action) {
          final prompt = action['prompt'] as String?;
          if (prompt == null) return true;
          return !completedPrompts.contains('$personaId:$prompt') &&
              !completedPayments.containsKey('$personaId:$prompt');
        })
        .take(3)
        .toList();
    if (visibleActions.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PREDICTED MICRO-ACTIONS',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            key: const Key('home-suggested-actions'),
            children: [
              for (var index = 0; index < visibleActions.length; index++) ...[
                if (index > 0) const SizedBox(width: 8),
                Expanded(
                  child: _HomeSuggestedActionCard(
                    action: visibleActions[index],
                    onTap: onTap,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _HomeSuggestedActionCard extends StatelessWidget {
  const _HomeSuggestedActionCard({required this.action, required this.onTap});

  final Map<String, dynamic> action;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    const colors = selectedDemoColors;
    final prompt = action['prompt'] as String?;
    final label = action['label'] as String? ?? prompt ?? '';
    final subtext = action['subtext'] as String? ?? '';
    final icon = switch (action['icon']) {
      'home_work_outlined' => Icons.home_work_outlined,
      'credit_card_off_outlined' => Icons.credit_card_off_outlined,
      'send_rounded' => Icons.send_rounded,
      _ => Icons.auto_awesome_outlined,
    };
    return Material(
      color: Color.lerp(colors.surface, colors.accent, 0.08),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: prompt == null ? null : Key('micro_action_$prompt'),
        borderRadius: BorderRadius.circular(14),
        onTap: prompt == null ? null : () => onTap(prompt),
        child: Container(
          height: 76,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.border.withValues(alpha: 0.8)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: colors.accent, size: 17),
              const SizedBox(height: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtext.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtext,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textMuted, fontSize: 7),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  final String message;

  const _InlineError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF7F1D1D),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}
