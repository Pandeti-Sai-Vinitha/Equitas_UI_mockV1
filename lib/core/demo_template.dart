import 'package:flutter/material.dart';

enum DemoTemplate { dark, light }

class DemoTemplateColors {
  final Color background;
  final Color surface;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color border;
  final Color accent;
  final Color hover;
  final Color subtleBorder;

  const DemoTemplateColors({
    required this.background,
    required this.surface,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.border,
    required this.accent,
    required this.hover,
    required this.subtleBorder,
  });

  static const dark = DemoTemplateColors(
    background: Color(0xFF0F172A),
    surface: Color(0xFF1E293B),
    textPrimary: Colors.white,
    textSecondary: Color(0xFF94A3B8),
    textMuted: Color(0xFF64748B),
    border: Color(0xFF334155),
    accent: Colors.indigoAccent,
    hover: Color(0xFF334155),
    subtleBorder: Color(0x0DFFFFFF),
  );

  static const light = DemoTemplateColors(
    background: Color(0xFFF8FAFC),
    surface: Colors.white,
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF475569),
    textMuted: Color(0xFF64748B),
    border: Color(0xFF2563EB),
    accent: Color(0xFF2563EB),
    hover: Color(0xFFEFF6FF),
    subtleBorder: Color(0xFFBFDBFE),
  );
}
