import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:mock2/data/banking_repository.dart';
import 'package:mock2/data/mock_api_client.dart';
import 'package:mock2/domain/demo_settings.dart';
import 'package:mock2/domain/fixed_deposit.dart';
import 'package:mock2/domain/models.dart';
import 'package:mock2/routes/mock_api_routes.dart';

import '../helpers/test_hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late BankingRepository repository;

  setUp(() async {
    directory = await openTestHive();
    await seedTestData();
    repository = BankingRepository(
      MockApiClient(MockApiRoutes(storage), settings: () => const DemoSettings(simulatedLatencyMs: 0)),
    );
  });

  tearDown(() => closeTestHive(directory));

  test('loads both personas with profile detail from Hive', () async {
    final personas = await repository.loadPersonas();

    expect(personas, hasLength(2));
    final ananya = personas.first;
    expect(ananya.name, 'Ananya Sharma');
    expect(ananya.heroBadge, 'PAYCHECK CLEARED');
    expect(ananya.microActions.first['label'], 'Pay House Rent');
    expect(ananya.totalSpend30D, ananya.financialSummary.projectedSpend30D);
    expect(ananya.goals, hasLength(2));

    final rajesh = personas.last;
    expect(rajesh.type, PersonaType.business);
    expect(rajesh.financialSummary.projectedDeficit, 65000);
    expect(rajesh.totalSpend30D, rajesh.financialSummary.projectedSpend30D);
  });

  test('loads a single persona and its transactions', () async {
    final persona = await repository.loadPersona('p_biz_02');
    expect(persona.name, 'Rajesh Traders');

    final transactions = await repository.loadTransactions('p_biz_02');
    expect(transactions, hasLength(10));
    expect(transactions.first.type, TransactionType.credit);
  });

  test('loads recommendations', () async {
    final recommendations = await repository.loadRecommendations('p_salaried_01');
    expect(recommendations.single.actionType, ActionType.openFD);
    expect(recommendations.single.recommendedAmount, 150000);
  });

  test('books a fixed deposit', () async {
    final booking = await repository.bookFixedDeposit(
      personaId: 'p_salaried_01',
      depositAmount: 100000,
      tenorMonths: 12,
      interestRate: 7.2,
      payoutOption: InterestPayout.atMaturity,
      autoRenew: true,
    );

    expect(booking.personaId, 'p_salaried_01');
    expect(booking.maturityAmount, closeTo(107200, 0.001));
  });
}
