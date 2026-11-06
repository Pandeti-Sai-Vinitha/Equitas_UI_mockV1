import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:mock2/chat/chat_models.dart';
import 'package:mock2/core/exceptions.dart';
import 'package:mock2/data/banking_repository.dart';
import 'package:mock2/data/mock_api_client.dart';
import 'package:mock2/domain/demo_settings.dart';
import 'package:mock2/domain/fixed_deposit.dart';
import 'package:mock2/domain/models.dart';
import 'package:mock2/routes/mock_api_routes.dart';

import '../helpers/test_hive.dart';

Matcher _apiError(String code) => throwsA(
  isA<MockApiException>().having((error) => error.code, 'code', code),
);

Persona _persona(String id) =>
    Persona.fromRecord(storage.getPersonaRecord(id)!);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late MockApiRoutes routes;
  late BankingRepository repository;

  setUp(() async {
    directory = await openTestHive();
    await seedTestData();
    routes = MockApiRoutes(storage);
    repository = BankingRepository(
      MockApiClient(
        routes,
        settings: () => const DemoSettings(simulatedLatencyMs: 0),
      ),
    );
  });

  tearDown(() => closeTestHive(directory));

  group('POST /api/chat', () {
    test('answers from the persona stored in Hive', () async {
      final response = await routes.dispatch(
        'POST',
        ApiEndpoints.chat,
        body: {
          'personaId': 'p_salaried_01',
          'message': 'I have some extra money this month',
        },
      );

      final reply = ChatReply.fromJson(
        response['data'] as Map<String, dynamic>,
      );
      expect(reply.intent, ChatIntent.recommend);
      expect(reply.text, contains('₹1,50,000'));
    });

    test(
      'offers follow the live account: after an FD the recommendation shrinks',
      () async {
        await routes.dispatch(
          'POST',
          ApiEndpoints.fdBookings,
          body: {
            'personaId': 'p_salaried_01',
            'depositAmount': 150000.0,
            'tenorMonths': 12,
            'interestRate': 7.2,
            'payoutOption': 'AT_MATURITY',
            'autoRenew': true,
          },
        );

        final reply = await repository.sendChatMessage(
          personaId: 'p_salaried_01',
          message: 'I have some extra money this month',
        );
        expect(reply.text, allOf(contains('₹70,000'), contains('₹45,000')));
      },
    );

    test('carries pending state from one request to the next', () async {
      final first = await repository.sendChatMessage(
        personaId: 'p_salaried_01',
        message: 'Create an FD of 1 lakh',
      );
      expect(first.pending!.awaiting, ChatAwaiting.tenor);

      final second = await repository.sendChatMessage(
        personaId: 'p_salaried_01',
        message: '12 months',
        pending: first.pending,
      );
      expect(second.action!.type, ChatActionType.openFd);
      expect(second.action!.params['depositAmount'], 100000);
    });

    test('raises and reuses a failed-transactions support ticket', () async {
      final first = await repository.sendChatMessage(
        personaId: 'p_salaried_01',
        message: 'Show failed transactions yesterday.',
      );
      final again = await repository.sendChatMessage(
        personaId: 'p_salaried_01',
        message: 'Show failed transactions yesterday.',
      );

      expect(first.ticketReference, 'EQ-TKT-0914');
      expect(again.ticketReference, first.ticketReference);
      expect(first.text, contains('I found 3 failed transactions'));
      expect(first.text, contains('₹2,76,270'));
      expect(storage.getSupportTickets(), hasLength(1));
      expect(storage.getSupportTickets().single, {
        'id': 'p_salaried_01:swiggy-expired-card',
        'reference': 'EQ-TKT-0914',
        'personaId': 'p_salaried_01',
        'merchant': 'Swiggy',
        'reason': 'Card expired',
        'status': 'OPEN',
        'createdAt': isA<String>(),
      });
    });

    test('validates the request', () {
      expect(
        routes.dispatch('POST', ApiEndpoints.chat),
        _apiError('BAD_REQUEST'),
      );
      expect(
        routes.dispatch(
          'POST',
          ApiEndpoints.chat,
          body: {'personaId': 'p_salaried_01'},
        ),
        _apiError('BAD_REQUEST'),
      );
      expect(
        routes.dispatch(
          'POST',
          ApiEndpoints.chat,
          body: {'personaId': 'nobody', 'message': 'hi'},
        ),
        _apiError('NOT_FOUND'),
      );
    });
  });

  group('POST /api/payments', () {
    Map<String, dynamic> body({
      double amount = 28500,
      String personaId = 'p_salaried_01',
    }) => {
      'personaId': personaId,
      'payee': 'House rent - landlord',
      'amount': amount,
      'category': 'RENT',
    };

    test('debits the balance and logs the transaction', () async {
      final response = await routes.dispatch(
        'POST',
        ApiEndpoints.payments,
        body: body(),
      );

      final receipt = response['data'] as Map<String, dynamic>;
      expect(receipt['id'], startsWith('PAY_'));
      expect(receipt['balanceAfter'], 156500);
      final ananya = _persona('p_salaried_01');
      expect(ananya.financialSummary.currentBalance, 156500);
      expect(
        ananya.recentTransactions.first.description,
        'House rent - landlord',
      );
      expect(ananya.recentTransactions.first.category, 'RENT');
      expect(ananya.holdings, isEmpty);
    });

    test('rejects more than the funds available', () async {
      expect(
        routes.dispatch(
          'POST',
          ApiEndpoints.payments,
          body: body(amount: 185000.5),
        ),
        _apiError('INSUFFICIENT_FUNDS'),
      );
      expect(_persona('p_salaried_01').financialSummary.currentBalance, 185000);
    });

    test(
      'can draw on an active overdraft, taking the balance below zero',
      () async {
        final payroll = {
          'personaId': 'p_biz_02',
          'payee': 'Payroll - 12 employees',
          'amount': 54000.0,
          'category': 'PAYROLL',
        };
        await expectLater(
          routes.dispatch('POST', ApiEndpoints.payments, body: payroll),
          _apiError('INSUFFICIENT_FUNDS'),
        );

        await routes.dispatch(
          'POST',
          ApiEndpoints.creditLines,
          body: {
            'personaId': 'p_biz_02',
            'productType': 'CREDIT_LINE',
            'amount': 80000.0,
            'interestRate': 11.5,
            'tenorMonths': 12,
          },
        );
        final response = await routes.dispatch(
          'POST',
          ApiEndpoints.payments,
          body: payroll,
        );

        expect((response['data'] as Map)['balanceAfter'], -9000);
        expect(_persona('p_biz_02').financialSummary.currentBalance, -9000);
      },
    );

    test('validates the request', () {
      expect(
        routes.dispatch('POST', ApiEndpoints.payments),
        _apiError('BAD_REQUEST'),
      );
      expect(
        routes.dispatch('POST', ApiEndpoints.payments, body: body(amount: 0)),
        _apiError('BAD_REQUEST'),
      );
      expect(
        routes.dispatch(
          'POST',
          ApiEndpoints.payments,
          body: body(personaId: 'nobody'),
        ),
        _apiError('NOT_FOUND'),
      );
    });
  });

  group('POST /api/cards/lock', () {
    test('locks the card once', () async {
      final response = await routes.dispatch(
        'POST',
        ApiEndpoints.cardLock,
        body: {'personaId': 'p_salaried_01'},
      );
      expect((response['data'] as Map)['status'], 'LOCKED');
      expect(_persona('p_salaried_01').cardLocked, isTrue);
      expect(_persona('p_biz_02').cardLocked, isFalse);

      expect(
        routes.dispatch(
          'POST',
          ApiEndpoints.cardLock,
          body: {'personaId': 'p_salaried_01'},
        ),
        _apiError('ALREADY_LOCKED'),
      );
    });

    test('the assistant then knows the card is locked', () async {
      await repository.lockCard('p_salaried_01');
      final reply = await repository.sendChatMessage(
        personaId: 'p_salaried_01',
        message: 'Lock my debit card',
      );
      expect(reply.text, contains('already locked'));
    });

    test('validates the request', () {
      expect(
        routes.dispatch('POST', ApiEndpoints.cardLock),
        _apiError('BAD_REQUEST'),
      );
      expect(
        routes.dispatch(
          'POST',
          ApiEndpoints.cardLock,
          body: {'personaId': 'nobody'},
        ),
        _apiError('NOT_FOUND'),
      );
    });
  });

  /// Plays both demo scenarios the way the chat UI will: send a message,
  /// run whatever the assistant asks to execute, send the next message.
  group('end-to-end scenarios through chat + routes', () {
    Future<ChatReply> say(
      String personaId,
      String text, [
      ChatPending? pending,
    ]) => repository.sendChatMessage(
      personaId: personaId,
      message: text,
      pending: pending,
    );

    test(
      'Ananya: recommend → create FD → confirm → balance and offer update',
      () async {
        final recommend = await say(
          'p_salaried_01',
          'I have some extra money this month',
        );
        final card = await say('p_salaried_01', recommend.suggestions.first);
        final confirmed = await say('p_salaried_01', 'yes', card.pending);

        final params = confirmed.execute!.params;
        final booking = await repository.bookFixedDeposit(
          personaId: 'p_salaried_01',
          depositAmount: (params['depositAmount'] as num).toDouble(),
          tenorMonths: params['tenorMonths'] as int,
          interestRate: (params['interestRate'] as num).toDouble(),
          payoutOption: InterestPayout.parse(params['payoutOption'] as String),
          autoRenew: params['autoRenew'] as bool,
        );

        expect(booking.depositAmount, 150000);
        expect(
          _persona('p_salaried_01').financialSummary.currentBalance,
          35000,
        );

        final after = await say('p_salaried_01', "What's my balance?");
        expect(after.text, contains('₹35,000'));
      },
    );

    test(
      'Rajesh: shortfall → overdraft → activate → payroll goes through',
      () async {
        final ask = await say(
          'p_biz_02',
          'Can I pay my electronics supplier this week?',
        );
        expect(ask.action!.type, ChatActionType.activateCredit);

        final confirmed = await say('p_biz_02', 'yes', ask.pending);
        final params = confirmed.execute!.params;
        await repository.activateCredit(
          personaId: 'p_biz_02',
          productType: params['productType'] as String,
          amount: (params['amount'] as num).toDouble(),
          interestRate: (params['interestRate'] as num).toDouble(),
          tenorMonths: params['tenorMonths'] as int,
        );
        expect(_persona('p_biz_02').availableCredit, 80000);

        final payroll = await say(
          'p_biz_02',
          'Approve payroll for my 12 employees',
        );
        expect(payroll.action!.type, ChatActionType.payBill);
        final pay = await say('p_biz_02', 'yes', payroll.pending);
        final payParams = pay.execute!.params;
        final receipt = await repository.makePayment(
          personaId: 'p_biz_02',
          payee: payParams['payee'] as String,
          amount: (payParams['amount'] as num).toDouble(),
          category: payParams['category'] as String,
        );

        expect(receipt['balanceAfter'], -9000);
        final balance = await say('p_biz_02', "what's my balance");
        expect(balance.text, contains('overdraft'));
      },
    );
  });
}
