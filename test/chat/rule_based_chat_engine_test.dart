import 'package:flutter_test/flutter_test.dart';

import 'package:mock2/chat/chat_engine.dart';
import 'package:mock2/chat/chat_models.dart';
import 'package:mock2/chat/rule_based_chat_engine.dart';
import 'package:mock2/domain/models.dart';

import '../helpers/chat_fixtures.dart';

Matcher _hasDetail(String label, String value) => predicate<ChatAction>(
  (action) =>
      action.details.any((item) => item.label == label && item.value == value),
  'has detail $label = $value',
);

void main() {
  group('Ananya (salaried, surplus)', () {
    late Conversation chat;

    setUp(() => chat = Conversation(ananya()));

    test(
      'greets her with her free cash and steers towards the offer',
      () async {
        final reply = await chat.say('hi');

        expect(reply.intent, ChatIntent.greeting);
        expect(
          reply.text,
          allOf(
            contains('Ananya'),
            contains('₹1,85,000'),
            contains('₹2,20,000'),
          ),
        );
        expect(
          reply.suggestions,
          contains('I have some extra money this month'),
        );
      },
    );

    test(
      'recommends the FD with maturity and what is left in the account',
      () async {
        final reply = await chat.say('I have some extra money this month');

        expect(reply.intent, ChatIntent.recommend);
        expect(
          reply.text,
          allOf(
            contains('₹2,20,000'),
            contains('₹1,50,000'),
            contains('7.2%'),
            contains('12 months'),
            contains('₹1,60,800'),
            contains('₹35,000'),
          ),
        );
        expect(
          reply.suggestions.first,
          'Create an FD of ₹1,50,000 for 12 months',
        );
        expect(reply.action, isNull);
      },
    );

    test(
      'full scenario: recommend → create FD → tenor → confirm → execute',
      () async {
        final recommend = await chat.say('I have some extra money this month');

        // Tapping the suggested chip goes straight to the confirmation card.
        final card = await chat.say(recommend.suggestions.first);
        expect(card.intent, ChatIntent.createFd);
        expect(card.action!.type, ChatActionType.openFd);
        expect(card.action!.params, {
          'depositAmount': 150000.0,
          'tenorMonths': 12,
          'interestRate': 7.2,
          'payoutOption': 'AT_MATURITY',
          'autoRenew': true,
        });
        expect(card.action!, _hasDetail('Maturity amount', '₹1,60,800'));
        expect(card.pending!.awaiting, ChatAwaiting.confirm);

        final done = await chat.say('yes');
        expect(done.execute!.type, ChatActionType.openFd);
        expect(done.intent, ChatIntent.createFd);
        expect(done.text, 'Great, booking your fixed deposit…');
        expect(done.pending, isNull);
      },
    );

    test('asks for the missing tenor, then builds the card', () async {
      final ask = await chat.say('Create an FD of 1 lakh');

      expect(ask.intent, ChatIntent.createFd);
      expect(ask.text, contains('For how long?'));
      expect(ask.suggestions, ['6 months', '12 months', '24 months']);
      expect(ask.pending!.awaiting, ChatAwaiting.tenor);
      expect(ask.pending!.slots['amount'], 100000);

      final card = await chat.say('12 months');
      expect(card.action!.params['depositAmount'], 100000);
      expect(card.action!, _hasDetail('Maturity amount', '₹1,07,200'));
      expect(card.action!, _hasDetail('Balance after', '₹85,000'));
    });

    test(
      'asks for the amount when none is given, offering the recommended one',
      () async {
        final ask = await chat.say('Create an FD');

        expect(ask.pending!.awaiting, ChatAwaiting.amount);
        expect(ask.text, allOf(contains('₹1,50,000'), contains('₹1,65,000')));
        expect(ask.suggestions, ['₹1,50,000']);

        final tenor = await chat.say('1.5 lakh');
        expect(tenor.pending!.awaiting, ChatAwaiting.tenor);

        final card = await chat.say('12');
        expect(card.action!.params['depositAmount'], 150000);
        expect(card.action!.params['tenorMonths'], 12);
      },
    );

    test(
      'accepts the amount and tenor together while the amount is awaited',
      () async {
        await chat.say('Create an FD');
        final card = await chat.say('2 lakh for 2 years');
        // ₹2 lakh is above her safe maximum, so she is asked again.
        expect(card.pending!.awaiting, ChatAwaiting.amount);

        final fixed = await chat.say('1 lakh for 2 years');
        expect(fixed.action!.params['tenorMonths'], 24);
        expect(fixed.action!.params['depositAmount'], 100000);
      },
    );

    test(
      'warns before the safety buffer is breached and suggests the safe maximum',
      () async {
        final reply = await chat.say('Create an FD of 1.8 lakh for 12 months');

        expect(reply.action, isNull);
        expect(
          reply.text,
          allOf(
            contains('safety buffer'),
            contains('₹20,000'),
            contains('₹1,65,000'),
          ),
        );
        expect(reply.suggestions, ['₹1,65,000']);
        expect(reply.pending!.awaiting, ChatAwaiting.amount);
        expect(reply.pending!.slots['tenorMonths'], 12);

        final card = await chat.say('₹1,65,000');
        expect(card.action!.params['depositAmount'], 165000);
        expect(card.action!.params['tenorMonths'], 12);
      },
    );

    test('refuses an amount above the balance', () async {
      final reply = await chat.say('Create an FD of 5 lakh');
      expect(
        reply.text,
        allOf(contains('only have ₹1,85,000'), contains('₹1,65,000')),
      );
      expect(reply.action, isNull);
    });

    test('refuses an amount below the product minimum', () async {
      final reply = await chat.say('create an fd of 5000 for 12 months');
      expect(reply.text, allOf(contains('minimum'), contains('₹10,000')));
      expect(reply.pending!.awaiting, ChatAwaiting.amount);
    });

    test(
      'can change the tenor while the card is waiting for confirmation',
      () async {
        await chat.say('Create an FD of 1.5 lakh for 12 months');
        final changed = await chat.say('make it 24 months');

        expect(changed.action!.params['tenorMonths'], 24);
        expect(changed.action!.params['depositAmount'], 150000);
        expect(changed.action!, _hasDetail('Maturity amount', '₹1,71,600'));
      },
    );

    test('cancels on "no" and forgets the task', () async {
      await chat.say('Create an FD of 1 lakh for 12 months');
      final reply = await chat.say('no');

      expect(reply.text, contains('cancelled'));
      expect(reply.action, isNull);
      expect(reply.execute, isNull);
      expect(reply.pending, isNull);
      expect(chat.pending, isNull);
    });

    test('a new question abandons the half-finished task', () async {
      await chat.say('Create an FD of 1 lakh');
      final reply = await chat.say("what's my balance?");

      expect(reply.intent, ChatIntent.checkBalance);
      expect(reply.pending, isNull);
    });

    test('explains her balance and free cash', () async {
      final reply = await chat.say("What's my balance?");

      expect(
        reply.text,
        allOf(
          contains('₹1,85,000'),
          contains('₹1,20,000'),
          contains('₹65,000'),
          contains('₹20,000'),
          contains('₹2,20,000'),
          contains('free'),
        ),
      );
    });

    test('breaks down spending and relates it to income', () async {
      final reply = await chat.say('Where is my money going?');

      expect(reply.intent, ChatIntent.spendInsight);
      expect(
        reply.text,
        allOf(
          contains('₹65,000'),
          contains('Rent: ₹28,500 (44%)'),
          contains('Dining: ₹9,400 (14%)'),
          contains('Groceries: ₹8,200 (13%)'),
          contains('mainly because of rent'),
        ),
      );
    });

    test(
      'answers the monthly spending query with the account breakdown',
      () async {
        final reply = await chat.say('How much I spent in this month');

        expect(reply.intent, ChatIntent.spendInsight);
        expect(
          reply.text,
          contains('Your spending totals ₹65,000 this month.'),
        );
        expect(reply.text, contains('Rent: ₹28,500'));
        expect(reply.text, contains('Dining: ₹9,400'));
      },
    );

    test('reports failed transactions from yesterday', () async {
      final reply = await chat.say('Show failed transactions yesterday.');

      expect(reply.intent, ChatIntent.failedTransactions);
      expect(reply.text, 'Failed transactions report');
    });

    test('books a requested FD amount after collecting its tenor', () async {
      final ask = await chat.say('Book an FD for 50,000.');

      expect(ask.intent, ChatIntent.createFd);
      expect(ask.pending?.awaiting, ChatAwaiting.tenor);
      expect(ask.pending?.slots['amount'], 50000);

      final review = await chat.say('12 months');
      expect(review.action?.type, ChatActionType.openFd);
      expect(review.action?.params['depositAmount'], 50000);
      expect(review.action?.params['tenorMonths'], 12);
      expect(review.pending?.awaiting, ChatAwaiting.confirm);

      final confirmation = await chat.say('yes');
      expect(confirmation.execute?.type, ChatActionType.openFd);
    });

    test(
      'warns and asks for a saved payee before a high-value transfer',
      () async {
        final warning = await chat.say('Transfer ₹2 lakh');

        expect(warning.text, contains('identified this transfer as unusual'));
        expect(warning.pending?.awaiting, ChatAwaiting.transferApproval);
        expect(warning.suggestions, contains('Proceed'));

        final choosePayee = await chat.say('Proceed');
        expect(choosePayee.pending?.awaiting, ChatAwaiting.payee);
        expect(choosePayee.suggestions, contains('Jada Winters'));

        final unknown = await chat.say('Someone else');
        expect(unknown.pending?.awaiting, ChatAwaiting.payee);
        expect(unknown.text, contains("couldn't find that recipient"));

        final insufficient = await chat.say('Jada Winters');
        expect(insufficient.action, isNull);
        expect(insufficient.text, contains('₹2,00,000'));
        expect(insufficient.text, contains('₹1,85,000'));
      },
    );

    test('debit limit increase produces a confirmation action', () async {
      final review = await chat.say('Increase my debit card limit.');

      expect(review.action?.type, ChatActionType.updateDebitLimit);
      expect(review.action?.params['currentLimit'], 50000);
      expect(review.action?.params['requestedLimit'], 150000);
      expect(review.pending?.awaiting, ChatAwaiting.confirm);

      final confirmation = await chat.say('yes');
      expect(confirmation.execute?.type, ChatActionType.updateDebitLimit);
    });

    test(
      'answers for one category, and for a category she does not spend on',
      () async {
        final dining = await chat.say('How much do I spend on dining?');
        expect(
          dining.text,
          allOf(contains('₹9,400 on dining'), contains('14%')),
        );

        final gst = await chat.say('How much do I spend on GST?');
        expect(gst.text, contains("don't see any GST spending"));
      },
    );

    test(
      'pays rent from her ledger: payee and usual amount come from her last rent debit',
      () async {
        final reply = await chat.say('Pay my house rent');

        expect(reply.intent, ChatIntent.payBill);
        expect(reply.action!.type, ChatActionType.payBill);
        expect(reply.action!.params, {
          'payee': 'House rent - landlord',
          'amount': 28500.0,
          'category': 'RENT',
        });
        expect(reply.action!, _hasDetail('Balance after', '₹1,56,500'));
        expect(
          reply.action!.details.any((item) => item.label == 'From overdraft'),
          isFalse,
        );

        final landlord = await Conversation(
          ananya(),
        ).say('Send money to my landlord');
        expect(landlord.action!.params['payee'], 'House rent - landlord');
      },
    );

    test('an explicit amount overrides the usual one', () async {
      final reply = await chat.say('Pay 5000 to my landlord');
      expect(reply.action!.params['amount'], 5000);
    });

    test(
      'asks for the amount when there is no history for that payee',
      () async {
        final ask = await chat.say('pay my gst');

        expect(ask.text, 'How much would you like to pay to GST?');
        expect(ask.pending!.awaiting, ChatAwaiting.amount);

        final card = await chat.say('2500');
        expect(card.action!.params, {
          'payee': 'GST',
          'amount': 2500.0,
          'category': 'GST',
        });
      },
    );

    test('asks who to pay when the payee is unclear', () async {
      final reply = await chat.say('I want to send money');

      expect(reply.intent, ChatIntent.payBill);
      expect(reply.text, contains('Who would you like to pay'));
      expect(reply.action, isNull);
      expect(reply.suggestions, contains('Pay my house rent'));
    });

    test(
      'can change the payment amount while it waits for confirmation',
      () async {
        await chat.say('Pay my house rent');
        final changed = await chat.say('make it 3000');
        expect(changed.action!.params['amount'], 3000);
      },
    );

    test(
      'refuses a payment bigger than her funds, with no credit offer to make',
      () async {
        final reply = await chat.say('Pay 5 lakh to my landlord');
        expect(reply.action, isNull);
        expect(reply.text, allOf(contains('₹5,00,000'), contains('₹1,85,000')));
      },
    );

    test(
      'locks the card after confirmation, and knows when it is already locked',
      () async {
        final card = await chat.say('Lock my debit card');
        expect(card.action!.type, ChatActionType.lockCard);
        expect((await chat.say('yes')).execute!.type, ChatActionType.lockCard);

        final locked = await Conversation(
          ananya().copyWith(cardLocked: true),
        ).say('lock my card');
        expect(locked.text, contains('currently locked'));
        expect(locked.action!.type, ChatActionType.unlockCard);
        expect(locked.action!.confirmLabel, 'Unlock card');
        expect(locked.pending!.awaiting, ChatAwaiting.confirm);

        final explicitlyUnlocked = await Conversation(
          ananya(),
        ).say('unlock my debit card');
        expect(explicitlyUnlocked.text, contains('already unlocked'));
        expect(explicitlyUnlocked.action, isNull);
      },
    );

    test('has no credit need and says so', () async {
      final reply = await chat.say('I need a loan');
      expect(reply.intent, ChatIntent.needCredit);
      expect(
        reply.text,
        allOf(contains("You're covered"), contains('₹2,20,000')),
      );
      expect(reply.action, isNull);
    });
  });

  group('Rajesh (business, deficit)', () {
    late Conversation chat;

    setUp(() => chat = Conversation(rajesh()));

    test('greeting warns about the projected shortfall', () async {
      final reply = await chat.say('hello');

      expect(
        reply.text,
        allOf(contains('Rajesh'), contains('short'), contains('₹65,000')),
      );
      expect(reply.suggestions, contains('Can I cover my upcoming payments?'));
    });

    test(
      'full scenario: affordability question → overdraft offer → activation',
      () async {
        final reply = await chat.say(
          'Can I pay my electronics supplier this week?',
        );

        expect(reply.intent, ChatIntent.needCredit);
        expect(
          reply.text,
          allOf(
            contains('₹65,000'),
            contains('Merchant Overdraft Line'),
            contains('₹80,000'),
            contains('11.5%'),
          ),
        );
        expect(reply.action!.type, ChatActionType.activateCredit);
        expect(reply.action!.params, {
          'productType': 'CREDIT_LINE',
          'amount': 80000.0,
          'interestRate': 11.5,
          'tenorMonths': 12,
        });
        expect(reply.action!, _hasDetail('Processing fee', 'Nil'));
        expect(reply.action!, _hasDetail('Approval', 'Pre-approved'));
        expect(reply.pending!.awaiting, ChatAwaiting.confirm);

        final done = await chat.say('yes please');
        expect(done.execute!.type, ChatActionType.activateCredit);
        expect(done.text, contains('activating merchant overdraft line'));
      },
    );

    test(
      'once the overdraft is active the same question gets a reassuring answer',
      () async {
        chat.persona = withCreditLine(rajesh());
        final reply = await chat.say(
          'Can I pay my electronics supplier this week?',
        );

        expect(
          reply.text,
          allOf(contains('₹80,000 of overdraft active'), contains('₹65,000')),
        );
        expect(reply.action, isNull);
      },
    );

    test(
      'a savings question is answered with the credit offer, not an FD',
      () async {
        final reply = await chat.say('what should I do with my savings');
        expect(reply.action!.type, ChatActionType.activateCredit);
      },
    );

    test(
      'payroll is more than the balance: offers the overdraft so it can go through',
      () async {
        final reply = await chat.say('Approve payroll for my 12 employees');

        expect(reply.intent, ChatIntent.needCredit);
        expect(
          reply.text,
          allOf(
            contains('₹54,000'),
            contains('Payroll - 12 employees'),
            contains('₹9,000'),
            contains('Merchant Overdraft Line'),
          ),
        );
        expect(reply.action!.type, ChatActionType.activateCredit);
      },
    );

    test('with the overdraft active, payroll is drawn from it', () async {
      chat.persona = withCreditLine(rajesh());
      final reply = await chat.say('Approve payroll for my 12 employees');

      expect(reply.action!.type, ChatActionType.payBill);
      expect(reply.action!.params['amount'], 54000);
      expect(reply.action!.params['category'], 'PAYROLL');
      expect(reply.action!, _hasDetail('From overdraft', '₹9,000'));
      expect(reply.action!, _hasDetail('Balance after', '-₹9,000'));
      expect(
        reply.text,
        contains('₹9,000 of it will be drawn from your overdraft'),
      );
    });

    test(
      'keeps the balance answer honest about the gap and the line',
      () async {
        final before = await chat.say("what's my balance");
        expect(
          before.text,
          allOf(contains('₹45,000'), contains('short'), contains('₹65,000')),
        );

        chat.persona = withCreditLine(rajesh());
        final after = await chat.say("what's my balance");
        expect(after.text, contains('₹80,000 of overdraft available'));
      },
    );

    test('answers GST from her own ledger', () async {
      final reply = await chat.say('How much should I keep aside for GST?');
      expect(reply.text, allOf(contains('₹12,000 on GST'), contains('4%')));
    });

    test(
      'a fixed deposit uses the business rate and her smaller safe maximum',
      () async {
        final ask = await chat.say('Create an FD');
        expect(
          ask.text,
          allOf(contains('₹35,000'), isNot(contains('recommend'))),
        );
        expect(ask.suggestions, ['₹35,000']);

        final card = await chat.say('30000 for 6 months');
        expect(card.action!.params['interestRate'], 7.5);
        expect(card.action!, _hasDetail('Maturity amount', '₹31,125'));
      },
    );

    test('no FD is possible when nothing is free above the buffer', () async {
      final reply = await Conversation(
        withBalance(rajesh(), 15000),
      ).say('open an fd');
      expect(
        reply.text,
        allOf(contains("don't have free funds"), contains('₹10,000')),
      );
      expect(reply.pending, isNull);
    });

    test('recommend with nothing to offer says so', () async {
      final covered = Conversation(withCreditLine(rajesh()));
      final reply = await covered.say('what should I do with my savings');
      expect(reply.text, contains('credit support'));

      final tight = ananya().copyWith(
        financialSummary: FinancialSummary(
          currentBalance: 20000,
          projectedIncome30D: 10000,
          projectedSpend30D: 10000,
          minimumBuffer: 10000,
        ),
      );
      final small = await Conversation(
        tight,
      ).say('what should I do with my savings');
      expect(small.text, contains("don't have a new offer"));
    });
  });

  group('general behaviour', () {
    test('help, thanks and an unknown message', () async {
      final chat = Conversation(ananya());

      expect((await chat.say('what can you do')).intent, ChatIntent.help);
      expect((await chat.say('thanks')).intent, ChatIntent.thanks);

      final unknown = await chat.say('asdf qwerty');
      expect(unknown.intent, ChatIntent.fallback);
      expect(unknown.suggestions, contains('Pay my house rent'));
    });

    test('an empty message gets the fallback', () async {
      expect(
        (await Conversation(ananya()).say('   ')).intent,
        ChatIntent.fallback,
      );
    });

    test('"no" with nothing pending is a polite cancel', () async {
      final reply = await Conversation(ananya()).say('no');
      expect(reply.intent, ChatIntent.cancel);
    });

    test('can be replaced by another engine through the interface', () async {
      final ChatEngine engine = const RuleBasedChatEngine();
      final reply = await engine.respond(contextFor(ananya()), 'hi');
      expect(reply.intent, ChatIntent.greeting);
    });

    test(
      'suggestions always start with the persona quick-action prompts',
      () async {
        final reply = await Conversation(rajesh()).say('what can you do');
        expect(reply.suggestions.first, 'Approve payroll for my 12 employees');
        expect(reply.suggestions, contains("What's my balance?"));
      },
    );
  });

  group('JSON round trip', () {
    test('replies keep text, card, pending state and execute action', () async {
      final chat = Conversation(ananya());
      final card = await chat.say('Create an FD of 1 lakh for 12 months');
      final confirmed = await chat.say('yes');

      for (final reply in [card, confirmed]) {
        final parsed = ChatReply.fromJson(reply.toJson());
        expect(parsed.text, reply.text);
        expect(parsed.intent, reply.intent);
        expect(parsed.suggestions, reply.suggestions);
        expect(parsed.action?.toJson(), reply.action?.toJson());
        expect(parsed.pending?.toJson(), reply.pending?.toJson());
        expect(parsed.execute?.toJson(), reply.execute?.toJson());
      }
      expect(
        ChatReply.fromJson(card.toJson()).pending!.awaiting,
        ChatAwaiting.confirm,
      );
      expect(
        ChatPending.fromJson(card.pending!.toJson()).action!.type,
        ChatActionType.openFd,
      );
    });
  });
}
