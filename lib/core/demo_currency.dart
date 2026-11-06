enum DemoCurrency {
  inr,
  usd,
  gbp;

  String get code => switch (this) {
    DemoCurrency.inr => 'INR',
    DemoCurrency.usd => 'USD',
    DemoCurrency.gbp => 'GBP',
  };

  String get symbol => switch (this) {
    DemoCurrency.inr => '₹',
    DemoCurrency.usd => r'$',
    DemoCurrency.gbp => '£',
  };

  double get amountScale => switch (this) {
    DemoCurrency.inr => 1,
    DemoCurrency.usd => 0.05,
    DemoCurrency.gbp => 0.03,
  };

  /// Lifestyle-based sample data scaling, not foreign-exchange conversion.
  /// Monthly net income is approximately $6,000 in the US demo and £3,600 in
  /// the UK demo, versus ₹1,20,000 in the India demo.
  double scaleAmount(num amount) => this == DemoCurrency.inr
      ? amount.toDouble()
      : (amount * amountScale).roundToDouble();

  double scaleCatalogueAmount(num amount) {
    if (this == DemoCurrency.inr) return amount.toDouble();
    final step = switch (this) {
      DemoCurrency.inr => 1,
      DemoCurrency.usd =>
        amount >= 10000
            ? 1000
            : amount >= 5000
            ? 500
            : 100,
      DemoCurrency.gbp =>
        amount >= 10000
            ? 500
            : amount >= 5000
            ? 250
            : 50,
    };
    return step.toDouble();
  }

  double get fixedDepositRate => switch (this) {
    DemoCurrency.inr => 7.2,
    DemoCurrency.usd => 4.5,
    DemoCurrency.gbp => 4.2,
  };

  double get businessDepositRate => switch (this) {
    DemoCurrency.inr => 7.5,
    DemoCurrency.usd => 4.2,
    DemoCurrency.gbp => 4.0,
  };

  double get overdraftRate => switch (this) {
    DemoCurrency.inr => 11.5,
    DemoCurrency.usd => 9.5,
    DemoCurrency.gbp => 9.0,
  };

  double get personalLoanRate => switch (this) {
    DemoCurrency.inr => 12,
    DemoCurrency.usd => 11.5,
    DemoCurrency.gbp => 10.5,
  };
}
