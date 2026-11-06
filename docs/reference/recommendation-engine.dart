enum ProductCategory { investment, credit }
enum ActionType { openFD, applyLoan, flexiCreditLine }

class ProductRecommendation {
  final String id;
  final String title;
  final String description;
  final ProductCategory category;
  final ActionType actionType;
  final double recommendedAmount;
  final double expectedReturnOrInterestRate; // e.g. 7.2% FD or 11.5% Loan
  final Map<String, dynamic> metadata; // Extra props like tenor options

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
}