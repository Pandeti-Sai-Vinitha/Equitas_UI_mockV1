import 'demo_currency.dart';
import 'demo_config.dart';

/// Formats [amount] using the currency selected for the demo.
String formatMoney(
  num amount, {
  int decimals = 0,
  DemoCurrency currency = selectedDemoCurrency,
}) {
  final fixed = amount.abs().toStringAsFixed(decimals);
  final parts = fixed.split('.');
  final fraction = parts.length > 1 ? '.${parts[1]}' : '';
  final sign = amount < 0 ? '-' : '';
  final grouped = currency == DemoCurrency.inr
      ? _groupIndian(parts.first)
      : _groupWestern(parts.first);
  return '$sign${currency.symbol}$grouped$fraction';
}

/// Kept for older callers; use [formatMoney] for new code.
String formatInr(num amount, {int decimals = 0}) =>
    formatMoney(amount, decimals: decimals);

const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `formatDate(DateTime(2027, 11, 1))` → `1 Nov 2027`.
String formatDate(DateTime date) =>
    '${date.day} ${_months[date.month - 1]} ${date.year}';

/// [date] plus [months] calendar months, clamped to the end of shorter months
/// (31 Jan + 1 month = 28/29 Feb).
DateTime addMonths(DateTime date, int months) {
  final monthIndex = date.month - 1 + months;
  final year = date.year + monthIndex ~/ 12;
  final month = monthIndex % 12 + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, date.day > lastDay ? lastDay : date.day);
}

/// Last three digits form one group; everything before is grouped in pairs.
String _groupIndian(String digits) {
  if (digits.length <= 3) return digits;
  final lastThree = digits.substring(digits.length - 3);
  var rest = digits.substring(0, digits.length - 3);
  final groups = <String>[];
  while (rest.length > 2) {
    groups.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) groups.insert(0, rest);
  return '${groups.join(',')},$lastThree';
}

String _groupWestern(String digits) {
  final groups = <String>[];
  var remaining = digits;
  while (remaining.length > 3) {
    groups.insert(0, remaining.substring(remaining.length - 3));
    remaining = remaining.substring(0, remaining.length - 3);
  }
  groups.insert(0, remaining);
  return groups.join(',');
}
