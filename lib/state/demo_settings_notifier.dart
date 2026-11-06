import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/hive_storage.dart';
import '../domain/demo_settings.dart';

/// Presenter settings, persisted in Hive so they survive restarts and resets.
class DemoSettingsNotifier extends StateNotifier<DemoSettings> {
  final LocalStorageService _storage;

  DemoSettingsNotifier(this._storage) : super(_storage.getDemoSettings());

  Future<void> setLatency(int milliseconds) async {
    state = state.copyWith(simulatedLatencyMs: milliseconds);
    await _storage.saveDemoSettings(state);
  }

  Future<void> setSimulateFailure(bool value) async {
    state = state.copyWith(simulateFailure: value);
    await _storage.saveDemoSettings(state);
  }
}
