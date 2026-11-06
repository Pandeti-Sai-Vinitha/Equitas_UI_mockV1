import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api_client.dart';
import '../data/banking_repository.dart';
import '../data/data_seeder.dart';
import '../data/hive_storage.dart';
import '../data/mock_api_client.dart';
import '../domain/demo_settings.dart';
import '../routes/mock_api_routes.dart';
import 'demo_settings_notifier.dart';

// Infrastructure providers. Override these in tests to swap in fakes.

final localStorageProvider = Provider<LocalStorageService>((ref) {
  return const LocalStorageService();
});

final dataSeederProvider = Provider<DataSeeder>((ref) {
  return DataSeeder(ref.watch(localStorageProvider));
});

final demoSettingsProvider =
    StateNotifierProvider<DemoSettingsNotifier, DemoSettings>((ref) {
      return DemoSettingsNotifier(ref.watch(localStorageProvider));
    });

final completedMicroActionsProvider = StateProvider<Set<String>>(
  (ref) => const {},
);

final debitCardLimitProvider = StateProvider.family<int, String>(
  (ref, _) => 50000,
);

final mockApiRoutesProvider = Provider<MockApiRoutes>((ref) {
  return MockApiRoutes(ref.watch(localStorageProvider));
});

final apiClientProvider = Provider<ApiClient>((ref) {
  return MockApiClient(
    ref.watch(mockApiRoutesProvider),
    settings: () => ref.read(demoSettingsProvider),
  );
});

final bankingRepositoryProvider = Provider<BankingRepository>((ref) {
  return BankingRepository(ref.watch(apiClientProvider));
});
