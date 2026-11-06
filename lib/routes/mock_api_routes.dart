import 'dart:convert';

import 'package:flutter/services.dart';

import '../core/exceptions.dart';
import '../core/format.dart';
import '../data/data_seeder.dart';
import '../chat/chat_engine.dart';
import '../core/demo_config.dart';
import '../chat/chat_models.dart';
import '../chat/rule_based_chat_engine.dart';
import '../data/hive_storage.dart';
import '../domain/models.dart';
import '../domain/recommendation_engine.dart';

class ApiEndpoints {
  static const String personas = '/api/personas';
  static const String recommendations = '/api/recommendations';
  static const String fdBookings = '/api/fd-bookings';
  static const String creditLines = '/api/credit-lines';
  static const String payments = '/api/payments';
  static const String cardLock = '/api/cards/lock';
  static const String cardUnlock = '/api/cards/unlock';
  static const String chat = '/api/chat';

  static String persona(String id) => '$personas/$id';
  static String personaTransactions(String id) => '$personas/$id/transactions';
  static String personaRecommendations(String id) => '$recommendations/$id';
  static String personaFdBookings(String id) => '$fdBookings?personaId=$id';
}

/// In-process stand-in for the banking backend. Persona data is served from
/// Hive (seeded by [DataSeeder]); the product catalogue is a bundled asset.
///
/// Write routes behave like a core-banking system: they update the persona
/// record (balance, transactions, holdings) so every later read reflects them.
class MockApiRoutes {
  final LocalStorageService _storage;
  final AssetBundle _bundle;
  final DateTime Function() _now;
  final ChatEngine _chatEngine;
  RecommendationEngine? _engine;

  MockApiRoutes(
    this._storage, {
    AssetBundle? bundle,
    DateTime Function()? now,
    ChatEngine? chatEngine,
  }) : _bundle = bundle ?? rootBundle,
       _now = now ?? DateTime.now,
       _chatEngine = chatEngine ?? const RuleBasedChatEngine();

  Future<Map<String, dynamic>> dispatch(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final normalizedMethod = method.toUpperCase();
    final uri = Uri.parse(path);
    final segments = uri.pathSegments;
    final isPersonas =
        segments.length >= 2 &&
        segments[0] == 'api' &&
        segments[1] == 'personas';

    if (normalizedMethod == 'GET' && uri.path == ApiEndpoints.personas) {
      return _success(_storage.getPersonaRecords());
    }

    if (normalizedMethod == 'GET' && isPersonas && segments.length == 3) {
      return _success(_requirePersona(segments[2]));
    }

    if (normalizedMethod == 'GET' &&
        isPersonas &&
        segments.length == 4 &&
        segments[3] == 'transactions') {
      final record = _requirePersona(segments[2]);
      return _success(
        record['recentTransactions'] as List<dynamic>? ?? const [],
      );
    }

    if (normalizedMethod == 'GET' &&
        segments.length == 3 &&
        segments[0] == 'api' &&
        segments[1] == 'recommendations') {
      final persona = Persona.fromRecord(_requirePersona(segments[2]));
      final engine = await _loadEngine();
      return _success(
        engine.recommend(persona).map((item) => item.toJson()).toList(),
      );
    }

    if (normalizedMethod == 'GET' && uri.path == ApiEndpoints.fdBookings) {
      final personaId = uri.queryParameters['personaId'];
      final bookings = _storage
          .getAllFDBookings()
          .where(
            (booking) => personaId == null || booking['personaId'] == personaId,
          )
          .toList();
      return _success(bookings);
    }

    if (normalizedMethod == 'POST' && uri.path == ApiEndpoints.fdBookings) {
      return _createFdBooking(body);
    }

    if (normalizedMethod == 'POST' && uri.path == ApiEndpoints.creditLines) {
      return _activateCredit(body);
    }

    if (normalizedMethod == 'POST' && uri.path == ApiEndpoints.payments) {
      return _makePayment(body);
    }

    if (normalizedMethod == 'POST' && uri.path == ApiEndpoints.cardLock) {
      return _lockCard(body);
    }

    if (normalizedMethod == 'POST' && uri.path == ApiEndpoints.cardUnlock) {
      return _unlockCard(body);
    }

    if (normalizedMethod == 'POST' && uri.path == ApiEndpoints.chat) {
      return _chat(body);
    }

    if (normalizedMethod != 'GET' && normalizedMethod != 'POST') {
      throw MockApiException.methodNotAllowed(
        'Unsupported mock API method: $normalizedMethod',
      );
    }
    throw MockApiException.notFound(
      'Mock API route not found: $normalizedMethod ${uri.path}',
    );
  }

  Map<String, dynamic> _requirePersona(String personaId) {
    final record = _storage.getPersonaRecord(personaId);
    if (record == null) {
      throw MockApiException.notFound('Persona not found: $personaId');
    }
    return record;
  }

  Future<RecommendationEngine> _loadEngine() async {
    final cached = _engine;
    if (cached != null) return cached;
    final content = await _bundle.loadString(
      '$kMockDataDir/product_catalogue.json',
    );
    final envelope = Map<String, dynamic>.from(jsonDecode(content) as Map);
    return _engine = RecommendationEngine.fromCatalogueJson(
      Map<String, dynamic>.from(envelope['data'] as Map),
      currency: selectedDemoCurrency,
    );
  }

  static Map<String, dynamic> _success(dynamic data) => {
    'status': 'success',
    'data': data,
  };

  Future<Map<String, dynamic>> _createFdBooking(
    Map<String, dynamic>? body,
  ) async {
    if (body == null) {
      throw const MockApiException.badRequest(
        'FD booking request body is required.',
      );
    }

    final personaId = body['personaId'];
    final depositAmount = body['depositAmount'];
    final tenorMonths = body['tenorMonths'];
    final interestRate = body['interestRate'];
    final payoutOption = body['payoutOption'];
    final autoRenew = body['autoRenew'];
    if (personaId is! String ||
        depositAmount is! num ||
        tenorMonths is! int ||
        interestRate is! num ||
        payoutOption is! String ||
        autoRenew is! bool) {
      throw const MockApiException.badRequest(
        'FD booking request is missing valid required fields.',
      );
    }
    if (depositAmount <= 0 || tenorMonths <= 0) {
      throw const MockApiException.badRequest(
        'Deposit amount and tenor must be positive.',
      );
    }

    final persona = Persona.fromRecord(_requirePersona(personaId));
    final balance = persona.financialSummary.currentBalance;
    final amount = depositAmount.toDouble();
    if (amount > balance) {
      throw MockApiException(
        'INSUFFICIENT_FUNDS',
        'Insufficient balance: you have ${formatMoney(balance)} available.',
        statusCode: 422,
      );
    }

    final now = _now();
    final id = 'FD_${now.millisecondsSinceEpoch}';
    final rate = interestRate.toDouble();
    final booking = {
      'id': id,
      'personaId': personaId,
      'depositAmount': amount,
      'tenorMonths': tenorMonths,
      'interestRate': rate,
      'payoutOption': payoutOption,
      'autoRenew': autoRenew,
      'createdAt': now.toIso8601String(),
      'maturityAmount': amount + (amount * (rate / 100) * (tenorMonths / 12)),
    };

    await _storage.savePersonaRecord(
      _applyToAccount(
        persona,
        balanceChange: -amount,
        transaction: BankTransaction(
          id: 't_$id',
          date: now,
          description: 'Fixed deposit $id',
          amount: amount,
          type: TransactionType.debit,
          category: 'INVESTMENT',
        ),
        holding: Holding(
          id: id,
          productType: ProductTypes.fixedDeposit,
          amount: amount,
          rate: rate,
        ),
      ).toRecord(),
    );
    await _storage.saveFDBooking(booking);
    return _success(booking);
  }

  Future<Map<String, dynamic>> _activateCredit(
    Map<String, dynamic>? body,
  ) async {
    final personaId = body?['personaId'];
    final productType = body?['productType'];
    final amount = body?['amount'];
    final interestRate = body?['interestRate'];
    final tenorMonths = body?['tenorMonths'];
    if (personaId is! String ||
        productType is! String ||
        amount is! num ||
        interestRate is! num ||
        tenorMonths is! int) {
      throw const MockApiException.badRequest(
        'Credit request is missing valid required fields.',
      );
    }
    if (productType != ProductTypes.creditLine &&
        productType != ProductTypes.personalLoan) {
      throw MockApiException.badRequest(
        'Unsupported credit product: $productType',
      );
    }
    if (amount <= 0 || tenorMonths <= 0) {
      throw const MockApiException.badRequest(
        'Amount and tenor must be positive.',
      );
    }

    final persona = Persona.fromRecord(_requirePersona(personaId));
    if (persona.holdsProduct(productType)) {
      throw const MockApiException(
        'ALREADY_ACTIVE',
        'This credit product is already active on your account.',
        statusCode: 409,
      );
    }

    final now = _now();
    final isLoan = productType == ProductTypes.personalLoan;
    final id = '${isLoan ? 'PL' : 'CL'}_${now.millisecondsSinceEpoch}';
    final limit = amount.toDouble();
    final rate = interestRate.toDouble();
    final creditLine = {
      'id': id,
      'personaId': personaId,
      'productType': productType,
      'amount': limit,
      'interestRate': rate,
      'tenorMonths': tenorMonths,
      'createdAt': now.toIso8601String(),
    };

    await _storage.savePersonaRecord(
      _applyToAccount(
        persona,
        // A loan is disbursed now; an overdraft line is only drawn when needed.
        balanceChange: isLoan ? limit : 0,
        transaction: isLoan
            ? BankTransaction(
                id: 't_$id',
                date: now,
                description: 'Personal loan disbursal $id',
                amount: limit,
                type: TransactionType.credit,
                category: 'LOAN',
              )
            : null,
        holding: Holding(
          id: id,
          productType: productType,
          amount: limit,
          rate: rate,
        ),
      ).toRecord(),
    );
    return _success(creditLine);
  }

  Future<Map<String, dynamic>> _makePayment(Map<String, dynamic>? body) async {
    final personaId = body?['personaId'];
    final payee = body?['payee'];
    final amount = body?['amount'];
    final category = body?['category'];
    if (personaId is! String ||
        payee is! String ||
        amount is! num ||
        category is! String) {
      throw const MockApiException.badRequest(
        'Payment request is missing valid required fields.',
      );
    }
    if (amount <= 0) {
      throw const MockApiException.badRequest(
        'Payment amount must be positive.',
      );
    }

    final persona = Persona.fromRecord(_requirePersona(personaId));
    final paid = amount.toDouble();
    final summary = persona.financialSummary;
    // An active overdraft line can be drawn on, taking the balance below zero.
    final available = summary.currentBalance + persona.availableCredit;
    if (paid > available) {
      throw MockApiException(
        'INSUFFICIENT_FUNDS',
        'Insufficient funds: you can use ${formatMoney(available)} right now.',
        statusCode: 422,
      );
    }

    final now = _now();
    final id = 'PAY_${now.millisecondsSinceEpoch}';
    final updated = _applyToAccount(
      persona,
      balanceChange: -paid,
      transaction: BankTransaction(
        id: 't_$id',
        date: now,
        createdAt: now,
        description: payee,
        amount: paid,
        type: TransactionType.debit,
        category: category,
      ),
    );
    await _storage.savePersonaRecord(updated.toRecord());
    return _success({
      'id': id,
      'personaId': personaId,
      'payee': payee,
      'amount': paid,
      'category': category,
      'createdAt': now.toIso8601String(),
      'balanceAfter': updated.financialSummary.currentBalance,
    });
  }

  Future<Map<String, dynamic>> _lockCard(Map<String, dynamic>? body) async {
    final personaId = body?['personaId'];
    if (personaId is! String) {
      throw const MockApiException.badRequest(
        'Card request needs a personaId.',
      );
    }
    final persona = Persona.fromRecord(_requirePersona(personaId));
    if (persona.cardLocked) {
      throw const MockApiException(
        'ALREADY_LOCKED',
        'Your card is already locked.',
        statusCode: 409,
      );
    }
    final now = _now();
    final reference = 'CARD_LOCK_${now.millisecondsSinceEpoch}';
    await _storage.savePersonaRecord(
      persona
          .copyWith(
            cardLocked: true,
            cardLockReference: reference,
            cardLockedAt: now,
          )
          .toRecord(),
    );
    return _success({
      'personaId': personaId,
      'status': 'LOCKED',
      'reference': reference,
      'createdAt': now.toIso8601String(),
    });
  }

  Future<Map<String, dynamic>> _unlockCard(Map<String, dynamic>? body) async {
    final personaId = body?['personaId'];
    if (personaId is! String) {
      throw const MockApiException.badRequest(
        'Card request needs a personaId.',
      );
    }
    final persona = Persona.fromRecord(_requirePersona(personaId));
    if (!persona.cardLocked) {
      throw const MockApiException(
        'ALREADY_UNLOCKED',
        'Your card is already unlocked.',
        statusCode: 409,
      );
    }
    final now = _now();
    await _storage.savePersonaRecord(
      persona
          .copyWith(cardLocked: false, clearCardLockReceipt: true)
          .toRecord(),
    );
    return _success({
      'personaId': personaId,
      'status': 'UNLOCKED',
      'createdAt': now.toIso8601String(),
    });
  }

  Future<Map<String, dynamic>> _chat(Map<String, dynamic>? body) async {
    final personaId = body?['personaId'];
    final message = body?['message'];
    if (personaId is! String || message is! String) {
      throw const MockApiException.badRequest(
        'Chat request needs a personaId and a message.',
      );
    }
    final pendingJson = body?['pending'];
    final pending = pendingJson is Map
        ? ChatPending.fromJson(Map<String, dynamic>.from(pendingJson))
        : null;

    final persona = Persona.fromRecord(_requirePersona(personaId));
    final engine = await _loadEngine();
    final segment = persona.type.name.toUpperCase();
    final fdProducts = engine.catalogue.where(
      (product) =>
          product.segments.contains(segment) &&
          product.category == ProductCategory.investment,
    );
    final context = ChatContext(
      persona: persona,
      recommendations: engine.recommend(persona),
      fdProduct: fdProducts.isEmpty ? null : fdProducts.first,
      debitCardLimit: body?['debitCardLimit'] is num
          ? (body!['debitCardLimit'] as num).toInt()
          : 50000,
      now: _now(),
    );
    final reply = await _chatEngine.respond(context, message, pending: pending);
    final response = reply.toJson();
    if (reply.intent == ChatIntent.failedTransactions) {
      // Ticket is raised only for the card-expiration decline (Swiggy).
      final ticketId = '$personaId:swiggy-expired-card';
      final existingTicket = _storage.getSupportTicket(ticketId);
      final ticket =
          existingTicket ??
          <String, dynamic>{
            'id': ticketId,
            'reference': 'EQ-TKT-0914',
            'personaId': personaId,
            'merchant': 'Swiggy',
            'reason': 'Card expired',
            'status': 'OPEN',
            'createdAt': _now().toIso8601String(),
          };
      if (existingTicket == null) {
        await _storage.saveSupportTicket(ticket);
      }
      response['ticketReference'] = ticket['reference'];
      final reportDate = _now().subtract(const Duration(days: 1));
      response['text'] =
          'I found 3 failed transactions on your account yesterday '
          '(${formatDate(reportDate)}), with a total attempted value of '
          '${formatMoney(276270)}.';
    }
    return _success(response);
  }

  static Persona _applyToAccount(
    Persona persona, {
    required double balanceChange,
    BankTransaction? transaction,
    Holding? holding,
  }) {
    final summary = persona.financialSummary;
    return persona.copyWith(
      financialSummary: summary.copyWith(
        currentBalance: summary.currentBalance + balanceChange,
      ),
      recentTransactions: [?transaction, ...persona.recentTransactions],
      holdings: [...persona.holdings, ?holding],
    );
  }
}
