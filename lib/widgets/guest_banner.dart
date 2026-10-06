// Banner mode tamu (login anonim): tamu hanya boleh melihat.
// lib/widgets/guest_banner.dart

import 'package:flutter/material.dart';

class GuestBanner extends StatelessWidget {
  const GuestBanner({super.key, required this.message, this.onLogin});

  /// Mis. "Kontrol perangkat hanya untuk peternak terdaftar."
  final String message;

  /// Aksi "Masuk dengan No. HP" (keluar dari sesi tamu → layar login).
  final VoidCallback? onLogin;

  static const Color _color = Color(0xFF8E8E93);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.visibility_rounded, color: _color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Mode tamu — hanya melihat',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1D1D1F),
                  ),
                ),
                Text(
                  message,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
                if (onLogin != null)
                  TextButton(
                    onPressed: onLogin,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Masuk dengan No. HP',
                      style: TextStyle(
                        color: Color(0xFF007AFF),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
