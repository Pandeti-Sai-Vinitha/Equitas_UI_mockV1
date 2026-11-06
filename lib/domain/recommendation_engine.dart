import '../core/format.dart';
import '../core/demo_currency.dart';
import '../core/demo_config.dart';
import 'models.dart';

/// A bank product as described in `product_catalogue.json`.
class CatalogueProduct {
  final String productId;
  final String recommendationId;
  final List<String> segments;
  final ProductCategory category;
  final ActionType actionType;
  final String title;
  final String descriptionTemplate;
  final double rate;
  final Map<String, dynamic> terms;

  const CatalogueProduct({
    required this.productId,
    required this.recommendationId,
    required this.segments,
    required this.category,
    required this.actionType,
    required this.title,
    required this.descriptionTemplate,
    required this.rate,
    this.terms = const {},
  });

  factory CatalogueProduct.fromJson(Map<String, dynamic> json) {
    return CatalogueProduct(
      productId: json['productId'] as String,
      recommendationId: json['recommendationId'] as String,
      segments: (json['segments'] as List<dynamic>).cast<String>(),
      category: (json['category'] as String).toProductCategory(),
      actionType: (json['actionType'] as String).toActionType(),
      title: json['title'] as String,
      descriptionTemplate: json['descriptionTemplate'] as String,
      rate: (json['rate'] as num).toDouble(),
      terms: Map<String, dynamic>.from(json['terms'] as Map? ?? const {}),
    );
  }

  double _term(String key, double fallback) =>
      (terms[key] as num?)?.toDouble() ?? fallback;
}

/// Turns a persona's cash-flow profile into product offers.
///
/// - Surplus → the segment's FD, sized to a share of the surplus.
/// - Deficit → the segment's credit product, sized to cover the gap plus a
///   buffer, unless the customer already holds that product.
class RecommendationEngine {
  final List<CatalogueProduct> catalogue;
  final DemoCurrency currency;

  const RecommendationEngine(
    this.catalogue, {
    this.currency = selectedDemoCurrency,
  });

  factory RecommendationEngine.fromCatalogueJson(
    Map<String, dynamic> data, {
    DemoCurrency currency = selectedDemoCurrency,
  }) {
    return RecommendationEngine(
      (data['products'] as List<dynamic>).map((item) {
        final product = Map<String, dynamic>.from(item as Map);
        final terms = Map<String, dynamic>.from(product['terms'] as Map);
        for (final key in ['minAmount', 'deficitBuffer', 'roundTo']) {
          final amount = terms[key];
          if (amount is num) {
            terms[key] = key == 'roundTo'
                ? currency.scaleCatalogueAmount(amount)
                : currency.scaleAmount(amount);
          }
        }
        product['terms'] = terms;
        product['rate'] = switch (product['productId']) {
          'FD_RETAIL' => currency.fixedDepositRate,
          'FD_BUSINESS' => currency.businessDepositRate,
          'MERCHANT_OD' => currency.overdraftRate,
          'PERSONAL_LOAN' => currency.personalLoanRate,
          _ => product['rate'],
        };
        return CatalogueProduct.fromJson(product);
      }).toList(),
      currency: currency,
    );
  }

  List<ProductRecommendation> recommend(Persona persona) {
    final segment = persona.type.name.toUpperCase();
    final summary = persona.financialSummary;
    final recommendations = <ProductRecommendation>[];

    for (final product in catalogue.where(
      (item) => item.segments.contains(segment),
    )) {
      final recommendation = switch (product.category) {
        ProductCategory.investment when summary.netAvailableForInvestment > 0 =>
          _investment(product, summary.netAvailableForInvestment),
        ProductCategory.credit when summary.projectedDeficit > 0 => _credit(
          product,
          persona,
          summary.projectedDeficit,
        ),
        _ => null,
      };
      if (recommendation != null) recommendations.add(recommendation);
    }
    return recommendations;
  }

  ProductRecommendation? _investment(CatalogueProduct product, double surplus) {
    final amount = _roundDown(
      surplus * product._term('surplusShare', 0.7),
      product._term('roundTo', 1000),
    );
    if (amount < product._term('minAmount', 0)) return null;
    return _build(product, amount, surplus: surplus);
  }

  ProductRecommendation? _credit(
    CatalogueProduct product,
    Persona persona,
    double deficit,
  ) {
    final productType = product.terms['productType'] as String?;
    if (productType != null && persona.holdsProduct(productType)) return null;
    final amount = _roundUp(
      deficit + product._term('deficitBuffer', 0),
      product._term('roundTo', 1000),
    );
    return _build(product, amount, deficit: deficit);
  }

  ProductRecommendation _build(
    CatalogueProduct product,
    double amount, {
    double surplus = 0,
    double deficit = 0,
  }) {
    return ProductRecommendation(
      id: product.recommendationId,
      title: product.title,
      description: product.descriptionTemplate
          .replaceAll('{surplus}', formatMoney(surplus, currency: currency))
          .replaceAll('{deficit}', formatMoney(deficit, currency: currency))
          .replaceAll('{amount}', formatMoney(amount, currency: currency)),
      category: product.category,
      actionType: product.actionType,
      recommendedAmount: amount,
      expectedReturnOrInterestRate: product.rate,
      metadata: {'productId': product.productId, ...product.terms},
    );
  }

  static double _roundDown(double value, double step) =>
      (value / step).floor() * step;

  static double _roundUp(double value, double step) =>
      (value / step).ceil() * step;
}
