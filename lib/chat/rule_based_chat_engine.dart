import 'dart:math';

import '../core/format.dart';
import '../core/demo_config.dart';
import '../domain/models.dart';
import 'chat_engine.dart';
import 'chat_models.dart';
import 'intent_classifier.dart';
import 'response_composer.dart';
import 'slot_extractor.dart';

/// Mock "AI": keyword intents, regex slot filling and templated replies that
/// are personalised from the customer's cash flow, spend and holdings.
///
/// Multi-step tasks (an FD that still needs a tenor, a card waiting for a
/// "yes") are carried by [ChatPending], so the engine itself holds no state.
class RuleBasedChatEngine implements ChatEngine {
  static final double fallbackFdRate = selectedDemoCurrency.fixedDepositRate;
  static const List<int> fallbackTenors = [6, 12, 24];
  static final double fallbackMinFd = selectedDemoCurrency.scaleAmount(10000);

  static const List<String> _confirmChips = ['Yes, go ahead', 'No, cancel'];
  static const List<String> _transferPayees = [
    'Jada Winters',
    'Priya Sharma',
    'Arjun Mehta',
    'Maya Patel',
  ];
  static const double _highValueTransferThreshold = 200000;

  /// Words that point at a spend category in "how much do I spend on …".
  static const Map<String, String> _spendKeywords = {
    'dining': 'DINING',
    'restaurant': 'DINING',
    'food': 'DINING',
    'groceries': 'GROCERIES',
    'grocery': 'GROCERIES',
    'shopping': 'SHOPPING',
    'rent': 'RENT',
    'utilities': 'UTILITIES',
    'electricity': 'UTILITIES',
    'transport': 'TRANSPORT',
    'cab': 'TRANSPORT',
    'gst': 'GST',
    'tax': 'GST',
    'payroll': 'PAYROLL',
    'wages': 'PAYROLL',
    'supplier': 'SUPPLIER_PAYMENTS',
    'vendor': 'SUPPLIER_PAYMENTS',
    'subscription': 'SUBSCRIPTIONS',
    'subscriptions': 'SUBSCRIPTIONS',
  };

  /// Words that identify who to pay, mapped to the ledger category whose
  /// latest debit gives the payee and the usual amount.
  static const Map<String, String> _payeeKeywords = {
    'rent': 'RENT',
    'landlord': 'RENT',
    'payroll': 'PAYROLL',
    'employees': 'PAYROLL',
    'wages': 'PAYROLL',
    'salary': 'PAYROLL',
    'electricity': 'UTILITIES',
    'utilities': 'UTILITIES',
    'bill': 'UTILITIES',
    'bills': 'UTILITIES',
    'gst': 'GST',
    'tax': 'GST',
  };

  final IntentClassifier _classifier;
  final SlotExtractor _slots;
  final ResponseComposer _composer;

  const RuleBasedChatEngine({
    IntentClassifier classifier = const IntentClassifier(),
    SlotExtractor slots = const SlotExtractor(),
    ResponseComposer composer = const ResponseComposer(),
  }) : _classifier = classifier,
       _slots = slots,
       _composer = composer;

  @override
  Future<ChatReply> respond(
    ChatContext context,
    String message, {
    ChatPending? pending,
  }) async {
    final normalized = IntentClassifier.normalize(message);
    if (normalized.isEmpty) return _fallback(context);

    if (pending != null) {
      final followUp = _continuePending(context, message, normalized, pending);
      if (followUp != null) return followUp;
    }
    if (IntentClassifier.isNegative(normalized)) {
      return _reply(context, ChatIntent.cancel, _composer.cancelled());
    }

    final match = _classifier.classify(normalized);
    return switch (match.intent) {
      ChatIntent.greeting => _greeting(context),
      ChatIntent.thanks => _reply(
        context,
        ChatIntent.thanks,
        _composer.thanks(),
      ),
      ChatIntent.help => _reply(context, ChatIntent.help, _composer.help()),
      ChatIntent.checkBalance => _reply(
        context,
        ChatIntent.checkBalance,
        _composer.balance(context),
      ),
      ChatIntent.spendInsight => _reply(
        context,
        ChatIntent.spendInsight,
        _composer.spend(
          context,
          categoryKey: _keywordCategory(normalized, _spendKeywords),
        ),
      ),
      ChatIntent.failedTransactions => ChatReply(
        text: _composer.failedTransactions(),
        intent: ChatIntent.failedTransactions,
        suggestions: const [],
      ),
      ChatIntent.recommend => _recommend(context),
      ChatIntent.createFd => _createFd(context, _initialSlots(message)),
      ChatIntent.needCredit => _needCredit(context),
      ChatIntent.payBill => _payBill(
        context,
        normalized,
        _initialSlots(message),
      ),
      ChatIntent.updateDebitLimit => _updateDebitLimit(
        context,
        _initialSlots(message),
      ),
      ChatIntent.lockCard => _lockCard(context, normalized),
      ChatIntent.cancel || ChatIntent.fallback => _fallback(context),
    };
  }

  // ---------- Multi-turn handling ----------

  ChatReply? _continuePending(
    ChatContext context,
    String message,
    String normalized,
    ChatPending pending,
  ) {
    if (IntentClassifier.isNegative(normalized)) {
      return _reply(context, pending.intent, _composer.cancelled());
    }

    if (pending.awaiting == ChatAwaiting.transferApproval) {
      if (!IntentClassifier.isAffirmative(normalized)) {
        return ChatReply(
          text: _composer.transferWarning(
            (pending.slots['amount'] as num).toDouble(),
          ),
          intent: ChatIntent.payBill,
          pending: pending,
          suggestions: const ['Proceed', 'No, cancel'],
        );
      }
      return ChatReply(
        text: _composer.chooseTransferPayee(),
        intent: ChatIntent.payBill,
        pending: ChatPending(
          awaiting: ChatAwaiting.payee,
          intent: ChatIntent.payBill,
          slots: {...pending.slots, 'transferApproved': true},
        ),
        suggestions: _transferPayees,
      );
    }

    if (pending.awaiting == ChatAwaiting.payee) {
      String? payee;
      for (final savedPayee in _transferPayees) {
        if (IntentClassifier.normalize(savedPayee) == normalized) {
          payee = savedPayee;
          break;
        }
      }
      if (payee == null) {
        return ChatReply(
          text: _composer.unknownTransferPayee(),
          intent: ChatIntent.payBill,
          pending: pending,
          suggestions: _transferPayees,
        );
      }
      return _payBill(context, 'transfer', {
        ...pending.slots,
        'payee': payee,
        'isTransfer': true,
      });
    }

    final action = pending.action;
    if (pending.awaiting == ChatAwaiting.confirm &&
        action != null &&
        IntentClassifier.isAffirmative(normalized)) {
      return ChatReply(
        text: _composer.confirming(action),
        intent: pending.intent,
        execute: action,
      );
    }

    final awaiting = pending.awaiting;
    final tenor = _slots.extractTenorMonths(
      message,
      allowBare: awaiting == ChatAwaiting.tenor,
    );
    final amount = _slots.extractAmount(
      message,
      allowBare: awaiting == ChatAwaiting.amount,
    );
    final slots = {...pending.slots};

    switch (pending.intent) {
      case ChatIntent.createFd:
        if (tenor == null && amount == null) return null;
        if (tenor != null) slots['tenorMonths'] = tenor;
        if (amount != null) slots['amount'] = amount;
        return _createFd(context, slots);
      case ChatIntent.payBill:
        if (amount == null) return null;
        slots['amount'] = amount;
        return _payBill(context, normalized, slots);
      case ChatIntent.updateDebitLimit:
        if (amount == null) return null;
        slots['amount'] = amount;
        return _updateDebitLimit(context, slots);
      default:
        return null;
    }
  }

  Map<String, dynamic> _initialSlots(String message) {
    final tenor = _slots.extractTenorMonths(message);
    final amount = _slots.extractAmount(message);
    return {'tenorMonths': ?tenor, 'amount': ?amount};
  }

  // ---------- Small talk and insights ----------

  ChatReply _greeting(ChatContext context) {
    final summary = context.persona.financialSummary;
    final suggestions = summary.netAvailableForInvestment > 0
        ? ['I have some extra money this month', 'Where is my money going?']
        : summary.projectedDeficit > 0
        ? ['Can I cover my upcoming payments?', "What's my balance?"]
        : _composer.defaultSuggestions(context);
    return ChatReply(
      text: _composer.greeting(context),
      intent: ChatIntent.greeting,
      suggestions: suggestions,
    );
  }

  ChatReply _fallback(ChatContext context) =>
      _reply(context, ChatIntent.fallback, _composer.fallback());

  ChatReply _reply(ChatContext context, ChatIntent intent, String text) {
    return ChatReply(
      text: text,
      intent: intent,
      suggestions: _composer.defaultSuggestions(context),
    );
  }

  String? _keywordCategory(String normalized, Map<String, String> keywords) {
    for (final entry in keywords.entries) {
      if (RegExp('\\b${entry.key}\\b').hasMatch(normalized)) return entry.value;
    }
    return null;
  }

  // ---------- Cross-sell ----------

  ChatReply _recommend(ChatContext context) {
    final investment = context.recommendationOf(ProductCategory.investment);
    if (investment != null) {
      final tenor = investment.metadata['defaultTenorMonths'] as int? ?? 12;
      return ChatReply(
        text: _composer.fdRecommendation(context, investment),
        intent: ChatIntent.recommend,
        suggestions: [
          'Create an FD of ${formatMoney(investment.recommendedAmount)} for $tenor months',
          'Where is my money going?',
        ],
      );
    }
    if (context.recommendationOf(ProductCategory.credit) != null) {
      return _needCredit(context);
    }
    return _reply(
      context,
      ChatIntent.recommend,
      _composer.noRecommendation(context),
    );
  }

  ChatReply _needCredit(ChatContext context) {
    final summary = context.persona.financialSummary;
    final credit = context.recommendationOf(ProductCategory.credit);

    if (summary.projectedDeficit <= 0) {
      return _reply(
        context,
        ChatIntent.needCredit,
        _composer.noCreditNeeded(context),
      );
    }
    if (credit == null) {
      return _reply(
        context,
        ChatIntent.needCredit,
        _composer.creditAlreadyActive(context),
      );
    }
    return _proposeCredit(
      context,
      credit,
      text: _composer.creditGap(context, credit),
    );
  }

  ChatReply _proposeCredit(
    ChatContext context,
    ProductRecommendation credit, {
    required String text,
  }) {
    final action = _creditAction(credit);
    return ChatReply(
      text: text,
      intent: ChatIntent.needCredit,
      action: action,
      pending: ChatPending(
        awaiting: ChatAwaiting.confirm,
        intent: ChatIntent.needCredit,
        action: action,
      ),
      suggestions: _confirmChips,
    );
  }

  ChatAction _creditAction(ProductRecommendation credit) {
    final metadata = credit.metadata;
    final isLoan = credit.actionType == ActionType.applyLoan;
    final productType =
        metadata['productType'] as String? ??
        (isLoan ? ProductTypes.personalLoan : ProductTypes.creditLine);
    final tenor = (metadata['defaultTenorMonths'] as num?)?.toInt() ?? 12;
    final zeroFee = metadata['zeroProcessingFee'] == true;

    return ChatAction(
      type: ChatActionType.activateCredit,
      title: credit.title,
      confirmLabel: isLoan ? 'Accept loan' : 'Activate',
      params: {
        'productType': productType,
        'amount': credit.recommendedAmount,
        'interestRate': credit.expectedReturnOrInterestRate,
        'tenorMonths': tenor,
      },
      details: [
        ChatDetail(
          isLoan ? 'Loan amount' : 'Credit limit',
          formatMoney(credit.recommendedAmount),
        ),
        ChatDetail(
          'Interest rate',
          '${credit.expectedReturnOrInterestRate}% p.a.',
        ),
        ChatDetail('Tenor', '$tenor months'),
        ChatDetail('Processing fee', zeroFee ? 'Nil' : 'As per bank schedule'),
        if (metadata['preApproved'] == true)
          const ChatDetail('Approval', 'Pre-approved'),
      ],
    );
  }

  // ---------- Fixed deposit ----------

  ChatReply _createFd(ChatContext context, Map<String, dynamic> slots) {
    final summary = context.persona.financialSummary;
    final offer = context.recommendationOf(ProductCategory.investment);
    final terms =
        offer?.metadata ??
        context.fdProduct?.terms ??
        const <String, dynamic>{};
    final rate =
        offer?.expectedReturnOrInterestRate ??
        context.fdProduct?.rate ??
        fallbackFdRate;
    final tenorOptions =
        (terms['tenorOptions'] as List<dynamic>?)
            ?.map((item) => (item as num).toInt())
            .toList() ??
        fallbackTenors;
    final minAmount = (terms['minAmount'] as num?)?.toDouble() ?? fallbackMinFd;
    final balance = summary.currentBalance;
    final safeMax = _floorTo(max(0.0, balance - summary.minimumBuffer), 1000);

    ChatReply ask(
      ChatAwaiting awaiting,
      String text,
      List<String> chips,
      Map<String, dynamic> kept,
    ) {
      return ChatReply(
        text: text,
        intent: ChatIntent.createFd,
        pending: ChatPending(
          awaiting: awaiting,
          intent: ChatIntent.createFd,
          slots: kept,
        ),
        suggestions: chips,
      );
    }

    if (safeMax < minAmount) {
      return _reply(
        context,
        ChatIntent.createFd,
        _composer.fdNoFreeFunds(buffer: summary.minimumBuffer),
      );
    }

    final amount = (slots['amount'] as num?)?.toDouble();
    final tenor = (slots['tenorMonths'] as num?)?.toInt();
    final withoutAmount = {...slots}..remove('amount');
    final suggestedAmount = min(offer?.recommendedAmount ?? safeMax, safeMax);

    if (amount == null) {
      return ask(
        ChatAwaiting.amount,
        _composer.askFdAmount(
          safeMax: safeMax,
          recommended: offer?.recommendedAmount,
        ),
        [formatMoney(suggestedAmount)],
        withoutAmount,
      );
    }
    if (amount < minAmount) {
      return ask(ChatAwaiting.amount, _composer.fdAmountTooSmall(minAmount), [
        formatMoney(suggestedAmount),
      ], withoutAmount);
    }
    if (amount > safeMax) {
      return ask(
        ChatAwaiting.amount,
        _composer.fdAmountTooHigh(
          amount: amount,
          balance: balance,
          buffer: summary.minimumBuffer,
          safeMax: safeMax,
        ),
        [formatMoney(safeMax)],
        withoutAmount,
      );
    }
    if (tenor == null) {
      return ask(
        ChatAwaiting.tenor,
        _composer.askFdTenor(options: tenorOptions),
        [for (final months in tenorOptions) '$months months'],
        {'amount': amount},
      );
    }

    final payout = terms['payoutOption'] as String? ?? 'AT_MATURITY';
    final autoRenew = terms['autoRenew'] as bool? ?? true;
    final maturity = amount + amount * (rate / 100) * (tenor / 12);
    final action = ChatAction(
      type: ChatActionType.openFd,
      title: 'Fixed Deposit',
      confirmLabel: 'Confirm FD',
      params: {
        'depositAmount': amount,
        'tenorMonths': tenor,
        'interestRate': rate,
        'payoutOption': payout,
        'autoRenew': autoRenew,
      },
      details: [
        ChatDetail('Amount', formatMoney(amount)),
        ChatDetail('Tenor', '$tenor months'),
        ChatDetail('Interest rate', '$rate% p.a.'),
        ChatDetail('Interest payout', _payoutLabel(payout)),
        ChatDetail('Auto-renew', autoRenew ? 'Yes' : 'No'),
        ChatDetail('Maturity amount', formatMoney(maturity)),
        ChatDetail('Balance after', formatMoney(balance - amount)),
      ],
    );
    return ChatReply(
      text: _composer.fdSummary(),
      intent: ChatIntent.createFd,
      action: action,
      pending: ChatPending(
        awaiting: ChatAwaiting.confirm,
        intent: ChatIntent.createFd,
        slots: {'amount': amount, 'tenorMonths': tenor},
        action: action,
      ),
      suggestions: _confirmChips,
    );
  }

  String _payoutLabel(String code) {
    return switch (code) {
      'MONTHLY' => 'Monthly',
      'QUARTERLY' => 'Quarterly',
      _ => 'At maturity',
    };
  }

  // ---------- Payments and card ----------

  ChatReply _payBill(
    ChatContext context,
    String normalized,
    Map<String, dynamic> slots,
  ) {
    final persona = context.persona;
    final balance = persona.financialSummary.currentBalance;
    final category =
        slots['payeeCategory'] as String? ??
        _keywordCategory(normalized, _payeeKeywords);
    final isTransfer =
        slots['isTransfer'] as bool? ??
        RegExp(r'\btransfer\b').hasMatch(normalized);

    var payee = slots['payee'] as String?;
    var amount = (slots['amount'] as num?)?.toDouble();
    if (category != null) {
      final last = _lastDebit(persona, category);
      payee ??= last?.description ?? ResponseComposer.categoryLabel(category);
      amount ??= last?.amount;
    }
    if (!isTransfer && payee != null && category != null) {
      final paidTransaction = _paidThisMonth(
        context,
        payee: payee,
        category: category,
      );
      if (paidTransaction != null) {
        final reference = paidTransaction.id.startsWith('t_')
            ? paidTransaction.id.substring(2)
            : paidTransaction.id;
        final completedAction = ChatAction(
          type: ChatActionType.payBill,
          title: 'Payment',
          confirmLabel: 'Paid',
          params: {
            'payee': paidTransaction.description,
            'amount': paidTransaction.amount,
            'category': paidTransaction.category,
          },
          details: [
            ChatDetail('Payee', paidTransaction.description),
            ChatDetail('Amount', formatMoney(paidTransaction.amount)),
            ChatDetail('Status', 'Completed'),
            ChatDetail('Reference', reference),
          ],
        );
        return ChatReply(
          text:
              'Your payment to $payee is already done for this month '
              '(ref $reference).',
          intent: ChatIntent.payBill,
          action: completedAction,
          actionCompleted: true,
          suggestions: _composer.defaultSuggestions(context),
        );
      }
    }
    final transferApproved = slots['transferApproved'] == true;
    if (isTransfer &&
        amount != null &&
        amount >= _highValueTransferThreshold &&
        !transferApproved) {
      return ChatReply(
        text: _composer.transferWarning(amount),
        intent: ChatIntent.payBill,
        pending: ChatPending(
          awaiting: ChatAwaiting.transferApproval,
          intent: ChatIntent.payBill,
          slots: {'amount': amount, 'isTransfer': true},
        ),
        suggestions: const ['Proceed', 'No, cancel'],
      );
    }

    if (payee == null) {
      return ChatReply(
        text: isTransfer
            ? _composer.chooseTransferPayee()
            : _composer.askPayee(context),
        intent: ChatIntent.payBill,
        pending: ChatPending(
          awaiting: ChatAwaiting.payee,
          intent: ChatIntent.payBill,
          slots: {
            'amount': ?amount,
            'isTransfer': isTransfer,
            'transferApproved': transferApproved,
          },
        ),
        suggestions: isTransfer
            ? _transferPayees
            : _composer.defaultSuggestions(context),
      );
    }
    if (amount == null) {
      return ChatReply(
        text: _composer.askPayAmount(payee),
        intent: ChatIntent.payBill,
        pending: ChatPending(
          awaiting: ChatAwaiting.amount,
          intent: ChatIntent.payBill,
          slots: {
            'payeeCategory': ?category,
            'payee': payee,
            'isTransfer': isTransfer,
            'transferApproved': transferApproved,
          },
        ),
        suggestions: const [],
      );
    }

    final available = balance + persona.availableCredit;
    if (amount > available) {
      final credit = context.recommendationOf(ProductCategory.credit);
      if (credit != null) {
        return _proposeCredit(
          context,
          credit,
          text: _composer.paymentShort(
            payee: payee,
            amount: amount,
            shortfall: amount - balance,
            context: context,
            recommendation: credit,
          ),
        );
      }
      return _reply(
        context,
        ChatIntent.payBill,
        _composer.paymentCannotCover(
          payee: payee,
          amount: amount,
          available: max(0.0, available),
        ),
      );
    }

    final drawn = max(0.0, amount - balance);
    final action = ChatAction(
      type: ChatActionType.payBill,
      title: isTransfer ? 'Transfer' : 'Payment',
      confirmLabel: isTransfer ? 'Confirm transfer' : 'Pay now',
      params: {
        'payee': payee,
        'amount': amount,
        'category': category ?? (isTransfer ? 'TRANSFER' : 'OTHERS'),
      },
      details: [
        ChatDetail(isTransfer ? 'Recipient' : 'Payee', payee),
        ChatDetail('Amount', formatMoney(amount)),
        if (drawn > 0) ChatDetail('From overdraft', formatMoney(drawn)),
        ChatDetail('Balance after', formatMoney(balance - amount)),
      ],
    );
    return ChatReply(
      text: isTransfer
          ? _composer.transferReview(payee: payee, amount: amount)
          : _composer.paymentSummary(payee: payee, drawn: drawn),
      intent: ChatIntent.payBill,
      action: action,
      pending: ChatPending(
        awaiting: ChatAwaiting.confirm,
        intent: ChatIntent.payBill,
        slots: {'payeeCategory': ?category, 'payee': payee, 'amount': amount},
        action: action,
      ),
      suggestions: _confirmChips,
    );
  }

  ChatReply _updateDebitLimit(ChatContext context, Map<String, dynamic> slots) {
    const cardLastFour = '1234';
    const defaultTarget = 150000;
    const maxLimit = 500000;
    final currentLimit = context.debitCardLimit;
    final requested = (slots['amount'] as num?)?.round() ?? defaultTarget;
    final target = min(max(requested, currentLimit + 50000), maxLimit);
    final action = ChatAction(
      type: ChatActionType.updateDebitLimit,
      title: 'Debit card limit',
      confirmLabel: 'Confirm limit',
      params: {
        'currentLimit': currentLimit,
        'requestedLimit': target,
        'cardLastFour': cardLastFour,
      },
      details: [
        ChatDetail('Card', '•••• $cardLastFour'),
        ChatDetail('Current limit', formatMoney(currentLimit.toDouble())),
        ChatDetail('New limit', formatMoney(target.toDouble())),
        const ChatDetail('Effective', 'Immediately after confirm'),
      ],
    );
    return ChatReply(
      text: _composer.debitLimitSummary(
        currentLimit: currentLimit,
        requestedLimit: target,
        cardLastFour: cardLastFour,
      ),
      intent: ChatIntent.updateDebitLimit,
      action: action,
      pending: ChatPending(
        awaiting: ChatAwaiting.confirm,
        intent: ChatIntent.updateDebitLimit,
        slots: {'amount': target},
        action: action,
      ),
      suggestions: _confirmChips,
    );
  }

  BankTransaction? _lastDebit(Persona persona, String category) {
    for (final transaction in persona.recentTransactions) {
      if (transaction.type == TransactionType.debit &&
          transaction.category == category) {
        return transaction;
      }
    }
    return null;
  }

  BankTransaction? _paidThisMonth(
    ChatContext context, {
    required String payee,
    required String category,
  }) {
    final now = context.now ?? DateTime.now();
    final normalizedPayee = payee.trim().toLowerCase();
    for (final transaction in context.persona.recentTransactions) {
      if (transaction.type != TransactionType.debit ||
          transaction.category != category ||
          !transaction.id.startsWith('t_PAY_') ||
          transaction.date.year != now.year ||
          transaction.date.month != now.month ||
          transaction.description.trim().toLowerCase() != normalizedPayee) {
        continue;
      }
      return transaction;
    }
    return null;
  }

  ChatReply _lockCard(ChatContext context, String normalized) {
    final explicitlyUnlocking = RegExp(r'\bunlock\b').hasMatch(normalized);
    if (!context.persona.cardLocked) {
      if (explicitlyUnlocking) {
        return _reply(
          context,
          ChatIntent.lockCard,
          'Your card is already unlocked.',
        );
      }
      const action = ChatAction(
        type: ChatActionType.lockCard,
        title: 'Lock card',
        confirmLabel: 'Lock card',
        params: {},
        details: [
          ChatDetail('Card', 'Debit card'),
          ChatDetail('Effect', 'Online and in-store use blocked'),
        ],
      );
      return ChatReply(
        text: _composer.lockSummary(),
        intent: ChatIntent.lockCard,
        action: action,
        pending: const ChatPending(
          awaiting: ChatAwaiting.confirm,
          intent: ChatIntent.lockCard,
          action: action,
        ),
        suggestions: _confirmChips,
      );
    }

    const action = ChatAction(
      type: ChatActionType.unlockCard,
      title: 'Unlock card',
      confirmLabel: 'Unlock card',
      params: {},
      details: [
        ChatDetail('Card', 'Debit card'),
        ChatDetail('Effect', 'Online and in-store payments enabled'),
      ],
    );
    return ChatReply(
      text: 'Your debit card is currently locked. Would you like to unlock it?',
      intent: ChatIntent.lockCard,
      action: action,
      pending: const ChatPending(
        awaiting: ChatAwaiting.confirm,
        intent: ChatIntent.lockCard,
        action: action,
      ),
      suggestions: _confirmChips,
    );
  }

  static double _floorTo(double value, double step) =>
      (value / step).floor() * step;
}
