import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock2/core/text_to_speech.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('speaks faster and reads Indian currency amounts naturally', () async {
    const channel = MethodChannel('flutter_tts');
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await TextToSpeech.speak(
      'Your balance is ₹1,50,000, and the fee is ₹1,000.',
    );

    expect(calls.map((call) => call.method), [
      'stop',
      'setLanguage',
      'setSpeechRate',
      'speak',
    ]);
    expect(calls[1].arguments, 'en-IN');
    expect(calls[2].arguments, 0.58);
    expect(
      calls.last.arguments,
      'Your balance is one and a half lakh rupees, and the fee is one thousand rupees.',
    );
  });
}
