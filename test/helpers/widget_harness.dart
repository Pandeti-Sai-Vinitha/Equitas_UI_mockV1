import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mock2/data/data_seeder.dart';
import 'package:mock2/data/hive_storage.dart';
import 'package:mock2/domain/demo_settings.dart';
import 'package:mock2/main.dart';
import 'package:mock2/routes/mock_api_routes.dart';
import 'package:mock2/state/chat_notifier.dart';
import 'package:mock2/state/providers.dart';

/// [LocalStorageService] kept in memory.
///
/// Hive does real file IO, which never completes inside a widget test's fake
/// clock. Every future here completes as a microtask, so screens can be
/// driven with plain `tester.pump()`.
class MemoryStorage extends LocalStorageService {
  String? _selected;
  int? _seedVersion;
  String? _seedCurrency;
  List<String> _order = [];
  final Map<String, Map<String, dynamic>> _personas = {};
  final Map<String, Map<String, dynamic>> _bookings = {};
  final Map<String, Map<String, dynamic>> _chats = {};
  final Map<String, Map<String, dynamic>> _supportTickets = {};
  DemoSettings _settings = const DemoSettings(simulatedLatencyMs: 0);

  MemoryStorage();

  static Map<String, dynamic> _copy(Map<String, dynamic> value) =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

  static String _id(Map<String, dynamic> record) =>
      (record['persona'] as Map)['id'] as String;

  @override
  Future<void> saveSelectedPersonaId(String id) async => _selected = id;

  @override
  String? getSelectedPersonaId() => _selected;

  @override
  int? get seedVersion => _seedVersion;

  @override
  String? get seedCurrency => _seedCurrency;

  @override
  Future<void> saveSeedCurrency(String currency) async =>
      _seedCurrency = currency;

  @override
  Future<void> savePersonaRecords(
    List<Map<String, dynamic>> records, {
    required int seedVersion,
  }) async {
    _personas
      ..clear()
      ..addEntries(
        records.map((record) => MapEntry(_id(record), _copy(record))),
      );
    _order = records.map(_id).toList();
    _seedVersion = seedVersion;
  }

  @override
  Future<void> savePersonaRecord(Map<String, dynamic> record) async =>
      _personas[_id(record)] = _copy(record);

  @override
  Map<String, dynamic>? getPersonaRecord(String id) {
    final record = _personas[id];
    return record == null ? null : _copy(record);
  }

  @override
  List<Map<String, dynamic>> getPersonaRecords() => [
    for (final id in _order) _copy(_personas[id]!),
  ];

  @override
  Future<void> saveFDBooking(Map<String, dynamic> bookingJson) async =>
      _bookings[bookingJson['id'] as String] = _copy(bookingJson);

  @override
  List<Map<String, dynamic>> getAllFDBookings() => [
    for (final b in _bookings.values) _copy(b),
  ];

  @override
  Future<void> saveSupportTicket(Map<String, dynamic> ticket) async =>
      _supportTickets[ticket['id'] as String] = _copy(ticket);

  @override
  Map<String, dynamic>? getSupportTicket(String id) {
    final ticket = _supportTickets[id];
    return ticket == null ? null : _copy(ticket);
  }

  @override
  List<Map<String, dynamic>> getSupportTickets() => [
    for (final ticket in _supportTickets.values) _copy(ticket),
  ];

  @override
  Future<void> saveChat(
    String personaId,
    Map<String, dynamic> conversation,
  ) async => _chats[personaId] = _copy(conversation);

  @override
  Map<String, dynamic>? getChat(String personaId) {
    final chat = _chats[personaId];
    return chat == null ? null : _copy(chat);
  }

  @override
  DemoSettings getDemoSettings() => _settings;

  @override
  Future<void> saveDemoSettings(DemoSettings settings) async =>
      _settings = settings;

  @override
  Future<void> clearDemoData() async {
    _personas.clear();
    _bookings.clear();
    _chats.clear();
    _supportTickets.clear();
    _order = [];
    _selected = null;
    _seedVersion = null;
    _seedCurrency = null;
  }
}

/// Serves the bundled mock data from disk synchronously, so loading it never
/// waits on real IO.
class MemoryBundle extends AssetBundle {
  final Map<String, String> _files;

  MemoryBundle._(this._files);

  factory MemoryBundle.fromDisk() {
    final directory = Directory(kMockDataDir);
    return MemoryBundle._({
      for (final file in directory.listSync().whereType<File>())
        '$kMockDataDir/${file.uri.pathSegments.last}': file.readAsStringSync(),
    });
  }

  @override
  Future<ByteData> load(String key) async {
    final bytes = Uint8List.fromList(utf8.encode(_files[key]!));
    return ByteData.sublistView(bytes);
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    final content = _files[key];
    if (content == null) throw FlutterError('Unknown asset: $key');
    return content;
  }
}

/// The app wired to in-memory storage and assets, seeded with the baseline.
class TestApp {
  final MemoryStorage storage = MemoryStorage();
  final MemoryBundle bundle = MemoryBundle.fromDisk();

  Future<Widget> build() async {
    await DataSeeder(storage, bundle: bundle).reseed();
    return ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(storage),
        dataSeederProvider.overrideWithValue(
          DataSeeder(storage, bundle: bundle),
        ),
        mockApiRoutesProvider.overrideWithValue(
          MockApiRoutes(storage, bundle: bundle),
        ),
        chatThinkingDurationProvider.overrideWithValue(
          const Duration(seconds: 1),
        ),
      ],
      child: const MyApp(),
    );
  }

  /// Opens the app on a phone-sized screen and lets the first loads finish.
  /// The menuless demo boots straight into the salaried home canvas.
  Future<void> launch(
    WidgetTester tester, {
    bool startAtWelcome = false,
  }) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await build());
    await settle(tester);
    // startAtWelcome is retained for call-site compatibility but ignored:
    // there is no login screen in this demo.
  }
}

/// Runs queued futures and animations. `pumpAndSettle` would wait forever on
/// the typing indicator's repeating animation, so pump a fixed number of frames.
Future<void> settle(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
