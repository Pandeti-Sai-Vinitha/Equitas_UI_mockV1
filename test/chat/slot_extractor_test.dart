import 'package:flutter_test/flutter_test.dart';

import 'package:mock2/chat/slot_extractor.dart';

void main() {
  const extractor = SlotExtractor();

  group('extractAmount', () {
    const cases = {
      '1 lakh': 100000.0,
      '1.5 lakh': 150000.0,
      '1L': 100000.0,
      '2 lacs': 200000.0,
      '₹2 lakhs': 200000.0,
      '50k': 50000.0,
      '2 thousand': 2000.0,
      '2 crore': 20000000.0,
      '1,50,000': 150000.0,
      '150000': 150000.0,
      'rs 25000': 25000.0,
      '₹1,50,000': 150000.0,
      'INR 3000': 3000.0,
      r'$2,500': 2500.0,
      '£1,200': 1200.0,
      'USD 4500': 4500.0,
      'GBP 3500': 3500.0,
    };
    cases.forEach((text, expected) {
      test(
        '"$text" → $expected',
        () => expect(extractor.extractAmount(text), expected),
      );
    });

    test('finds the amount inside a sentence and ignores the tenor', () {
      expect(
        extractor.extractAmount('create an fd of 1 lakh for 12 months'),
        100000,
      );
      expect(
        extractor.extractAmount('open fd of ₹1,50,000 for 2 years'),
        150000,
      );
    });

    test('ignores small plain numbers unless a bare number is expected', () {
      expect(
        extractor.extractAmount('approve payroll for my 12 employees'),
        isNull,
      );
      expect(extractor.extractAmount('500'), isNull);
      expect(extractor.extractAmount('500', allowBare: true), 500);
      expect(extractor.extractAmount('about 750 please', allowBare: true), 750);
    });

    test('returns null when there is no amount or only a tenor', () {
      expect(extractor.extractAmount('hello there'), isNull);
      expect(extractor.extractAmount('12 months'), isNull);
      expect(extractor.extractAmount('12 months', allowBare: true), isNull);
      expect(extractor.extractAmount('0 lakh'), isNull);
    });
  });

  group('extractTenorMonths', () {
    const cases = {
      '12 months': 12,
      '1 month': 1,
      '1 year': 12,
      '2 yrs': 24,
      '18m': 18,
      '6 mos': 6,
      '1.5 years': 18,
      '10 years': 120,
    };
    cases.forEach((text, expected) {
      test(
        '"$text" → $expected',
        () => expect(extractor.extractTenorMonths(text), expected),
      );
    });

    test('finds the tenor inside a sentence', () {
      expect(
        extractor.extractTenorMonths('create an fd of 1 lakh for 24 months'),
        24,
      );
    });

    test('bare numbers count as months only when expected', () {
      expect(extractor.extractTenorMonths('12'), isNull);
      expect(extractor.extractTenorMonths('12', allowBare: true), 12);
      expect(extractor.extractTenorMonths('make it 18', allowBare: true), 18);
      expect(extractor.extractTenorMonths('200', allowBare: true), isNull);
      expect(extractor.extractTenorMonths('150000', allowBare: true), isNull);
      expect(extractor.extractTenorMonths('twelve', allowBare: true), isNull);
    });

    test('rejects zero and out-of-range tenors', () {
      expect(extractor.extractTenorMonths('0 months'), isNull);
      expect(extractor.extractTenorMonths('11 years'), isNull);
    });
  });
}
