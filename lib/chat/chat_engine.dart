import '../domain/models.dart';
import '../domain/recommendation_engine.dart';
import 'chat_models.dart';

/// Everything the assistant knows about the customer for one turn.
class ChatContext {
  final Persona persona;

  /// Current offers from the recommendation engine (already filtered by
  /// what the customer holds).
  final List<ProductRecommendation> recommendations;

  /// The segment's fixed-deposit product, used for rates and tenors even
  /// when no FD is being recommended.
  final CatalogueProduct? fdProduct;
  final int debitCardLimit;
  final DateTime? now;

  const ChatContext({
    required this.persona,
    this.recommendations = const [],
    this.fdProduct,
    this.debitCardLimit = 50000,
    this.now,
  });

  ProductRecommendation? recommendationOf(ProductCategory category) {
    for (final item in recommendations) {
      if (item.category == category) return item;
    }
    return null;
  }
}

/// Turns a customer message into an assistant reply.
///
/// The rule-based engine is the mock; an LLM-backed implementation can
/// replace it without touching the routes, notifiers or UI.
abstract interface class ChatEngine {
  Future<ChatReply> respond(
    ChatContext context,
    String message, {
    ChatPending? pending,
  });
}
