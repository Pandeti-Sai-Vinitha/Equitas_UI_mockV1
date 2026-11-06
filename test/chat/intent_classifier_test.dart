import 'package:flutter_test/flutter_test.dart';

import 'package:mock2/chat/chat_models.dart';
import 'package:mock2/chat/intent_classifier.dart';

void main() {
  const classifier = IntentClassifier();

  ChatIntent classify(String text) =>
      classifier.classify(IntentClassifier.normalize(text)).intent;

  const utterances = <ChatIntent, List<String>>{
    ChatIntent.greeting: [
      'hi',
      'Hello',
      'hey there',
      'Good morning!',
      'namaste',
    ],
    ChatIntent.thanks: ['thanks', 'Thank you so much'],
    ChatIntent.help: ['help', 'what can you do', 'How does this work?'],
    ChatIntent.checkBalance: [
      "What's my balance?",
      'how much do I have',
      'money in my account',
      'how am I doing',
    ],
    ChatIntent.spendInsight: [
      'Where is my money going?',
      'how much do I spend on rent',
      'how much on dining',
      'show my spending',
      'How much should I keep aside for GST?',
    ],
    ChatIntent.recommend: [
      'I have some extra money this month',
      'what should I do with my savings',
      'where should I park my money',
      'any investment ideas',
      'recommend something',
    ],
    ChatIntent.createFd: [
      'Create an FD of 1 lakh',
      'open a fixed deposit',
      'book fd for 12 months',
      'I want to make a deposit',
    ],
    ChatIntent.needCredit: [
      'Can I pay my electronics supplier this week?',
      "I'm short on cash",
      'need a loan',
      'Can I cover my upcoming payments?',
      'I want an overdraft',
      'cash crunch this month',
    ],
    ChatIntent.payBill: [
      'Pay my house rent',
      'Send money to my landlord',
      'Approve payroll for my 12 employees',
      'transfer 5000',
      'pay electricity bill',
    ],
    ChatIntent.lockCard: [
      'Lock my debit card',
      'Unlock my debit card',
      'I lost my card',
      'block my card',
      'my card was stolen',
    ],
  };

  utterances.forEach((intent, texts) {
    for (final text in texts) {
      test('"$text" → ${intent.name}', () => expect(classify(text), intent));
    }
  });

  test('unrelated or empty text falls back', () {
    expect(classify('asdf qwerty'), ChatIntent.fallback);
    expect(classify('pay'), ChatIntent.fallback);
    expect(classify(''), ChatIntent.fallback);
    expect(classifier.classify('blah').score, 0);
  });

  test('a greeting inside a longer request does not hijack it', () {
    expect(classify("hi, what's my balance"), ChatIntent.checkBalance);
  });

  test('scores add up across matching rules', () {
    final match = classifier.classify(
      IntentClassifier.normalize('create an fd'),
    );
    expect(match.intent, ChatIntent.createFd);
    expect(match.score, 5);
  });

  test('normalize lower-cases, trims and unifies punctuation', () {
    expect(
      IntentClassifier.normalize('  What’s   MY  Balance? '),
      "what's my balance?",
    );
  });

  test('yes and no detection', () {
    for (final yes in [
      'yes',
      'Yes please',
      'ok',
      'okay',
      'confirm',
      'go ahead',
      'y',
      'sure thing',
    ]) {
      expect(
        IntentClassifier.isAffirmative(IntentClassifier.normalize(yes)),
        isTrue,
        reason: yes,
      );
    }
    for (final no in [
      'no',
      'No thanks',
      'cancel',
      'not now',
      'never mind',
      "don't",
    ]) {
      expect(
        IntentClassifier.isNegative(IntentClassifier.normalize(no)),
        isTrue,
        reason: no,
      );
    }
    for (final other in ['nothing else', 'you', 'create an fd', 'yesterday']) {
      final normalized = IntentClassifier.normalize(other);
      expect(
        IntentClassifier.isAffirmative(normalized),
        isFalse,
        reason: other,
      );
      expect(IntentClassifier.isNegative(normalized), isFalse, reason: other);
    }
  });
}
