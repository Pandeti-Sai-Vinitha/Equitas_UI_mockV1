// ==================== PERSISTED FD BOOKING NOTIFIER ====================

class FDBookingNotifier extends StateNotifier<FDBookingState> {
  FDBookingNotifier() : super(FDBookingState());

  Future<void> bookFixedDeposit({
    required String personaId,
    required double depositAmount,
    required int tenorMonths,
    required double interestRate,
    required InterestPayout payoutOption,
    required bool autoRenew,
  }) async {
    state = state.copyWith(status: FDBookingStatus.loading, errorMessage: null);

    try {
      await Future.delayed(const Duration(seconds: 1.5)); // Simulated API latency

      final booking = FDApplication(
        id: 'FD_${DateTime.now().millisecondsSinceEpoch}',
        personaId: personaId,
        depositAmount: depositAmount,
        tenorMonths: tenorMonths,
        interestRate: interestRate,
        payoutOption: payoutOption,
        autoRenew: autoRenew,
        createdAt: DateTime.now(),
      );

      // Serialize and save to Hive
      final bookingJson = {
        'id': booking.id,
        'personaId': booking.personaId,
        'depositAmount': booking.depositAmount,
        'tenorMonths': booking.tenorMonths,
        'interestRate': booking.interestRate,
        'payoutOption': booking.payoutOption.toString(),
        'autoRenew': booking.autoRenew,
        'createdAt': booking.createdAt.toIso8601String(),
        'maturityAmount': booking.maturityAmount,
      };

      await LocalStorageService.saveFDBooking(bookingJson);

      state = state.copyWith(
        status: FDBookingStatus.success,
        bookingResult: booking,
      );
    } catch (e) {
      state = state.copyWith(
        status: FDBookingStatus.error,
        errorMessage: 'Failed to persist FD: ${e.toString()}',
      );
    }
  }
}