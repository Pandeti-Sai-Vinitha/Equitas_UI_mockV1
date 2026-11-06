import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mock2/chat/chat_message.dart';
import 'package:mock2/chat/chat_models.dart';
import 'package:mock2/core/demo_config.dart';
import 'package:mock2/state/booking_notifier.dart';
import 'package:mock2/state/chat_notifier.dart';
import 'package:mock2/state/demo_reset.dart';
import 'package:mock2/state/persona_notifier.dart';
import 'package:mock2/state/providers.dart';
import 'package:mock2/widgets/chat_view.dart';

import '../helpers/test_hive.dart';

const ananya = 'p_salaried_01';
const rajesh = 'p_biz_02';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late ProviderContainer container;

  setUp(() async {
    directory = await openTestHive();
    await seedTestData();
    container = createContainer();
    await waitUntil(() => !container.read(personaProvider).isLoading);
  });

  tearDown(() async {
    container.dispose();
    await closeTestHive(directory);
  });

  Future<ChatNotifier> open(String personaId) async {
    final notifier = container.read(chatProvider(personaId).notifier);
    await notifier.ready;
    return notifier;
  }

  ChatState chatOf(String personaId) => container.read(chatProvider(personaId));

  List<ChatMessage> userMessages(String personaId) =>
      chatOf(personaId).messages.where((message) => message.isUser).toList();

  Future<void> settlePersona() =>
      waitUntil(() => !container.read(personaProvider).isLoading);

  group('opening the conversation', () {
    test(
      'the assistant greets first, with no customer bubble for the greeting',
      () async {
        await open(ananya);

        final chat = chatOf(ananya);
        expect(chat.messages, hasLength(1));
        expect(chat.messages.single.role, ChatRole.assistant);
        expect(
          chat.messages.single.text,
          allOf(contains('Ananya'), contains('₹2,20,000')),
        );
        expect(
          chat.messages.single.suggestions,
          contains('I have some extra money this month'),
        );
        expect(chat.isTyping, isFalse);
        expect(chat.pending, isNull);
      },
    );

    test(
      'is saved, and reopening restores it without greeting again',
      () async {
        final notifier = await open(ananya);
        await notifier.send("What's my balance?");
        expect(chatOf(ananya).messages, hasLength(3));
        await waitUntil(
          () => (storage.getChat(ananya)?['messages'] as List?)?.length == 3,
        );

        container.dispose();
        container = createContainer();
        await waitUntil(() => !container.read(personaProvider).isLoading);
        await open(ananya);

        final restored = chatOf(ananya);
        expect(restored.messages, hasLength(3));
        expect(restored.messages[1].text, "What's my balance?");
        expect(restored.messages[1].isUser, isTrue);
      },
    );

    test('each persona has their own conversation', () async {
      await (await open(ananya)).send("What's my balance?");
      await open(rajesh);

      expect(chatOf(rajesh).messages, hasLength(1));
      expect(
        chatOf(rajesh).messages.single.text,
        allOf(contains('Rajesh'), contains('₹65,000')),
      );
      expect(chatOf(ananya).messages, hasLength(3));
    });

    test('a message sent while the greeting is loading waits for it', () async {
      final notifier = container.read(chatProvider(ananya).notifier);
      await notifier.send("What's my balance?");

      final messages = chatOf(ananya).messages;
      expect(messages.map((message) => message.role), [
        ChatRole.assistant,
        ChatRole.user,
        ChatRole.assistant,
      ]);
    });
  });

  group('sending', () {
    test('ignores blank messages and double sends', () async {
      final notifier = await open(ananya);
      await notifier.send('   ');
      expect(chatOf(ananya).messages, hasLength(1));

      await Future.wait([
        notifier.send("What's my balance?"),
        notifier.send("What's my balance?"),
      ]);
      expect(userMessages(ananya), hasLength(1));
    });

    test('shows the assistant as typing until the reply arrives', () async {
      final notifier = await open(ananya);
      final seen = <bool>[];
      container.listen(
        chatProvider(ananya),
        (_, next) => seen.add(next.isTyping),
      );

      await notifier.send("What's my balance?");

      expect(seen.first, isTrue);
      expect(seen.last, isFalse);
    });

    test(
      'keeps the thinking indicator visible for the configured duration',
      () async {
        container.dispose();
        container = ProviderContainer(
          overrides: [
            chatThinkingDurationProvider.overrideWithValue(
              const Duration(milliseconds: 100),
            ),
          ],
        );
        await settlePersona();
        final notifier = await open(ananya);
        final response = notifier.send("What's my balance?");

        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(chatOf(ananya).isTyping, isTrue);

        await response;
        expect(chatOf(ananya).isTyping, isFalse);
      },
    );

    test(
      'a network error becomes a retryable error bubble and keeps the customer bubble',
      () async {
        final notifier = await open(ananya);
        await container
            .read(demoSettingsProvider.notifier)
            .setSimulateFailure(true);

        await notifier.send('Where is my money going?');

        var chat = chatOf(ananya);
        expect(chat.isTyping, isFalse);
        expect(chat.messages.last.isError, isTrue);
        expect(chat.messages.last.text, contains('could not reach the bank'));
        expect(chat.messages.last.suggestions, [ChatNotifier.retryText]);
        expect(userMessages(ananya).single.text, 'Where is my money going?');

        await container
            .read(demoSettingsProvider.notifier)
            .setSimulateFailure(false);
        await notifier.send(ChatNotifier.retryText);

        chat = chatOf(ananya);
        expect(userMessages(ananya).map((message) => message.text), [
          'Where is my money going?',
          'Where is my money going?',
        ]);
        expect(chat.messages.last.isError, isFalse);
        expect(chat.messages.last.text, contains('Rent'));
      },
    );

    test('a failed greeting can be retried', () async {
      await container
          .read(demoSettingsProvider.notifier)
          .setSimulateFailure(true);
      final notifier = await open(ananya);
      expect(chatOf(ananya).messages.single.isError, isTrue);

      await container
          .read(demoSettingsProvider.notifier)
          .setSimulateFailure(false);
      await notifier.send(ChatNotifier.retryText);

      expect(chatOf(ananya).messages, hasLength(1));
      expect(chatOf(ananya).messages.single.text, contains('Hi Ananya'));
    });
  });

  group('Ananya: recommend → create FD → confirm', () {
    test('a confirmation without the correct MPIN cannot execute', () async {
      final notifier = await open(ananya);
      await notifier.send('Create an FD of 1 lakh for 12 months');

      await notifier.send(kConfirmText);

      final chat = chatOf(ananya);
      expect(chat.pending, isNull);
      expect(
        chat.messages
            .firstWhere((message) => message.action != null)
            .actionStatus,
        ChatActionStatus.failed,
      );
      expect(
        chat.messages.last.text,
        contains("MPIN verification failed, so I've cancelled that"),
      );
      expect(chat.messages.last.isError, isFalse);
      expect(chat.messages.last.suggestions, isNotEmpty);
      expect(chat.messages.last.suggestions, contains("What's my balance?"));
      expect(storage.getAllFDBookings(), isEmpty);
      expect(
        container
            .read(personaProvider)
            .selectedPersona
            .financialSummary
            .currentBalance,
        185000,
      );
    });

    test(
      'books the FD through the same route as the home screen and updates the account',
      () async {
        final notifier = await open(ananya);
        await notifier.send('I have some extra money this month');
        final chip = chatOf(ananya).messages.last.suggestions.first;
        expect(chip, 'Create an FD of ₹1,50,000 for 12 months');

        await notifier.send(chip);
        final card = chatOf(ananya).messages.last;
        expect(card.action!.type, ChatActionType.openFd);
        expect(card.actionStatus, ChatActionStatus.proposed);
        expect(chatOf(ananya).pending!.awaiting, ChatAwaiting.confirm);

        await notifier.send(kConfirmText, mpin: demoMpin);

        final chat = chatOf(ananya);
        expect(chat.isTyping, isFalse);
        expect(chat.pending, isNull);
        expect(
          chat.messages.firstWhere((m) => m.action != null).actionStatus,
          ChatActionStatus.done,
        );
        expect(
          chat.messages.last.text,
          allOf(
            contains('Done!'),
            contains('₹1,50,000'),
            contains('matures on'),
            contains('₹1,60,800'),
          ),
        );
        expect(chat.messages.last.suggestions, contains("What's my balance?"));

        expect(container.read(fdBookingProvider).bookings, hasLength(1));
        expect(storage.getAllFDBookings().single['depositAmount'], 150000);
        await settlePersona();
        expect(
          container
              .read(personaProvider)
              .selectedPersona
              .financialSummary
              .currentBalance,
          35000,
        );

        await notifier.send("What's my balance?");
        expect(chatOf(ananya).messages.last.text, contains('₹35,000'));
      },
    );

    test('collects the missing details turn by turn', () async {
      final notifier = await open(ananya);
      await notifier.send('Create an FD of 1 lakh');
      expect(chatOf(ananya).messages.last.text, contains('For how long?'));
      expect(chatOf(ananya).messages.last.suggestions, [
        '6 months',
        '12 months',
        '24 months',
      ]);

      await notifier.send('12 months');
      expect(
        chatOf(ananya).messages.last.action!.params['depositAmount'],
        100000,
      );
    });

    test('declining cancels the card and books nothing', () async {
      final notifier = await open(ananya);
      await notifier.send('Create an FD of 1 lakh for 12 months');
      await notifier.send(kCancelText);

      final chat = chatOf(ananya);
      expect(
        chat.messages.firstWhere((m) => m.action != null).actionStatus,
        ChatActionStatus.cancelled,
      );
      expect(chat.messages.last.text, contains('cancelled'));
      expect(chat.pending, isNull);
      expect(storage.getAllFDBookings(), isEmpty);
    });

    test('a changed proposal replaces the old card', () async {
      final notifier = await open(ananya);
      await notifier.send('Create an FD of 1 lakh for 12 months');
      await notifier.send('make it 24 months');

      final cards = chatOf(
        ananya,
      ).messages.where((m) => m.action != null).toList();
      expect(cards.map((m) => m.actionStatus), [
        ChatActionStatus.cancelled,
        ChatActionStatus.proposed,
      ]);
      expect(cards.last.action!.params['tenorMonths'], 24);
    });

    test('asking something else leaves the old card cancelled', () async {
      final notifier = await open(ananya);
      await notifier.send('Create an FD of 1 lakh for 12 months');
      await notifier.send("What's my balance?");

      expect(
        chatOf(
          ananya,
        ).messages.firstWhere((m) => m.action != null).actionStatus,
        ChatActionStatus.cancelled,
      );
      expect(chatOf(ananya).pending, isNull);
    });

    test(
      'a task the bank refuses marks the card failed and explains why',
      () async {
        final notifier = await open(ananya);
        await notifier.send('Create an FD of 1.5 lakh for 12 months');

        // The balance drops before the customer confirms.
        await container
            .read(bankingRepositoryProvider)
            .makePayment(
              personaId: ananya,
              payee: 'Someone',
              amount: 100000,
              category: 'OTHERS',
            );
        await notifier.send(kConfirmText, mpin: demoMpin);

        final chat = chatOf(ananya);
        expect(chat.isTyping, isFalse);
        expect(
          chat.messages.firstWhere((m) => m.action != null).actionStatus,
          ChatActionStatus.failed,
        );
        expect(chat.messages.last.isError, isTrue);
        expect(chat.messages.last.text, contains('Insufficient balance'));
        expect(storage.getAllFDBookings(), isEmpty);
      },
    );
  });

  group('Rajesh: shortfall → overdraft → payroll', () {
    test(
      'activates the overdraft, then pays payroll by drawing on it',
      () async {
        await container.read(personaProvider.notifier).selectPersona(rajesh);
        final notifier = await open(rajesh);

        await notifier.send('Can I pay my electronics supplier this week?');
        expect(
          chatOf(rajesh).messages.last.action!.type,
          ChatActionType.activateCredit,
        );
        await notifier.send(kConfirmText, mpin: demoMpin);

        expect(
          chatOf(rajesh).messages.last.text,
          allOf(
            contains('overdraft line of ₹80,000 is active'),
            contains('11.5%'),
          ),
        );
        await settlePersona();
        expect(
          container.read(personaProvider).selectedPersona.availableCredit,
          80000,
        );
        expect(await container.read(recommendationsProvider.future), isEmpty);

        await notifier.send('Approve payroll for my 12 employees');
        final card = chatOf(rajesh).messages.last;
        expect(card.action!.type, ChatActionType.payBill);
        expect(card.action!.params['amount'], 54000);

        await notifier.send(kConfirmText, mpin: demoMpin);
        expect(
          chatOf(rajesh).messages.last.text,
          allOf(
            contains('Paid ₹54,000'),
            contains('balance is now -₹9,000'),
            contains('drawn from your overdraft'),
          ),
        );
        await settlePersona();
        expect(
          container
              .read(personaProvider)
              .selectedPersona
              .financialSummary
              .currentBalance,
          -9000,
        );
        expect(
          container
              .read(personaProvider)
              .selectedPersona
              .recentTransactions
              .first
              .category,
          'PAYROLL',
        );
      },
    );
  });

  group('card and reset', () {
    test('locks the card on confirmation', () async {
      final notifier = await open(ananya);
      await notifier.send('Lock my debit card');
      await notifier.send(kConfirmText, mpin: demoMpin);

      expect(
        chatOf(ananya).messages.last.text,
        contains('Your card is locked'),
      );
      await settlePersona();
      expect(
        container.read(personaProvider).selectedPersona.cardLocked,
        isTrue,
      );

      await notifier.send('lock my card');
      expect(chatOf(ananya).messages.last.text, contains('currently locked'));
      expect(
        chatOf(ananya).messages.last.action?.type,
        ChatActionType.unlockCard,
      );
      await notifier.send(kConfirmText, mpin: demoMpin);
      expect(
        chatOf(ananya).messages.last.text,
        contains('Your card has been unlocked'),
      );
      await settlePersona();
      expect(
        container.read(personaProvider).selectedPersona.cardLocked,
        isFalse,
      );
    });

    test('a demo reset clears the conversations and the account', () async {
      final notifier = await open(ananya);
      await notifier.send('Lock my debit card');
      await notifier.send(kConfirmText, mpin: demoMpin);
      await settlePersona();
      await waitUntil(() => storage.getChat(ananya) != null);

      await container.read(demoResetProvider)();
      await settlePersona();

      expect(storage.getChat(ananya), isNull);
      await open(ananya);
      expect(chatOf(ananya).messages, hasLength(1));
      expect(chatOf(ananya).messages.single.text, contains('Hi Ananya'));
      expect(
        container.read(personaProvider).selectedPersona.cardLocked,
        isFalse,
      );
    });
  });

  group('ChatMessage', () {
    test('round-trips through JSON including its card and status', () async {
      final notifier = await open(ananya);
      await notifier.send('Create an FD of 1 lakh for 12 months');

      for (final message in chatOf(ananya).messages) {
        final parsed = ChatMessage.fromJson(message.toJson());
        expect(parsed.id, message.id);
        expect(parsed.role, message.role);
        expect(parsed.text, message.text);
        expect(parsed.createdAt, message.createdAt);
        expect(parsed.actionStatus, message.actionStatus);
        expect(parsed.action?.toJson(), message.action?.toJson());
        expect(parsed.suggestions, message.suggestions);
        expect(parsed.isError, message.isError);
      }
    });

    test(
      'a pending card survives a restart so it can still be answered',
      () async {
        final notifier = await open(ananya);
        await notifier.send('Create an FD of 1 lakh for 12 months');
        await waitUntil(() => storage.getChat(ananya)?['pending'] != null);

        container.dispose();
        container = createContainer();
        await waitUntil(() => !container.read(personaProvider).isLoading);
        final restored = await open(ananya);
        expect(chatOf(ananya).pending!.awaiting, ChatAwaiting.confirm);

        await restored.send(kConfirmText, mpin: demoMpin);
        expect(chatOf(ananya).messages.last.text, contains('Done!'));
      },
    );
  });
}
