// Verifikasi kontras token redesign (WCAG 2.1: teks normal ≥ 4.5:1).
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitik_app/theme/pitik_tokens.dart';
import 'package:pitik_app/widgets/status_chip.dart';

double _lum(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  final hi = math.max(la, lb), lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  const white = Colors.white;

  void aa(String name, Color fg, Color bg) {
    final r = contrast(fg, bg);
    expect(r, greaterThanOrEqualTo(4.5),
        reason: '$name: ${r.toStringAsFixed(2)}:1 < 4.5:1');
  }

  test('aksen #2F62D9 di semua latar aktual & sebagai isi tombol', () {
    aa('accent / surface', PitikColors.accent, PitikColors.surface);
    aa('accent / background', PitikColors.accent, PitikColors.background);
    aa('accent / accentSoft (tombol tonal)', PitikColors.accent,
        PitikColors.accentSoft);
    aa('accent / accentTint (tab aktif)', PitikColors.accent,
        PitikColors.accentTint);
    aa('putih / accent (isi tombol)', white, PitikColors.accent);
    aa('putih / accentPressed', white, PitikColors.accentPressed);
  });

  test('aksen lama #007AFF memang di bawah AA (alasan penggantian)', () {
    expect(contrast(const Color(0xFF007AFF), white), lessThan(4.5));
  });

  test('teks utama & sekunder di semua permukaan', () {
    for (final bg in [
      PitikColors.surface,
      PitikColors.background,
      PitikColors.surfaceMuted,
    ]) {
      aa('text', PitikColors.text, bg);
      aa('textMuted', PitikColors.textMuted, bg);
      aa('textSecondary', PitikColors.textSecondary, bg);
    }
    aa('navInactive / surface', PitikColors.navInactive, PitikColors.surface);
    aa('textMuted / neutralBg', PitikColors.textMuted, PitikColors.neutralBg);
  });

  test('badge: foreground di atas background tiap tone', () {
    for (final t in PitikTone.values) {
      aa('badge $t', t.foreground, t.background);
      aa('chip solid $t (teks putih)', white, t.solid);
    }
  });

  test('kartu status & banner', () {
    aa('successStrong / successSurface', PitikColors.successStrong,
        PitikColors.successSurface);
    aa('textSecondary / successSurface', PitikColors.textSecondary,
        PitikColors.successSurface);
    aa('warningStrong / warningSurface', PitikColors.warningStrong,
        PitikColors.warningSurface);
    aa('dangerStrong / dangerSurface', PitikColors.dangerStrong,
        PitikColors.dangerSurface);
    aa('dangerText / dangerSurface', PitikColors.dangerText,
        PitikColors.dangerSurface);
    aa('danger / surface', PitikColors.danger, PitikColors.surface);
    aa('success / surface', PitikColors.success, PitikColors.surface);
  });
}
