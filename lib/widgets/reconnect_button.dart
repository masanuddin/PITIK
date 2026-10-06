// Tombol "Sambungkan Ulang": putus-sambung koneksi app ↔ Firebase, langgan
// ulang data realtime, lalu tunggu data segar dari ESP32.
// Tidak menulis apa pun ke database → boleh dipakai tamu.
// lib/widgets/reconnect_button.dart

import 'package:flutter/material.dart';

import '../services/device_state.dart';

class ReconnectButton extends StatelessWidget {
  const ReconnectButton({
    super.key,
    required this.deviceState,
    this.color = const Color(0xFF007AFF),
  });

  final DeviceState deviceState;
  final Color color;

  Future<void> _run(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await deviceState.reconnect();
    final (text, bg) = switch (result) {
      ReconnectResult.deviceOnline => (
          'Tersambung — perangkat online.',
          const Color(0xFF34C759),
        ),
      ReconnectResult.deviceOffline => (
          'Server tersambung, tapi perangkat belum mengirim data.\n'
              'Periksa daya & WiFi ESP32 di kandang.',
          const Color(0xFFFF9500),
        ),
      ReconnectResult.serverError => (
          'Gagal terhubung ke server. Periksa koneksi internet HP.',
          const Color(0xFFFF3B30),
        ),
    };
    messenger.showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: bg,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: deviceState,
      builder: (context, _) {
        final busy = deviceState.isReconnecting;
        return TextButton.icon(
          onPressed: busy ? null : () => _run(context),
          style: TextButton.styleFrom(
            foregroundColor: color,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(0, 34),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: busy
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: color),
                )
              : const Icon(Icons.refresh_rounded, size: 18),
          label: Text(
            busy ? 'Menyambungkan…' : 'Sambungkan Ulang',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        );
      },
    );
  }
}
