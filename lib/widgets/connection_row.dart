// Baris koneksi (Dashboard v4): umur data perangkat + tombol "Sambungkan Ulang"
// + hasil reconnect inline. Tombol selalu tersedia (online maupun offline).
//
// Tiga hal dibedakan:
//   - koneksi app ↔ server Firebase  → hasil reconnect
//   - umur data perangkat            → "Update x lalu" (DeviceState.isOnline)
//   - kesehatan sensor               → kartu status/KPI (bukan di sini)
// Firebase tersambung BUKAN bukti ESP32 pulih.
// lib/widgets/connection_row.dart

import 'package:flutter/material.dart';

import '../services/device_state.dart';
import '../theme/pitik_tokens.dart';
import '../utils/wib_time.dart';
import 'pitik_card.dart';

class ConnectionRow extends StatelessWidget {
  const ConnectionRow({
    super.key,
    required this.deviceState,
    required this.onReconnect,
    this.result,
  });

  final DeviceState deviceState;
  final VoidCallback onReconnect;

  /// Hasil reconnect yang masih relevan untuk ditampilkan di baris ini
  /// (deviceOnline / serverError). deviceOffline ditampilkan di banner offline.
  final ReconnectResult? result;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final info = _UpdateInfo(deviceState: deviceState);
    final button = ReconnectAction(
      busy: deviceState.isReconnecting,
      onPressed: onReconnect,
    );
    final feedback = switch (result) {
      ReconnectResult.deviceOnline => const _Feedback(
          icon: Icons.check_circle_rounded,
          color: PitikColors.success,
          text: 'Server terhubung · data perangkat masih terbaru',
        ),
      ReconnectResult.serverError => const _Feedback(
          icon: Icons.error_rounded,
          color: PitikColors.danger,
          text: 'Belum terhubung ke server. Periksa internet ponsel.',
        ),
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(builder: (context, constraints) {
          // Dua baris bila sempit atau teks besar — tanpa mengecilkan huruf.
          final twoRows = constraints.maxWidth < 340 * scale;
          if (twoRows) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [info, const SizedBox(height: 10), button],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: info),
              const SizedBox(width: 12),
              button,
            ],
          );
        }),
        // Hasil reconnect selebar baris (tidak terjepit di samping tombol),
        // diumumkan ke pembaca layar.
        Semantics(
          liveRegion: true,
          child: RevealSize(
            child: feedback ?? const SizedBox(width: double.infinity),
          ),
        ),
      ],
    );
  }
}

class _UpdateInfo extends StatelessWidget {
  const _UpdateInfo({required this.deviceState});

  final DeviceState deviceState;

  @override
  Widget build(BuildContext context) {
    final s = deviceState.sensor;
    final String primary;
    String? secondary;
    if (s == null) {
      primary = deviceState.error != null
          ? 'Belum terhubung ke server'
          : 'Menunggu data perangkat…';
    } else if (!s.hasNtpTime) {
      primary = 'Waktu perangkat belum sinkron';
      secondary = 'Perangkat belum mendapat jam NTP';
    } else {
      final age = deviceState.nowEpochUtc - s.timestamp;
      primary = 'Update ${WibTime.ago(age)}';
      secondary = WibTime.dayMonthTime(s.timestamp);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(primary, style: PitikText.bodyStrong),
          if (secondary != null)
            Text(secondary, style: PitikText.caption),
        ],
      ),
    );
  }
}

class _Feedback extends StatelessWidget {
  const _Feedback({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: PitikText.caption
                  .copyWith(fontWeight: FontWeight.w700, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tombol "Sambungkan Ulang" bergaya tonal. Selama proses: nonaktif,
/// teks "Menyambungkan…", spinner (ikon statis bila animasi dikurangi).
class ReconnectAction extends StatelessWidget {
  const ReconnectAction({
    super.key,
    required this.busy,
    required this.onPressed,
  });

  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final reduced = PitikMotion.reduced(context);
    final Widget icon = !busy
        ? const Icon(Icons.refresh_rounded, size: 18)
        : reduced
            ? const Icon(Icons.hourglass_top_rounded, size: 18)
            : const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: PitikColors.accent,
                  backgroundColor: PitikColors.accentSoftBorder,
                ),
              );
    return TextButton.icon(
      onPressed: busy ? null : onPressed,
      style: TextButton.styleFrom(
        backgroundColor: PitikColors.accentSoft,
        foregroundColor: PitikColors.accent,
        // Saat proses tetap biru & terbaca (bukan abu-abu pucat).
        disabledBackgroundColor: PitikColors.accentSoft,
        disabledForegroundColor: PitikColors.accent,
        side: const BorderSide(color: PitikColors.accentSoftBorder),
        minimumSize: const Size(PitikSpace.touch, PitikSpace.touch),
        padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PitikRadius.control),
        ),
        // Turunan dari tema (bukan TextStyle polos) agar font keluarga tema
        // ikut terpakai; textStyle tombol menggantikan, bukan menggabungkan.
        textStyle: (Theme.of(context).textTheme.labelLarge ?? const TextStyle())
            .copyWith(fontSize: 15, fontWeight: FontWeight.w700, height: 1.25),
      ),
      icon: icon,
      label: Text(busy ? 'Menyambungkan…' : 'Sambungkan Ulang'),
    );
  }
}
