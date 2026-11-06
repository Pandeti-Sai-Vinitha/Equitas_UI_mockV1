import 'dart:math';

import '../core/exceptions.dart';
import '../domain/demo_settings.dart';
import '../routes/mock_api_routes.dart';
import 'api_client.dart';

typedef DelayFn = Future<void> Function(Duration duration);

/// [ApiClient] that adds simulated network latency (and optional failures)
/// in front of [MockApiRoutes].
///
/// [settings] is read on every call, so changes in the demo panel apply to
/// the very next request.
class MockApiClient implements ApiClient {
  /// Latency varies by up to ±20% so repeated calls don't feel scripted.
  static const double jitter = 0.2;
  final MockApiRoutes _routes;
  final DemoSettings Function() _settings;
  final Random _random;
  final DelayFn _delay;

  MockApiClient(
    this._routes, {
    required DemoSettings Function() settings,
    Random? random,
    DelayFn? delay,
  }) : _settings = settings,
       _random = random ?? Random(),
       _delay = delay ?? Future<void>.delayed;

  @override
  Future<Map<String, dynamic>> get(String path) => _send('GET', path);

  @override
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) =>
      _send('POST', path, body: body);

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final settings = _settings();
    final isChat = Uri.parse(path).path == ApiEndpoints.chat;
    final latency = isChat
        ? chatLatencyFor(settings.simulatedLatencyMs)
        : latencyFor(settings.simulatedLatencyMs);
    if (latency > Duration.zero) await _delay(latency);

    if (settings.simulateFailure) {
      throw const MockApiException.networkUnavailable(
        'We could not reach the bank right now. Please try again.',
      );
    }
    return _routes.dispatch(method, path, body: body);
  }

  /// The assistant thinking delay is handled by the chat notifier so it can
  /// overlap the request with its one-second loading indicator.
  Duration chatLatencyFor(int baseMs) {
    return latencyFor(baseMs);
  }

  Duration latencyFor(int baseMs) {
    if (baseMs <= 0) return Duration.zero;
    final factor = 1 + (_random.nextDouble() * 2 - 1) * jitter;
    return Duration(milliseconds: (baseMs * factor).round());
  }
}
