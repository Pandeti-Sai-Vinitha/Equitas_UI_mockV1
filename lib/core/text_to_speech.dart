import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TextToSpeech {
  TextToSpeech._();

  static final _engine = FlutterTts();
  static bool _isConfigured = false;
  static const _speechRate = 0.58;

  static Future<void> speak(String text) async {
    final response = _prepareForSpeech(text);
    if (response.isEmpty) return;

    try {
      await _engine.stop();
      if (!_isConfigured) {
        await _engine.setLanguage('en-IN');
        await _engine.setSpeechRate(_speechRate);
        _isConfigured = true;
      }
      await _engine.speak(response);
    } on MissingPluginException catch (error) {
      debugPrint('Text-to-speech is unavailable on this platform: $error');
    } on PlatformException catch (error) {
      debugPrint('Could not speak the assistant response: ${error.message}');
    }
  }

  static String _prepareForSpeech(String text) {
    return text.replaceAllMapped(RegExp(r'₹\s*(-?\d(?:[\d,]*\d)?(?:\.\d+)?)'), (
      match,
    ) {
      final value = match[1]!.replaceAll(',', '');
      final amount = double.parse(value);
      final rupees = amount.abs().truncate();
      final paise = ((amount.abs() - rupees) * 100).round();
      final words = _rupeeAmountInWords(rupees);
      final sign = amount < 0 ? 'minus ' : '';
      if (paise == 0) return '$sign$words rupees';
      return '$sign$words rupees and ${_integerInWords(paise)} paise';
    });
  }

  static String _rupeeAmountInWords(int amount) {
    if (amount >= 150000 && amount % 100000 == 50000) {
      return '${_integerInWords(amount ~/ 100000)} and a half lakh';
    }
    return _integerInWords(amount);
  }

  static String _integerInWords(int value) {
    if (value == 0) return 'zero';
    final words = <String>[];
    var remaining = value;
    for (final (scale, name) in [
      (10000000, 'crore'),
      (100000, 'lakh'),
      (1000, 'thousand'),
    ]) {
      if (remaining < scale) continue;
      words
        ..add(_integerInWords(remaining ~/ scale))
        ..add(name);
      remaining %= scale;
    }
    if (remaining > 0) words.add(_underThousand(remaining));
    return words.join(' ');
  }

  static String _underThousand(int value) {
    const ones = [
      'zero',
      'one',
      'two',
      'three',
      'four',
      'five',
      'six',
      'seven',
      'eight',
      'nine',
      'ten',
      'eleven',
      'twelve',
      'thirteen',
      'fourteen',
      'fifteen',
      'sixteen',
      'seventeen',
      'eighteen',
      'nineteen',
    ];
    const tens = [
      '',
      '',
      'twenty',
      'thirty',
      'forty',
      'fifty',
      'sixty',
      'seventy',
      'eighty',
      'ninety',
    ];

    final words = <String>[];
    var remaining = value;
    if (remaining >= 100) {
      words
        ..add(ones[remaining ~/ 100])
        ..add('hundred');
      remaining %= 100;
    }
    if (remaining >= 20) {
      words.add(tens[remaining ~/ 10]);
      remaining %= 10;
    }
    if (remaining > 0) words.add(ones[remaining]);
    return words.join(' ');
  }
}
