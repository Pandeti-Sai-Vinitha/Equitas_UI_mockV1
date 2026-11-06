List<ProductRecommendation> getRecommendations(Persona persona) {
  final summary = persona.financialSummary;
  final recommendations = <ProductRecommendation>[];

  if (summary.netAvailableForInvestment > 10000) {
    recommendations.add(
      ProductRecommendation(
        id: 'rec_fd_01',
        title: 'High-Yield Fixed Deposit',
        description: 'You have ₹${summary.netAvailableForInvestment.toStringAsFixed(0)} idle balance available.',
        category: ProductCategory.investment,
        actionType: ActionType.openFD,
        recommendedAmount: (summary.netAvailableForInvestment * 0.7), // Suggest investing 70% of surplus
        expectedReturnOrInterestRate: persona.type == PersonaType.business ? 7.5 : 7.2,
        metadata: {'defaultTenorMonths': 12},
      ),
    );
  } else if (summary.projectedDeficit > 0) {
    recommendations.add(
      ProductRecommendation(
        id: 'rec_loan_01',
        title: persona.type == PersonaType.business ? 'Merchant Overdraft Line' : 'Pre-Approved Personal Loan',
        description: 'Upcoming liquidity gap of ₹${summary.projectedDeficit.toStringAsFixed(0)} detected in next 30 days.',
        category: ProductCategory.credit,
        actionType: persona.type == PersonaType.business ? ActionType.flexiCreditLine : ActionType.applyLoan,
        recommendedAmount: summary.projectedDeficit + 15000, // Suggest deficit + buffer
        expectedReturnOrInterestRate: persona.type == PersonaType.business ? 11.5 : 12.0,
      ),
    );
  }

  return recommendations;
}