import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:mock2/data/data_seeder.dart';
import 'package:mock2/data/hive_storage.dart';
import 'package:mock2/domain/demo_settings.dart';
import 'package:mock2/state/chat_notifier.dart';

const storage = LocalStorageService();

/// Opens all app boxes in a fresh temp directory.
Future<Directory> openTestHive() async {
  final directory = await Directory.systemTemp.createTemp('mock2_hive_test');
  Hive.init(directory.path);
  await LocalStorageService.openBoxes();
  return directory;
}

Future<void> closeTestHive(Directory directory) async {
  await Hive.close();
  await directory.delete(recursive: true);
}

/// Seeds the JSON baseline with zero latency so tests run instantly.
Future<void> seedTestData() async {
  await storage.saveDemoSettings(const DemoSettings(simulatedLatencyMs: 0));
  await DataSeeder(storage).reseed();
}

/// Lets fire-and-forget notifier loads finish.
Future<void> waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 200 && !condition(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  if (!condition()) throw StateError('Condition not met in time');
}

ProviderContainer createContainer() => ProviderContainer(
  overrides: [chatThinkingDurationProvider.overrideWithValue(Duration.zero)],
);
