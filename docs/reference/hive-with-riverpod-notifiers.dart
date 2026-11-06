// ==================== PERSISTED PERSONA NOTIFIER ====================

class PersonaNotifier extends StateNotifier<PersonaState> {
  PersonaNotifier()
      : super(PersonaState(
          personas: mockPersonas,
          selectedPersona: mockPersonas.first,
        )) {
    _loadPersistedPersona();
  }

  void _loadPersistedPersona() {
    final savedId = LocalStorageService.getSelectedPersonaId();
    if (savedId != null) {
      final target = state.personas.firstWhere(
        (p) => p.id == savedId,
        orElse: () => state.selectedPersona,
      );
      state = state.copyWith(selectedPersona: target);
    }
  }

  Future<void> selectPersona(String personaId) async {
    final target = state.personas.firstWhere(
      (p) => p.id == personaId,
      orElse: () => state.selectedPersona,
    );
    state = state.copyWith(selectedPersona: target);
    await LocalStorageService.saveSelectedPersonaId(personaId);
  }
}