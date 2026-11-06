/// Presenter-controlled knobs for the mock network layer.
class DemoSettings {
  static const int defaultLatencyMs = 600;

  final int simulatedLatencyMs;
  final bool simulateFailure;

  const DemoSettings({
    this.simulatedLatencyMs = defaultLatencyMs,
    this.simulateFailure = false,
  });

  DemoSettings copyWith({int? simulatedLatencyMs, bool? simulateFailure}) {
    return DemoSettings(
      simulatedLatencyMs: simulatedLatencyMs ?? this.simulatedLatencyMs,
      simulateFailure: simulateFailure ?? this.simulateFailure,
    );
  }
}
