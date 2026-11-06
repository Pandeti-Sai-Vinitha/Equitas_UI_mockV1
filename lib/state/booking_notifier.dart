import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/exceptions.dart';
import '../data/banking_repository.dart';
import '../domain/fixed_deposit.dart';
import 'persona_notifier.dart';
import 'providers.dart';

enum FDBookingStatus { initial, loading, success, error }

class FDBookingState {
  final FDBookingStatus status;
  final FDApplication? bookingResult;
  final String? errorMessage;
  final List<FDApplication> bookings;
  final bool isLoadingBookings;

  FDBookingState({
    this.status = FDBookingStatus.initial,
    this.bookingResult,
    this.errorMessage,
    this.bookings = const [],
    this.isLoadingBookings = false,
  });

  FDBookingState copyWith({
    FDBookingStatus? status,
    FDApplication? bookingResult,
    String? errorMessage,
    List<FDApplication>? bookings,
    bool? isLoadingBookings,
    bool clearBookingResult = false,
    bool clearError = false,
  }) {
    return FDBookingState(
      status: status ?? this.status,
      bookingResult: clearBookingResult ? null : bookingResult ?? this.bookingResult,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      bookings: bookings ?? this.bookings,
      isLoadingBookings: isLoadingBookings ?? this.isLoadingBookings,
    );
  }
}

class FDBookingNotifier extends StateNotifier<FDBookingState> {
  final BankingRepository _repository;

  /// Called after a successful booking so account views can reload the
  /// debited balance and recomputed offers.
  final Future<void> Function()? _onBooked;

  FDBookingNotifier(this._repository, {Future<void> Function()? onBooked})
      : _onBooked = onBooked,
        super(FDBookingState(isLoadingBookings: true)) {
    _loadSavedBookings();
  }

  Future<void> _loadSavedBookings() async {
    try {
      final bookings = await _repository.loadFdBookings()
        ..sort((first, second) => second.createdAt.compareTo(first.createdAt));
      if (!mounted) return;
      state = state.copyWith(bookings: bookings, isLoadingBookings: false);
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(
        isLoadingBookings: false,
        errorMessage: 'Failed to load saved FD bookings: ${describeError(error)}',
      );
    }
  }

  Future<void> bookFixedDeposit({
    required String personaId,
    required double depositAmount,
    required int tenorMonths,
    required double interestRate,
    required InterestPayout payoutOption,
    required bool autoRenew,
  }) async {
    state = state.copyWith(
      status: FDBookingStatus.loading,
      clearError: true,
    );

    try {
      final booking = await _repository.bookFixedDeposit(
        personaId: personaId,
        depositAmount: depositAmount,
        tenorMonths: tenorMonths,
        interestRate: interestRate,
        payoutOption: payoutOption,
        autoRenew: autoRenew,
      );
      if (!mounted) return;
      state = state.copyWith(
        status: FDBookingStatus.success,
        bookingResult: booking,
        bookings: [booking, ...state.bookings],
        clearError: true,
      );
      await _onBooked?.call();
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(
        status: FDBookingStatus.error,
        errorMessage: 'Failed to book or save Fixed Deposit: ${describeError(error)}',
      );
    }
  }

  void reset() {
    state = state.copyWith(
      status: FDBookingStatus.initial,
      clearBookingResult: true,
      clearError: true,
    );
  }
}

final fdBookingProvider = StateNotifierProvider<FDBookingNotifier, FDBookingState>((ref) {
  return FDBookingNotifier(
    ref.watch(bankingRepositoryProvider),
    onBooked: () => ref.read(personaProvider.notifier).refreshPersonas(),
  );
});

/// The selected persona's bookings, newest first.
final personaBookingsProvider = Provider<List<FDApplication>>((ref) {
  final personaId = ref.watch(personaProvider.select((state) => state.selectedPersona.id));
  return ref
      .watch(fdBookingProvider.select((state) => state.bookings))
      .where((booking) => booking.personaId == personaId)
      .toList();
});
