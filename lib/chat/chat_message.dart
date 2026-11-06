import 'chat_models.dart';

enum ChatRole { user, assistant }

/// Where a confirmation card is in its life.
enum ChatActionStatus {
  /// Waiting for the customer's yes/no.
  proposed,

  /// Confirmed and being carried out.
  running,
  done,
  failed,

  /// Declined, or replaced by a newer message.
  cancelled,
}

/// One bubble in the conversation.
class ChatMessage {
  final String id;
  final ChatRole role;
  final String text;
  final DateTime createdAt;
  final ChatIntent? intent;
  final String? ticketReference;
  final ChatAction? action;
  final ChatActionStatus? actionStatus;
  final List<String> suggestions;
  final bool isError;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
    this.intent,
    this.ticketReference,
    this.action,
    this.actionStatus,
    this.suggestions = const [],
    this.isError = false,
  });

  bool get isUser => role == ChatRole.user;

  ChatMessage copyWith({ChatActionStatus? actionStatus}) {
    return ChatMessage(
      id: id,
      role: role,
      text: text,
      createdAt: createdAt,
      intent: intent,
      ticketReference: ticketReference,
      action: action,
      actionStatus: actionStatus ?? this.actionStatus,
      suggestions: suggestions,
      isError: isError,
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      role: ChatRole.values.byName(json['role'] as String),
      text: json['text'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      intent: json['intent'] == null
          ? null
          : ChatIntent.values.byName(json['intent'] as String),
      ticketReference: json['ticketReference'] as String?,
      action: json['action'] == null
          ? null
          : ChatAction.fromJson(
              Map<String, dynamic>.from(json['action'] as Map),
            ),
      actionStatus: json['actionStatus'] == null
          ? null
          : ChatActionStatus.values.byName(json['actionStatus'] as String),
      suggestions: (json['suggestions'] as List<dynamic>? ?? const [])
          .cast<String>(),
      isError: json['isError'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role.name,
    'text': text,
    'createdAt': createdAt.toIso8601String(),
    'intent': intent?.name,
    'ticketReference': ticketReference,
    'action': action?.toJson(),
    'actionStatus': actionStatus?.name,
    'suggestions': suggestions,
    'isError': isError,
  };
}

/// What the chat screen renders.
class ChatState {
  final List<ChatMessage> messages;

  /// The assistant is "thinking" or carrying out a confirmed task.
  final bool isTyping;

  /// A confirmed banking action is being processed.
  final bool isProcessingTransaction;

  /// Half-finished task to send back with the next message.
  final ChatPending? pending;

  const ChatState({
    this.messages = const [],
    this.isTyping = false,
    this.isProcessingTransaction = false,
    this.pending,
  });

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isTyping,
    bool? isProcessingTransaction,
    ChatPending? pending,
    bool clearPending = false,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isTyping: isTyping ?? this.isTyping,
      isProcessingTransaction:
          isProcessingTransaction ?? this.isProcessingTransaction,
      pending: clearPending ? null : pending ?? this.pending,
    );
  }

  ChatMessage? get lastMessage => messages.isEmpty ? null : messages.last;
}
