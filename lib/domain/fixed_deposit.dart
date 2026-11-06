enum InterestPayout {
  monthly,
  quarterly,
  atMaturity;

  /// Accepts the enum's own `toString()` (`InterestPayout.atMaturity`), its
  /// name (`atMaturity`) or the catalogue's API code (`AT_MATURITY`).
  static InterestPayout parse(String value) {
    final normalized = value.split('.').last.replaceAll('_', '').toLowerCase();
    return InterestPayout.values.firstWhere(
      (option) => option.name.toLowerCase() == normalized,
      orElse: () => throw ArgumentError.value(value, 'value', 'Unknown payout option'),
    );
  }
}

class FDApplication {
  final String id;
  final String personaId;
  final double depositAmount;
  final int tenorMonths;
  final double interestRate;
  final InterestPayout payoutOption;
  final bool autoRenew;
  final DateTime createdAt;

  FDApplication({
    required this.id,
    required this.personaId,
    required this.depositAmount,
    required this.tenorMonths,
    required this.interestRate,
    required this.payoutOption,
    required this.autoRenew,
    required this.createdAt,
  });

  factory FDApplication.fromJson(Map<String, dynamic> json) {
    final payoutOption = InterestPayout.parse(json['payoutOption'] as String);

    return FDApplication(
      id: json['id'] as String,
      personaId: json['personaId'] as String,
      depositAmount: (json['depositAmount'] as num).toDouble(),
      tenorMonths: json['tenorMonths'] as int,
      interestRate: (json['interestRate'] as num).toDouble(),
      payoutOption: payoutOption,
      autoRenew: json['autoRenew'] as bool,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'personaId': personaId,
        'depositAmount': depositAmount,
        'tenorMonths': tenorMonths,
        'interestRate': interestRate,
        'payoutOption': payoutOption.toString(),
        'autoRenew': autoRenew,
        'createdAt': createdAt.toIso8601String(),
        'maturityAmount': maturityAmount,
      };

  double get maturityAmount {
    // Simple interest calculation for POC display
    return depositAmount + (depositAmount * (interestRate / 100) * (tenorMonths / 12));
  }
}