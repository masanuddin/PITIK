// Pill status Online/Offline & badge status (Normal/Waspada/Bahaya/…).
// lib/widgets/status_chip.dart

import 'package:flutter/material.dart';

import '../theme/pitik_tokens.dart';

enum PitikTone { success, warning, danger, neutral, accent }

extension PitikToneColors on PitikTone {
  Color get background => switch (this) {
        PitikTone.success => PitikColors.successBg,
        PitikTone.warning => PitikColors.warningBg,
        PitikTone.danger => PitikColors.dangerBg,
        PitikTone.neutral => PitikColors.neutralBg,
        PitikTone.accent => PitikColors.accentSoft,
      };

  Color get foreground => switch (this) {
        PitikTone.success => PitikColors.success,
        PitikTone.warning => PitikColors.warning,
        PitikTone.danger => PitikColors.danger,
        PitikTone.neutral => PitikColors.textMuted,
        PitikTone.accent => PitikColors.accent,
      };

  /// Isi solid (teks putih), mis. chip "THI 68.9".
  Color get solid => switch (this) {
        PitikTone.success => PitikColors.success,
        PitikTone.warning => PitikColors.warning,
        PitikTone.danger => PitikColors.danger,
        PitikTone.neutral => PitikColors.textMuted,
        PitikTone.accent => PitikColors.accent,
      };
}

/// Badge kecil berisi teks status. Teks dibungkus bila sempit.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.text,
    required this.tone,
    this.large = false,
  });

  final String text;
  final PitikTone tone;

  /// Versi besar (pill di bawah gauge).
  final bool large;

  @override
  Widget build(BuildContext context) {
    // Status netral ("Terakhir: …") tidak dicetak tebal — bukan kondisi kini.
    final weight = tone == PitikTone.neutral ? FontWeight.w500 : FontWeight.w700;
    return Container(
      padding: large
          ? const EdgeInsets.symmetric(horizontal: 16, vertical: 6)
          : const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(large ? 999 : PitikRadius.chip),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: PitikText.chip.copyWith(
          fontSize: large ? 16 : 14,
          fontWeight: weight,
          color: tone.foreground,
        ),
      ),
    );
  }
}

/// Pill "Online"/"Offline" di header. Status mengikuti umur data perangkat
/// (DeviceState.isOnline), BUKAN status koneksi Firebase.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.online});

  final bool online;

  @override
  Widget build(BuildContext context) {
    final bg = online ? PitikColors.successBg : PitikColors.dangerBg;
    final fg = online ? PitikColors.success : PitikColors.danger;
    final dot = online ? PitikColors.successDot : PitikColors.dangerDot;
    final text = online ? 'Online' : 'Offline';
    return Semantics(
      label: 'Status perangkat: $text',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 34),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              text,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
