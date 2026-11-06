import '../core/format.dart';
import '../domain/models.dart';
import 'chat_engine.dart';
import 'chat_models.dart';

/// All customer-facing wording, so the dialog logic stays readable and the
/// copy can be tuned in one place.
class ResponseComposer {
  const ResponseComposer();

  static String firstName(Persona persona) => persona.name.split(' ').first;

  /// "SUPPLIER_PAYMENTS" → "Supplier payments".
  static String categoryLabel(String key) {
    if (key == 'GST') return key;
    final words = key.toLowerCase().replaceAll('_', ' ');
    return words.isEmpty
        ? words
        : '${words[0].toUpperCase()}${words.substring(1)}';
  }

  /// Chips that always make sense: the persona's own quick actions first.
  List<String> defaultSuggestions(ChatContext context) {
    final prompts = [
      for (final action in context.persona.microActions)
        if (action['prompt'] is String) action['prompt'] as String,
    ];
    final electricityPrompt = prompts.where(
      (prompt) => prompt.toLowerCase().contains('electricity'),
    );
    final otherPrompts = prompts.where(
      (prompt) => !prompt.toLowerCase().contains('electricity'),
    );
    return {
      ...electricityPrompt.take(1),
      ...otherPrompts.take(2),
      'How much I spent in this month',
      'Book an FD for 50,000.',
      'Show failed transactions yesterday.',
      'Transfer ₹2 lakh',
      'Increase my debit card limit.',
      "What's my balance?",
    }.toList();
  }

  String greeting(ChatContext context) {
    final persona = context.persona;
    final summary = persona.financialSummary;
    final name = firstName(persona);
    if (summary.netAvailableForInvestment > 0) {
      return 'Hi $name! Your balance is ${formatMoney(summary.currentBalance)} and about '
          '${formatMoney(summary.netAvailableForInvestment)} of it is free over the next 30 days '
          'after your bills and safety buffer. Want me to put it to work?';
    }
    if (summary.projectedDeficit > 0) {
      return 'Hi $name! Heads-up: your upcoming payments could leave you about '
          '${formatMoney(summary.projectedDeficit)} short over the next 30 days. '
          'I can help you cover it.';
    }
    return 'Hi $name! How can I help you today?';
  }

  String help() {
    return 'I can check your balance, break down your spending, suggest what to do with '
        'spare money, open a fixed deposit, arrange credit when you are short, pay bills, '
        'or lock your card. Just ask.';
  }

  String thanks() => "You're welcome! Anything else I can help with?";

  String fallback() {
    return "I didn't quite catch that. I can check your balance, explain your spending, "
        'suggest how to use your money, open an FD or arrange credit. Try one of these:';
  }

  String cancelled() =>
      "No problem, I've cancelled that. Anything else I can help with?";

  String confirming(ChatAction action) => 'Great, ${_gerund(action)}…';

  String _gerund(ChatAction action) {
    return switch (action.type) {
      ChatActionType.openFd => 'booking your fixed deposit',
      ChatActionType.activateCredit =>
        'activating ${action.title.toLowerCase()}',
      ChatActionType.payBill => 'sending your payment',
      ChatActionType.updateDebitLimit => 'updating your debit card limit',
      ChatActionType.lockCard => 'locking your card',
      ChatActionType.unlockCard => 'unlocking your card',
    };
  }

  String balance(ChatContext context) {
    final persona = context.persona;
    final summary = persona.financialSummary;
    final buffer = StringBuffer(
      'Your balance is ${formatMoney(summary.currentBalance)}. Over the next 30 days you expect '
      '${formatMoney(summary.projectedIncome30D)} in and ${formatMoney(summary.projectedSpend30D)} out. ',
    );
    if (summary.projectedDeficit > 0) {
      buffer.write(
        'After keeping your ${formatMoney(summary.minimumBuffer)} safety buffer, '
        "you'd be about ${formatMoney(summary.projectedDeficit)} short.",
      );
    } else {
      buffer.write(
        'After keeping your ${formatMoney(summary.minimumBuffer)} safety buffer, '
        "you'll have about ${formatMoney(summary.netAvailableForInvestment)} free.",
      );
    }
    if (persona.availableCredit > 0) {
      buffer.write(
        ' You also have ${formatMoney(persona.availableCredit)} of overdraft available.',
      );
    }
    return buffer.toString();
  }

  String spend(ChatContext context, {String? categoryKey}) {
    final persona = context.persona;
    final total = persona.totalSpend30D;
    if (total <= 0) {
      return "I don't have any spending recorded for you this month yet.";
    }

    String share(double amount) => '${(amount / total * 100).round()}%';

    if (categoryKey != null) {
      final match = persona.spendByCategory.where(
        (item) => item.category == categoryKey,
      );
      final label = categoryKey == 'GST'
          ? 'GST'
          : categoryLabel(categoryKey).toLowerCase();
      if (match.isEmpty) return "I don't see any $label spending this month.";
      final amount = match.first.amount;
      return 'You spent ${formatMoney(amount)} on $label this month, '
          '${share(amount)} of your ${formatMoney(total)} total spend.';
    }

    final sorted = [...persona.spendByCategory]
      ..sort((a, b) => b.amount.compareTo(a.amount));
    final lines = sorted
        .take(5)
        .map(
          (item) =>
              '• ${categoryLabel(item.category)}: ${formatMoney(item.amount)} (${share(item.amount)})',
        )
        .join('\n');
    final top = sorted.isEmpty ? null : sorted.first;
    final tip = top == null
        ? ''
        : '\n\nYour spending is higher than last month, mainly because of '
              '${categoryLabel(top.category).toLowerCase()}. Consider setting a '
              '${categoryLabel(top.category).toLowerCase()} budget for next month.';
    return 'Your spending totals ${formatMoney(total)} this month.\n$lines$tip';
  }

  String failedTransactions() {
    return 'Failed transactions report';
  }

  String debitLimitSummary({
    required int currentLimit,
    required int requestedLimit,
    required String cardLastFour,
  }) {
    return 'Your debit card ending in $cardLastFour currently has a daily limit of '
        '${formatMoney(currentLimit.toDouble())}. I can raise it to '
        '${formatMoney(requestedLimit.toDouble())} based on your account standing. Shall I go ahead?';
  }

  String debitLimitDone({
    required int from,
    required int to,
    required String cardLastFour,
  }) {
    return "Your debit card's daily transaction limit has been increased from "
        '${formatMoney(from.toDouble())} to ${formatMoney(to.toDouble())}. '
        'This increase was approved based on your account tenure, consistent '
        'transaction activity, and good account standing. The new limit is '
        'effective immediately for your debit card ending in $cardLastFour.';
  }

  String transferWarning(double amount) {
    return "We've identified this transfer as unusual based on your recent "
        'account activity due to the requested amount of ${formatMoney(amount)}. '
        'Please review the transaction details and confirm whether you wish to proceed.';
  }

  String chooseTransferPayee() => 'Who should receive the transfer?';

  String unknownTransferPayee() =>
      "I couldn't find that recipient in your saved payees. Please choose one of the listed recipients.";

  String transferReview({required String payee, required double amount}) {
    return 'I can help you review and confirm this transfer of '
        '${formatMoney(amount)} to $payee.';
  }

  String noRecommendation(ChatContext context) {
    final persona = context.persona;
    if (persona.financialSummary.projectedDeficit > 0) {
      return 'I do not see spare cash right now, and you already have the credit support available '
          'to cover your upcoming payments.';
    }
    return "I don't have a new offer for you right now. Your free cash is below what a "
        'fixed deposit needs. Check back after your next credit.';
  }

  String fdRecommendation(
    ChatContext context,
    ProductRecommendation recommendation,
  ) {
    final summary = context.persona.financialSummary;
    final tenor = recommendation.metadata['defaultTenorMonths'] as int? ?? 12;
    final amount = recommendation.recommendedAmount;
    final rate = recommendation.expectedReturnOrInterestRate;
    final maturity = amount + amount * (rate / 100) * (tenor / 12);
    return 'You have about ${formatMoney(summary.netAvailableForInvestment)} free after your upcoming '
        "bills. I'd suggest putting ${formatMoney(amount)} into a fixed deposit at $rate% for $tenor months. "
        'It grows to ${formatMoney(maturity)}, and your balance would still be '
        '${formatMoney(summary.currentBalance - amount)}.';
  }

  String askFdAmount({required double safeMax, double? recommended}) {
    final hint = recommended == null
        ? 'You can safely deposit up to ${formatMoney(safeMax)}.'
        : 'I recommend ${formatMoney(recommended)}; you can safely deposit up to ${formatMoney(safeMax)}.';
    return 'How much would you like to deposit? $hint';
  }

  String fdAmountTooSmall(double minimum) =>
      'The minimum for this fixed deposit is ${formatMoney(minimum)}. How much would you like to deposit?';

  String fdAmountTooHigh({
    required double amount,
    required double balance,
    required double buffer,
    required double safeMax,
  }) {
    if (amount > balance) {
      return 'You only have ${formatMoney(balance)} in your account, so ${formatMoney(amount)} is too high. '
          'The most I would suggest is ${formatMoney(safeMax)}. What amount works?';
    }
    return 'That would take you below your ${formatMoney(buffer)} safety buffer. '
        'The most I would suggest is ${formatMoney(safeMax)}. What amount works?';
  }

  String fdNoFreeFunds({required double buffer}) =>
      "You don't have free funds above your ${formatMoney(buffer)} safety buffer for a fixed deposit right now.";

  String askFdTenor({required List<int> options}) =>
      'For how long? Popular choices are ${options.map((m) => '$m months').join(', ')}.';

  String fdSummary() => "Here's your fixed deposit. Shall I go ahead?";

  String creditGap(ChatContext context, ProductRecommendation recommendation) {
    final summary = context.persona.financialSummary;
    final rate = recommendation.expectedReturnOrInterestRate;
    return 'Over the next 30 days you expect ${formatMoney(summary.projectedIncome30D)} in and '
        '${formatMoney(summary.projectedSpend30D)} out, so you could be about '
        '${formatMoney(summary.projectedDeficit)} short even after using your balance of '
        '${formatMoney(summary.currentBalance)}. I can arrange the ${recommendation.title} for '
        '${formatMoney(recommendation.recommendedAmount)} at $rate% to cover it.';
  }

  String creditAlreadyActive(ChatContext context) {
    final persona = context.persona;
    final limit = persona.availableCredit;
    return limit > 0
        ? 'You have ${formatMoney(limit)} of overdraft active, which covers your projected gap of '
              '${formatMoney(persona.financialSummary.projectedDeficit)}. No further credit is needed.'
        : 'You already have credit arranged for your projected gap of '
              '${formatMoney(persona.financialSummary.projectedDeficit)}.';
  }

  String noCreditNeeded(ChatContext context) {
    final summary = context.persona.financialSummary;
    return "You're covered: after your upcoming payments and safety buffer you'd still have about "
        '${formatMoney(summary.netAvailableForInvestment)} free, so you do not need credit right now.';
  }

  String askPayee(ChatContext context) =>
      'Who would you like to pay, and how much? For example, "Pay my house rent".';

  String askPayAmount(String payee) =>
      'How much would you like to pay to $payee?';

  String paymentSummary({required String payee, required double drawn}) {
    final overdraft = drawn > 0
        ? ' ${formatMoney(drawn)} of it will be drawn from your overdraft.'
        : '';
    return "Here's the payment to $payee.$overdraft Shall I send it?";
  }

  String paymentShort({
    required String payee,
    required double amount,
    required double shortfall,
    required ChatContext context,
    required ProductRecommendation recommendation,
  }) {
    return 'Paying ${formatMoney(amount)} to $payee is ${formatMoney(shortfall)} more than your balance of '
        '${formatMoney(context.persona.financialSummary.currentBalance)}. '
        'I can arrange the ${recommendation.title} for ${formatMoney(recommendation.recommendedAmount)} '
        'at ${recommendation.expectedReturnOrInterestRate}% so the payment goes through.';
  }

  String paymentCannotCover({
    required String payee,
    required double amount,
    required double available,
  }) {
    return 'Paying ${formatMoney(amount)} to $payee is more than the ${formatMoney(available)} you can use '
        'right now. Try a smaller amount.';
  }

  String lockSummary() =>
      'I can lock your card right away. You can unlock it any time. Shall I go ahead?';

  String alreadyLocked() => 'Your card is already locked.';
}
