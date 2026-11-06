import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../chat/chat_message.dart';
import '../chat/chat_models.dart';
import '../chat/intent_classifier.dart';
import '../chat/response_composer.dart';
import '../core/exceptions.dart';
import '../core/format.dart';
import '../core/demo_config.dart';
import '../data/banking_repository.dart';
import '../data/hive_storage.dart';
import '../domain/fixed_deposit.dart';
import 'booking_notifier.dart';
import 'credit_line_notifier.dart';
import 'persona_notifier.dart';
import 'providers.dart';

/// One persona's conversation with the assistant.
///
/// Sends messages to `POST /api/chat`, keeps the half-finished task
/// ([ChatState.pending]) between turns, and carries out a task through the
/// same routes the home screen uses once the customer confirms its card.
/// History is saved per persona in Hive.
class ChatNotifier extends StateNotifier<ChatState> {
  static const String greetingPrompt = 'hi';
  static const Duration transactionProcessingDuration = Duration(seconds: 3);

  /// Adjust this to change how long the assistant shows its thinking indicator.
  static const Duration thinkingDuration = Duration(seconds: 1);

  /// Chip on an error bubble: resends the last message (or the greeting).
  static const String retryText = 'Try again';

  final String personaId;
  final Ref _ref;
  final BankingRepository _repository;
  final LocalStorageService _storage;
  final DateTime Function() _now;

  late final Future<void> _ready;
  var _counter = 0;

  ChatNotifier(
    this.personaId,
    this._ref,
    this._repository,
    this._storage, {
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       super(const ChatState()) {
    _ready = _restoreOrGreet();
  }

  /// Completes once history is loaded, or the opening greeting has arrived.
  Future<void> get ready => _ready;

  Future<void> _restoreOrGreet() async {
    final saved = _storage.getChat(personaId);
    final messages = (saved?['messages'] as List<dynamic>? ?? const [])
        .map(
          (item) =>
              ChatMessage.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    if (messages.isNotEmpty) {
      final pending = saved?['pending'];
      state = ChatState(
        messages: messages,
        pending: pending is Map
            ? ChatPending.fromJson(Map<String, dynamic>.from(pending))
            : null,
      );
      return;
    }

    await _greet();
  }

  /// The assistant opens the conversation. Only its reply is shown.
  Future<void> _greet() async {
    state = state.copyWith(isTyping: true);
    try {
      final reply = await _repository.sendChatMessage(
        personaId: personaId,
        message: greetingPrompt,
        debitCardLimit: _ref.read(debitCardLimitProvider(personaId)),
      );
      if (!mounted) return;
      _update(
        state.copyWith(
          messages: [
            ...state.messages,
            _assistantMessage(
              reply.text,
              intent: reply.intent,
              ticketReference: reply.ticketReference,
              suggestions: reply.suggestions,
            ),
          ],
          isTyping: false,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _update(
        state.copyWith(
          messages: [...state.messages, _errorMessage(error)],
          isTyping: false,
          isProcessingTransaction: false,
        ),
      );
    }
  }

  /// Sends [text] as the customer and shows the assistant's reply. A confirmed
  /// card is carried out before this completes.
  Future<void> send(
    String text, {
    String? mpin,
    bool startNewQuery = false,
  }) async {
    await _ready;
    var trimmed = text.trim();
    if (!mounted || trimmed.isEmpty || state.isTyping) return;

    final isConfirming =
        state.pending?.awaiting == ChatAwaiting.confirm &&
        IntentClassifier.isAffirmative(IntentClassifier.normalize(trimmed));
    final transactionTimer = isConfirming ? (Stopwatch()..start()) : null;
    if (isConfirming && mpin != demoMpin) {
      _failPendingAction();
      return;
    }

    if (trimmed == retryText) {
      final previous = state.messages.where((message) => message.isUser);
      if (previous.isEmpty) {
        _update(const ChatState());
        await _greet();
        return;
      }
      trimmed = previous.last.text;
    }
    final pending = startNewQuery ? null : state.pending;
    final cancelledAction =
        pending != null &&
            IntentClassifier.isNegative(IntentClassifier.normalize(trimmed))
        ? pending.action
        : null;

    _update(
      state.copyWith(
        messages: [...state.messages, _message(ChatRole.user, trimmed)],
        isTyping: true,
        isProcessingTransaction: isConfirming,
        clearPending: startNewQuery,
      ),
    );

    final responseFuture = _repository.sendChatMessage(
      personaId: personaId,
      message: trimmed,
      debitCardLimit: _ref.read(debitCardLimitProvider(personaId)),
      pending: pending,
    );
    final ChatReply reply;
    try {
      final results = await Future.wait<ChatReply?>([
        responseFuture,
        Future<void>.delayed(
          _ref.read(chatThinkingDurationProvider),
        ).then((_) => null),
      ]);
      final result = results.first;
      if (result == null) {
        throw StateError('Chat request completed without a reply.');
      }
      reply = result;
    } catch (error) {
      await _finishProcessingAnimation(transactionTimer);
      if (!mounted) return;
      _update(
        state.copyWith(
          messages: [...state.messages, _errorMessage(error)],
          isTyping: false,
          isProcessingTransaction: false,
        ),
      );
      return;
    }
    if (!mounted) return;

    final execute = reply.execute;
    final settled = _settleCards(
      state.messages,
      confirming: execute != null && !startNewQuery,
    );
    final assistant =
        _assistantMessage(
          reply.text,
          intent: reply.intent,
          ticketReference: reply.ticketReference,
          action: reply.action ?? cancelledAction,
          suggestions: reply.suggestions,
        ).copyWith(
          actionStatus: reply.actionCompleted ? ChatActionStatus.done : null,
        );
    final visibleAssistant = cancelledAction == null
        ? assistant
        : assistant.copyWith(actionStatus: ChatActionStatus.cancelled);
    _update(
      ChatState(
        messages: [...settled, visibleAssistant],
        isTyping: execute != null,
        isProcessingTransaction: execute != null && isConfirming,
        pending: reply.pending,
      ),
    );

    if (execute != null) {
      await _execute(execute, transactionTimer: transactionTimer);
    }
  }

  void _failPendingAction() {
    final lastProposed = state.messages.lastIndexWhere(
      (message) => message.actionStatus == ChatActionStatus.proposed,
    );
    if (lastProposed < 0) return;

    final messages = [
      for (var i = 0; i < state.messages.length; i++)
        if (state.messages[i].actionStatus == ChatActionStatus.proposed)
          state.messages[i].copyWith(
            actionStatus: i == lastProposed
                ? ChatActionStatus.failed
                : ChatActionStatus.cancelled,
          )
        else
          state.messages[i],
    ];
    final failedActionMessage = messages.lastWhere(
      (message) => message.actionStatus == ChatActionStatus.failed,
    );
    _update(
      ChatState(
        messages: [
          ...messages,
          _assistantMessage(
            "MPIN verification failed, so I've cancelled that. Anything else I can help with?",
            action: failedActionMessage.action,
            suggestions: _followUps(),
          ).copyWith(actionStatus: ChatActionStatus.failed),
        ],
      ),
    );
  }

  /// Cards that were waiting are now answered: the confirmed one is running,
  /// any other is cancelled (declined, or replaced by a newer proposal).
  List<ChatMessage> _settleCards(
    List<ChatMessage> messages, {
    required bool confirming,
  }) {
    final lastProposed = messages.lastIndexWhere(
      (message) => message.actionStatus == ChatActionStatus.proposed,
    );
    return [
      for (var i = 0; i < messages.length; i++)
        if (messages[i].actionStatus == ChatActionStatus.proposed)
          messages[i].copyWith(
            actionStatus: confirming && i == lastProposed
                ? ChatActionStatus.running
                : ChatActionStatus.cancelled,
          )
        else
          messages[i],
    ];
  }

  Future<void> _execute(
    ChatAction action, {
    required Stopwatch? transactionTimer,
  }) async {
    try {
      final summary = await _run(action);
      await _finishProcessingAnimation(transactionTimer);
      if (!mounted) return;
      _finishCard(ChatActionStatus.done);
      _update(
        state.copyWith(
          messages: [
            ...state.messages,
            _assistantMessage(
              summary,
              action: action,
              suggestions: _followUps(),
            ).copyWith(actionStatus: ChatActionStatus.done),
          ],
          isTyping: false,
          isProcessingTransaction: false,
        ),
      );
      await SchedulerBinding.instance.endOfFrame;
      await _playTransactionSuccessSound(action);
    } catch (error) {
      await _finishProcessingAnimation(transactionTimer);
      if (!mounted) return;
      _finishCard(ChatActionStatus.failed);
      _update(
        state.copyWith(
          messages: [...state.messages, _errorMessage(error)],
          isTyping: false,
          isProcessingTransaction: false,
        ),
      );
    }
  }

  Future<void> _finishProcessingAnimation(Stopwatch? timer) async {
    if (timer == null) return;
    final remaining = transactionProcessingDuration - timer.elapsed;
    if (remaining > Duration.zero) await Future<void>.delayed(remaining);
  }

  Future<void> _playTransactionSuccessSound(ChatAction action) async {
    final soundMethod = switch (action.type) {
      ChatActionType.lockCard => 'playCardLock',
      ChatActionType.unlockCard => 'playCardUnlock',
      ChatActionType.updateDebitLimit => 'playCardLimit',
      _ => 'playSuccess',
    };
    try {
      await const MethodChannel(
        'com.example.mock2/transaction_sound',
      ).invokeMethod<void>(soundMethod);
      return;
    } on PlatformException catch (error) {
      debugPrint('Could not play transaction success chime: $error');
    } on MissingPluginException {
      // Other platforms use Flutter's built-in alert sound.
    }

    try {
      await SystemSound.play(SystemSoundType.alert);
    } on PlatformException catch (error) {
      debugPrint('Could not play transaction success sound: $error');
    } on MissingPluginException catch (error) {
      debugPrint('Transaction success sound is unavailable: $error');
    }
  }

  void _finishCard(ChatActionStatus status) {
    final messages = [
      for (final message in state.messages)
        if (message.actionStatus == ChatActionStatus.running)
          message.copyWith(actionStatus: status)
        else
          message,
    ];
    state = state.copyWith(messages: messages);
  }

  Future<String> _run(ChatAction action) {
    final params = action.params;
    switch (action.type) {
      case ChatActionType.openFd:
        return _bookFd(params);
      case ChatActionType.activateCredit:
        return _activateCredit(params);
      case ChatActionType.payBill:
        return _pay(params);
      case ChatActionType.updateDebitLimit:
        return _updateDebitLimit(params);
      case ChatActionType.lockCard:
        return _lockCard();
      case ChatActionType.unlockCard:
        return _unlockCard();
    }
  }

  Future<String> _updateDebitLimit(Map<String, dynamic> params) async {
    final from = (params['currentLimit'] as num).toInt();
    final to = (params['requestedLimit'] as num).toInt();
    final cardLastFour = params['cardLastFour'] as String? ?? '1234';
    _ref.read(debitCardLimitProvider(personaId).notifier).state = to;
    return ResponseComposer().debitLimitDone(
      from: from,
      to: to,
      cardLastFour: cardLastFour,
    );
  }

  Future<String> _bookFd(Map<String, dynamic> params) async {
    await _ref
        .read(fdBookingProvider.notifier)
        .bookFixedDeposit(
          personaId: personaId,
          depositAmount: (params['depositAmount'] as num).toDouble(),
          tenorMonths: (params['tenorMonths'] as num).toInt(),
          interestRate: (params['interestRate'] as num).toDouble(),
          payoutOption: InterestPayout.parse(params['payoutOption'] as String),
          autoRenew: params['autoRenew'] as bool,
        );
    final result = _ref.read(fdBookingProvider);
    final booking = result.bookingResult;
    if (result.status != FDBookingStatus.success || booking == null) {
      throw _ActionFailed(
        result.errorMessage ?? 'The fixed deposit could not be booked.',
      );
    }
    final maturesOn = addMonths(booking.createdAt, booking.tenorMonths);
    return 'Done! Your fixed deposit ${booking.id} of ${formatMoney(booking.depositAmount)} is booked '
        'at ${booking.interestRate}%. It matures on ${formatDate(maturesOn)} with '
        '${formatMoney(booking.maturityAmount)}.';
  }

  Future<String> _activateCredit(Map<String, dynamic> params) async {
    await _ref
        .read(creditLineProvider.notifier)
        .activateWith(
          personaId: personaId,
          productType: params['productType'] as String,
          amount: (params['amount'] as num).toDouble(),
          interestRate: (params['interestRate'] as num).toDouble(),
          tenorMonths: (params['tenorMonths'] as num).toInt(),
        );
    final result = _ref.read(creditLineProvider);
    final line = result.result;
    if (result.status != CreditActivationStatus.success || line == null) {
      throw _ActionFailed(
        result.errorMessage ?? 'The credit could not be activated.',
      );
    }
    return line.isLoan
        ? 'Done! ${formatMoney(line.amount)} has been credited to your account at '
              '${line.interestRate}% (ref ${line.id}).'
        : 'Done! Your overdraft line of ${formatMoney(line.amount)} is active at '
              '${line.interestRate}% (ref ${line.id}). You can use it for payments right away.';
  }

  Future<String> _pay(Map<String, dynamic> params) async {
    final receipt = await _repository.makePayment(
      personaId: personaId,
      payee: params['payee'] as String,
      amount: (params['amount'] as num).toDouble(),
      category: params['category'] as String,
    );
    await _ref.read(personaProvider.notifier).refreshPersonas();
    final balance = (receipt['balanceAfter'] as num).toDouble();
    final overdraft = balance < 0
        ? ' (${formatMoney(-balance)} is drawn from your overdraft)'
        : '';
    return 'Paid ${formatMoney((receipt['amount'] as num).toDouble())} to ${receipt['payee']} '
        '(ref ${receipt['id']}). Your balance is now ${formatMoney(balance)}$overdraft.';
  }

  Future<String> _lockCard() async {
    await _repository.lockCard(personaId);
    await _ref.read(personaProvider.notifier).refreshPersonas();
    return 'Your card is locked. Online and in-store payments are blocked until you unlock it.';
  }

  Future<String> _unlockCard() async {
    await _repository.unlockCard(personaId);
    await _ref.read(personaProvider.notifier).refreshPersonas();
    return 'Your card has been unlocked. Online and in-store payments are enabled.';
  }

  /// Next-step chips after a task finishes.
  List<String> _followUps() {
    final persona = _ref.read(personaProvider).selectedPersona;
    final prompts = [
      for (final action in persona.microActions)
        if (action['prompt'] is String) action['prompt'] as String,
    ];
    return [
      ...prompts
          .where((prompt) => prompt.toLowerCase().contains('electricity'))
          .take(1),
      ...prompts
          .where((prompt) => !prompt.toLowerCase().contains('electricity'))
          .take(2),
      "What's my balance?",
    ];
  }

  // ---------- Messages and persistence ----------

  ChatMessage _message(
    ChatRole role,
    String text, {
    ChatIntent? intent,
    String? ticketReference,
    ChatAction? action,
    List<String> suggestions = const [],
    bool isError = false,
  }) {
    final createdAt = _now();
    return ChatMessage(
      id: '${createdAt.microsecondsSinceEpoch}_${_counter++}',
      role: role,
      text: text,
      createdAt: createdAt,
      intent: intent,
      ticketReference: ticketReference,
      action: action,
      actionStatus: action == null ? null : ChatActionStatus.proposed,
      suggestions: suggestions,
      isError: isError,
    );
  }

  ChatMessage _assistantMessage(
    String text, {
    ChatIntent? intent,
    String? ticketReference,
    ChatAction? action,
    List<String> suggestions = const [],
  }) {
    return _message(
      ChatRole.assistant,
      text,
      intent: intent,
      ticketReference: ticketReference,
      action: action,
      suggestions: suggestions,
    );
  }

  ChatMessage _errorMessage(Object error) {
    return _message(
      ChatRole.assistant,
      'Sorry, that did not work: ${describeError(error)}',
      isError: true,
      suggestions: const ['Try again'],
    );
  }

  void _update(ChatState next) {
    state = next;
    unawaited(
      _storage
          .saveChat(personaId, {
            'messages': next.messages
                .map((message) => message.toJson())
                .toList(),
            'pending': next.pending?.toJson(),
          })
          .catchError((Object _) {}),
    );
  }
}

/// A confirmed task that the bank refused; [toString] is the customer-facing text.
class _ActionFailed implements Exception {
  final String message;
  const _ActionFailed(this.message);

  @override
  String toString() => message;
}

/// The conversation for [personaId]; one instance per persona, so switching
/// persona switches conversation.
final chatProvider =
    StateNotifierProvider.family<ChatNotifier, ChatState, String>((
      ref,
      personaId,
    ) {
      return ChatNotifier(
        personaId,
        ref,
        ref.watch(bankingRepositoryProvider),
        ref.watch(localStorageProvider),
      );
    });

final chatThinkingDurationProvider = Provider<Duration>(
  (ref) => ChatNotifier.thinkingDuration,
);
