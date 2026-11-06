import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:mock2/core/exceptions.dart';
import 'package:mock2/domain/credit_line.dart';
import 'package:mock2/domain/models.dart';
import 'package:mock2/routes/mock_api_routes.dart';

import '../helpers/test_hive.dart';

Matcher _apiError(String code) =>
    throwsA(isA<MockApiException>().having((error) => error.code, 'code', code));

Map<String, dynamic> _fdBody({double amount = 100000, String personaId = 'p_salaried_01'}) => {
      'personaId': personaId,
      'depositAmount': amount,
      'tenorMonths': 12,
      'interestRate': 7.2,
      'payoutOption': 'AT_MATURITY',
      'autoRenew': true,
    };

Map<String, dynamic> _creditBody({String productType = 'CREDIT_LINE', String personaId = 'p_biz_02'}) => {
      'personaId': personaId,
      'productType': productType,
      'amount': 80000.0,
      'interestRate': 11.5,
      'tenorMonths': 12,
    };

Persona _persona(String id) => Persona.fromRecord(storage.getPersonaRecord(id)!);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late MockApiRoutes routes;
  var clock = DateTime(2026, 11, 1, 10);

  setUp(() async {
    directory = await openTestHive();
    await seedTestData();
    clock = DateTime(2026, 11, 1, 10);
    routes = MockApiRoutes(storage, now: () => clock = clock.add(const Duration(seconds: 1)));
  });

  tearDown(() => closeTestHive(directory));

  group('POST fd-bookings', () {
    test('debits the balance, logs a transaction, adds a holding and stores the booking', () async {
      final response = await routes.dispatch('POST', ApiEndpoints.fdBookings, body: _fdBody());
      final booking = response['data'] as Map<String, dynamic>;

      final ananya = _persona('p_salaried_01');
      expect(ananya.financialSummary.currentBalance, 85000);
      expect(ananya.recentTransactions.first.description, contains(booking['id']));
      expect(ananya.recentTransactions.first.type, TransactionType.debit);
      expect(ananya.recentTransactions.first.amount, 100000);
      expect(ananya.holdings.single.productType, ProductTypes.fixedDeposit);
      expect(storage.getAllFDBookings().single['id'], booking['id']);
    });

    test('rejects deposits above the balance and non-positive amounts', () async {
      expect(
        routes.dispatch('POST', ApiEndpoints.fdBookings, body: _fdBody(amount: 185000.01)),
        _apiError('INSUFFICIENT_FUNDS'),
      );
      expect(
        routes.dispatch('POST', ApiEndpoints.fdBookings, body: _fdBody(amount: 0)),
        _apiError('BAD_REQUEST'),
      );
      await expectLater(
        routes.dispatch('POST', ApiEndpoints.fdBookings, body: _fdBody(amount: 185000.01)),
        throwsA(isA<MockApiException>().having((error) => error.message, 'message', contains('₹1,85,000'))),
      );
      expect(_persona('p_salaried_01').financialSummary.currentBalance, 185000);
    });

    test('recommendation shrinks after booking', () async {
      await routes.dispatch('POST', ApiEndpoints.fdBookings, body: _fdBody(amount: 150000));

      final response =
          await routes.dispatch('GET', ApiEndpoints.personaRecommendations('p_salaried_01'));
      expect((response['data'] as List).single['recommendedAmount'], 45000.0);
    });
  });

  test('GET fd-bookings lists all or one persona', () async {
    await routes.dispatch('POST', ApiEndpoints.fdBookings, body: _fdBody(amount: 10000));
    await routes.dispatch('POST', ApiEndpoints.fdBookings,
        body: _fdBody(amount: 10000, personaId: 'p_biz_02'));

    final all = await routes.dispatch('GET', ApiEndpoints.fdBookings);
    expect(all['data'] as List, hasLength(2));

    final mine = await routes.dispatch('GET', ApiEndpoints.personaFdBookings('p_biz_02'));
    expect((mine['data'] as List).single['personaId'], 'p_biz_02');
  });

  group('POST credit-lines', () {
    test('activates an overdraft without moving the balance and removes the offer', () async {
      final response = await routes.dispatch('POST', ApiEndpoints.creditLines, body: _creditBody());
      final creditLine = CreditLine.fromJson(response['data'] as Map<String, dynamic>);

      expect(creditLine.id, startsWith('CL_'));
      expect(creditLine.isLoan, isFalse);
      final rajesh = _persona('p_biz_02');
      expect(rajesh.financialSummary.currentBalance, 45000);
      expect(rajesh.availableCredit, 80000);
      expect(rajesh.recentTransactions, hasLength(10));

      final recommendations =
          await routes.dispatch('GET', ApiEndpoints.personaRecommendations('p_biz_02'));
      expect(recommendations['data'], isEmpty);
    });

    test('rejects a second activation of the same product', () async {
      await routes.dispatch('POST', ApiEndpoints.creditLines, body: _creditBody());
      expect(
        routes.dispatch('POST', ApiEndpoints.creditLines, body: _creditBody()),
        _apiError('ALREADY_ACTIVE'),
      );
    });

    test('a personal loan is disbursed into the balance', () async {
      final response = await routes.dispatch('POST', ApiEndpoints.creditLines,
          body: _creditBody(productType: 'PERSONAL_LOAN', personaId: 'p_salaried_01'));
      final loan = CreditLine.fromJson(response['data'] as Map<String, dynamic>);

      expect(loan.isLoan, isTrue);
      expect(loan.toJson()['productType'], 'PERSONAL_LOAN');
      final ananya = _persona('p_salaried_01');
      expect(ananya.financialSummary.currentBalance, 265000);
      expect(ananya.recentTransactions.first.type, TransactionType.credit);
      expect(ananya.availableCredit, 0);
    });

    test('validates the request', () {
      expect(routes.dispatch('POST', ApiEndpoints.creditLines), _apiError('BAD_REQUEST'));
      expect(
        routes.dispatch('POST', ApiEndpoints.creditLines, body: _creditBody(productType: 'MORTGAGE')),
        _apiError('BAD_REQUEST'),
      );
      expect(
        routes.dispatch('POST', ApiEndpoints.creditLines, body: _creditBody()..['amount'] = -1),
        _apiError('BAD_REQUEST'),
      );
      expect(
        routes.dispatch('POST', ApiEndpoints.creditLines, body: _creditBody(personaId: 'nobody')),
        _apiError('NOT_FOUND'),
      );
    });
  });
}
