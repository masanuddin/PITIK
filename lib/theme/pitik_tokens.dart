// Token desain PITIK (redesign 2026-10, referensi Claude Design export).
// Dipakai EKSPLISIT oleh widget yang sudah di-redesign; ThemeData global
// tidak diubah, sehingga Login/OTP dan tab yang belum di-redesign tetap sama.
// lib/theme/pitik_tokens.dart

import 'package:flutter/material.dart';

abstract final class PitikColors {
  // Permukaan & teks
  static const Color background = Color(0xFFF3F4F6);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF5F6F8);
  static const Color border = Color(0xFFE6E8EC);
  static const Color divider = Color(0xFFEEF0F3);
  static const Color text = Color(0xFF111827);

  /// Teks penting sekunder & nilai "data terakhir" (tetap terbaca, tidak redup).
  static const Color textMuted = Color(0xFF374151);
  static const Color textSecondary = Color(0xFF4B5563);
  static const Color navInactive = Color(0xFF6B7280);

  // Aksen (biru PITIK, lebih gelap dari #007AFF agar lolos kontras AA)
  static const Color accent = Color(0xFF2F62D9);
  static const Color accentPressed = Color(0xFF2450B8);
  static const Color accentSoft = Color(0xFFEEF3FE);
  static const Color accentSoftBorder = Color(0xFFD5E0FA);
  static const Color accentTint = Color(0xFFE8EFFD);

  // Status
  static const Color success = Color(0xFF1E7B3A);
  static const Color successStrong = Color(0xFF17692F);
  static const Color successBg = Color(0xFFE6F4EA);
  static const Color successSurface = Color(0xFFF0F9F2);
  static const Color successBorder = Color(0xFFCFEBD6);
  static const Color successIconBg = Color(0xFFDCF1E1);
  static const Color successDot = Color(0xFF2EA350);

  static const Color warning = Color(0xFF8A5100);
  static const Color warningStrong = Color(0xFF6B4100);
  static const Color warningBg = Color(0xFFFFF1D6);
  static const Color warningSurface = Color(0xFFFFF7E8);
  static const Color warningBorder = Color(0xFFF1DDB0);
  static const Color warningIconBg = Color(0xFFFCE9C4);

  static const Color danger = Color(0xFFB42318);
  static const Color dangerStrong = Color(0xFFA8281E);
  static const Color dangerBg = Color(0xFFFDECEA);
  static const Color dangerSurface = Color(0xFFFDF1EF);
  static const Color dangerBorder = Color(0xFFF3C6BF);
  static const Color dangerIconBg = Color(0xFFFBE0DB);
  static const Color dangerIcon = Color(0xFFC8372B);
  static const Color dangerText = Color(0xFF4A2520);
  static const Color dangerDot = Color(0xFFE5483B);

  static const Color neutralBg = Color(0xFFEEF0F3);

  // Warna sensor (ikon & tint)
  static const Color temp = Color(0xFFEF8A17);
  static const Color tempBg = Color(0xFFFFF3E0);
  static const Color humidity = Color(0xFF3B7BF2);
  static const Color humidityBg = Color(0xFFE8F0FE);
  static const Color thi = Color(0xFF5A55D6);
  static const Color thiBg = Color(0xFFEEEDFC);
  static const Color ammonia = Color(0xFF43A85A);
  static const Color ammoniaBg = Color(0xFFE7F6EA);

  // Zona gauge THI & legenda
  static const Color zoneNormal = Color(0xFFD6EFDC);
  static const Color zoneNormalEdge = Color(0xFF5DBB72);
  static const Color zoneWarning = Color(0xFFFBE6BF);
  static const Color zoneWarningEdge = Color(0xFFE9A23B);
  static const Color zoneDanger = Color(0xFFF8D2CC);
  static const Color zoneDangerEdge = Color(0xFFE06456);
  static const Color arcNormal = Color(0xFF2E9D4F);
  static const Color arcWarning = Color(0xFFD98A1C);
  static const Color arcDanger = Color(0xFFD93D30);
  static const Color arcMuted = Color(0xFF9CA3AF);
}

abstract final class PitikRadius {
  static const double card = 20;
  static const double tile = 14;
  static const double control = 12;
  static const double chip = 8;
}

abstract final class PitikSpace {
  static const double page = 16;
  static const double gap = 12;
  static const double card = 16;

  /// Target sentuh minimum.
  static const double touch = 48;
}

abstract final class PitikText {
  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  static const TextStyle pageTitle = TextStyle(
      fontSize: 24, fontWeight: FontWeight.w700, height: 1.15,
      letterSpacing: -0.24, color: PitikColors.text);
  static const TextStyle cardTitle = TextStyle(
      fontSize: 18, fontWeight: FontWeight.w700, height: 1.3,
      color: PitikColors.text);
  static const TextStyle body = TextStyle(
      fontSize: 15, height: 1.45, color: PitikColors.textSecondary);
  static const TextStyle bodyStrong = TextStyle(
      fontSize: 15, fontWeight: FontWeight.w700, height: 1.35,
      color: PitikColors.text);
  static const TextStyle label = TextStyle(
      fontSize: 15, fontWeight: FontWeight.w500, height: 1.25,
      color: PitikColors.textSecondary);
  static const TextStyle caption = TextStyle(
      fontSize: 14, height: 1.35, color: PitikColors.textSecondary);
  static const TextStyle metricValue = TextStyle(
      fontSize: 34, fontWeight: FontWeight.w700, height: 1.05,
      letterSpacing: -0.34, fontFeatures: _tabular);
  static const TextStyle metricUnit = TextStyle(
      fontSize: 18, fontWeight: FontWeight.w500,
      color: PitikColors.textSecondary);
  static const TextStyle chip = TextStyle(
      fontSize: 14, fontWeight: FontWeight.w700, height: 1.2);
  static const TextStyle tabular = TextStyle(fontFeatures: _tabular);
}

abstract final class PitikMotion {
  static const Duration press = Duration(milliseconds: 120);
  static const Duration reveal = Duration(milliseconds: 180);

  /// Pengaturan "kurangi animasi" dari sistem.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  static Duration of(BuildContext context, Duration d) =>
      reduced(context) ? Duration.zero : d;
}

abstract final class PitikDecor {
  static const List<BoxShadow> cardShadow = [
    BoxShadow(color: Color(0x0A101828), blurRadius: 2, offset: Offset(0, 1)),
  ];

  static BoxDecoration card({
    Color color = PitikColors.surface,
    Color border = PitikColors.border,
    bool shadow = true,
  }) =>
      BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(PitikRadius.card),
        border: Border.all(color: border),
        boxShadow: shadow ? cardShadow : null,
      );
}
