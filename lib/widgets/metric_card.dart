// Kartu metrik redesign (Dashboard). Pengganti tampilan KPICard di Dashboard;
// KPICard lama tidak diubah. Teks tidak dipotong — kartu tumbuh mengikuti
// ukuran teks sistem.
// lib/widgets/metric_card.dart

import 'package:flutter/material.dart';

import '../theme/pitik_tokens.dart';
import 'pitik_card.dart';
import 'status_chip.dart';

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.label,
    required this.value,
    this.unit,
    this.valueColor = PitikColors.text,
    this.badge,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String label;
  final String value;
  final String? unit;

  /// Abu gelap (textMuted) untuk "data terakhir" — tetap terbaca.
  final Color valueColor;
  final StatusBadge? badge;

  @override
  Widget build(BuildContext context) {
    return PitikCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Wrap: bila label tidak muat di samping ikon, label turun ke baris
          // berikutnya — tidak pernah dipotong di tengah kata ("Kelembapa/n").
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 6,
            children: [
              IconTile(
                  icon: icon, color: iconColor, background: iconBackground),
              Text(label, style: PitikText.label),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 4,
            children: [
              Text(value,
                  style: PitikText.metricValue.copyWith(color: valueColor)),
              if (unit != null && value != '--')
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(unit!, style: PitikText.metricUnit),
                ),
            ],
          ),
          if (badge != null) ...[
            const SizedBox(height: 10),
            badge!,
          ],
        ],
      ),
    );
  }
}

/// Grid 2 kolom yang turun menjadi 1 kolom bila sempit / teks besar.
/// Kartu dalam satu baris disamakan tingginya.
class AdaptiveGrid extends StatelessWidget {
  const AdaptiveGrid({
    super.key,
    required this.children,
    required this.minItemWidth,
    this.spacing = PitikSpace.gap,
  });

  final List<Widget> children;

  /// Lebar minimum per kolom pada skala teks 1.0 (dikalikan skala teks).
  final double minItemWidth;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(builder: (context, constraints) {
      final twoColumns =
          constraints.maxWidth >= minItemWidth * scale * 2 + spacing;
      if (!twoColumns) {
        return Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(height: spacing),
              children[i],
            ],
          ],
        );
      }
      final rows = <Widget>[];
      for (var i = 0; i < children.length; i += 2) {
        if (i > 0) rows.add(SizedBox(height: spacing));
        rows.add(IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: children[i]),
              SizedBox(width: spacing),
              Expanded(
                child: i + 1 < children.length
                    ? children[i + 1]
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ));
      }
      return Column(children: rows);
    });
  }
}
