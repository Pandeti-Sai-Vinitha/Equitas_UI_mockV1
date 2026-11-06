import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mock2/domain/demo_settings.dart';
import 'package:mock2/domain/fixed_deposit.dart';
import 'package:mock2/state/booking_notifier.dart';
import 'package:mock2/state/credit_line_notifier.dart';
import 'package:mock2/state/demo_reset.dart';
import 'package:mock2/state/persona_notifier.dart';
import 'package:mock2/state/providers.dart';

import '../helpers/test_hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late ProviderContainer container;

  setUp(() async {
    directory = await openTestHive();
    await seedTestData();
    container = createContainer();
    await waitUntil(() => !container.read(personaProvider).isLoading);
  });

  tearDown(() async {
    container.dispose();
    await closeTestHive(directory);
  });

  /// Runs both demo scenarios so there is plenty of state to wipe.
  Future<void> dirtyTheDemo() async {
    await container.read(fdBookingProvider.notifier).bookFixedDeposit(
          personaId: 'p_salaried_01',
          depositAmount: 150000,
          tenorMonths: 12,
          interestRate: 7.2,
          payoutOption: InterestPayout.atMaturity,
          autoRenew: true,
        );
    await waitUntil(() => !container.read(personaProvider).isLoading);

    await container.read(personaProvider.notifier).selectPersona('p_biz_02');
    final offer = (await container.read(recommendationsProvider.future)).single;
    await container.read(creditLineProvider.notifier).activate(personaId: 'p_biz_02', recommendation: offer);
    await waitUntil(() => !container.read(personaProvider).isLoading);
  }

  test('reset restores balances, offers, bookings, credit and selection', () async {
    await dirtyTheDemo();
    expect(container.read(fdBookingProvider).bookings, hasLength(1));
    expect(container.read(creditLineProvider).status, CreditActivationStatus.success);
    expect(container.read(personaProvider).selectedPersona.id, 'p_biz_02');

    await container.read(demoResetProvider)();
    await waitUntil(() => !container.read(personaProvider).isLoading);
    await waitUntil(() => !container.read(fdBookingProvider).isLoadingBookings);

    final persona = container.read(personaProvider);
    expect(persona.selectedPersona.id, 'p_salaried_01');
    expect(persona.personas.first.financialSummary.currentBalance, 185000);
    expect(persona.personas.last.availableCredit, 0);
    expect(persona.personas.expand((item) => item.holdings), isEmpty);
    expect(container.read(fdBookingProvider).bookings, isEmpty);
    expect(container.read(fdBookingProvider).status, FDBookingStatus.initial);
    expect(container.read(creditLineProvider).status, CreditActivationStatus.initial);
    expect(storage.getAllFDBookings(), isEmpty);

    // Offers are back to the baseline for both personas.
    final ananyaOffer = (await container.read(recommendationsProvider.future)).single;
    expect(ananyaOffer.recommendedAmount, 150000);
    await container.read(personaProvider.notifier).selectPersona('p_biz_02');
    final rajeshOffer = (await container.read(recommendationsProvider.future)).single;
    expect(rajeshOffer.recommendedAmount, 80000);
  });

  test('reset keeps presenter settings and works while failures are simulated', () async {
    await container.read(demoSettingsProvider.notifier).setLatency(1500);
    await container.read(demoSettingsProvider.notifier).setSimulateFailure(true);

    await container.read(demoResetProvider)();

    final settings = storage.getDemoSettings();
    expect(settings.simulatedLatencyMs, 1500);
    expect(settings.simulateFailure, isTrue);
    expect(storage.getPersonaRecords(), hasLength(2));
  });

  test('can run the whole demo again after a reset', () async {
    await dirtyTheDemo();
    await container.read(demoResetProvider)();
    await container.read(demoSettingsProvider.notifier).setLatency(0);
    await container.read(demoSettingsProvider.notifier).setSimulateFailure(false);
    await waitUntil(() => !container.read(personaProvider).isLoading);

    await container.read(fdBookingProvider.notifier).bookFixedDeposit(
          personaId: 'p_salaried_01',
          depositAmount: 150000,
          tenorMonths: 12,
          interestRate: 7.2,
          payoutOption: InterestPayout.atMaturity,
          autoRenew: true,
        );

    expect(container.read(fdBookingProvider).status, FDBookingStatus.success);
    await waitUntil(() => !container.read(personaProvider).isLoading);
    expect(container.read(personaProvider).selectedPersona.financialSummary.currentBalance, 35000);
  });

  test('settings notifier restores persisted values on startup', () async {
    await container.read(demoSettingsProvider.notifier).setLatency(2000);
    final fresh = ProviderContainer();
    addTearDown(fresh.dispose);

    expect(fresh.read(demoSettingsProvider).simulatedLatencyMs, 2000);
    expect(fresh.read(demoSettingsProvider).simulateFailure, isFalse);
    expect(const DemoSettings().simulatedLatencyMs, DemoSettings.defaultLatencyMs);
  });
}
