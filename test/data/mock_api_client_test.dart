import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:mock2/core/exceptions.dart';
import 'package:mock2/data/mock_api_client.dart';
import 'package:mock2/domain/demo_settings.dart';
import 'package:mock2/routes/mock_api_routes.dart';

import '../helpers/test_hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late List<Duration> delays;
  late DemoSettings settings;
  late MockApiClient client;

  setUp(() async {
    directory = await openTestHive();
    await seedTestData();
    delays = [];
    settings = const DemoSettings(simulatedLatencyMs: 1000);
    client = MockApiClient(
      MockApiRoutes(storage),
      settings: () => settings,
      random: Random(42),
      delay: (duration) async => delays.add(duration),
    );
  });

  tearDown(() => closeTestHive(directory));

  test('applies jittered latency before each call', () async {
    final response = await client.get(ApiEndpoints.personas);

    expect(response['status'], 'success');
    expect(delays, hasLength(1));
    expect(delays.single.inMilliseconds, inInclusiveRange(800, 1200));
  });

  test('jitter stays within ±20% across many samples', () {
    final samples = List.generate(
      500,
      (_) => client.latencyFor(1000).inMilliseconds,
    );
    expect(samples.every((ms) => ms >= 800 && ms <= 1200), isTrue);
    expect(samples.toSet().length, greaterThan(50));
  });

  test('zero latency skips the delay', () async {
    settings = const DemoSettings(simulatedLatencyMs: 0);
    await client.post(ApiEndpoints.fdBookings, {
      'personaId': 'p_salaried_01',
      'depositAmount': 1000,
      'tenorMonths': 6,
      'interestRate': 7.0,
      'payoutOption': 'InterestPayout.atMaturity',
      'autoRenew': false,
    });
    expect(delays, isEmpty);
  });

  test('simulated failure throws a network error after the delay', () async {
    settings = const DemoSettings(
      simulatedLatencyMs: 200,
      simulateFailure: true,
    );

    await expectLater(
      client.get(ApiEndpoints.personas),
      throwsA(
        isA<MockApiException>()
            .having((error) => error.code, 'code', 'NETWORK_UNAVAILABLE')
            .having((error) => error.statusCode, 'statusCode', 503),
      ),
    );
    expect(delays, hasLength(1));
  });

  test('reads settings on every call', () async {
    await client.get(ApiEndpoints.personas);
    settings = const DemoSettings(simulatedLatencyMs: 3000);
    await client.get(ApiEndpoints.personas);

    expect(delays.last.inMilliseconds, inInclusiveRange(2400, 3600));
  });

  group('chat latency', () {
    Future<void> chat() => client.post(ApiEndpoints.chat, {
      'personaId': 'p_salaried_01',
      'message': 'hi',
    });

    test('uses the configured network latency for chat requests', () async {
      settings = const DemoSettings(simulatedLatencyMs: 100);
      await chat();
      expect(delays.single.inMilliseconds, inInclusiveRange(80, 120));
    });

    test('a slow network applies its configured latency', () async {
      settings = const DemoSettings(simulatedLatencyMs: 3000);
      await chat();
      expect(delays.single.inMilliseconds, inInclusiveRange(2400, 3600));
    });

    test('zero latency switches the thinking time off', () async {
      settings = const DemoSettings(simulatedLatencyMs: 0);
      await chat();
      expect(delays, isEmpty);
    });

    test('other calls are not slowed down', () async {
      settings = const DemoSettings(simulatedLatencyMs: 100);
      await client.get(ApiEndpoints.personas);
      expect(delays.single.inMilliseconds, inInclusiveRange(80, 120));
    });
  });

  test('describeError shows the customer message', () {
    expect(describeError(const MockApiException.badRequest('Nope')), 'Nope');
    expect(describeError(StateError('boom')), contains('boom'));
    expect(
      const MockApiException.notFound('x').toString(),
      contains('NOT_FOUND'),
    );
  });
}
