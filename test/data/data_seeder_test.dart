import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:mock2/data/data_seeder.dart';
import 'package:mock2/data/hive_storage.dart';
import 'package:mock2/core/demo_currency.dart';
import 'package:mock2/domain/demo_settings.dart';

import '../helpers/test_hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late DataSeeder seeder;

  setUp(() async {
    directory = await openTestHive();
    seeder = DataSeeder(storage);
  });

  tearDown(() => closeTestHive(directory));

  test('first run copies persona JSON into Hive in display order', () async {
    expect(storage.getPersonaRecords(), isEmpty);

    expect(await seeder.seedIfNeeded(), isTrue);

    final records = storage.getPersonaRecords();
    expect(records.map((record) => (record['persona'] as Map)['id']), [
      'p_salaried_01',
      'p_biz_02',
    ]);
    expect(storage.seedVersion, kSeedVersion);
    expect(records.first['recentTransactions'], hasLength(10));
  });

  test(
    'does not reseed when data is current, preserving demo changes',
    () async {
      await seeder.seedIfNeeded();
      final record = storage.getPersonaRecord('p_salaried_01')!;
      (record['financialSummary'] as Map)['currentBalance'] = 1.0;
      await storage.savePersonaRecord(record);

      expect(await seeder.seedIfNeeded(), isFalse);
      expect(
        (storage.getPersonaRecord('p_salaried_01')!['financialSummary']
            as Map)['currentBalance'],
        1.0,
      );
    },
  );

  test('reseeds when the stored seed version is outdated', () async {
    await seeder.seedIfNeeded();
    await Hive.box<dynamic>(
      HiveBoxes.settings,
    ).put('seed_version', kSeedVersion - 1);

    expect(await seeder.seedIfNeeded(), isTrue);
    expect(storage.seedVersion, kSeedVersion);
  });

  test(
    'reseed restores baseline and clears demo data but keeps presenter settings',
    () async {
      await seeder.seedIfNeeded();
      await storage.saveDemoSettings(
        const DemoSettings(simulatedLatencyMs: 1500),
      );
      await storage.saveSelectedPersonaId('p_biz_02');
      await storage.saveFDBooking({'id': 'FD_x', 'personaId': 'p_salaried_01'});
      final record = storage.getPersonaRecord('p_salaried_01')!;
      (record['financialSummary'] as Map)['currentBalance'] = 1.0;
      await storage.savePersonaRecord(record);

      await seeder.reseed();

      expect(storage.getAllFDBookings(), isEmpty);
      expect(storage.getSelectedPersonaId(), isNull);
      expect(
        (storage.getPersonaRecord('p_salaried_01')!['financialSummary']
            as Map)['currentBalance'],
        185000.0,
      );
      expect(storage.getDemoSettings().simulatedLatencyMs, 1500);
    },
  );

  test(
    'currency selection reseeds realistic salaried and business balances',
    () async {
      await seeder.seedIfNeeded();

      final usdSeeder = DataSeeder(storage, currency: DemoCurrency.usd);
      expect(await usdSeeder.seedIfNeeded(), isTrue);
      final usdPersona = storage.getPersonaRecord('p_salaried_01')!;
      final usdSummary = usdPersona['financialSummary'] as Map;
      expect(usdSummary['currency'], 'USD');
      expect(usdSummary['projectedIncome30D'], 6000.0);
      expect(usdSummary['currentBalance'], 9250.0);
      expect(
        storage.getPersonaRecord('p_biz_02')!['financialSummary']['currency'],
        'USD',
      );

      final gbpSeeder = DataSeeder(storage, currency: DemoCurrency.gbp);
      expect(await gbpSeeder.seedIfNeeded(), isTrue);
      final gbpSummary =
          storage.getPersonaRecord('p_salaried_01')!['financialSummary'] as Map;
      expect(gbpSummary['currency'], 'GBP');
      expect(gbpSummary['projectedIncome30D'], 3600.0);
      expect(gbpSummary['currentBalance'], 5550.0);
    },
  );
}
