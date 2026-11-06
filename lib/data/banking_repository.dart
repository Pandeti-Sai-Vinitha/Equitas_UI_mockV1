import '../chat/chat_models.dart';
import '../domain/credit_line.dart';
import '../domain/fixed_deposit.dart';
import '../domain/models.dart';
import '../routes/mock_api_routes.dart';
import 'api_client.dart';

/// Converts API envelopes into domain models.
class BankingRepository {
  final ApiClient _api;

  BankingRepository(this._api);

  Future<List<Persona>> loadPersonas() async {
    final response = await _api.get(ApiEndpoints.personas);
    return (response['data'] as List<dynamic>)
        .map(
          (item) => Persona.fromRecord(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<Persona> loadPersona(String personaId) async {
    final response = await _api.get(ApiEndpoints.persona(personaId));
    return Persona.fromRecord(
      Map<String, dynamic>.from(response['data'] as Map),
    );
  }

  Future<List<BankTransaction>> loadTransactions(String personaId) async {
    final response = await _api.get(
      ApiEndpoints.personaTransactions(personaId),
    );
    return (response['data'] as List<dynamic>)
        .map(
          (item) =>
              BankTransaction.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<List<ProductRecommendation>> loadRecommendations(
    String personaId,
  ) async {
    final response = await _api.get(
      ApiEndpoints.personaRecommendations(personaId),
    );
    return (response['data'] as List<dynamic>)
        .map(
          (item) => ProductRecommendation.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
  }

  Future<FDApplication> bookFixedDeposit({
    required String personaId,
    required double depositAmount,
    required int tenorMonths,
    required double interestRate,
    required InterestPayout payoutOption,
    required bool autoRenew,
  }) async {
    final response = await _api.post(ApiEndpoints.fdBookings, {
      'personaId': personaId,
      'depositAmount': depositAmount,
      'tenorMonths': tenorMonths,
      'interestRate': interestRate,
      'payoutOption': payoutOption.toString(),
      'autoRenew': autoRenew,
    });
    return FDApplication.fromJson(
      Map<String, dynamic>.from(response['data'] as Map),
    );
  }

  /// All FD bookings, or only [personaId]'s when given.
  Future<List<FDApplication>> loadFdBookings({String? personaId}) async {
    final response = await _api.get(
      personaId == null
          ? ApiEndpoints.fdBookings
          : ApiEndpoints.personaFdBookings(personaId),
    );
    return (response['data'] as List<dynamic>)
        .map(
          (item) =>
              FDApplication.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<ChatReply> sendChatMessage({
    required String personaId,
    required String message,
    int debitCardLimit = 50000,
    ChatPending? pending,
  }) async {
    final response = await _api.post(ApiEndpoints.chat, {
      'personaId': personaId,
      'message': message,
      'debitCardLimit': debitCardLimit,
      'pending': pending?.toJson(),
    });
    return ChatReply.fromJson(
      Map<String, dynamic>.from(response['data'] as Map),
    );
  }

  /// Returns the payment receipt (`id`, `payee`, `amount`, `balanceAfter`...).
  Future<Map<String, dynamic>> makePayment({
    required String personaId,
    required String payee,
    required double amount,
    required String category,
  }) async {
    final response = await _api.post(ApiEndpoints.payments, {
      'personaId': personaId,
      'payee': payee,
      'amount': amount,
      'category': category,
    });
    return Map<String, dynamic>.from(response['data'] as Map);
  }

  Future<void> lockCard(String personaId) async {
    await _api.post(ApiEndpoints.cardLock, {'personaId': personaId});
  }

  Future<void> unlockCard(String personaId) async {
    await _api.post(ApiEndpoints.cardUnlock, {'personaId': personaId});
  }

  Future<CreditLine> activateCredit({
    required String personaId,
    required String productType,
    required double amount,
    required double interestRate,
    required int tenorMonths,
  }) async {
    final response = await _api.post(ApiEndpoints.creditLines, {
      'personaId': personaId,
      'productType': productType,
      'amount': amount,
      'interestRate': interestRate,
      'tenorMonths': tenorMonths,
    });
    return CreditLine.fromJson(
      Map<String, dynamic>.from(response['data'] as Map),
    );
  }
}
