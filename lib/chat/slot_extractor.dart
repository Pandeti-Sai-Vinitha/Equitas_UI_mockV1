/// Pulls amounts and tenors out of free text: `1.5 lakh`, `$50k`, `1,50,000`,
/// `12 months`, `2 yrs`.
class SlotExtractor {
  const SlotExtractor();

  static final RegExp _tenor = RegExp(
    r'(\d+(?:\.\d+)?)\s*(months?|mos?|m|years?|yrs?|yr|y)\b',
    caseSensitive: false,
  );

  static final RegExp _amount = RegExp(
    r'(\$|£|₹|rs\.?|inr|usd|gbp)?\s*(\d[\d,]*(?:\.\d+)?)\s*(crores?|cr|lakhs?|lacs?|lac|l|k|thousand)?(?![a-z0-9])',
    caseSensitive: false,
  );

  static const int maxTenorMonths = 120;

  /// Tenor in months, or null. With [allowBare], a lone small number
  /// (`"12"`, `"make it 18"`) counts as months.
  int? extractTenorMonths(String text, {bool allowBare = false}) {
    final match = _tenor.firstMatch(text);
    if (match != null) {
      final value = double.parse(match.group(1)!);
      final unit = match.group(2)!.toLowerCase();
      final months = unit.startsWith('y') ? value * 12 : value;
      final rounded = months.round();
      return rounded >= 1 && rounded <= maxTenorMonths ? rounded : null;
    }
    if (allowBare) {
      final bare = RegExp(r'^\D*(\d{1,3})\D*$').firstMatch(text);
      final value = bare == null ? null : int.parse(bare.group(1)!);
      if (value != null && value >= 1 && value <= maxTenorMonths) return value;
    }
    return null;
  }

  /// Currency amount, or null. Plain numbers need to be at least 1,000 (so
  /// "12 employees" is ignored) unless [allowBare] is set, e.g. when the
  /// assistant has just asked "how much?".
  double? extractAmount(String text, {bool allowBare = false}) {
    final withoutTenor = text.replaceAll(_tenor, ' ');
    for (final match in _amount.allMatches(withoutTenor)) {
      final value = double.tryParse(match.group(2)!.replaceAll(',', ''));
      if (value == null || value <= 0) {
        continue;
      }

      final currency = match.group(1);
      final unit = match.group(3)?.toLowerCase();
      final amount = value * _multiplier(unit);
      if (unit != null || currency != null || value >= 1000 || allowBare) {
        return amount;
      }
    }
    return null;
  }

  static double _multiplier(String? unit) {
    switch (unit) {
      case 'cr':
      case 'crore':
      case 'crores':
        return 10000000;
      case 'l':
      case 'lac':
      case 'lacs':
      case 'lakh':
      case 'lakhs':
        return 100000;
      case 'k':
      case 'thousand':
        return 1000;
      default:
        return 1;
    }
  }
}
