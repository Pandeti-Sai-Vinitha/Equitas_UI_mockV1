import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:mock2/core/exceptions.dart';
import 'package:mock2/routes/mock_api_routes.dart';

import '../helpers/test_hive.dart';

Matcher _apiError(String code) =>
    throwsA(isA<MockApiException>().having((error) => error.code, 'code', code));

Map<String, dynamic> _fdBody() => {
      'personaId': 'p_salaried_01',
      'depositAmount': 100000.0,
      'tenorMonths': 12,
      'interestRate': 7.2,
      'payoutOption': 'InterestPayout.atMaturity',
      'autoRenew': true,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late MockApiRoutes routes;

  setUp(() async {
    directory = await openTestHive();
    await seedTestData();
    routes = MockApiRoutes(storage);
  });

  tearDown(() => closeTestHive(directory));

  test('GET personas serves Hive records in order', () async {
    final response = await routes.dispatch('GET', ApiEndpoints.personas);

    expect(response['status'], 'success');
    final data = response['data'] as List;
    expect(data.map((item) => item['persona']['id']), ['p_salaried_01', 'p_biz_02']);
  });

  test('GET persona reflects changes written to Hive', () async {
    final record = storage.getPersonaRecord('p_biz_02')!;
    (record['persona'] as Map)['name'] = 'Renamed Traders';
    await storage.savePersonaRecord(record);

    final response = await routes.dispatch('get', ApiEndpoints.persona('p_biz_02'));
    expect(response['data']['persona']['name'], 'Renamed Traders');
  });

  test('GET unknown persona is 404', () {
    expect(routes.dispatch('GET', ApiEndpoints.persona('nobody')), _apiError('NOT_FOUND'));
  });

  test('GET transactions returns the persona ledger', () async {
    final response =
        await routes.dispatch('GET', ApiEndpoints.personaTransactions('p_salaried_01'));
    final data = response['data'] as List;
    expect(data, hasLength(10));
    expect(data.first['type'], 'CREDIT');
  });

  test('GET recommendations returns rules for a persona and 404 for unknown', () async {
    final response =
        await routes.dispatch('GET', ApiEndpoints.personaRecommendations('p_biz_02'));
    expect((response['data'] as List).single['actionType'], 'FLEXI_CREDIT_LINE');

    expect(
      routes.dispatch('GET', ApiEndpoints.personaRecommendations('nobody')),
      _apiError('NOT_FOUND'),
    );
  });

  test('POST fd-bookings creates a booking with maturity amount', () async {
    final response = await routes.dispatch('POST', ApiEndpoints.fdBookings, body: _fdBody());
    final booking = response['data'] as Map<String, dynamic>;

    expect(booking['id'], startsWith('FD_'));
    expect(booking['maturityAmount'], 107200.0);
  });

  test('POST fd-bookings validates input', () {
    expect(routes.dispatch('POST', ApiEndpoints.fdBookings), _apiError('BAD_REQUEST'));
    expect(
      routes.dispatch('POST', ApiEndpoints.fdBookings, body: _fdBody()..remove('tenorMonths')),
      _apiError('BAD_REQUEST'),
    );
    expect(
      routes.dispatch('POST', ApiEndpoints.fdBookings,
          body: _fdBody()..['personaId'] = 'nobody'),
      _apiError('NOT_FOUND'),
    );
  });

  test('unknown routes and methods are rejected', () {
    expect(routes.dispatch('GET', '/api/unknown'), _apiError('NOT_FOUND'));
    expect(routes.dispatch('DELETE', ApiEndpoints.personas), _apiError('METHOD_NOT_ALLOWED'));
  });
}
