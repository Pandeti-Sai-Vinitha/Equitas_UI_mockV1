import 'models.dart';

/// An activated credit product: a merchant overdraft line or a personal loan.
class CreditLine {
  final String id;
  final String personaId;
  final String productType;
  final double amount;
  final double interestRate;
  final int tenorMonths;
  final DateTime createdAt;

  CreditLine({
    required this.id,
    required this.personaId,
    required this.productType,
    required this.amount,
    required this.interestRate,
    required this.tenorMonths,
    required this.createdAt,
  });

  /// Loans are disbursed into the account; credit lines are drawn on demand.
  bool get isLoan => productType == ProductTypes.personalLoan;

  factory CreditLine.fromJson(Map<String, dynamic> json) {
    return CreditLine(
      id: json['id'] as String,
      personaId: json['personaId'] as String,
      productType: json['productType'] as String,
      amount: (json['amount'] as num).toDouble(),
      interestRate: (json['interestRate'] as num).toDouble(),
      tenorMonths: json['tenorMonths'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'personaId': personaId,
        'productType': productType,
        'amount': amount,
        'interestRate': interestRate,
        'tenorMonths': tenorMonths,
        'createdAt': createdAt.toIso8601String(),
      };
}
