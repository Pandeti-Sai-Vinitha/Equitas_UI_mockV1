import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:mock2/data/hive_storage.dart';
import 'package:mock2/domain/demo_settings.dart';

import '../helpers/test_hive.dart';

void main() {
  test('persists persona selection, bookings and settings across reopen', () async {
    final directory = await openTestHive();
    try {
      await storage.saveSelectedPersonaId('p_biz_02');
      await storage.saveFDBooking({
        'id': 'FD_test',
        'personaId': 'p_biz_02',
        'depositAmount': 50000.0,
      });
      await storage.saveDemoSettings(
        const DemoSettings(simulatedLatencyMs: 900, simulateFailure: true),
      );
      await Hive.close();

      Hive.init(directory.path);
      await LocalStorageService.openBoxes();

      expect(storage.getSelectedPersonaId(), 'p_biz_02');
      expect(storage.getAllFDBookings().single['id'], 'FD_test');
      final settings = storage.getDemoSettings();
      expect(settings.simulatedLatencyMs, 900);
      expect(settings.simulateFailure, isTrue);
    } finally {
      await closeTestHive(directory);
    }
  });

  test('defaults when nothing is stored', () async {
    final directory = await openTestHive();
    try {
      expect(storage.getSelectedPersonaId(), isNull);
      expect(storage.getPersonaRecord('missing'), isNull);
      expect(storage.getPersonaRecords(), isEmpty);
      expect(storage.seedVersion, isNull);
      expect(storage.getDemoSettings().simulatedLatencyMs, DemoSettings.defaultLatencyMs);
      expect(storage.getDemoSettings().simulateFailure, isFalse);
    } finally {
      await closeTestHive(directory);
    }
  });
}
