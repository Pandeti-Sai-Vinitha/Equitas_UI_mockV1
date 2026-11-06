import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/demo_config.dart';
import '../state/booking_notifier.dart';
import '../state/credit_line_notifier.dart';
import '../state/persona_notifier.dart';
import '../widgets/demo_control_panel_drawer.dart';
import 'dynamic_home_canvas.dart';

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSigningIn = false;
  String? _loginError;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_isSigningIn) return;

    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;
    final account = demoLoginAccounts.where(
      (candidate) => candidate.email.toLowerCase() == email,
    );
    if (account.isEmpty || account.first.password != password) {
      setState(() => _loginError = 'Email or password is incorrect.');
      return;
    }

    final personaState = ref.read(personaProvider);
    if (personaState.isLoading) return;
    if (personaState.errorMessage != null) {
      setState(() => _loginError = personaState.errorMessage);
      return;
    }

    final persona = personaState.personas.where(
      (candidate) => candidate.id == account.first.personaId,
    );
    if (persona.isEmpty) {
      setState(() => _loginError = 'No matching account is configured.');
      return;
    }

    setState(() {
      _isSigningIn = true;
      _loginError = null;
    });
    FocusScope.of(context).unfocus();
    final previousPersonaId = personaState.selectedPersona.id;
    await ref.read(personaProvider.notifier).selectPersona(persona.first.id);
    if (!mounted) return;

    final updatedPersonaState = ref.read(personaProvider);
    if (updatedPersonaState.errorMessage != null) {
      setState(() {
        _isSigningIn = false;
        _loginError = updatedPersonaState.errorMessage;
      });
      return;
    }
    if (updatedPersonaState.selectedPersona.id != account.first.personaId) {
      setState(() {
        _isSigningIn = false;
        _loginError = 'Unable to open your account. Please try again.';
      });
      return;
    }

    if (previousPersonaId != account.first.personaId) {
      ref.read(fdBookingProvider.notifier).reset();
      ref.read(creditLineProvider.notifier).reset();
    }

    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const DynamicHomeCanvas()),
    );
  }

  @override
  Widget build(BuildContext context) {
    const colors = selectedDemoColors;
    final personaState = ref.watch(personaProvider);

    return Scaffold(
      backgroundColor: colors.background,
      endDrawer: const DemoControlPanelDrawer(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: colors.accent,
                    child: const Icon(
                      Icons.account_balance_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Equitas',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Builder(
                    builder: (context) => IconButton(
                      key: const Key('welcome_menu'),
                      tooltip: 'Menu',
                      icon: Icon(
                        Icons.tune_rounded,
                        color: colors.textSecondary,
                      ),
                      onPressed: () => Scaffold.of(context).openEndDrawer(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 52),
              Text(
                'Banking that\nunderstands you.',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 34,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Sign in to access your personalized banking experience.',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              TextField(
                key: const Key('login_email'),
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Email',
                  labelStyle: TextStyle(color: colors.textSecondary),
                  prefixIcon: Icon(Icons.email_outlined, color: colors.accent),
                  filled: true,
                  fillColor: colors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: colors.border),
                  ),
                ),
                style: TextStyle(color: colors.textPrimary),
                onChanged: (_) => _clearLoginError(),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('login_password'),
                controller: _passwordController,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _signIn(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  labelStyle: TextStyle(color: colors.textSecondary),
                  prefixIcon: Icon(Icons.lock_outline, color: colors.accent),
                  filled: true,
                  fillColor: colors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: colors.border),
                  ),
                ),
                style: TextStyle(color: colors.textPrimary),
                onChanged: (_) => _clearLoginError(),
              ),
              if (_loginError != null) ...[
                const SizedBox(height: 12),
                Text(
                  _loginError!,
                  key: const Key('login_error'),
                  style: const TextStyle(color: Color(0xFFEF4444)),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  key: const Key('login_submit'),
                  onPressed: personaState.isLoading || _isSigningIn
                      ? null
                      : _signIn,
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isSigningIn || personaState.isLoading
                      ? const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                              semanticsLabel: 'Preparing account',
                            ),
                          ),
                        )
                      : const Text(
                          'Sign In',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _clearLoginError() {
    if (_loginError != null) setState(() => _loginError = null);
  }
}
