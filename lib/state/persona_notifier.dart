import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/exceptions.dart';
import '../data/banking_repository.dart';
import '../data/hive_storage.dart';
import '../domain/mock_persona_datasets.dart';
import '../domain/models.dart';
import 'providers.dart';

class PersonaState {
  final List<Persona> personas;
  final Persona selectedPersona;
  final bool isLoading;
  final String? errorMessage;

  PersonaState({
    required this.personas,
    required this.selectedPersona,
    this.isLoading = false,
    this.errorMessage,
  });

  PersonaState copyWith({
    List<Persona>? personas,
    Persona? selectedPersona,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return PersonaState(
      personas: personas ?? this.personas,
      selectedPersona: selectedPersona ?? this.selectedPersona,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class PersonaNotifier extends StateNotifier<PersonaState> {
  final BankingRepository _repository;
  final LocalStorageService _storage;

  PersonaNotifier(this._repository, this._storage)
      : super(PersonaState(
          personas: mockPersonas,
          selectedPersona: mockPersonas.first,
          isLoading: true,
        )) {
    _loadPersonas();
  }

  Future<void> _loadPersonas() async {
    try {
      final personas = await _repository.loadPersonas();
      if (personas.isEmpty) {
        throw StateError('No personas were found in local storage.');
      }

      final savedId = _storage.getSelectedPersonaId();
      final selectedPersona = personas.firstWhere(
        (persona) => persona.id == savedId,
        orElse: () => personas.firstWhere(
          (persona) => persona.id == 'p_salaried_01',
          orElse: () => personas.first,
        ),
      );
      if (savedId != selectedPersona.id) {
        try {
          await _storage.saveSelectedPersonaId(selectedPersona.id);
        } catch (_) {
          // Selection still proceeds even if persistence fails.
        }
      }
      if (!mounted) return;
      state = state.copyWith(
        personas: personas,
        selectedPersona: selectedPersona,
        isLoading: false,
        clearError: true,
      );
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load persona data: ${describeError(error)}',
      );
    }
  }

  Future<void> selectPersona(String personaId) async {
    final target = state.personas.firstWhere(
      (persona) => persona.id == personaId,
      orElse: () => state.selectedPersona,
    );
    if (target.id == state.selectedPersona.id) return;

    state = state.copyWith(selectedPersona: target, clearError: true);
    try {
      await _storage.saveSelectedPersonaId(target.id);
    } catch (error) {
      state = state.copyWith(
        errorMessage: 'Failed to save the selected persona: ${describeError(error)}',
      );
    }
  }

  Future<void> refreshPersonas() async {
    state = state.copyWith(isLoading: true, clearError: true);
    await _loadPersonas();
  }
}

final personaProvider = StateNotifierProvider<PersonaNotifier, PersonaState>((ref) {
  return PersonaNotifier(
    ref.watch(bankingRepositoryProvider),
    ref.watch(localStorageProvider),
  );
});

final recommendationsProvider = FutureProvider<List<ProductRecommendation>>((ref) {
  final selectedPersona = ref.watch(
    personaProvider.select((state) => state.selectedPersona),
  );
  return ref.watch(bankingRepositoryProvider).loadRecommendations(selectedPersona.id);
});
