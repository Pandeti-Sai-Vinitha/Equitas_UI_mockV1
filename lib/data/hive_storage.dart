import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../domain/demo_settings.dart';

class HiveBoxes {
  static const String settings = 'settingsBox';
  static const String personas = 'personasBox';
  static const String transactions = 'transactionsBox';
  static const String chat = 'chatBox';
  static const String supportTickets = 'supportTicketsBox';

  static const List<String> all = [
    settings,
    personas,
    transactions,
    chat,
    supportTickets,
  ];

  /// Boxes wiped by a demo reset. Settings are cleared key by key instead so
  /// presenter preferences (latency, failure toggle) survive a reset.
  static const List<String> demoData = [
    personas,
    transactions,
    chat,
    supportTickets,
  ];
}

/// Thin wrapper over the Hive boxes the app uses.
///
/// Persona records are stored as JSON strings so nested maps round-trip
/// without Hive's `Map<dynamic, dynamic>` casting issues.
class LocalStorageService {
  const LocalStorageService();

  static const String _selectedPersonaKey = 'selected_persona_id';
  static const String _seedVersionKey = 'seed_version';
  static const String _seedCurrencyKey = 'seed_currency';
  static const String _personaOrderKey = 'persona_ids';
  static const String _latencyKey = 'latency_ms';
  static const String _simulateFailureKey = 'simulate_failure';

  static Future<void> initialize() async {
    await Hive.initFlutter();
    await openBoxes();
  }

  static Future<void> openBoxes() async {
    for (final name in HiveBoxes.all) {
      await Hive.openBox<dynamic>(name);
    }
  }

  Box<dynamic> get _settingsBox => Hive.box<dynamic>(HiveBoxes.settings);
  Box<dynamic> get _personasBox => Hive.box<dynamic>(HiveBoxes.personas);
  Box<dynamic> get _transactionsBox =>
      Hive.box<dynamic>(HiveBoxes.transactions);
  Box<dynamic> get _chatBox => Hive.box<dynamic>(HiveBoxes.chat);
  Box<dynamic> get _supportTicketsBox =>
      Hive.box<dynamic>(HiveBoxes.supportTickets);

  // ---------- Selected persona ----------

  Future<void> saveSelectedPersonaId(String id) async {
    await _settingsBox.put(_selectedPersonaKey, id);
  }

  String? getSelectedPersonaId() {
    return _settingsBox.get(_selectedPersonaKey) as String?;
  }

  // ---------- Persona records (seeded from JSON) ----------

  int? get seedVersion => _settingsBox.get(_seedVersionKey) as int?;

  String? get seedCurrency => _settingsBox.get(_seedCurrencyKey) as String?;

  Future<void> saveSeedCurrency(String currency) async {
    await _settingsBox.put(_seedCurrencyKey, currency);
  }

  /// Replaces all persona records, keeping [records] order for display.
  Future<void> savePersonaRecords(
    List<Map<String, dynamic>> records, {
    required int seedVersion,
  }) async {
    final ids = records.map(_recordId).toList();
    await _personasBox.clear();
    await _personasBox.putAll({
      for (final record in records) _recordId(record): jsonEncode(record),
    });
    await _settingsBox.put(_personaOrderKey, ids);
    await _settingsBox.put(_seedVersionKey, seedVersion);
  }

  Future<void> savePersonaRecord(Map<String, dynamic> record) async {
    await _personasBox.put(_recordId(record), jsonEncode(record));
  }

  Map<String, dynamic>? getPersonaRecord(String id) {
    final raw = _personasBox.get(id) as String?;
    if (raw == null) return null;
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  List<Map<String, dynamic>> getPersonaRecords() {
    final ids =
        (_settingsBox.get(_personaOrderKey) as List<dynamic>? ?? const [])
            .cast<String>();
    return [for (final id in ids) ?getPersonaRecord(id)];
  }

  // ---------- FD bookings ----------

  Future<void> saveFDBooking(Map<String, dynamic> bookingJson) async {
    final id = bookingJson['id'] as String;
    await _transactionsBox.put(id, bookingJson);
  }

  List<Map<String, dynamic>> getAllFDBookings() {
    return _transactionsBox.values
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .toList();
  }

  Future<void> saveSupportTicket(Map<String, dynamic> ticket) async {
    final id = ticket['id'] as String;
    await _supportTicketsBox.put(id, jsonEncode(ticket));
  }

  Map<String, dynamic>? getSupportTicket(String id) {
    final raw = _supportTicketsBox.get(id) as String?;
    if (raw == null) return null;
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  List<Map<String, dynamic>> getSupportTickets() {
    return _supportTicketsBox.values
        .map(
          (entry) =>
              Map<String, dynamic>.from(jsonDecode(entry as String) as Map),
        )
        .toList();
  }

  // ---------- Chat history (one conversation per persona) ----------

  Future<void> saveChat(
    String personaId,
    Map<String, dynamic> conversation,
  ) async {
    await _chatBox.put(personaId, jsonEncode(conversation));
  }

  Map<String, dynamic>? getChat(String personaId) {
    final raw = _chatBox.get(personaId) as String?;
    if (raw == null) return null;
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  // ---------- Demo settings ----------

  DemoSettings getDemoSettings() {
    return DemoSettings(
      simulatedLatencyMs:
          _settingsBox.get(_latencyKey) as int? ??
          DemoSettings.defaultLatencyMs,
      simulateFailure: _settingsBox.get(_simulateFailureKey) as bool? ?? false,
    );
  }

  Future<void> saveDemoSettings(DemoSettings settings) async {
    await _settingsBox.put(_latencyKey, settings.simulatedLatencyMs);
    await _settingsBox.put(_simulateFailureKey, settings.simulateFailure);
  }

  // ---------- Reset ----------

  /// Wipes everything a demo creates, keeping presenter settings.
  Future<void> clearDemoData() async {
    for (final name in HiveBoxes.demoData) {
      await Hive.box<dynamic>(name).clear();
    }
    await _settingsBox.deleteAll([
      _selectedPersonaKey,
      _seedVersionKey,
      _seedCurrencyKey,
      _personaOrderKey,
    ]);
  }

  static String _recordId(Map<String, dynamic> record) {
    return (record['persona'] as Map)['id'] as String;
  }
}
