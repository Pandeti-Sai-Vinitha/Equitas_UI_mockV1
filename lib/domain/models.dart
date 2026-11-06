// ==================== ENUMS ====================

enum PersonaType { salaried, business }

enum ProductCategory { investment, credit }

enum ActionType {
  openFD('OPEN_FD'),
  applyLoan('APPLY_LOAN'),
  flexiCreditLine('FLEXI_CREDIT_LINE');

  /// API/JSON representation.
  final String code;
  const ActionType(this.code);
}

/// Holding product types written by the mock API.
class ProductTypes {
  static const String fixedDeposit = 'FD';
  static const String creditLine = 'CREDIT_LINE';
  static const String personalLoan = 'PERSONAL_LOAN';
}

// Helper extension to parse enums safely from JSON strings
extension EnumParser on String {
  PersonaType toPersonaType() {
    return this == 'SALARIED' ? PersonaType.salaried : PersonaType.business;
  }

  ProductCategory toProductCategory() {
    return this == 'INVESTMENT'
        ? ProductCategory.investment
        : ProductCategory.credit;
  }

  ActionType toActionType() {
    switch (this) {
      case 'OPEN_FD':
        return ActionType.openFD;
      case 'APPLY_LOAN':
        return ActionType.applyLoan;
      case 'FLEXI_CREDIT_LINE':
      default:
        return ActionType.flexiCreditLine;
    }
  }
}

// ==================== FINANCIAL SUMMARY MODEL ====================

class FinancialSummary {
  final String currency;
  final double currentBalance;
  final double projectedIncome30D;
  final double projectedSpend30D;
  final double minimumBuffer;

  FinancialSummary({
    this.currency = 'INR',
    required this.currentBalance,
    required this.projectedIncome30D,
    required this.projectedSpend30D,
    required this.minimumBuffer,
  });

  factory FinancialSummary.fromJson(Map<String, dynamic> json) {
    return FinancialSummary(
      currency: json['currency'] as String? ?? 'INR',
      currentBalance: (json['currentBalance'] as num).toDouble(),
      projectedIncome30D: (json['projectedIncome30D'] as num).toDouble(),
      projectedSpend30D: (json['projectedSpend30D'] as num).toDouble(),
      minimumBuffer: (json['minimumBuffer'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'currency': currency,
    'currentBalance': currentBalance,
    'projectedIncome30D': projectedIncome30D,
    'projectedSpend30D': projectedSpend30D,
    'minimumBuffer': minimumBuffer,
  };

  FinancialSummary copyWith({double? currentBalance}) {
    return FinancialSummary(
      currency: currency,
      currentBalance: currentBalance ?? this.currentBalance,
      projectedIncome30D: projectedIncome30D,
      projectedSpend30D: projectedSpend30D,
      minimumBuffer: minimumBuffer,
    );
  }

  double get netAvailableForInvestment {
    final net30Day =
        (currentBalance + projectedIncome30D) -
        projectedSpend30D -
        minimumBuffer;
    return net30Day > 0 ? net30Day : 0.0;
  }

  double get projectedDeficit {
    final net30Day =
        (currentBalance + projectedIncome30D) -
        projectedSpend30D -
        minimumBuffer;
    return net30Day < 0 ? net30Day.abs() : 0.0;
  }
}

// ==================== PERSONA MODEL ====================

class Persona {
  final String id;
  final String name;
  final String occupation;
  final PersonaType type;
  final String avatarUrl;
  final FinancialSummary financialSummary;
  final String heroBadge;
  final String heroSubtext;
  final List<Map<String, dynamic>> microActions;
  final List<SpendCategory> spendByCategory;
  final List<BankTransaction> recentTransactions;
  final List<Holding> holdings;
  final List<FinancialGoal> goals;
  final bool cardLocked;
  final String? cardLockReference;
  final DateTime? cardLockedAt;

  Persona({
    required this.id,
    required this.name,
    required this.occupation,
    required this.type,
    required this.avatarUrl,
    required this.financialSummary,
    this.heroBadge = '',
    this.heroSubtext = '',
    this.microActions = const [],
    this.spendByCategory = const [],
    this.recentTransactions = const [],
    this.holdings = const [],
    this.goals = const [],
    this.cardLocked = false,
    this.cardLockReference,
    this.cardLockedAt,
  });

  factory Persona.fromJson(
    Map<String, dynamic> personaJson,
    Map<String, dynamic> summaryJson, [
    Map<String, dynamic>? contextualTriggers,
  ]) {
    return Persona(
      id: personaJson['id'] as String,
      name: personaJson['name'] as String,
      occupation: personaJson['occupation'] as String,
      type: (personaJson['type'] as String).toPersonaType(),
      avatarUrl: personaJson['avatarUrl'] as String,
      financialSummary: FinancialSummary.fromJson(summaryJson),
      heroBadge: contextualTriggers?['heroBadge'] as String? ?? '',
      heroSubtext: contextualTriggers?['heroSubtext'] as String? ?? '',
      microActions:
          (contextualTriggers?['microActions'] as List<dynamic>? ?? const [])
              .map((action) => Map<String, dynamic>.from(action as Map))
              .toList(),
    );
  }

  /// Parses a full persona record as stored in Hive and served by
  /// `GET /api/personas/{id}` (the `data` object of the persona JSON assets).
  factory Persona.fromRecord(Map<String, dynamic> record) {
    final base = Persona.fromJson(
      Map<String, dynamic>.from(record['persona'] as Map),
      Map<String, dynamic>.from(record['financialSummary'] as Map),
      record['contextualTriggers'] == null
          ? null
          : Map<String, dynamic>.from(record['contextualTriggers'] as Map),
    );
    return Persona(
      id: base.id,
      name: base.name,
      occupation: base.occupation,
      type: base.type,
      avatarUrl: base.avatarUrl,
      financialSummary: base.financialSummary,
      heroBadge: base.heroBadge,
      heroSubtext: base.heroSubtext,
      microActions: base.microActions,
      spendByCategory: _parseList(
        record['spendByCategory'],
        SpendCategory.fromJson,
      ),
      recentTransactions: _parseList(
        record['recentTransactions'],
        BankTransaction.fromJson,
      ),
      holdings: _parseList(record['holdings'], Holding.fromJson),
      goals: _parseList(record['goals'], FinancialGoal.fromJson),
      cardLocked: record['cardLocked'] as bool? ?? false,
      cardLockReference:
          (record['cardLockReceipt'] as Map?)?['reference'] as String?,
      cardLockedAt: (record['cardLockReceipt'] as Map?)?['createdAt'] is String
          ? DateTime.parse(
              (record['cardLockReceipt'] as Map)['createdAt'] as String,
            )
          : null,
    );
  }

  /// Inverse of [Persona.fromRecord].
  Map<String, dynamic> toRecord() => {
    'persona': {
      'id': id,
      'name': name,
      'occupation': occupation,
      'type': type.name.toUpperCase(),
      'avatarUrl': avatarUrl,
    },
    'financialSummary': financialSummary.toJson(),
    'contextualTriggers': {
      'heroBadge': heroBadge,
      'heroSubtext': heroSubtext,
      'microActions': microActions,
    },
    'spendByCategory': spendByCategory.map((item) => item.toJson()).toList(),
    'recentTransactions': recentTransactions
        .map((item) => item.toJson())
        .toList(),
    'holdings': holdings.map((item) => item.toJson()).toList(),
    'goals': goals.map((item) => item.toJson()).toList(),
    'cardLocked': cardLocked,
    if (cardLockReference != null && cardLockedAt != null)
      'cardLockReceipt': {
        'reference': cardLockReference,
        'createdAt': cardLockedAt!.toIso8601String(),
      },
  };

  double get totalSpend30D =>
      spendByCategory.fold(0.0, (total, item) => total + item.amount);

  bool holdsProduct(String productType) =>
      holdings.any((holding) => holding.productType == productType);

  /// Sanctioned limit of all active credit lines.
  double get availableCredit => holdings
      .where((holding) => holding.productType == ProductTypes.creditLine)
      .fold(0.0, (total, holding) => total + holding.amount);

  Persona copyWith({
    FinancialSummary? financialSummary,
    List<BankTransaction>? recentTransactions,
    List<Holding>? holdings,
    bool? cardLocked,
    String? cardLockReference,
    DateTime? cardLockedAt,
    bool clearCardLockReceipt = false,
  }) {
    return Persona(
      id: id,
      name: name,
      occupation: occupation,
      type: type,
      avatarUrl: avatarUrl,
      financialSummary: financialSummary ?? this.financialSummary,
      heroBadge: heroBadge,
      heroSubtext: heroSubtext,
      microActions: microActions,
      spendByCategory: spendByCategory,
      recentTransactions: recentTransactions ?? this.recentTransactions,
      holdings: holdings ?? this.holdings,
      goals: goals,
      cardLocked: cardLocked ?? this.cardLocked,
      cardLockReference: clearCardLockReceipt
          ? null
          : cardLockReference ?? this.cardLockReference,
      cardLockedAt: clearCardLockReceipt
          ? null
          : cardLockedAt ?? this.cardLockedAt,
    );
  }
}

List<T> _parseList<T>(Object? raw, T Function(Map<String, dynamic>) parse) {
  return (raw as List<dynamic>? ?? const [])
      .map((item) => parse(Map<String, dynamic>.from(item as Map)))
      .toList();
}

// ==================== PROFILE DETAIL MODELS ====================

class SpendCategory {
  final String category;
  final double amount;

  const SpendCategory({required this.category, required this.amount});

  factory SpendCategory.fromJson(Map<String, dynamic> json) {
    return SpendCategory(
      category: json['category'] as String,
      amount: (json['amount'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {'category': category, 'amount': amount};
}

enum TransactionType { credit, debit }

class BankTransaction {
  final String id;
  final DateTime date;
  final DateTime? createdAt;
  final String description;
  final double amount;
  final TransactionType type;
  final String category;

  const BankTransaction({
    required this.id,
    required this.date,
    this.createdAt,
    required this.description,
    required this.amount,
    required this.type,
    required this.category,
  });

  factory BankTransaction.fromJson(Map<String, dynamic> json) {
    return BankTransaction(
      id: json['id'] as String,
      date: DateTime.parse(json['date'] as String),
      createdAt: json['createdAt'] is String
          ? DateTime.parse(json['createdAt'] as String)
          : null,
      description: json['description'] as String,
      amount: (json['amount'] as num).toDouble(),
      type: json['type'] == 'CREDIT'
          ? TransactionType.credit
          : TransactionType.debit,
      category: json['category'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date.toIso8601String().split('T').first,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    'description': description,
    'amount': amount,
    'type': type.name.toUpperCase(),
    'category': category,
  };
}

/// A product the customer already holds (FD, credit line, card...).
/// Used to avoid cross-selling something they already have.
class Holding {
  final String id;
  final String productType;
  final double amount;
  final double rate;

  const Holding({
    required this.id,
    required this.productType,
    required this.amount,
    required this.rate,
  });

  factory Holding.fromJson(Map<String, dynamic> json) {
    return Holding(
      id: json['id'] as String,
      productType: json['productType'] as String,
      amount: (json['amount'] as num).toDouble(),
      rate: (json['rate'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'productType': productType,
    'amount': amount,
    'rate': rate,
  };
}

class FinancialGoal {
  final String name;
  final double target;

  const FinancialGoal({required this.name, required this.target});

  factory FinancialGoal.fromJson(Map<String, dynamic> json) {
    return FinancialGoal(
      name: json['name'] as String,
      target: (json['target'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'target': target};
}

// ==================== PRODUCT RECOMMENDATION MODEL ====================

class ProductRecommendation {
  final String id;
  final String title;
  final String description;
  final ProductCategory category;
  final ActionType actionType;
  final double recommendedAmount;
  final double expectedReturnOrInterestRate;
  final Map<String, dynamic> metadata;

  ProductRecommendation({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.actionType,
    required this.recommendedAmount,
    required this.expectedReturnOrInterestRate,
    this.metadata = const {},
  });

  factory ProductRecommendation.fromJson(Map<String, dynamic> json) {
    return ProductRecommendation(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      category: (json['category'] as String).toProductCategory(),
      actionType: (json['actionType'] as String).toActionType(),
      recommendedAmount: (json['recommendedAmount'] as num).toDouble(),
      expectedReturnOrInterestRate:
          (json['expectedReturnOrInterestRate'] as num).toDouble(),
      metadata: json['metadata'] != null
          ? Map<String, dynamic>.from(json['metadata'])
          : {},
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'category': category.toString().split('.').last.toUpperCase(),
    'actionType': actionType.code,
    'recommendedAmount': recommendedAmount,
    'expectedReturnOrInterestRate': expectedReturnOrInterestRate,
    'metadata': metadata,
  };
}
