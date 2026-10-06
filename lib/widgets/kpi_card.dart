// [INDO] KPI Card - FINAL FIX
// Guaranteed no overflow
// lib/widgets/kpi_card.dart

import 'package:flutter/material.dart';

class KPICard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String status;
  final Color color;

  /// Bila diisi, badge status diganti badge netral (abu-abu) berisi teks ini —
  /// mis. "ADC · belum dikalibrasi" untuk nilai tanpa ambang.
  final String? badgeLabel;

  /// Warna badge [badgeLabel]; default abu-abu. Mis. merah untuk "Sensor error".
  final Color? badgeColor;

  const KPICard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.status,
    required this.color,
    this.badgeLabel,
    this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        children: [
          // Icon container
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 8),
          // Text content - use Flexible to prevent overflow
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Label
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[500],
                    letterSpacing: 0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                // Value
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                // Status badge
                _buildStatusBadge(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge() {
    Color badgeColor;
    String statusText;

    if (badgeLabel != null) {
      badgeColor = this.badgeColor ?? const Color(0xFF8E8E93);
      statusText = badgeLabel!;
    } else {
      switch (status) {
        case 'danger':
          badgeColor = const Color(0xFFFF3B30);
          statusText = 'BAHAYA';
          break;
        case 'warning':
          badgeColor = const Color(0xFFFF9500);
          statusText = 'PERHATIAN';
          break;
        default:
          badgeColor = const Color(0xFF34C759);
          statusText = 'NORMAL';
      }
    }

    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        statusText,
        style: TextStyle(
          fontSize: 7,
          fontWeight: FontWeight.w700,
          color: badgeColor,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
