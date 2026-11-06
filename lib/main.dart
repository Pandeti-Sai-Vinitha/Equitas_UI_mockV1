import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/demo_config.dart';
import 'data/data_seeder.dart';
import 'data/hive_storage.dart';
import 'screens/dynamic_home_canvas.dart';

// Currency and UI template are set in `core/demo_config.dart`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalStorageService.initialize();
  await DataSeeder(
    const LocalStorageService(),
    currency: selectedDemoCurrency,
  ).seedIfNeeded();
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const colors = selectedDemoColors;
    return MaterialApp(
      title: 'Equitas',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: colors.accent,
          brightness: Brightness.dark,
          surface: colors.surface,
        ),
        scaffoldBackgroundColor: colors.background,
        useMaterial3: true,
      ),
      home: const DynamicHomeCanvas(),
    );
  }
}