import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mock2/domain/demo_settings.dart';
import 'package:mock2/domain/fixed_deposit.dart';
import 'package:mock2/domain/models.dart';
import 'package:mock2/state/booking_notifier.dart';
import 'package:mock2/state/credit_line_notifier.dart';
import 'package:mock2/state/persona_notifier.dart';
import 'package:mock2/state/providers.dart';

import '../helpers/test_hive.dart';

Future<void> _book(ProviderContainer container) {
  return container.read(fdBookingProvider.notifier).bookFixedDeposit(
        personaId: 'p_salaried_01',
        depositAmount: 50000,
        tenorMonths: 12,
        interestRate: 7.2,
        payoutOption: InterestPayout.atMaturity,
        autoRenew: true,
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late ProviderContainer container;

  setUp(() async {
    directory = await openTestHive();
    await seedTestData();
  });

  tearDown(() async {
    container.dispose();
    await closeTestHive(directory);
  });

  group('PersonaNotifier', () {
    test('loads personas from Hive and restores the saved selection', () async {
      await storage.saveSelectedPersonaId('p_biz_02');
      container = createContainer();

      await waitUntil(() => !container.read(personaProvider).isLoading);
      final state = container.read(personaProvider);
      expect(state.personas, hasLength(2));
      expect(state.selectedPersona.id, 'p_biz_02');
      expect(state.selectedPersona.recentTransactions, hasLength(10));
      expect(state.errorMessage, isNull);
    });

    test('selectPersona updates state and persists', () async {
      container = createContainer();
      await waitUntil(() => !container.read(personaProvider).isLoading);

      await container.read(personaProvider.notifier).selectPersona('p_biz_02');
      expect(container.read(personaProvider).selectedPersona.id, 'p_biz_02');
      expect(storage.getSelectedPersonaId(), 'p_biz_02');

      // Unknown IDs and re-selecting the current persona are no-ops.
      await container.read(personaProvider.notifier).selectPersona('nobody');
      expect(container.read(personaProvider).selectedPersona.id, 'p_biz_02');
    });

    test('surfaces a friendly error when the network fails', () async {
      await storage.saveDemoSettings(const DemoSettings(simulatedLatencyMs: 0, simulateFailure: true));
      container = createContainer();

      await waitUntil(() => !container.read(personaProvider).isLoading);
      expect(container.read(personaProvider).errorMessage, contains('could not reach the bank'));

      await container.read(demoSettingsProvider.notifier).setSimulateFailure(false);
      await container.read(personaProvider.notifier).refreshPersonas();
      expect(container.read(personaProvider).errorMessage, isNull);
    });

    test('recommendations follow the selected persona', () async {
      container = createContainer();
      await waitUntil(() => !container.read(personaProvider).isLoading);

      final salaried = await container.read(recommendationsProvider.future);
      expect(salaried.single.id, 'rec_fd_01');

      await container.read(personaProvider.notifier).selectPersona('p_biz_02');
      final business = await container.read(recommendationsProvider.future);
      expect(business.single.id, 'rec_credit_01');
    });
  });

  group('FDBookingNotifier', () {
    test('books, persists and lists the FD', () async {
      container = createContainer();
      await _book(container);

      final state = container.read(fdBookingProvider);
      expect(state.status, FDBookingStatus.success);
      expect(state.bookings, hasLength(1));
      expect(storage.getAllFDBookings().single['id'], state.bookingResult!.id);

      // The booking refreshes the persona so the debit shows on the home screen.
      await waitUntil(() => !container.read(personaProvider).isLoading);
      expect(container.read(personaProvider).selectedPersona.financialSummary.currentBalance, 135000);

      container.read(fdBookingProvider.notifier).reset();
      expect(container.read(fdBookingProvider).status, FDBookingStatus.initial);
      expect(container.read(fdBookingProvider).bookingResult, isNull);
    });

    test('loads saved bookings newest first', () async {
      container = createContainer();
      await _book(container);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await _book(container);
      container.dispose();

      container = createContainer();
      await waitUntil(() => !container.read(fdBookingProvider).isLoadingBookings);
      final bookings = container.read(fdBookingProvider).bookings;
      expect(bookings, hasLength(2));
      expect(bookings.first.createdAt.isAfter(bookings.last.createdAt), isTrue);
    });

    test('reports booking failures', () async {
      await storage.saveDemoSettings(const DemoSettings(simulatedLatencyMs: 0, simulateFailure: true));
      container = createContainer();
      await _book(container);

      final state = container.read(fdBookingProvider);
      expect(state.status, FDBookingStatus.error);
      expect(state.errorMessage, contains('could not reach the bank'));
      expect(storage.getAllFDBookings(), isEmpty);
    });
  });

  test('personaBookingsProvider only shows the selected persona FDs', () async {
    container = createContainer();
    await waitUntil(() => !container.read(personaProvider).isLoading);
    await _book(container);
    await waitUntil(() => !container.read(personaProvider).isLoading);
    expect(container.read(personaBookingsProvider), hasLength(1));

    await container.read(personaProvider.notifier).selectPersona('p_biz_02');
    expect(container.read(personaBookingsProvider), isEmpty);
  });

  group('CreditLineNotifier', () {
    Future<void> activateFirstOffer() async {
      await container.read(personaProvider.notifier).selectPersona('p_biz_02');
      final offer = (await container.read(recommendationsProvider.future)).single;
      await container.read(creditLineProvider.notifier).activate(
            personaId: 'p_biz_02',
            recommendation: offer,
          );
    }

    test('activates the overdraft and refreshes the persona', () async {
      container = createContainer();
      await waitUntil(() => !container.read(personaProvider).isLoading);
      await activateFirstOffer();

      final state = container.read(creditLineProvider);
      expect(state.status, CreditActivationStatus.success);
      expect(state.result!.amount, 80000);
      await waitUntil(() => !container.read(personaProvider).isLoading);
      expect(container.read(personaProvider).selectedPersona.availableCredit, 80000);
      expect(await container.read(recommendationsProvider.future), isEmpty);

      container.read(creditLineProvider.notifier).reset();
      expect(container.read(creditLineProvider).status, CreditActivationStatus.initial);
    });

    test('reports activation failures', () async {
      container = createContainer();
      await waitUntil(() => !container.read(personaProvider).isLoading);
      await activateFirstOffer();
      await waitUntil(() => !container.read(personaProvider).isLoading);

      // Second activation of the same product is refused by the API.
      final offer = ProductRecommendation(
        id: 'rec_credit_01',
        title: 'OD',
        description: '',
        category: ProductCategory.credit,
        actionType: ActionType.flexiCreditLine,
        recommendedAmount: 80000,
        expectedReturnOrInterestRate: 11.5,
      );
      await container.read(creditLineProvider.notifier).activate(personaId: 'p_biz_02', recommendation: offer);

      final state = container.read(creditLineProvider);
      expect(state.status, CreditActivationStatus.error);
      expect(state.errorMessage, contains('already active'));
    });
  });

  group('DemoSettingsNotifier', () {
    test('persists latency changes', () async {
      container = createContainer();
      await container.read(demoSettingsProvider.notifier).setLatency(2500);

      expect(container.read(demoSettingsProvider).simulatedLatencyMs, 2500);
      expect(storage.getDemoSettings().simulatedLatencyMs, 2500);
    });
  });
}
