import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/demo_config.dart';
import '../domain/models.dart';
import '../state/booking_notifier.dart';
import '../state/credit_line_notifier.dart';
import '../state/demo_reset.dart';
import '../state/persona_notifier.dart';
import '../state/providers.dart';

/// Presenter-only side panel: switch persona, tune the mock network, and
/// reset the demo to the JSON baseline.
class DemoControlPanelDrawer extends ConsumerWidget {
  const DemoControlPanelDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const colors = selectedDemoColors;
    final personaState = ref.watch(personaProvider);
    final demoSettings = ref.watch(demoSettingsProvider);
    final currentPersona = personaState.selectedPersona;

    final savedBookingsCount = ref.watch(
      fdBookingProvider.select((state) => state.bookings.length),
    );
    final creditProductCount = personaState.personas
        .expand((persona) => persona.holdings)
        .where((holding) => holding.productType != ProductTypes.fixedDeposit)
        .length;

    return Drawer(
      backgroundColor: colors.background,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drawer Header
            Container(
              padding: const EdgeInsets.all(20),
              color: colors.surface,
              child: Row(
                children: [
                  Icon(Icons.tune_rounded, color: colors.accent, size: 28),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Account Settings",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          "Presenter controls",
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                children: [
                  // 1. PERSONA SWITCHER SECTION
                  const _SectionHeader(title: "ACTIVE PERSONA"),
                  const SizedBox(height: 8),
                  ...personaState.personas.map((p) {
                    final isSelected = p.id == currentPersona.id;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.indigo.withValues(alpha: 0.2)
                            : colors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? colors.accent
                              : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        child: ListTile(
                          hoverColor: colors.hover,
                          leading: CircleAvatar(
                            backgroundColor: p.type == PersonaType.salaried
                                ? Colors.blue
                                : Colors.lightBlue,
                            child: Text(
                              p.name[0],
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          title: Text(
                            p.name,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            p.type == PersonaType.salaried
                                ? "Salaried (Surplus)"
                                : "Business (Deficit)",
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          trailing: isSelected
                              ? Icon(Icons.check_circle, color: colors.accent)
                              : null,
                          onTap: () {
                            ref
                                .read(personaProvider.notifier)
                                .selectPersona(p.id);
                            ref.read(fdBookingProvider.notifier).reset();
                            ref.read(creditLineProvider.notifier).reset();
                          },
                        ),
                      ),
                    );
                  }),

                  const SizedBox(height: 20),
                  Divider(color: colors.border),
                  const SizedBox(height: 10),

                  // 2. SYNTHETIC NETWORK LATENCY CONTROLS
                  const _SectionHeader(title: "NETWORK & SIMULATION CONTROLS"),
                  const SizedBox(height: 12),
                  Text(
                    "Simulated Delay: ${demoSettings.simulatedLatencyMs} ms",
                    style: TextStyle(color: colors.textSecondary, fontSize: 13),
                  ),
                  Slider(
                    value: demoSettings.simulatedLatencyMs.toDouble(),
                    min: 0,
                    max: 3000,
                    divisions: 30,
                    activeColor: colors.accent,
                    inactiveColor: colors.border,
                    label: "${demoSettings.simulatedLatencyMs} ms",
                    onChanged: (val) {
                      ref
                          .read(demoSettingsProvider.notifier)
                          .setLatency(val.toInt());
                    },
                  ),
                  SwitchListTile(
                    activeThumbColor: colors.accent,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      "Simulate Failure",
                      style: TextStyle(color: colors.textPrimary, fontSize: 14),
                    ),
                    subtitle: Text(
                      "API requests return a network error",
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    value: demoSettings.simulateFailure,
                    onChanged: (val) {
                      ref
                          .read(demoSettingsProvider.notifier)
                          .setSimulateFailure(val);
                    },
                  ),

                  const SizedBox(height: 20),
                  Divider(color: colors.border),
                  const SizedBox(height: 10),

                  // 3. PERSISTENCE & CACHE MANAGEMENT
                  const _SectionHeader(title: "PERSISTENCE & STORAGE"),
                  const SizedBox(height: 12),
                  _CountRow(label: "Booked FDs", count: savedBookingsCount),
                  const SizedBox(height: 8),
                  _CountRow(
                    label: "Active credit products",
                    count: creditProductCount,
                  ),
                  const SizedBox(height: 14),

                  // RESET DEMO BUTTON
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(
                        0xFFEF4444,
                      ).withValues(alpha: 0.2),
                      foregroundColor: const Color(0xFFEF4444),
                      side: const BorderSide(color: Color(0xFFEF4444)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: const Text(
                      "Restore Default Settings",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: () => resetDemo(context, ref),
                  ),
                ],
              ),
            ),

            // Footer Version Tag
            Container(
              padding: const EdgeInsets.all(16),
              alignment: Alignment.center,
              child: Text(
                "Flutter BFS AI Advisory POC v1.0.0",
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: 10,
                  letterSpacing: 1.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reset the demo and tell the presenter. Shared with the avatar long-press
/// shortcut on the home screen.
Future<void> resetDemo(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  try {
    await ref.read(demoResetProvider)();
    if (navigator.canPop()) navigator.pop();
    messenger.showSnackBar(
      const SnackBar(
        content: Text("Settings restored to defaults."),
        backgroundColor: Colors.green,
      ),
    );
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(
        content: Text("Reset failed: $error"),
        backgroundColor: Colors.red,
      ),
    );
  }
}

class _CountRow extends StatelessWidget {
  final String label;
  final int count;
  const _CountRow({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    const colors = selectedDemoColors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
          ),
          Chip(
            label: Text(
              "$count",
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
            backgroundColor: colors.accent,
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    const colors = selectedDemoColors;
    return Text(
      title,
      style: TextStyle(
        color: colors.textMuted,
        fontSize: 10,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    );
  }
}
