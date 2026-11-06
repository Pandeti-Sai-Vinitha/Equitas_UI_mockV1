import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mock2/chat/chat_message.dart';
import 'package:mock2/chat/chat_models.dart';
import 'package:mock2/widgets/chat_action_card.dart';
import 'package:mock2/widgets/chat_view.dart';
import 'package:mock2/widgets/transaction_processing_animation.dart';

final _now = DateTime(2026, 11, 1, 10);

ChatMessage _user(String text) =>
    ChatMessage(id: 'u$text', role: ChatRole.user, text: text, createdAt: _now);

ChatMessage _assistant(
  String text, {
  ChatAction? action,
  ChatActionStatus? status,
  List<String> suggestions = const [],
  bool isError = false,
}) {
  return ChatMessage(
    id: 'a$text',
    role: ChatRole.assistant,
    text: text,
    createdAt: _now,
    action: action,
    actionStatus: status,
    suggestions: suggestions,
    isError: isError,
  );
}

const _fdCard = ChatAction(
  type: ChatActionType.openFd,
  title: 'Fixed Deposit',
  confirmLabel: 'Confirm FD',
  params: {},
  details: [
    ChatDetail('Amount', '₹1,50,000'),
    ChatDetail('Maturity amount', '₹1,60,800'),
  ],
);

Future<List<String>> _pump(
  WidgetTester tester,
  ChatState state, {
  Size size = const Size(400, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final sent = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ChatView(state: state, onSend: sent.add),
      ),
    ),
  );
  return sent;
}

void main() {
  testWidgets('renders both sides of the conversation', (tester) async {
    await _pump(
      tester,
      ChatState(
        messages: [
          _assistant('Hi Ananya!'),
          _user("What's my balance?"),
          _assistant('It is ₹1,85,000.'),
        ],
      ),
    );

    expect(find.text('Hi Ananya!'), findsOneWidget);
    expect(find.text("What's my balance?"), findsOneWidget);
    expect(find.text('It is ₹1,85,000.'), findsOneWidget);
    expect(find.byKey(const Key('typing_indicator')), findsNothing);
  });

  testWidgets('shows the typing indicator while the assistant is busy', (
    tester,
  ) async {
    await _pump(tester, ChatState(messages: [_user('hi')], isTyping: true));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('typing_indicator')), findsOneWidget);
    final send = tester.widget<IconButton>(find.byKey(const Key('chat_send')));
    expect(send.onPressed, isNull);
  });

  testWidgets('keeps processing animation out of the chat list', (
    tester,
  ) async {
    await _pump(
      tester,
      ChatState(
        messages: [_user('Yes, go ahead')],
        isTyping: true,
        isProcessingTransaction: true,
      ),
    );

    expect(find.byKey(const Key('typing_indicator')), findsOneWidget);
    expect(find.byType(TransactionProcessingAnimation), findsNothing);
  });

  testWidgets('shows card-specific processing in a blurred overlay', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: const [
              TransactionProcessingOverlay(actionType: ChatActionType.lockCard),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Securing your debit card'), findsOneWidget);
    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);
    final animationCenter = tester.getCenter(
      find.byType(TransactionProcessingAnimation),
    );
    expect(animationCenter.dx, closeTo(200, 1));
    expect(animationCenter.dy, closeTo(400, 1));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: const [
              TransactionProcessingOverlay(
                actionType: ChatActionType.updateDebitLimit,
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Updating your debit card limit'), findsOneWidget);
    expect(find.byIcon(Icons.trending_up_rounded), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: const [
              TransactionProcessingOverlay(actionType: ChatActionType.payBill),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Processing your transaction'), findsOneWidget);
  });

  testWidgets('voice input opens over the current chat screen', (tester) async {
    await _pump(tester, ChatState(messages: []));
    await tester.tap(find.byKey(const Key('chat_send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const ValueKey('voice-prompt-screen')), findsOneWidget);
    expect(find.text('Your words will appear in the message box'), findsNothing);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-wave')), findsOneWidget);
    expect(find.byKey(const Key('chat_input')), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-listen-toggle')), findsNothing);
    expect(find.byKey(const ValueKey('voice-send-query')), findsNothing);
    expect(
      tester.getRect(find.byType(BackdropFilter)).bottom,
      lessThan(tester.getRect(find.byKey(const Key('chat_input'))).top),
    );
    expect(find.text('Speak your query'), findsNothing);
    expect(find.text('Your words will appear here'), findsNothing);
    expect(find.text('Send query'), findsNothing);
    expect(find.text('Voice input is coming soon.'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('close-voice-prompt')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('voice-prompt-screen')), findsNothing);
  });

  group('quick-reply chips', () {
    testWidgets(
      'appear under the latest assistant message and send their text',
      (tester) async {
        final sent = await _pump(
          tester,
          ChatState(
            messages: [
              _assistant(
                'Hello',
                suggestions: ["What's my balance?", 'Where is my money going?'],
              ),
            ],
          ),
        );

        expect(find.byType(ActionChip), findsAtLeastNWidgets(1));
        await tester.tap(find.text("What's my balance?"));
        expect(sent, ["What's my balance?"]);
      },
    );

    testWidgets('are hidden after the customer replies and while typing', (
      tester,
    ) async {
      await _pump(
        tester,
        ChatState(
          messages: [
            _assistant('Hello', suggestions: const ['A']),
            _user('hi'),
          ],
        ),
      );
      expect(find.byType(ActionChip), findsNothing);

      await _pump(
        tester,
        ChatState(
          messages: [
            _assistant('Hello', suggestions: const ['A']),
          ],
          isTyping: true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(ActionChip), findsNothing);
    });
  });

  group('input', () {
    testWidgets(
      'scrolls the conversation to the latest message on keyboard open',
      (tester) async {
        final messages = [
          for (var index = 0; index < 30; index++) _user('Message $index'),
        ];
        await _pump(tester, ChatState(messages: messages));

        final scrollableFinder = find.descendant(
          of: find.byKey(const Key('chat_list')),
          matching: find.byType(Scrollable),
        );
        final position = tester
            .state<ScrollableState>(scrollableFinder)
            .position;
        position.jumpTo(0);
        await tester.pump();

        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        tester.binding.handleMetricsChanged();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(position.pixels, position.maxScrollExtent);
        expect(find.text('Message 29'), findsOneWidget);
      },
    );

    testWidgets('sends typed text from the button and clears the box', (
      tester,
    ) async {
      final sent = await _pump(tester, const ChatState());

      await tester.enterText(
        find.byKey(const Key('chat_input')),
        '  Create an FD  ',
      );
      await tester.tap(find.byKey(const Key('chat_send')));
      await tester.pump();

      expect(sent, ['Create an FD']);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('chat_input')))
            .controller!
            .text,
        isEmpty,
      );
    });

    testWidgets('sends on the keyboard send action', (tester) async {
      final sent = await _pump(tester, const ChatState());

      await tester.enterText(find.byKey(const Key('chat_input')), 'hello');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();

      expect(sent, ['hello']);
    });

    testWidgets(
      'ignores blank input and anything typed while the assistant is busy',
      (tester) async {
        var sent = await _pump(tester, const ChatState());
        await tester.enterText(find.byKey(const Key('chat_input')), '   ');
        await tester.tap(find.byKey(const Key('chat_send')));
        await tester.pump();
        expect(sent, isEmpty);

        sent = await _pump(tester, const ChatState(isTyping: true));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.enterText(find.byKey(const Key('chat_input')), 'hello');
        await tester.testTextInput.receiveAction(TextInputAction.send);
        await tester.pump();
        expect(sent, isEmpty);
      },
    );
  });

  group('confirmation card', () {
    testWidgets('shows the details and sends yes or no', (tester) async {
      final sent = await _pump(
        tester,
        ChatState(
          messages: [
            _assistant(
              "Here's your fixed deposit.",
              action: _fdCard,
              status: ChatActionStatus.proposed,
            ),
          ],
        ),
      );

      expect(find.text('Fixed Deposit'), findsOneWidget);
      expect(find.text('Maturity amount'), findsOneWidget);
      expect(find.text('₹1,60,800'), findsOneWidget);
      expect(find.text('Awaiting you'), findsOneWidget);

      await tester.tap(find.byKey(const Key('card_confirm')));
      await tester.tap(find.byKey(const Key('card_cancel')));
      expect(sent, [kConfirmText, kCancelText]);
    });

    testWidgets('hides the action buttons while the assistant is busy', (
      tester,
    ) async {
      await _pump(
        tester,
        ChatState(
          messages: [
            _assistant(
              'Card',
              action: _fdCard,
              status: ChatActionStatus.proposed,
            ),
          ],
          isTyping: true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('card_confirm')), findsNothing);
      expect(find.byKey(const Key('card_cancel')), findsNothing);
    });

    for (final (status, badge) in [
      (ChatActionStatus.running, 'Working…'),
      (ChatActionStatus.done, 'Done'),
      (ChatActionStatus.failed, 'Failed'),
      (ChatActionStatus.cancelled, 'Cancelled'),
    ]) {
      testWidgets('a $badge card has no buttons left', (tester) async {
        await _pump(
          tester,
          ChatState(
            messages: [_assistant('Card', action: _fdCard, status: status)],
          ),
        );

        expect(find.text(badge), findsOneWidget);
        expect(find.byKey(const Key('card_confirm')), findsNothing);
        expect(find.byKey(const Key('card_cancel')), findsNothing);
      });
    }

    for (final type in ChatActionType.values) {
      testWidgets('${type.name} card renders', (tester) async {
        final action = ChatAction(
          type: type,
          title: 'Card ${type.name}',
          confirmLabel: 'Go',
          params: const {},
          details: const [ChatDetail('Label', 'Value')],
        );
        await _pump(
          tester,
          ChatState(
            messages: [
              _assistant(
                'x',
                action: action,
                status: ChatActionStatus.proposed,
              ),
            ],
          ),
        );

        expect(find.byType(ChatActionCard), findsOneWidget);
        expect(find.text('Card ${type.name}'), findsOneWidget);
        expect(find.text('Go'), findsOneWidget);
      });
    }
  });

  testWidgets('error messages are rendered', (tester) async {
    await _pump(
      tester,
      ChatState(
        messages: [
          _assistant(
            'Sorry, that did not work',
            isError: true,
            suggestions: const ['Try again'],
          ),
        ],
      ),
    );
    expect(find.text('Sorry, that did not work'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('keeps the latest message in view as the conversation grows', (
    tester,
  ) async {
    final messages = [for (var i = 0; i < 30; i++) _assistant('Message $i')];
    await _pump(
      tester,
      ChatState(messages: messages),
      size: const Size(400, 500),
    );
    expect(find.text('Message 29'), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatView(
            state: ChatState(
              messages: [...messages, _assistant('Newest message')],
            ),
            onSend: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Newest message'), findsOneWidget);
  });
}
