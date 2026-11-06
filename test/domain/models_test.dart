import 'package:flutter_test/flutter_test.dart';

import 'package:mock2/domain/fixed_deposit.dart';
import 'package:mock2/domain/models.dart';

Map<String, dynamic> _record() => {
      'persona': {
        'id': 'p_test',
        'name': 'Test User',
        'occupation': 'Tester',
        'type': 'SALARIED',
        'avatarUrl': 'a.png',
      },
      'financialSummary': {
        'currency': 'INR',
        'currentBalance': 100000,
        'projectedIncome30D': 50000,
        'projectedSpend30D': 30000,
        'minimumBuffer': 10000,
      },
      'contextualTriggers': {
        'heroBadge': 'BADGE',
        'heroSubtext': 'Sub',
        'microActions': [
          {'label': 'Pay', 'icon': 'x', 'intent': 'PAY_BILL', 'prompt': 'Pay rent'},
        ],
      },
      'spendByCategory': [
        {'category': 'RENT', 'amount': 20000},
        {'category': 'DINING', 'amount': 10000},
      ],
      'recentTransactions': [
        {
          'id': 't1',
          'date': '2026-10-31',
          'description': 'Salary',
          'amount': 50000,
          'type': 'CREDIT',
          'category': 'INCOME',
        },
        {
          'id': 't2',
          'date': '2026-10-30',
          'description': 'Dinner',
          'amount': 900,
          'type': 'DEBIT',
          'category': 'DINING',
        },
      ],
      'holdings': [
        {'id': 'h1', 'productType': 'FD', 'amount': 50000, 'rate': 7.0},
      ],
      'goals': [
        {'name': 'Trip', 'target': 200000},
      ],
    };

void main() {
  group('FinancialSummary', () {
    test('surplus persona has investable amount and no deficit', () {
      final summary = FinancialSummary(
        currentBalance: 185000,
        projectedIncome30D: 120000,
        projectedSpend30D: 65000,
        minimumBuffer: 20000,
      );
      expect(summary.netAvailableForInvestment, 220000);
      expect(summary.projectedDeficit, 0);
      expect(summary.currency, 'INR');
    });

    test('deficit persona has a projected gap and nothing to invest', () {
      final summary = FinancialSummary(
        currentBalance: 45000,
        projectedIncome30D: 210000,
        projectedSpend30D: 310000,
        minimumBuffer: 10000,
      );
      expect(summary.netAvailableForInvestment, 0);
      expect(summary.projectedDeficit, 65000);
    });
  });

  group('Persona record', () {
    test('parses profile details', () {
      final persona = Persona.fromRecord(_record());

      expect(persona.id, 'p_test');
      expect(persona.type, PersonaType.salaried);
      expect(persona.heroBadge, 'BADGE');
      expect(persona.microActions.single['intent'], 'PAY_BILL');
      expect(persona.spendByCategory, hasLength(2));
      expect(persona.totalSpend30D, 30000);
      expect(persona.recentTransactions.first.type, TransactionType.credit);
      expect(persona.recentTransactions.last.type, TransactionType.debit);
      expect(persona.recentTransactions.first.date, DateTime(2026, 10, 31));
      expect(persona.holdings.single.productType, 'FD');
      expect(persona.goals.single.target, 200000);
    });

    test('round-trips through toRecord', () {
      final original = _record();
      final roundTripped = Persona.fromRecord(Persona.fromRecord(original).toRecord()).toRecord();

      expect(roundTripped['persona'], original['persona']);
      expect(roundTripped['spendByCategory'], [
        {'category': 'RENT', 'amount': 20000.0},
        {'category': 'DINING', 'amount': 10000.0},
      ]);
      expect((roundTripped['recentTransactions'] as List).first['date'], '2026-10-31');
      expect((roundTripped['recentTransactions'] as List).first['type'], 'CREDIT');
      expect((roundTripped['holdings'] as List).single['id'], 'h1');
      expect((roundTripped['goals'] as List).single['name'], 'Trip');
      expect((roundTripped['contextualTriggers'] as Map)['heroBadge'], 'BADGE');
    });

    test('missing optional sections default to empty', () {
      final record = _record()
        ..remove('contextualTriggers')
        ..remove('spendByCategory')
        ..remove('recentTransactions')
        ..remove('holdings')
        ..remove('goals');
      final persona = Persona.fromRecord(record);

      expect(persona.heroBadge, isEmpty);
      expect(persona.microActions, isEmpty);
      expect(persona.spendByCategory, isEmpty);
      expect(persona.totalSpend30D, 0);
    });

    test('cardLocked defaults to false and survives copyWith and the record round trip', () {
      final persona = Persona.fromRecord(_record());
      expect(persona.cardLocked, isFalse);

      final locked = persona.copyWith(cardLocked: true);
      expect(locked.cardLocked, isTrue);
      expect(locked.copyWith(recentTransactions: const []).cardLocked, isTrue);
      expect(Persona.fromRecord(locked.toRecord()).cardLocked, isTrue);
    });

    test('BUSINESS type parses as business', () {
      final record = _record();
      (record['persona'] as Map)['type'] = 'BUSINESS';
      expect(Persona.fromRecord(record).type, PersonaType.business);
    });
  });

  group('ProductRecommendation', () {
    test('parses and serialises', () {
      final recommendation = ProductRecommendation.fromJson({
        'id': 'r1',
        'title': 'FD',
        'description': 'desc',
        'category': 'INVESTMENT',
        'actionType': 'OPEN_FD',
        'recommendedAmount': 150000,
        'expectedReturnOrInterestRate': 7.2,
        'metadata': {'defaultTenorMonths': 12},
      });

      expect(recommendation.category, ProductCategory.investment);
      expect(recommendation.actionType, ActionType.openFD);
      expect(recommendation.metadata['defaultTenorMonths'], 12);
      expect(recommendation.toJson()['category'], 'INVESTMENT');
    });

    test('maps action types', () {
      expect('APPLY_LOAN'.toActionType(), ActionType.applyLoan);
      expect('FLEXI_CREDIT_LINE'.toActionType(), ActionType.flexiCreditLine);
      expect('CREDIT'.toProductCategory(), ProductCategory.credit);
    });
  });

  test('FDApplication computes simple-interest maturity and round-trips', () {
    final booking = FDApplication(
      id: 'FD_1',
      personaId: 'p',
      depositAmount: 100000,
      tenorMonths: 6,
      interestRate: 8,
      payoutOption: InterestPayout.quarterly,
      autoRenew: false,
      createdAt: DateTime(2026, 11, 1),
    );

    expect(booking.maturityAmount, 104000);
    final parsed = FDApplication.fromJson(booking.toJson());
    expect(parsed.payoutOption, InterestPayout.quarterly);
    expect(parsed.createdAt, booking.createdAt);
  });
}
