import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../core/demo_config.dart';

Future<String?> showVoicePrompt(
  BuildContext context, {
  ValueChanged<String>? onTranscript,
}) {
  const colors = selectedDemoColors;
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: false,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, _, _) => Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            bottom: 104,
            child: ClipRect(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 9, sigmaY: 9),
                child: ColoredBox(
                  color: colors.background.withValues(alpha: 0.42),
                ),
              ),
            ),
          ),
          _VoicePromptScreen(onTranscript: onTranscript),
        ],
      ),
    ),
    transitionBuilder: (context, animation, secondaryAnimation, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

class _VoiceQueryRecognizer {
  _VoiceQueryRecognizer._();

  static final instance = _VoiceQueryRecognizer._();

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _initialized = false;
  bool _available = false;
  ValueChanged<String>? _onResult;
  ValueChanged<String>? _onStatus;
  ValueChanged<String>? _onError;
  ValueChanged<double>? _onSoundLevel;

  bool get isListening => _speech.isListening;

  Future<void> start({
    required ValueChanged<String> onResult,
    required ValueChanged<String> onStatus,
    required ValueChanged<String> onError,
    required ValueChanged<double> onSoundLevel,
  }) async {
    _onResult = onResult;
    _onStatus = onStatus;
    _onError = onError;
    _onSoundLevel = onSoundLevel;

    try {
      if (!_initialized) {
        _available = await _speech.initialize(
          onStatus: (status) => _onStatus?.call(status),
          onError: (error) => _onError?.call(error.errorMsg),
        );
        _initialized = _available;
      }
      if (!_available) {
        _onError?.call('Speech recognition is unavailable on this device.');
        return;
      }

      final locales = await _speech.locales();
      String? localeId;
      for (final locale in locales) {
        final normalized = locale.localeId.toLowerCase().replaceAll('_', '-');
        if (normalized == 'en-in') {
          localeId = locale.localeId;
          break;
        }
        if (normalized.startsWith('en') && localeId == null) {
          localeId = locale.localeId;
        }
      }

      await _speech.listen(
        onResult: (result) => _onResult?.call(result.recognizedWords),
        onSoundLevelChange: (level) => _onSoundLevel?.call(level),
        listenOptions: stt.SpeechListenOptions(
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 4),
          partialResults: true,
          listenMode: stt.ListenMode.dictation,
          localeId: localeId,
        ),
      );
    } on MissingPluginException {
      _onError?.call('Voice input is not supported on this platform.');
    } on PlatformException catch (error) {
      _onError?.call(error.message ?? 'Could not start voice input.');
    }
  }

  Future<void> stop() async {
    if (!_speech.isListening) return;
    try {
      await _speech.stop();
    } on MissingPluginException {
      _onError?.call('Voice input is not supported on this platform.');
    } on PlatformException catch (error) {
      _onError?.call(error.message ?? 'Could not stop voice input.');
    }
  }

  Future<void> close() async {
    _onResult = null;
    _onStatus = null;
    _onError = null;
    _onSoundLevel = null;
    if (_speech.isListening) {
      try {
        await _speech.cancel();
      } on MissingPluginException catch (error) {
        debugPrint('Could not close the voice input session: $error');
      } on PlatformException catch (error) {
        debugPrint('Could not close the voice input session: $error');
      }
    }
  }
}

class _VoicePromptScreen extends StatefulWidget {
  const _VoicePromptScreen({this.onTranscript});

  final ValueChanged<String>? onTranscript;

  @override
  State<_VoicePromptScreen> createState() => _VoicePromptScreenState();
}

class _VoicePromptScreenState extends State<_VoicePromptScreen> {
  String _recognizedText = '';
  String? _errorMessage;
  bool _isListening = false;
  bool _hasSubmitted = false;
  double _soundLevel = 0;
  Timer? _autoSubmitTimer;

  @override
  void initState() {
    super.initState();
    _startListening();
  }

  @override
  void dispose() {
    _autoSubmitTimer?.cancel();
    unawaited(_VoiceQueryRecognizer.instance.close());
    super.dispose();
  }

  Future<void> _startListening() async {
    _autoSubmitTimer?.cancel();
    setState(() {
      _isListening = true;
      _errorMessage = null;
      _hasSubmitted = false;
    });
    await _VoiceQueryRecognizer.instance.start(
      onResult: (text) {
        if (!mounted) return;
        setState(() => _recognizedText = text);
        widget.onTranscript?.call(text);
      },
      onStatus: (status) {
        if (!mounted) return;
        final isListening = status == 'listening';
        setState(() => _isListening = isListening);
        if (isListening) {
          _autoSubmitTimer?.cancel();
        } else {
          _scheduleAutoSubmit();
        }
      },
      onError: (message) {
        if (!mounted) return;
        final noSpeech =
            message == 'error_speech_timeout' || message == 'error_no_match';
        setState(() {
          _isListening = false;
          _errorMessage = noSpeech
              ? (_recognizedText.trim().isEmpty
                    ? 'No speech detected. Tap the microphone to try again.'
                    : null)
              : message;
        });
        if (_recognizedText.trim().isNotEmpty) _scheduleAutoSubmit();
      },
      onSoundLevel: (level) {
        if (!mounted) return;
        setState(() => _soundLevel = level);
      },
    );
    if (mounted && !_VoiceQueryRecognizer.instance.isListening) {
      setState(() => _isListening = false);
    }
  }

  void _scheduleAutoSubmit() {
    _autoSubmitTimer?.cancel();
    _autoSubmitTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted && !_isListening && _recognizedText.trim().isNotEmpty) {
        _submitRecognizedText();
      }
    });
  }

  void _submitRecognizedText() {
    final query = _recognizedText.trim();
    if (!mounted || query.isEmpty || _hasSubmitted) return;
    _autoSubmitTimer?.cancel();
    _hasSubmitted = true;
    unawaited(_VoiceQueryRecognizer.instance.stop());
    Navigator.of(context).pop(query);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      key: const ValueKey('voice-prompt-screen'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                key: const ValueKey('close-voice-prompt'),
                tooltip: 'Close voice input',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _isListening ? 'Listening…' : 'Voice input',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      height: 160,
                      width: double.infinity,
                      child: _VoiceWaveform(soundLevel: _soundLevel),
                    ),
                  ],
                ),
              ),
            ),
            if (_errorMessage != null) ...[
              Text(
                _errorMessage!,
                key: const ValueKey('voice-input-error'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _VoiceWaveform extends StatefulWidget {
  const _VoiceWaveform({required this.soundLevel});

  final double soundLevel;

  @override
  State<_VoiceWaveform> createState() => _VoiceWaveformState();
}

class _VoiceWaveformState extends State<_VoiceWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion == _reduceMotion) return;
    _reduceMotion = reduceMotion;
    if (reduceMotion) {
      _controller
        ..stop()
        ..value = 0;
    } else {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = selectedDemoColors;
    return SizedBox.expand(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0015)
            ..rotateX(_reduceMotion ? 0 : -0.09)
            ..rotateY(
              _reduceMotion
                  ? 0
                  : math.sin(_controller.value * math.pi * 2) * 0.035,
            ),
          child: CustomPaint(
            key: const ValueKey('voice-wave'),
            painter: _VoiceWavePainter(
              phase: _reduceMotion ? 0 : _controller.value * math.pi * 2,
              soundLevel: widget.soundLevel,
              accent: colors.accent,
            ),
          ),
        ),
      ),
    );
  }
}

class _VoiceWavePainter extends CustomPainter {
  const _VoiceWavePainter({
    required this.phase,
    required this.soundLevel,
    required this.accent,
  });

  final double phase;
  final double soundLevel;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final normalizedLevel = ((soundLevel + 2) / 12).clamp(0.0, 1.0);
    _drawWave(
      canvas,
      size,
      phase - 0.58,
      accent.withValues(alpha: 0.72),
      3,
      0.2 + (normalizedLevel * 0.2),
    );
    _drawWave(
      canvas,
      size,
      phase,
      Color.lerp(accent, Colors.white, 0.45)!,
      1.8,
      0.15 + (normalizedLevel * 0.14),
    );
    _drawWave(
      canvas,
      size,
      phase + 0.78,
      Colors.white.withValues(alpha: 0.92),
      1.25,
      0.1 + (normalizedLevel * 0.09),
    );
  }

  void _drawWave(
    Canvas canvas,
    Size size,
    double phase,
    Color color,
    double strokeWidth,
    double amplitudeFactor,
  ) {
    final centerY = size.height * 0.5;
    final path = Path();
    final amplitude = size.height * amplitudeFactor;
    for (var index = 0; index <= 120; index++) {
      final progress = index / 120;
      final x = size.width * progress;
      final envelope = 0.35 + (0.65 * math.sin(progress * math.pi));
      final fundamental = math.sin((progress * math.pi * 2.2) + phase);
      final detail = math.sin((progress * math.pi * 4.1) - (phase * 0.7));
      final y =
          centerY +
          (amplitude * envelope * (fundamental * 0.72 + detail * 0.28));
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: color.a * 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth * 4
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_VoiceWavePainter oldDelegate) =>
      phase != oldDelegate.phase ||
      soundLevel != oldDelegate.soundLevel ||
      accent != oldDelegate.accent;
}
