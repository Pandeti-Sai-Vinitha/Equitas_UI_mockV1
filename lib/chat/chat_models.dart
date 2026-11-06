/// What the customer is trying to do.
enum ChatIntent {
  greeting,
  thanks,
  help,
  checkBalance,
  spendInsight,
  failedTransactions,
  recommend,
  createFd,
  needCredit,
  payBill,
  updateDebitLimit,
  lockCard,
  cancel,
  fallback,
}

/// What a half-finished task is waiting for.
enum ChatAwaiting { amount, tenor, confirm, transferApproval, payee }

/// Tasks the assistant can carry out once the customer confirms.
enum ChatActionType {
  openFd,
  activateCredit,
  payBill,
  updateDebitLimit,
  lockCard,
  unlockCard,
}

class ChatDetail {
  final String label;
  final String value;

  const ChatDetail(this.label, this.value);

  factory ChatDetail.fromJson(Map<String, dynamic> json) =>
      ChatDetail(json['label'] as String, json['value'] as String);

  Map<String, dynamic> toJson() => {'label': label, 'value': value};
}

/// A task proposed as a confirmation card. [params] carries the values the
/// matching API call needs (the caller adds `personaId`).
class ChatAction {
  final ChatActionType type;
  final String title;
  final List<ChatDetail> details;
  final Map<String, dynamic> params;
  final String confirmLabel;

  const ChatAction({
    required this.type,
    required this.title,
    required this.details,
    required this.params,
    required this.confirmLabel,
  });

  factory ChatAction.fromJson(Map<String, dynamic> json) {
    return ChatAction(
      type: ChatActionType.values.byName(json['type'] as String),
      title: json['title'] as String,
      details: (json['details'] as List<dynamic>)
          .map(
            (item) =>
                ChatDetail.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
      params: Map<String, dynamic>.from(json['params'] as Map),
      confirmLabel: json['confirmLabel'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'title': title,
    'details': details.map((item) => item.toJson()).toList(),
    'params': params,
    'confirmLabel': confirmLabel,
  };
}

/// Conversation state carried between turns: a task that is still missing a
/// value, or one that is waiting for the customer's yes/no.
class ChatPending {
  final ChatAwaiting awaiting;
  final ChatIntent intent;
  final Map<String, dynamic> slots;
  final ChatAction? action;

  const ChatPending({
    required this.awaiting,
    required this.intent,
    this.slots = const {},
    this.action,
  });

  factory ChatPending.fromJson(Map<String, dynamic> json) {
    return ChatPending(
      awaiting: ChatAwaiting.values.byName(json['awaiting'] as String),
      intent: ChatIntent.values.byName(json['intent'] as String),
      slots: Map<String, dynamic>.from(json['slots'] as Map? ?? const {}),
      action: json['action'] == null
          ? null
          : ChatAction.fromJson(
              Map<String, dynamic>.from(json['action'] as Map),
            ),
    );
  }

  Map<String, dynamic> toJson() => {
    'awaiting': awaiting.name,
    'intent': intent.name,
    'slots': slots,
    'action': action?.toJson(),
  };
}

/// One assistant turn.
class ChatReply {
  final String text;
  final ChatIntent intent;

  /// A confirmation card to show under the text.
  final ChatAction? action;

  /// State to send back with the customer's next message.
  final ChatPending? pending;

  /// Quick-reply chips; tapping one sends its text.
  final List<String> suggestions;

  /// Reference for a support ticket created while handling this turn.
  final String? ticketReference;

  /// Set when the customer just confirmed a card: the caller should run it.
  final ChatAction? execute;

  /// True when [action] describes a transaction that was completed earlier.
  final bool actionCompleted;

  const ChatReply({
    required this.text,
    required this.intent,
    this.action,
    this.pending,
    this.suggestions = const [],
    this.ticketReference,
    this.execute,
    this.actionCompleted = false,
  });

  factory ChatReply.fromJson(Map<String, dynamic> json) {
    ChatAction? action(String key) => json[key] == null
        ? null
        : ChatAction.fromJson(Map<String, dynamic>.from(json[key] as Map));

    return ChatReply(
      text: json['text'] as String,
      intent: ChatIntent.values.byName(json['intent'] as String),
      action: action('action'),
      pending: json['pending'] == null
          ? null
          : ChatPending.fromJson(
              Map<String, dynamic>.from(json['pending'] as Map),
            ),
      suggestions: (json['suggestions'] as List<dynamic>? ?? const [])
          .cast<String>(),
      ticketReference: json['ticketReference'] as String?,
      execute: action('execute'),
      actionCompleted: json['actionCompleted'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'text': text,
    'intent': intent.name,
    'action': action?.toJson(),
    'pending': pending?.toJson(),
    'suggestions': suggestions,
    'ticketReference': ticketReference,
    'execute': execute?.toJson(),
    'actionCompleted': actionCompleted,
  };
}
