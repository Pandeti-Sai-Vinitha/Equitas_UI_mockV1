enum PersonaType { salaried, business }

class Persona {
  final String id;
  final String name;
  final String occupation;
  final PersonaType type;
  final String avatarUrl;
  final FinancialSummary financialSummary;

  Persona({
    required this.id,
    required this.name,
    required this.occupation,
    required this.type,
    required this.avatarUrl,
    required this.financialSummary,
  });
}

class FinancialSummary {
  final double currentBalance;
  final double projectedIncome30D;
  final double projectedSpend30D;
  final double minimumBuffer; // Safety margin reserved by user/bank rules

  FinancialSummary({
    required this.currentBalance,
    required this.projectedIncome30D,
    required this.projectedSpend30D,
    this.minimumBuffer = 5000.0,
  });

  /// Surplus available for investments (FD/Mutual Funds)
  double get netAvailableForInvestment {
    final net30Day = (currentBalance + projectedIncome30D) - projectedSpend30D - minimumBuffer;
    return net30Day > 0 ? net30Day : 0.0;
  }

  /// Deficit indicator to trigger loan offers
  double get projectedDeficit {
    final net30Day = (currentBalance + projectedIncome30D) - projectedSpend30D - minimumBuffer;
    return net30Day < 0 ? net30Day.abs() : 0.0;
  }
}