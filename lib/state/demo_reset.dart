import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'booking_notifier.dart';
import 'chat_notifier.dart';
import 'credit_line_notifier.dart';
import 'persona_notifier.dart';
import 'providers.dart';

/// Restores the JSON baseline in Hive, then rebuilds every account-facing
/// provider so the UI matches a fresh install without restarting the app.
///
/// This is a presenter control, not a customer API call: it talks to the
/// seeder directly so it still works while "simulate failure" is switched on.
/// Latency and failure settings survive a reset.
final demoResetProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    await ref.read(dataSeederProvider).reseed();
    ref.invalidate(personaProvider);
    ref.invalidate(fdBookingProvider);
    ref.invalidate(creditLineProvider);
    ref.invalidate(debitCardLimitProvider);
    ref.invalidate(chatProvider);
    // Offers are recomputed by recommendationsProvider, which watches personaProvider.
  };
});
