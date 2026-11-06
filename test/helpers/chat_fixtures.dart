import 'dart:convert';
import 'dart:io';

import 'package:mock2/chat/chat_engine.dart';
import 'package:mock2/chat/chat_models.dart';
import 'package:mock2/chat/rule_based_chat_engine.dart';
import 'package:mock2/domain/models.dart';
import 'package:mock2/domain/recommendation_engine.dart';

Map<String, dynamic> _readData(String file) {
  final envelope = jsonDecode(File('lib/mock_data/$file').readAsStringSync()) as Map;
  return Map<String, dynamic>.from(envelope['data'] as Map);
}

final RecommendationEngine recommendationEngine =
    RecommendationEngine.fromCatalogueJson(_readData('product_catalogue.json'));

Persona ananya() => Persona.fromRecord(_readData('salaried_persona.json'));

Persona rajesh() => Persona.fromRecord(_readData('business_persona.json'));

/// The same context the chat route builds: offers are recomputed from the
/// persona, so a persona that already holds a product gets no offer for it.
ChatContext contextFor(Persona persona) {
  final segment = persona.type.name.toUpperCase();
  final fdProduct = recommendationEngine.catalogue.firstWhere(
    (product) => product.segments.contains(segment) && product.category == ProductCategory.investment,
  );
  return ChatContext(
    persona: persona,
    recommendations: recommendationEngine.recommend(persona),
    fdProduct: fdProduct,
  );
}

Persona withCreditLine(Persona persona) {
  return persona.copyWith(
    holdings: [
      ...persona.holdings,
      const Holding(id: 'CL_1', productType: ProductTypes.creditLine, amount: 80000, rate: 11.5),
    ],
  );
}

Persona withBalance(Persona persona, double balance) {
  return persona.copyWith(financialSummary: persona.financialSummary.copyWith(currentBalance: balance));
}

/// Drives the engine like the app does: carries `pending` between turns.
class Conversation {
  final RuleBasedChatEngine engine = const RuleBasedChatEngine();
  Persona persona;
  ChatPending? pending;

  Conversation(this.persona);

  Future<ChatReply> say(String message) async {
    final reply = await engine.respond(contextFor(persona), message, pending: pending);
    pending = reply.pending;
    return reply;
  }
}
