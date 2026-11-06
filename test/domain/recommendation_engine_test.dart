import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:mock2/core/demo_currency.dart';
import 'package:mock2/domain/models.dart';
import 'package:mock2/domain/recommendation_engine.dart';

RecommendationEngine _engine() {
  final envelope =
      jsonDecode(
            File('lib/mock_data/product_catalogue.json').readAsStringSync(),
          )
          as Map;
  return RecommendationEngine.fromCatalogueJson(
    Map<String, dynamic>.from(envelope['data'] as Map),
  );
}

Persona _persona({
  required PersonaType type,
  required double balance,
  required double income,
  required double spend,
  required double buffer,
  List<Holding> holdings = const [],
}) {
  return Persona(
    id: 'p',
    name: 'P',
    occupation: 'O',
    type: type,
    avatarUrl: '',
    financialSummary: FinancialSummary(
      currentBalance: balance,
      projectedIncome30D: income,
      projectedSpend30D: spend,
      minimumBuffer: buffer,
    ),
    holdings: holdings,
  );
}

void main() {
  final engine = _engine();

  test('salaried surplus → FD for 70% of surplus rounded down to ₹5,000', () {
    final ananya = _persona(
      type: PersonaType.salaried,
      balance: 185000,
      income: 120000,
      spend: 65000,
      buffer: 20000,
    );

    final recommendation = engine.recommend(ananya).single;

    expect(recommendation.id, 'rec_fd_01');
    expect(recommendation.actionType, ActionType.openFD);
    expect(recommendation.recommendedAmount, 150000);
    expect(recommendation.expectedReturnOrInterestRate, 7.2);
    expect(recommendation.description, contains('₹2,20,000'));
    expect(recommendation.metadata['defaultTenorMonths'], 12);
    expect(recommendation.metadata['payoutOption'], 'AT_MATURITY');
    expect(recommendation.metadata['productId'], 'FD_RETAIL');
  });

  test('uses localized product thresholds and rates for USD and GBP', () {
    final envelope =
        jsonDecode(
              File('lib/mock_data/product_catalogue.json').readAsStringSync(),
            )
            as Map;
    final data = Map<String, dynamic>.from(envelope['data'] as Map);
    final usdEngine = RecommendationEngine.fromCatalogueJson(
      data,
      currency: DemoCurrency.usd,
    );
    final usdRecommendation = usdEngine
        .recommend(
          _persona(
            type: PersonaType.salaried,
            balance: 9250,
            income: 6000,
            spend: 3250,
            buffer: 1000,
          ),
        )
        .single;
    expect(usdRecommendation.recommendedAmount, 7500);
    expect(usdRecommendation.expectedReturnOrInterestRate, 4.5);
    expect(usdRecommendation.description, contains(r'$11,000'));

    final gbpEngine = RecommendationEngine.fromCatalogueJson(
      data,
      currency: DemoCurrency.gbp,
    );
    final gbpRecommendation = gbpEngine
        .recommend(
          _persona(
            type: PersonaType.salaried,
            balance: 5550,
            income: 3600,
            spend: 1950,
            buffer: 600,
          ),
        )
        .single;
    expect(gbpRecommendation.recommendedAmount, 4500);
    expect(gbpRecommendation.expectedReturnOrInterestRate, 4.2);
    expect(gbpRecommendation.description, contains('£6,600'));
  });

  test('offer recomputes after the balance drops', () {
    final afterBooking = _persona(
      type: PersonaType.salaried,
      balance: 35000,
      income: 120000,
      spend: 65000,
      buffer: 20000,
    );

    final recommendation = engine.recommend(afterBooking).single;
    expect(recommendation.recommendedAmount, 45000);
    expect(recommendation.description, contains('₹70,000'));
  });

  test('surplus below the product minimum gets no FD offer', () {
    final small = _persona(
      type: PersonaType.salaried,
      balance: 25000,
      income: 10000,
      spend: 10000,
      buffer: 20000,
    );
    expect(engine.recommend(small), isEmpty);
  });

  test('business deficit → overdraft covering the gap plus buffer', () {
    final rajesh = _persona(
      type: PersonaType.business,
      balance: 45000,
      income: 210000,
      spend: 310000,
      buffer: 10000,
    );

    final recommendation = engine.recommend(rajesh).single;

    expect(recommendation.id, 'rec_credit_01');
    expect(recommendation.actionType, ActionType.flexiCreditLine);
    expect(recommendation.category, ProductCategory.credit);
    expect(recommendation.recommendedAmount, 80000);
    expect(recommendation.expectedReturnOrInterestRate, 11.5);
    expect(recommendation.description, contains('₹65,000'));
    expect(recommendation.metadata['productType'], ProductTypes.creditLine);
  });

  test('no credit offer once the customer holds that product', () {
    final rajesh = _persona(
      type: PersonaType.business,
      balance: 45000,
      income: 210000,
      spend: 310000,
      buffer: 10000,
      holdings: const [
        Holding(
          id: 'CL_1',
          productType: 'CREDIT_LINE',
          amount: 80000,
          rate: 11.5,
        ),
      ],
    );
    expect(engine.recommend(rajesh), isEmpty);
  });

  test('salaried deficit → personal loan; business surplus → business FD', () {
    final stretched = _persona(
      type: PersonaType.salaried,
      balance: 5000,
      income: 60000,
      spend: 80000,
      buffer: 10000,
    );
    final loan = engine.recommend(stretched).single;
    expect(loan.actionType, ActionType.applyLoan);
    expect(loan.recommendedAmount, 40000);

    final cashRich = _persona(
      type: PersonaType.business,
      balance: 300000,
      income: 200000,
      spend: 150000,
      buffer: 50000,
    );
    final fd = engine.recommend(cashRich).single;
    expect(fd.expectedReturnOrInterestRate, 7.5);
    expect(fd.recommendedAmount, 180000);
    expect(fd.metadata['defaultTenorMonths'], 6);
  });

  test('recommendations round-trip through JSON', () {
    final rajesh = _persona(
      type: PersonaType.business,
      balance: 45000,
      income: 210000,
      spend: 310000,
      buffer: 10000,
    );
    final original = engine.recommend(rajesh).single;
    final parsed = ProductRecommendation.fromJson(original.toJson());

    expect(parsed.actionType, original.actionType);
    expect(parsed.category, original.category);
    expect(parsed.recommendedAmount, original.recommendedAmount);
  });
}
