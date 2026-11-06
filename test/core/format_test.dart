import 'package:flutter_test/flutter_test.dart';

import 'package:mock2/core/demo_currency.dart';
import 'package:mock2/core/format.dart';

void main() {
  test('groups rupees the Indian way', () {
    expect(formatInr(0), '₹0');
    expect(formatInr(999), '₹999');
    expect(formatInr(1000), '₹1,000');
    expect(formatInr(185000), '₹1,85,000');
    expect(formatInr(310000), '₹3,10,000');
    expect(formatInr(12345678), '₹1,23,45,678');
  });

  test('formats dates', () {
    expect(formatDate(DateTime(2027, 11, 1)), '1 Nov 2027');
    expect(formatDate(DateTime(2026, 1, 31)), '31 Jan 2026');
  });

  test('adds calendar months, clamping to the end of short months', () {
    expect(addMonths(DateTime(2026, 11, 1), 12), DateTime(2027, 11, 1));
    expect(addMonths(DateTime(2026, 11, 15), 3), DateTime(2027, 2, 15));
    expect(addMonths(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
    expect(addMonths(DateTime(2027, 1, 31), 1), DateTime(2027, 2, 28));
    expect(addMonths(DateTime(2027, 12, 31), 2), DateTime(2028, 2, 29));
    expect(addMonths(DateTime(2026, 6, 10), 24), DateTime(2028, 6, 10));
  });

  test('supports decimals and negatives', () {
    expect(formatInr(107200, decimals: 2), '₹1,07,200.00');
    expect(formatInr(1234567.456, decimals: 2), '₹12,34,567.46');
    expect(formatInr(-65000), '-₹65,000');
  });

  test('formats US dollars and British pounds with western grouping', () {
    expect(
      formatMoney(1234567.45, decimals: 2, currency: DemoCurrency.usd),
      r'$1,234,567.45',
    );
    expect(formatMoney(-1234567, currency: DemoCurrency.gbp), '-£1,234,567');
  });
}
