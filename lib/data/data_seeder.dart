import 'dart:convert';

import 'package:flutter/services.dart';

import '../core/demo_currency.dart';
import '../core/demo_config.dart';
import 'hive_storage.dart';

/// Bump when persona JSON changes so installed demos reseed.
const int kSeedVersion = 3;

/// Persona assets, in display order.
const List<String> kPersonaAssets = [
  'salaried_persona.json',
  'business_persona.json',
];

const String kMockDataDir = 'lib/mock_data';

/// Copies the bundled persona JSON into Hive. After seeding, Hive is the
/// source of truth and the app never re-reads the persona assets.
class DataSeeder {
  final LocalStorageService _storage;
  final AssetBundle _bundle;
  final DemoCurrency _currency;

  DataSeeder(
    this._storage, {
    AssetBundle? bundle,
    DemoCurrency currency = selectedDemoCurrency,
  }) : _bundle = bundle ?? rootBundle,
       _currency = currency;

  /// Seeds on first run or when [kSeedVersion] changed. Returns whether it seeded.
  Future<bool> seedIfNeeded() async {
    final upToDate =
        _storage.seedVersion == kSeedVersion &&
        _storage.seedCurrency == _currency.code &&
        _storage.getPersonaRecords().length == kPersonaAssets.length;
    if (upToDate) return false;
    await reseed();
    return true;
  }

  /// Clears all demo data and restores the JSON baseline.
  Future<void> reseed() async {
    final records = await Future.wait(kPersonaAssets.map(_loadRecord));
    for (final record in records) {
      _scaleMoneyFields(record);
    }
    await _storage.clearDemoData();
    await _storage.savePersonaRecords(records, seedVersion: kSeedVersion);
    await _storage.saveSeedCurrency(_currency.code);
  }

  Future<Map<String, dynamic>> _loadRecord(String fileName) async {
    final content = await _bundle.loadString('$kMockDataDir/$fileName');
    final envelope = Map<String, dynamic>.from(jsonDecode(content) as Map);
    return Map<String, dynamic>.from(envelope['data'] as Map);
  }

  void _scaleMoneyFields(Map<String, dynamic> record) {
    const moneyFields = {
      'currentBalance',
      'projectedIncome30D',
      'projectedSpend30D',
      'minimumBuffer',
      'amount',
      'target',
    };

    void scaleValue(Map<String, dynamic> object) {
      for (final entry in object.entries.toList()) {
        final value = entry.value;
        if (entry.key == 'currency') {
          object[entry.key] = _currency.code;
        } else if (moneyFields.contains(entry.key) && value is num) {
          object[entry.key] = _currency.scaleAmount(value);
        } else if (value is Map<String, dynamic>) {
          scaleValue(value);
        } else if (value is List) {
          for (final item in value) {
            if (item is Map<String, dynamic>) scaleValue(item);
          }
        }
      }
    }

    scaleValue(record);
  }
}
