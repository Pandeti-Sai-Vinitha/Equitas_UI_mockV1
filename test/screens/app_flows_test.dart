import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mock2/core/demo_config.dart';
import 'package:mock2/domain/demo_settings.dart';
import 'package:mock2/state/persona_notifier.dart';
import 'package:mock2/state/providers.dart';

import '../helpers/widget_harness.dart';

/// Drives the menuless salaried demo: home → single-query response → history.
void main() {
  late TestApp app;

  setUp(() => app = TestApp());

  List<String> captureTransactionSounds() {
    const channel = MethodChannel('com.example.mock2/transaction_sound');
    final calls = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    return calls;
  }

  Future<void> shootQuery(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('ask_ai')), text);
    await tester.tap(find.byKey(const Key('ask_ai_send')));
    await settle(tester, frames: 80);
  }

  Future<void> closeQuery(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('home-profile-avatar')));
    await settle(tester);
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await settle(tester, frames: 80);
  }

  Future<void> enterMpin(WidgetTester tester, String mpin) async {
    await tester.enterText(find.byKey(const Key('mpin_input')), mpin);
    await tester.pump();
  }

  Future<void> confirmWithMpin(
    WidgetTester tester, {
    String mpin = demoMpin,
  }) async {
    await tester.drag(
      find.byKey(const Key('chat_list')),
      const Offset(0, -300),
    );
    await settle(tester);
    await tapAndSettle(tester, find.byKey(const Key('card_confirm')));
    await enterMpin(tester, mpin);
    await tapAndSettle(tester, find.byKey(const Key('mpin_verify')));
    await settle(tester, frames: 60);
  }

  Future<void> setFailure(WidgetTester tester, {required bool on}) async {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).first),
    );
    await container.read(demoSettingsProvider.notifier).setSimulateFailure(on);
  }

  group('home screen', () {
    testWidgets('boots straight into the salaried home canvas', (tester) async {
      await app.launch(tester);

      expect(find.byKey(const Key('login_email')), findsNothing);
      expect(find.textContaining('Ananya'), findsWidgets);
      expect(find.text('PAYCHECK CLEARED'), findsNothing);
      expect(find.byKey(const Key('home-account-summary')), findsOneWidget);
      expect(find.text('CURRENT BALANCE'), findsOneWidget);
      expect(find.text('₹1,85,000'), findsOneWidget);
      expect(find.byKey(const Key('home-financial-metrics')), findsOneWidget);
      expect(find.text('30-DAY INFLOW'), findsOneWidget);
      expect(find.text('30-DAY OUTFLOW'), findsOneWidget);
      expect(find.text('SAFETY BUFFER'), findsOneWidget);
      expect(find.text('₹1,20,000'), findsOneWidget);
      expect(find.text('₹65,000'), findsOneWidget);
      expect(find.text('₹20,000'), findsOneWidget);
      final summary = tester.getRect(
        find.byKey(const Key('home-account-summary')),
      );
      expect(summary.width, 132);
      expect(
        summary.right,
        closeTo(
          tester.view.physicalSize.width / tester.view.devicePixelRatio - 27,
          1,
        ),
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('home-account-summary-value')))
            .style
            ?.color,
        Colors.white,
      );
      expect(find.byKey(const Key('ask_ai')), findsOneWidget);
      expect(find.byKey(const ValueKey('ambient-orb')), findsNothing);
      expect(find.byKey(const ValueKey('mountain-backdrop')), findsOneWidget);
      expect(app.storage.getSelectedPersonaId(), 'p_salaried_01');
      expect(find.byKey(const ValueKey('home-greeting')), findsOneWidget);
      expect(
        tester.getRect(find.byKey(const ValueKey('home-greeting'))).top,
        greaterThan(
          tester.view.physicalSize.height / tester.view.devicePixelRatio * 0.22,
        ),
      );
      final greetingText = tester.widget<Text>(
        find
            .descendant(
              of: find.byKey(const ValueKey('home-greeting')),
              matching: find.byType(Text),
            )
            .first,
      );
      expect(greetingText.data, contains('Ananya!'));
      expect(greetingText.maxLines, 2);
      expect(find.byKey(const Key('home-suggested-actions')), findsOneWidget);
      expect(find.text('PREDICTED MICRO-ACTIONS'), findsOneWidget);
      expect(
        find.byKey(const Key('micro_action_Pay my house rent')),
        findsOneWidget,
      );
      expect(find.text('Pay House Rent'), findsOneWidget);
      expect(find.text('Lock Card'), findsOneWidget);
      expect(find.text('Pay EB Bill'), findsOneWidget);
      final actionRows = [
        tester.getRect(find.byKey(const Key('micro_action_Pay my house rent'))),
        tester.getRect(
          find.byKey(const Key('micro_action_Lock my debit card')),
        ),
        tester.getRect(
          find.byKey(const Key('micro_action_Pay my electricity bill')),
        ),
      ];
      expect(actionRows.map((rect) => rect.center.dy).toSet().length, 1);
      final metrics = tester.getRect(
        find.byKey(const Key('home-financial-metrics')),
      );
      expect(metrics.left, closeTo(27, 1));
      expect(
        metrics.right,
        closeTo(
          tester.view.physicalSize.width / tester.view.devicePixelRatio - 27,
          1,
        ),
      );
      expect(
        metrics.top,
        greaterThan(
          tester
              .getRect(find.byKey(const Key('recommendation-text-section')))
              .bottom,
        ),
      );
      expect(
        metrics.bottom,
        lessThan(
          tester.getRect(find.byKey(const Key('home-suggested-actions'))).top,
        ),
      );
      expect(
        actionRows.first.top,
        greaterThanOrEqualTo(
          tester
                  .getRect(find.byKey(const Key('recommendation-text-section')))
                  .bottom +
              12,
        ),
      );
      expect(find.byIcon(Icons.north_east_rounded), findsOneWidget);
      expect(
        tester
            .getRect(find.byKey(const Key('home-suggested-actions')))
            .center
            .dx,
        closeTo(
          tester.view.physicalSize.width / tester.view.devicePixelRatio / 2,
          1,
        ),
      );
      await tester.pump(const Duration(seconds: 10));
      expect(find.text('CURRENT BALANCE'), findsOneWidget);
      expect(find.text('30-DAY INFLOW'), findsOneWidget);
      expect(find.text('30-DAY OUTFLOW'), findsOneWidget);
      expect(find.text('SAFETY BUFFER'), findsOneWidget);
      expect(find.text('₹1,85,000'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('home-account-summary-value')))
            .style
            ?.color,
        Colors.white,
      );
    });

    testWidgets('shows typing dots instead of an orb while a query loads', (
      tester,
    ) async {
      await app.launch(tester);
      final homeMountainRect = tester.getRect(
        find.byKey(const ValueKey('mountain-backdrop')),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold).first),
      );
      await container.read(demoSettingsProvider.notifier).setLatency(5000);

      await tester.enterText(
        find.byKey(const Key('ask_ai')),
        "What's my balance?",
      );
      await tester.tap(find.byKey(const Key('ask_ai_send')));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const ValueKey('response-thinking')), findsOneWidget);
      expect(find.byKey(const Key('typing_indicator')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-profile-avatar')), findsOneWidget);
      expect(find.byKey(const Key('home-account-summary')), findsNothing);
      expect(
        find.byKey(const Key('recommendation-text-section')),
        findsNothing,
      );
      expect(find.byKey(const Key('home-financial-metrics')), findsNothing);
      expect(find.byKey(const Key('home-suggested-actions')), findsNothing);
      expect(find.byKey(const Key('chat_cancel')), findsNothing);
      expect(find.byKey(const ValueKey('mountain-backdrop')), findsOneWidget);
      expect(
        tester.getRect(find.byKey(const ValueKey('mountain-backdrop'))),
        homeMountainRect,
      );
      expect(find.byKey(const ValueKey('thinking-orb')), findsNothing);
      final queryRect = tester.getRect(
        find.byKey(const ValueKey('submitted-query')),
      );
      final typingRect = tester.getRect(
        find.byKey(const Key('typing_indicator')),
      );
      expect(typingRect.top, greaterThanOrEqualTo(queryRect.bottom));
      expect(typingRect.top, closeTo(queryRect.bottom + 32, 1));
      expect(typingRect.left, closeTo(queryRect.left, 1));
      await tester.pump(const Duration(seconds: 7));
      await settle(tester);
    });

    testWidgets('swiping right from a query response returns to home', (
      tester,
    ) async {
      await app.launch(tester);
      await shootQuery(tester, "What's my balance?");

      expect(find.byKey(const ValueKey('submitted-query')), findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('query-swipe-to-home')),
        const Offset(280, 0),
      );
      await settle(tester);

      expect(find.byKey(const ValueKey('submitted-query')), findsNothing);
      expect(find.byKey(const Key('chat_cancel')), findsNothing);
      expect(find.byKey(const Key('home-suggested-actions')), findsOneWidget);
    });

    testWidgets('voice input opens over the current home screen', (
      tester,
    ) async {
      await app.launch(tester);
      expect(
        tester.widget<IconButton>(find.byKey(const Key('ask_ai_send'))).icon,
        isA<Icon>().having((icon) => icon.icon, 'icon', Icons.mic_none_rounded),
      );
      await tester.tap(find.byKey(const Key('ask_ai_send')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const ValueKey('voice-prompt-screen')), findsOneWidget);
      expect(find.text('Your words will appear in the message box'), findsNothing);
      expect(find.byKey(const ValueKey('home-profile-avatar')), findsOneWidget);
      expect(find.byKey(const Key('ask_ai')), findsOneWidget);
      expect(find.byKey(const ValueKey('voice-listen-toggle')), findsNothing);
      expect(find.byKey(const ValueKey('voice-send-query')), findsNothing);
      expect(
        tester.getRect(find.byType(BackdropFilter)).bottom,
        lessThan(tester.getRect(find.byKey(const Key('ask_ai'))).top),
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('voice-prompt-screen'))).top,
        closeTo(0, 1),
      );
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(find.byKey(const ValueKey('voice-wave')), findsOneWidget);
      expect(find.text('Speak your query'), findsNothing);
      expect(find.text('Your words will appear here'), findsNothing);
      expect(find.text('Send query'), findsNothing);
      expect(find.text('Voice input is coming soon.'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('close-voice-prompt')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('voice-prompt-screen')), findsNothing);
    });

    testWidgets('typed composer query shows send icon instead of microphone', (
      tester,
    ) async {
      await app.launch(tester);
      await tester.enterText(find.byKey(const Key('ask_ai')), 'Check balance');
      await tester.pump();

      final sendButton = tester.widget<IconButton>(
        find.byKey(const Key('ask_ai_send')),
      );
      expect(
        sendButton.icon,
        isA<Icon>().having(
          (icon) => icon.icon,
          'icon',
          Icons.arrow_forward_rounded,
        ),
      );
    });

    testWidgets('reveals an answer word by word after loading', (tester) async {
      await app.launch(tester);
      await tester.enterText(
        find.byKey(const Key('ask_ai')),
        "What's my balance?",
      );
      await tester.tap(find.byKey(const Key('ask_ai_send')));
      await settle(tester, frames: 10);
      expect(find.byKey(const ValueKey('response-thinking')), findsOneWidget);
      await settle(tester, frames: 24);

      expect(find.textContaining('Your balance is'), findsOneWidget);
      expect(find.textContaining('After keeping your'), findsNothing);

      await settle(tester, frames: 60);
      expect(
        find.textContaining(
          'Your balance is ₹1,85,000. Over the next 30 days you expect',
        ),
        findsOneWidget,
      );
    });

    testWidgets('home chat opens only after a non-empty message is sent', (
      tester,
    ) async {
      await app.launch(tester);

      expect(find.byKey(const Key('home-suggested-actions')), findsOneWidget);
      expect(
        find.byKey(const Key('micro_action_Pay my house rent')),
        findsOneWidget,
      );
      expect(
        tester
            .getRect(find.byKey(const Key('micro_action_Pay my house rent')))
            .top,
        tester
            .getRect(find.byKey(const Key('micro_action_Lock my debit card')))
            .top,
      );
      expect(
        tester
            .getRect(find.byKey(const Key('micro_action_Lock my debit card')))
            .top,
        tester
            .getRect(
              find.byKey(const Key('micro_action_Pay my electricity bill')),
            )
            .top,
      );

      await tester.tap(find.byKey(const Key('ask_ai')));
      await tester.pump();
      expect(find.byKey(const ValueKey('submitted-query')), findsNothing);

      await tester.enterText(find.byKey(const Key('ask_ai')), '   ');
      await tester.tap(find.byKey(const Key('ask_ai_send')));
      await settle(tester);
      expect(find.byKey(const ValueKey('submitted-query')), findsNothing);

      await shootQuery(tester, "What's my balance?");

      expect(find.byKey(const ValueKey('submitted-query')), findsOneWidget);
      expect(find.text("What's my balance?"), findsWidgets);
      expect(find.textContaining('Your balance is ₹1,85,000'), findsOneWidget);

      await closeQuery(tester);
      expect(find.byKey(const ValueKey('home-greeting')), findsOneWidget);
    });

    testWidgets('salaried persona: reviews and confirms the recommended FD', (
      tester,
    ) async {
      await app.launch(tester);

      expect(find.textContaining('Ananya'), findsWidgets);
      expect(find.text('PAYCHECK CLEARED'), findsNothing);
      expect(
        find.textContaining(
          'You have ₹2,20,000 idle balance available for deployment over the next 30 days, so consider ₹1,50,000 in High-Yield Fixed Deposit for 12 months at 7.2% p.a.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Review FD of'), findsNothing);
      expect(
        find.byKey(const Key('recommendation-text-section')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('recommendation-arrow')), findsOneWidget);
      expect(find.byKey(const Key('home-suggested-actions')), findsOneWidget);
      expect(find.text('Pay House Rent'), findsOneWidget);
      expect(find.text('Lock Card'), findsOneWidget);
      expect(find.text('Pay EB Bill'), findsOneWidget);
      expect(find.text('SAVED FD BOOKINGS'), findsNothing);
      expect(find.byKey(const Key('home-account-summary')), findsOneWidget);

      await tapAndSettle(
        tester,
        find.byKey(const Key('recommendation-action')),
      );

      expect(find.byKey(const ValueKey('submitted-query')), findsOneWidget);
      expect(find.text('Awaiting you'), findsOneWidget);
      expect(find.text('₹1,50,000'), findsOneWidget);
      expect(app.storage.getAllFDBookings(), isEmpty);

      await confirmWithMpin(tester);
      expect(find.textContaining('Done! Your fixed deposit'), findsOneWidget);
      expect(app.storage.getAllFDBookings(), hasLength(1));
      await closeQuery(tester);
      await settle(tester, frames: 12);

      expect(find.text('SAVED FD BOOKINGS'), findsNothing);
      expect(find.textContaining('FD booked.'), findsNothing);
      expect(
        find.byKey(const Key('recommendation-text-section')),
        findsNothing,
      );
      expect(find.byKey(const Key('home-financial-metrics')), findsNothing);
      expect(find.text('30-DAY INFLOW'), findsNothing);
      expect(find.text('30-DAY OUTFLOW'), findsNothing);
      expect(find.text('SAFETY BUFFER'), findsNothing);
      expect(find.byKey(const Key('home-spending-prompt')), findsOneWidget);
      expect(find.byKey(const Key('home-suggested-actions')), findsOneWidget);
      expect(find.text('Fixed Deposit Receipt'), findsNothing);
    });

    testWidgets(
      'shows monthly spending prompt after all home actions complete',
      (tester) async {
        await app.launch(tester);

        await tapAndSettle(
          tester,
          find.byKey(const Key('recommendation-action')),
        );
        await confirmWithMpin(tester);
        await closeQuery(tester);
        await settle(tester, frames: 12);

        final container = ProviderScope.containerOf(
          tester.element(find.byType(Scaffold).first),
        );
        container.read(completedMicroActionsProvider.notifier).state = {
          'p_salaried_01:Pay my house rent',
          'p_salaried_01:Lock my debit card',
          'p_salaried_01:Pay my electricity bill',
        };
        await tester.pump();
        await settle(tester, frames: 12);

        expect(
          find.byKey(const Key('recommendation-text-section')),
          findsNothing,
        );
        expect(find.byKey(const Key('home-financial-metrics')), findsNothing);
        expect(find.byKey(const Key('home-suggested-actions')), findsNothing);
        expect(
          find.byKey(const Key('home-spending-prompt-text')),
          findsOneWidget,
        );
        final greeting = tester.widget<Text>(
          find
              .descendant(
                of: find.byKey(const ValueKey('home-greeting')),
                matching: find.byType(Text),
              )
              .first,
        );
        expect(greeting.maxLines, 2);
        expect(
          tester.getRect(find.byKey(const Key('home-spending-prompt'))).top,
          greaterThan(
            tester.getRect(find.byKey(const ValueKey('home-greeting'))).bottom,
          ),
        );
        expect(
          find.byKey(const Key('home-spending-prompt-arrow')),
          findsOneWidget,
        );
        final spendingTextRect = tester.getRect(
          find.byKey(const Key('home-spending-prompt-text')),
        );
        final spendingArrowRect = tester.getRect(
          find.byKey(const Key('home-spending-prompt-arrow')),
        );
        expect(spendingArrowRect.left, greaterThan(spendingTextRect.left));
        expect(
          spendingArrowRect.right,
          lessThanOrEqualTo(spendingTextRect.right),
        );

        await tapAndSettle(
          tester,
          find.byKey(const Key('home-spending-prompt')),
        );
        expect(find.text('How much I spent in this month'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('monthly-spending-result-card')),
          findsOneWidget,
        );
      },
    );

    testWidgets('shows an inline error when the network is down', (
      tester,
    ) async {
      await app.storage.saveDemoSettings(
        const DemoSettings(simulatedLatencyMs: 0, simulateFailure: true),
      );
      await app.launch(tester);

      expect(find.textContaining('could not reach the bank'), findsWidgets);
    });
  });

  group('single-query assistant', () {
    testWidgets('answers monthly-spending and failed-transaction queries', (
      tester,
    ) async {
      await app.launch(tester);

      await shootQuery(tester, 'How much I spent in this month');
      expect(
        find.widgetWithText(ActionChip, 'Pay my electricity bill'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('monthly-spending-result-card')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('spending-pie-chart')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('monthly-spending-chart-total')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('monthly-spending-insight')),
        findsOneWidget,
      );
      expect(find.text('Rent'), findsOneWidget);
      expect(find.text('₹28,500'), findsOneWidget);
      expect(
        find.textContaining('Your spending totals ₹65,000 this month.'),
        findsNothing,
      );
      await settle(tester, frames: 30);
      await shootQuery(tester, 'Show failed transactions yesterday.');
      expect(find.text('Show failed transactions yesterday.'), findsOneWidget);
      expect(find.text('How much I spent in this month'), findsNothing);
      expect(find.textContaining('3 failed transactions'), findsOneWidget);
      expect(find.textContaining('₹2,76,270'), findsOneWidget);
      expect(find.textContaining('Amazon India'), findsWidgets);
      expect(find.textContaining('Netflix'), findsWidgets);
      expect(find.text('₹2,75,000'), findsOneWidget);
      expect(find.text('Insufficient balance'), findsOneWidget);
      expect(find.text('Card expired'), findsOneWidget);
      expect(find.text('Autopay mandate failed'), findsOneWidget);
      expect(
        find.textContaining('08:52 PM · UPI Autopay · Declined'),
        findsOneWidget,
      );
      expect(find.textContaining('No card was charged'), findsOneWidget);
      expect(find.textContaining('No funds were debited.'), findsOneWidget);
      expect(
        find.textContaining('Support ticket raised for expired card'),
        findsOneWidget,
      );
      expect(find.textContaining('EQ-TKT-0914'), findsOneWidget);
      expect(find.text('AI transaction review'), findsNothing);
      expect(
        find.byKey(const ValueKey('failed-transactions-result-card')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('failed-transactions-ticket')),
        findsOneWidget,
      );
      expect(
        find.textContaining('I found 4 failed transactions'),
        findsNothing,
      );
      expect(app.storage.getSupportTickets(), hasLength(1));
      expect(app.storage.getSupportTickets().single['merchant'], 'Swiggy');
      expect(app.storage.getSupportTickets().single['reason'], 'Card expired');
    });

    testWidgets('books a typed FD amount only after MPIN verification', (
      tester,
    ) async {
      await app.launch(tester);
      await shootQuery(tester, 'Book an FD for 50,000.');

      expect(find.textContaining('For how long?'), findsOneWidget);
      await tapAndSettle(
        tester,
        find.descendant(
          of: find.byKey(const Key('chat_suggestions')),
          matching: find.text('12 months'),
        ),
      );
      expect(find.text('Confirm FD'), findsOneWidget);
      await confirmWithMpin(tester);

      expect(find.textContaining('Done! Your fixed deposit'), findsOneWidget);
      expect(app.storage.getAllFDBookings(), hasLength(1));
      expect(app.storage.getAllFDBookings().single['depositAmount'], 50000);
    });

    testWidgets('high-value transfer is reviewed and MPIN-verified', (
      tester,
    ) async {
      final soundCalls = captureTransactionSounds();
      await app.launch(tester);
      final record = app.storage.getPersonaRecord('p_salaried_01')!;
      final summary = Map<String, dynamic>.from(
        record['financialSummary'] as Map,
      );
      summary['currentBalance'] = 250000;
      record['financialSummary'] = summary;
      await app.storage.savePersonaRecord(record);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold).first),
      );
      await container.read(personaProvider.notifier).refreshPersonas();

      await shootQuery(tester, 'Transfer ₹2 lakh');
      expect(
        find.textContaining('identified this transfer as unusual'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('transfer-risk-review-card')),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('Paid ₹2,00,000'), findsNothing);
      await tapAndSettle(tester, find.text('Proceed'));
      expect(find.text('Who should receive the transfer?'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('transfer-payee-selection-card')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('chat_suggestions')), findsNothing);
      expect(
        find.byKey(const ValueKey('transfer-payee-Jada Winters')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('transfer-payee-Jada Winters')),
          matching: find.byKey(
            const ValueKey('transfer-payee-avatar-Jada Winters'),
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('transfer-payee-arrow-Jada Winters')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('transfer-payee-avatar-Jada Winters')),
          matching: find.text('J'),
        ),
        findsOneWidget,
      );
      expect(find.text('Choose recipient'), findsOneWidget);
      expect(find.text('4 saved'), findsOneWidget);
      expect(find.text('Saved bank accounts'), findsOneWidget);
      expect(find.textContaining('HDFC Bank · •••• 4821'), findsOneWidget);
      expect(find.textContaining('ICICI Bank · •••• 1736'), findsOneWidget);
      expect(find.textContaining('IFSC HDFC0004821'), findsOneWidget);
      expect(find.textContaining('Last paid'), findsNWidgets(4));
      await tapAndSettle(
        tester,
        find.byKey(const ValueKey('transfer-payee-Jada Winters')),
      );
      expect(find.text('Confirm transfer'), findsOneWidget);
      await confirmWithMpin(tester);

      expect(
        find.textContaining('Paid ₹2,00,000 to Jada Winters'),
        findsOneWidget,
      );
      expect(soundCalls, ['playSuccess']);
      final updated = app.storage.getPersonaRecord('p_salaried_01')!;
      expect((updated['financialSummary'] as Map)['currentBalance'], 50000);
    });

    testWidgets('a new request replaces an unfinished payment query', (
      tester,
    ) async {
      await app.launch(tester);
      await shootQuery(tester, 'Pay my house rent');
      expect(find.text('Pay my house rent'), findsWidgets);
      expect(find.text('Awaiting you'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('ask_ai')),
        'Increase my debit card limit.',
      );
      await tester.tap(find.byKey(const Key('ask_ai_send')));
      await settle(tester, frames: 80);

      expect(find.text('Increase my debit card limit.'), findsOneWidget);
      expect(find.text('Pay my house rent'), findsNothing);
      expect(find.text('Payment'), findsNothing);
      expect(find.text('Debit card limit'), findsOneWidget);
      expect(find.text('Confirm limit'), findsOneWidget);
    });

    testWidgets(
      'debit limit change is MPIN-verified and affects the next quote',
      (tester) async {
        final soundCalls = captureTransactionSounds();
        await app.launch(tester);
        await shootQuery(tester, 'Increase my debit card limit.');

        expect(find.textContaining('₹50,000'), findsWidgets);
        expect(find.text('Confirm limit'), findsOneWidget);
        await confirmWithMpin(tester);
        expect(
          find.textContaining(
            "Your debit card's daily transaction limit has been increased from "
            '₹50,000 to ₹1,50,000.',
          ),
          findsOneWidget,
        );
        expect(soundCalls, ['playCardLimit']);

        await closeQuery(tester);
        await shootQuery(tester, 'Increase my debit card limit.');
        expect(
          find.textContaining('currently has a daily limit of ₹1,50,000'),
          findsOneWidget,
        );
        expect(find.textContaining('raise it to ₹2,00,000'), findsOneWidget);
      },
    );

    testWidgets('Ananya: recommend → create FD → confirm → account updates', (
      tester,
    ) async {
      await app.launch(tester);
      await shootQuery(tester, 'I have some extra money this month');

      expect(find.textContaining('₹1,60,800'), findsOneWidget);

      await tapAndSettle(
        tester,
        find.text('Create an FD of ₹1,50,000 for 12 months'),
      );
      await settle(tester, frames: 12);
      expect(find.text('Fixed Deposit'), findsOneWidget);
      expect(find.text('Awaiting you'), findsOneWidget);
      expect(find.text('Confirm FD'), findsOneWidget);

      await confirmWithMpin(tester);

      expect(find.textContaining('Done! Your fixed deposit'), findsOneWidget);
      expect(find.text('Done'), findsWidgets);
      expect(find.byKey(const Key('card_confirm')), findsNothing);

      await closeQuery(tester);
      await settle(tester, frames: 12);
      expect(find.byKey(const Key('home-account-summary')), findsOneWidget);
      expect(find.text('SAVED FD BOOKINGS'), findsNothing);
      expect(find.textContaining('FD booked.'), findsNothing);
    });

    testWidgets('declining a card cancels it', (tester) async {
      await app.launch(tester);
      await shootQuery(tester, 'Create an FD of 1 lakh for 12 months');
      expect(find.text('Awaiting you'), findsOneWidget);

      await tapAndSettle(tester, find.byKey(const Key('card_cancel')));
      await settle(tester, frames: 60);

      expect(find.text('Cancelled'), findsOneWidget);
      expect(find.byKey(const Key('card_confirm')), findsNothing);
      expect(find.textContaining("I've cancelled that"), findsOneWidget);
      expect(app.storage.getAllFDBookings(), isEmpty);
    });

    testWidgets('a wrong MPIN fails and does not send a payment', (
      tester,
    ) async {
      await app.launch(tester);
      await tapAndSettle(
        tester,
        find.byKey(const Key('micro_action_Pay my house rent')),
      );
      await settle(tester, frames: 80);

      await confirmWithMpin(tester, mpin: '0000');

      expect(find.text('Failed'), findsOneWidget);
      expect(
        find.textContaining("MPIN verification failed, so I've cancelled that"),
        findsOneWidget,
      );
      expect(find.byKey(const Key('card_confirm')), findsNothing);
      expect(find.byKey(const Key('chat_suggestions')), findsOneWidget);
      final record = app.storage.getPersonaRecord('p_salaried_01')!;
      final summary = record['financialSummary'] as Map<String, dynamic>;
      expect(summary['currentBalance'], 185000);
    });

    testWidgets('typing yes also requires MPIN verification', (tester) async {
      await app.launch(tester);
      await shootQuery(tester, 'Create an FD of 1 lakh for 12 months');
      expect(find.text('Awaiting you'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('ask_ai')), 'yes');
      await tapAndSettle(tester, find.byKey(const Key('ask_ai_send')));
      expect(find.text('Enter your 4-digit MPIN to verify'), findsOneWidget);
      expect(app.storage.getAllFDBookings(), isEmpty);
      final promptRect = tester.getRect(
        find.text('Enter your 4-digit MPIN to verify'),
      );
      final cancelRect = tester.getRect(find.byKey(const Key('mpin_cancel')));
      final verifyRect = tester.getRect(find.byKey(const Key('mpin_verify')));
      expect(cancelRect.left, closeTo(promptRect.left, 1));
      expect(verifyRect.right, closeTo(promptRect.right, 1));
      expect(cancelRect.width, closeTo(verifyRect.width, 1));

      await enterMpin(tester, demoMpin);
      await tapAndSettle(tester, find.byKey(const Key('mpin_verify')));
      await settle(tester, frames: 60);
      expect(find.textContaining('Done! Your fixed deposit'), findsOneWidget);
      expect(app.storage.getAllFDBookings(), hasLength(1));
    });

    testWidgets(
      'a quick-action tile opens a single-query response with its prompt',
      (tester) async {
        final soundCalls = captureTransactionSounds();
        await app.launch(tester);

        await tapAndSettle(
          tester,
          find.byKey(const Key('micro_action_Pay my house rent')),
        );
        await settle(tester, frames: 80);

        expect(find.text('Pay my house rent'), findsOneWidget);
        expect(find.text('Payment'), findsOneWidget);
        expect(find.text('House rent - landlord'), findsOneWidget);
        expect(find.text('₹28,500'), findsOneWidget);
        expect(find.byKey(const ValueKey('submitted-query')), findsOneWidget);
        expect(soundCalls, isEmpty);

        await confirmWithMpin(tester);
        expect(
          find.textContaining('Paid ₹28,500 to House rent - landlord'),
          findsOneWidget,
        );
        expect(soundCalls, ['playSuccess']);
        expect(find.text('Pay my house rent'), findsWidgets);
        expect(find.byKey(const ValueKey('submitted-query')), findsOneWidget);
        expect(find.text('Done'), findsOneWidget);
        expect(find.text('Payment'), findsOneWidget);
        expect(find.text('Payee'), findsOneWidget);
        expect(find.text('House rent - landlord'), findsOneWidget);
        expect(find.text('Amount'), findsOneWidget);
        expect(find.text('₹28,500'), findsOneWidget);

        await tester.enterText(
          find.byKey(const Key('ask_ai')),
          "What's my balance?",
        );
        await tester.tap(find.byKey(const Key('ask_ai_send')));
        await settle(tester, frames: 80);
        expect(find.text("What's my balance?"), findsOneWidget);
        expect(
          find.textContaining('Your balance is ₹1,56,500'),
          findsOneWidget,
        );
        expect(find.text('Payment'), findsNothing);
        expect(find.textContaining('Paid ₹28,500'), findsNothing);

        await closeQuery(tester);
        await settle(tester, frames: 12);
        expect(find.byKey(const Key('home-account-summary')), findsOneWidget);
        expect(
          find.byKey(const Key('micro_action_Pay my house rent')),
          findsNothing,
        );

        await shootQuery(tester, 'Show failed transactions yesterday.');
        expect(
          find.byKey(const ValueKey('failed-transactions-result-card')),
          findsOneWidget,
        );
        expect(find.text('Payment'), findsNothing);
        expect(find.textContaining('Paid ₹28,500'), findsNothing);
        expect(
          find.textContaining('I found 3 failed transactions'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Support ticket raised for expired card'),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('failed-transaction-suggestions')),
          findsNothing,
        );
      },
    );

    testWidgets('a chat payment removes its matching predicted action', (
      tester,
    ) async {
      await app.launch(tester);
      await shootQuery(tester, 'Pay my house rent');
      await confirmWithMpin(tester);
      await closeQuery(tester);
      await settle(tester, frames: 12);

      expect(
        find.byKey(const Key('micro_action_Pay my house rent')),
        findsNothing,
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold).first),
      );
      container.read(completedMicroActionsProvider.notifier).state = const {};
      await container.read(personaProvider.notifier).refreshPersonas();
      await tester.pump();
      await settle(tester, frames: 12);
      expect(
        find.byKey(const Key('micro_action_Pay my house rent')),
        findsNothing,
      );

      await shootQuery(tester, 'Pay my house rent');
      expect(
        find.textContaining('is already done for this month'),
        findsOneWidget,
      );
      expect(find.textContaining('(ref PAY_'), findsOneWidget);
      expect(find.text('Payment'), findsOneWidget);
      expect(find.text('Payee'), findsOneWidget);
      expect(find.text('House rent - landlord'), findsOneWidget);
      expect(find.text('Amount'), findsOneWidget);
      expect(find.text('₹28,500'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Reference'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Pay now'), findsNothing);
    });

    testWidgets('a chat card lock removes the matching predicted action', (
      tester,
    ) async {
      final soundCalls = captureTransactionSounds();
      await app.launch(tester);
      await shootQuery(tester, 'Lock my debit card');
      await confirmWithMpin(tester);
      await closeQuery(tester);
      await settle(tester, frames: 12);

      expect(
        find.byKey(const Key('micro_action_Lock my debit card')),
        findsNothing,
      );
      expect(soundCalls, ['playCardLock']);
    });

    testWidgets('a locked card can be unlocked after MPIN confirmation', (
      tester,
    ) async {
      final soundCalls = captureTransactionSounds();
      await app.launch(tester);
      await shootQuery(tester, 'Lock my debit card');
      await confirmWithMpin(tester);
      await closeQuery(tester);
      await settle(tester, frames: 12);
      expect(
        find.byKey(const Key('micro_action_Lock my debit card')),
        findsNothing,
      );

      await shootQuery(tester, 'Lock my debit card');
      expect(find.textContaining('currently locked'), findsOneWidget);
      expect(find.text('Unlock card'), findsNWidgets(2));
      expect(find.byKey(const Key('card_confirm')), findsOneWidget);
      await confirmWithMpin(tester);
      expect(soundCalls, ['playCardLock', 'playCardUnlock']);
    });

    testWidgets('the electricity quick action pays the electricity bill', (
      tester,
    ) async {
      await app.launch(tester);

      await tapAndSettle(
        tester,
        find.byKey(const Key('micro_action_Pay my electricity bill')),
      );
      await settle(tester, frames: 80);

      expect(find.text('Pay my electricity bill'), findsWidgets);
      expect(find.text('Electricity bill'), findsOneWidget);
      expect(find.text('₹1,850'), findsOneWidget);

      await confirmWithMpin(tester);

      expect(
        find.textContaining('Paid ₹1,850 to Electricity bill'),
        findsOneWidget,
      );
      await closeQuery(tester);
      expect(
        find.byKey(const Key('micro_action_Pay my electricity bill')),
        findsNothing,
      );
      expect(find.text('Paid EB Bill'), findsNothing);
      expect(find.text('₹1,83,150'), findsWidgets);
    });

    testWidgets('locks the card and removes its predicted action from home', (
      tester,
    ) async {
      await app.launch(tester);
      await shootQuery(tester, 'Lock my debit card');
      await confirmWithMpin(tester);
      expect(find.textContaining('Your card is locked'), findsOneWidget);

      await closeQuery(tester);
      await settle(tester, frames: 12);
      expect(find.text('Card locked'), findsNothing);
      expect(
        find.byKey(const Key('micro_action_Lock my debit card')),
        findsNothing,
      );
    });

    testWidgets(
      'shows an error with a retry chip when the bank is unreachable',
      (tester) async {
        await app.launch(tester);
        await setFailure(tester, on: true);
        await shootQuery(tester, "What's my balance?");
        expect(find.textContaining('could not reach the bank'), findsOneWidget);
        expect(find.text('Try again'), findsOneWidget);

        await setFailure(tester, on: false);
        await tapAndSettle(tester, find.text('Try again'));
        await settle(tester, frames: 12);
        expect(
          find.textContaining('Your balance is ₹1,85,000. Over the next'),
          findsOneWidget,
        );
      },
    );

    testWidgets('swipe history button opens conversations page', (
      tester,
    ) async {
      await app.launch(tester);
      await shootQuery(tester, "What's my balance?");
      await closeQuery(tester);

      await tester.tap(find.byKey(const Key('ask_ai_open_chat')));
      await settle(tester, frames: 12);
      expect(find.text('Conversations'), findsOneWidget);
      expect(find.text("What's my balance?"), findsWidgets);
      expect(find.byKey(const ValueKey('ambient-orb')), findsNothing);
    });
  });

  group('demo reset', () {
    testWidgets('long-pressing the avatar resets the demo', (tester) async {
      await app.launch(tester);
      await tapAndSettle(
        tester,
        find.byKey(const Key('recommendation-action')),
      );
      await settle(tester, frames: 12);
      await confirmWithMpin(tester);
      await closeQuery(tester);
      await settle(tester, frames: 12);
      expect(find.text('SAVED FD BOOKINGS'), findsNothing);

      await tester.longPress(find.widgetWithText(CircleAvatar, 'A'));
      await settle(tester, frames: 12);

      expect(
        find.textContaining('Settings restored to defaults'),
        findsOneWidget,
      );
      expect(find.text('SAVED FD BOOKINGS'), findsNothing);
      expect(find.byKey(const Key('home-account-summary')), findsOneWidget);
    });
  });
}
