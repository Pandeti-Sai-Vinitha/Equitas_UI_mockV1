import 'chat_models.dart';

class IntentMatch {
  final ChatIntent intent;
  final int score;

  const IntentMatch(this.intent, this.score);
}

class _Rule {
  final ChatIntent intent;
  final RegExp pattern;
  final int weight;

  _Rule(this.intent, String pattern, this.weight) : pattern = RegExp(pattern);
}

/// Scores keyword patterns per intent; the highest score at or above
/// [threshold] wins, otherwise the message is a [ChatIntent.fallback].
class IntentClassifier {
  static const int threshold = 3;

  const IntentClassifier();

  /// Lower-cases and collapses whitespace so rules can stay simple.
  static String normalize(String text) {
    return text
        .toLowerCase()
        .replaceAll('’', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static final RegExp _yes = RegExp(
    r'^(yes|yep|yeah|yup|y|sure|ok|okay|confirm|confirmed|go ahead|do it|proceed|continue|please do|sounds good|looks good|book it|open it|activate it)\b',
  );

  static final RegExp _no = RegExp(
    r"^(no|nope|nah|cancel|stop|not now|never ?mind|don't|do not|abort)\b",
  );

  static bool isAffirmative(String normalized) => _yes.hasMatch(normalized);

  static bool isNegative(String normalized) => _no.hasMatch(normalized);

  /// Earlier entries win ties.
  static const List<ChatIntent> _priority = [
    ChatIntent.lockCard,
    ChatIntent.updateDebitLimit,
    ChatIntent.failedTransactions,
    ChatIntent.createFd,
    ChatIntent.payBill,
    ChatIntent.needCredit,
    ChatIntent.recommend,
    ChatIntent.spendInsight,
    ChatIntent.checkBalance,
    ChatIntent.help,
    ChatIntent.greeting,
    ChatIntent.thanks,
  ];

  static final List<_Rule> _rules = [
    // Unlocking a locked card uses the same confirmation flow as locking.
    _Rule(ChatIntent.lockCard, r'\bunlock\b.*\bcard\b', 7),

    // Locking a card
    _Rule(
      ChatIntent.lockCard,
      r'\b(lock|block|freeze|disable|deactivate)\b.*\bcard\b',
      6,
    ),
    _Rule(
      ChatIntent.lockCard,
      r'\bcard\b.*\b(lock|block|lost|stolen|misplaced|missing|freeze)\b',
      6,
    ),
    _Rule(
      ChatIntent.lockCard,
      r'\b(lost|stolen|misplaced|missing)\b.*\bcard\b',
      6,
    ),

    // Debit card limit changes
    _Rule(
      ChatIntent.updateDebitLimit,
      r'\b(debit|card)\b.*\blimit\b.*\b(increase|raise|set|change|update)\b',
      7,
    ),
    _Rule(
      ChatIntent.updateDebitLimit,
      r'\b(increase|raise|set|change|update)\b.*\b(debit|card)\b.*\blimit\b',
      7,
    ),
    _Rule(ChatIntent.updateDebitLimit, r'\bdebit card limit\b', 5),

    // Failed transactions report
    _Rule(ChatIntent.failedTransactions, r'\bfailed\b.*\btransactions?\b', 7),
    _Rule(ChatIntent.failedTransactions, r'\btransactions?\b.*\bfailed\b', 7),

    // Opening a fixed deposit
    _Rule(
      ChatIntent.createFd,
      r'\b(fd|fds|fixed deposits?|term deposits?)\b',
      3,
    ),
    _Rule(
      ChatIntent.createFd,
      r'\b(create|open|book|start|make|set up|setup|place)\b',
      2,
    ),
    _Rule(ChatIntent.createFd, r'\bdeposit\b', 3),

    // Paying someone
    _Rule(ChatIntent.payBill, r'\b(pay|paying|payment|payments)\b', 2),
    _Rule(ChatIntent.payBill, r'\bsend (money|funds|rupees|cash)\b', 3),
    _Rule(ChatIntent.payBill, r'\btransfer\b', 3),
    _Rule(
      ChatIntent.payBill,
      r'\b(rent|landlord|emi|electricity|bills?|payroll|wages|employees|salary payment)\b',
      3,
    ),
    _Rule(ChatIntent.payBill, r'\bapprove\b', 2),
    // "pay my gst" is a payment, while "how much gst" stays a spending question.
    _Rule(ChatIntent.payBill, r'\b(pay|paying|payment)\b.*\b(gst|tax)\b', 3),

    // Needing credit / a liquidity gap
    _Rule(
      ChatIntent.needCredit,
      r'\b(short|low) (on|of) (cash|funds|money)\b',
      5,
    ),
    _Rule(
      ChatIntent.needCredit,
      r'\bcash (crunch|crisis|gap|shortage|flow problem)\b',
      5,
    ),
    _Rule(
      ChatIntent.needCredit,
      r'\b(shortfall|liquidity|overdraft|credit line|line of credit|working capital)\b',
      4,
    ),
    _Rule(ChatIntent.needCredit, r'\b(loan|borrow|borrowing|credit)\b', 3),
    _Rule(
      ChatIntent.needCredit,
      r'\bneed (some |more )?(money|funds|cash|financing|finance)\b',
      4,
    ),
    _Rule(ChatIntent.needCredit, r'\bcan i (pay|afford|cover|manage)\b', 4),
    _Rule(
      ChatIntent.needCredit,
      r'\b(supplier|vendor|distributor|inventory|payables?)\b',
      3,
    ),
    _Rule(
      ChatIntent.needCredit,
      r'\b(run out of|not enough) (money|cash|funds)\b',
      5,
    ),

    // Asking what to do with money
    _Rule(
      ChatIntent.recommend,
      r'\b(extra|spare|idle|surplus|excess|free) (money|cash|funds|balance)\b',
      4,
    ),
    _Rule(ChatIntent.recommend, r'\b(savings?|surplus)\b', 3),
    _Rule(ChatIntent.recommend, r'\bwhat (should|can) i do with\b', 4),
    _Rule(ChatIntent.recommend, r'\binvest(ing|ment|ments)?\b', 3),
    _Rule(ChatIntent.recommend, r'\bgrow my (money|savings)\b', 4),
    _Rule(
      ChatIntent.recommend,
      r'\b(recommend|suggest|advise|advice|offers?)\b',
      3,
    ),
    _Rule(ChatIntent.recommend, r'\bwhere (to|should i) (put|park|keep)\b', 4),
    _Rule(ChatIntent.recommend, r'\bbest (product|option|scheme)\b', 3),

    // Spending insight
    _Rule(
      ChatIntent.spendInsight,
      r'\b(spend|spent|spending|expenses?|expenditure)\b',
      4,
    ),
    _Rule(
      ChatIntent.spendInsight,
      r'\bhow much (did i|have i|do i) (spend|spent|pay|paid)\b',
      3,
    ),
    _Rule(
      ChatIntent.spendInsight,
      r'\bwhere (is|did|does) my money (go|going|went)\b',
      6,
    ),
    _Rule(
      ChatIntent.spendInsight,
      r'\b(dining|groceries|grocery|shopping|subscriptions?|utilities|gst|tax|categor(y|ies)|breakdown|top spends?)\b',
      3,
    ),
    _Rule(ChatIntent.spendInsight, r'\bkeep aside\b', 2),

    // Balance
    _Rule(ChatIntent.checkBalance, r'\bbalance\b', 4),
    _Rule(ChatIntent.checkBalance, r'\bhow much (money |cash )?do i have\b', 5),
    _Rule(
      ChatIntent.checkBalance,
      r'\b(money|cash) (in|left in) my account\b',
      4,
    ),
    _Rule(
      ChatIntent.checkBalance,
      r'\b(financial (health|snapshot|summary|position)|how am i doing)\b',
      4,
    ),

    // Chit-chat
    _Rule(
      ChatIntent.help,
      r'\b(help|what can you do|how does (this|it) work|what do you do|features|capabilities|what can i ask)\b',
      4,
    ),
    _Rule(
      ChatIntent.greeting,
      r'^(hi|hii+|hello|hey|namaste|good (morning|afternoon|evening))\W*(there|bank|assistant)?\W*$',
      5,
    ),
    _Rule(ChatIntent.thanks, r'\b(thanks|thank you|thx)\b', 5),
  ];

  IntentMatch classify(String normalized) {
    final scores = <ChatIntent, int>{};
    for (final rule in _rules) {
      if (rule.pattern.hasMatch(normalized)) {
        scores[rule.intent] = (scores[rule.intent] ?? 0) + rule.weight;
      }
    }

    var best = const IntentMatch(ChatIntent.fallback, 0);
    for (final intent in _priority) {
      final score = scores[intent] ?? 0;
      if (score > best.score) best = IntentMatch(intent, score);
    }
    return best.score >= threshold
        ? best
        : const IntentMatch(ChatIntent.fallback, 0);
  }
}
