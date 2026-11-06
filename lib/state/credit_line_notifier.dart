import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/exceptions.dart';
import '../data/banking_repository.dart';
import '../domain/credit_line.dart';
import '../domain/models.dart';
import 'persona_notifier.dart';
import 'providers.dart';

enum CreditActivationStatus { initial, loading, success, error }

class CreditLineState {
  final CreditActivationStatus status;
  final CreditLine? result;
  final String? errorMessage;

  const CreditLineState({
    this.status = CreditActivationStatus.initial,
    this.result,
    this.errorMessage,
  });
}

/// Activates the overdraft line or personal loan offered in a credit
/// recommendation.
class CreditLineNotifier extends StateNotifier<CreditLineState> {
  final BankingRepository _repository;
  final Future<void> Function()? _onActivated;

  CreditLineNotifier(this._repository, {Future<void> Function()? onActivated})
      : _onActivated = onActivated,
        super(const CreditLineState());

  Future<void> activate({
    required String personaId,
    required ProductRecommendation recommendation,
  }) async {
    return activateWith(
      personaId: personaId,
      productType: recommendation.metadata['productType'] as String? ??
          (recommendation.actionType == ActionType.applyLoan
              ? ProductTypes.personalLoan
              : ProductTypes.creditLine),
      amount: recommendation.recommendedAmount,
      interestRate: recommendation.expectedReturnOrInterestRate,
      tenorMonths: recommendation.metadata['defaultTenorMonths'] as int? ?? 12,
    );
  }

  /// Activation from explicit terms, e.g. a confirmed chat card.
  Future<void> activateWith({
    required String personaId,
    required String productType,
    required double amount,
    required double interestRate,
    required int tenorMonths,
  }) async {
    state = const CreditLineState(status: CreditActivationStatus.loading);
    try {
      final creditLine = await _repository.activateCredit(
        personaId: personaId,
        productType: productType,
        amount: amount,
        interestRate: interestRate,
        tenorMonths: tenorMonths,
      );
      if (!mounted) return;
      state = CreditLineState(status: CreditActivationStatus.success, result: creditLine);
      await _onActivated?.call();
    } catch (error) {
      if (!mounted) return;
      state = CreditLineState(
        status: CreditActivationStatus.error,
        errorMessage: 'Failed to activate credit: ${describeError(error)}',
      );
    }
  }

  void reset() => state = const CreditLineState();
}

final creditLineProvider = StateNotifierProvider<CreditLineNotifier, CreditLineState>((ref) {
  return CreditLineNotifier(
    ref.watch(bankingRepositoryProvider),
    onActivated: () => ref.read(personaProvider.notifier).refreshPersonas(),
  );
});
