// Kartu grafik riwayat (redesign batch 2, referensi PitikRiwayat).
//  - Garis lurus antar titik (tanpa smoothing yang mengubah interpretasi).
//  - Label sumbu ringkas (skala dibatasi 1.3× agar tetap di area grafik);
//    nilai penting tersedia sebagai TEKS skala penuh (readout & statistik).
//  - Readout titik terpilih memakai tanggal/jam & nilai titik data ASLI.
//  - Tanpa animasi berulang; animasi transisi dimatikan saat reduced motion.
// lib/widgets/history_chart_card.dart

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/history_point.dart';
import '../theme/pitik_tokens.dart';
import '../utils/wib_time.dart';
import 'pitik_card.dart';

/// Satu statistik kecil di bawah grafik.
class ChartStat {
  const ChartStat(this.label, this.value);
  final String label;
  final String value;
}

/// Zona ambang THI (dari /controls).
class ThiZones {
  const ThiZones({required this.normal, required this.danger});
  final double normal;
  final double danger;
}

class HistoryChartCard extends StatelessWidget {
  const HistoryChartCard({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.tint,
    required this.periodLabel,
    required this.points,
    required this.valueOf,
    required this.unit,
    required this.decimals,
    required this.stats,
    required this.selectedIndex,
    required this.onSelect,
    this.zones,
    this.emptyText = 'Tidak ada data pada periode ini.',
    this.footer,
  });

  final String title;
  final IconData icon;
  final Color color;
  final Color tint;

  /// Periode dataset yang SEDANG ditampilkan (bukan periode yang sedang dimuat).
  final String periodLabel;

  /// Titik data yang memiliki nilai untuk grafik ini (urut waktu).
  final List<HistoryPoint> points;
  final double Function(HistoryPoint p) valueOf;

  /// '°C', '%', '' (THI), atau 'ADC'.
  final String unit;
  final int decimals;
  final List<ChartStat> stats;
  final int? selectedIndex;
  final ValueChanged<int?> onSelect;
  final ThiZones? zones;
  final String emptyText;
  final Widget? footer;

  String _fmt(double v) {
    final n = v.toStringAsFixed(decimals);
    return switch (unit) {
      '' => n,
      'ADC' => '$n ADC',
      _ => '$n$unit',
    };
  }

  String _when(HistoryPoint p) => '${WibTime.shortDate(p.date)} ${p.time} WIB';

  @override
  Widget build(BuildContext context) {
    final sel =
        selectedIndex != null &&
            selectedIndex! >= 0 &&
            selectedIndex! < points.length
        ? selectedIndex
        : null;
    return PitikCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Judul + chip periode data.
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              IconTile(icon: icon, color: color, background: tint),
              Text(title, style: PitikText.cardTitle),
              _PeriodChip(text: periodLabel),
            ],
          ),
          if (points.isEmpty) ...[
            const SizedBox(height: 12),
            Text(emptyText, style: PitikText.body),
          ] else ...[
            const SizedBox(height: 10),
            // Readout titik terpilih (teks skala penuh).
            Semantics(
              liveRegion: true,
              child: sel == null
                  ? Row(
                      children: [
                        const Icon(
                          Icons.touch_app_rounded,
                          size: 18,
                          color: PitikColors.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Ketuk grafik untuk melihat nilai',
                            style: PitikText.caption,
                          ),
                        ),
                      ],
                    )
                  : Wrap(
                      crossAxisAlignment: WrapCrossAlignment.end,
                      spacing: 8,
                      children: [
                        Text(
                          _when(points[sel]),
                          style: PitikText.caption.copyWith(
                            color: PitikColors.textMuted,
                          ),
                        ),
                        Text(
                          _fmt(valueOf(points[sel])),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: PitikColors.text,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 10),
            Semantics(
              label:
                  'Grafik $title, $periodLabel. '
                  'Ketuk untuk melihat nilai per waktu.',
              child: ExcludeSemantics(
                child: SizedBox(
                  height: 190,
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.3,
                    child: _Chart(
                      points: points,
                      valueOf: valueOf,
                      color: color,
                      decimals: decimals,
                      zones: zones,
                      selectedIndex: sel,
                      onSelect: onSelect,
                    ),
                  ),
                ),
              ),
            ),
          ],
          if (stats.isNotEmpty) ...[
            const SizedBox(height: 12),
            _StatTiles(stats: stats),
          ],
          if (footer != null) ...[const SizedBox(height: 12), footer!],
        ],
      ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Data $text',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: PitikColors.background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: PitikColors.border),
        ),
        child: Text(
          text,
          style: PitikText.caption.copyWith(
            fontWeight: FontWeight.w500,
            color: PitikColors.textMuted,
          ),
        ),
      ),
    );
  }
}

class _StatTiles extends StatelessWidget {
  const _StatTiles({required this.stats});
  final List<ChartStat> stats;

  static const _gap = 6.0;
  static const _hPad = 10.0 + 8.0;
  static const _valueStyle = TextStyle(
    fontSize: 19,
    fontWeight: FontWeight.w700,
    height: 1.25,
    color: PitikColors.text,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final base = DefaultTextStyle.of(context).style;
    // Lebar yang dibutuhkan teks terpanjang (label / nilai) pada skala aktif.
    double widest = 0;
    for (final s in stats) {
      for (final (text, style) in [
        (s.label, base.merge(PitikText.caption)),
        (s.value, base.merge(_valueStyle)),
      ]) {
        final tp = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        widest = math.max(widest, tp.width);
        tp.dispose();
      }
    }
    return LayoutBuilder(builder: (context, c) {
      // Kolom sebanyak mungkin selama teks muat satu baris; jika tidak,
      // turun ke lebih sedikit kolom (teks tetap skala penuh, tanpa potong).
      var cols = stats.length;
      while (cols > 1 &&
          (c.maxWidth - _gap * (cols - 1)) / cols < widest + _hPad + 1) {
        cols--;
      }
      final w = (c.maxWidth - _gap * (cols - 1)) / cols;
      return Wrap(
        spacing: _gap,
        runSpacing: _gap,
        children: [
          for (final s in stats)
            Container(
              width: w,
              padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
              decoration: BoxDecoration(
                color: PitikColors.surfaceMuted,
                borderRadius: BorderRadius.circular(PitikRadius.control),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.label, style: PitikText.caption),
                  const SizedBox(height: 2),
                  Text(s.value, style: _valueStyle),
                ],
              ),
            ),
        ],
      );
    });
  }
}

/// Langkah sumbu "bulat" ≥ [raw]: 1, 2, 2,5, 5 × 10^n — hanya langkah yang
/// bisa ditulis dengan jumlah desimal yang ditampilkan (mis. 0,25 tidak).
double _niceStep(double raw, int decimals) {
  final unit = math.pow(10, -decimals).toDouble();
  final r = math.max(raw, unit);
  final mag = math.pow(10, (math.log(r) / math.ln10).floor()).toDouble();
  for (final m in const [1.0, 2.0, 2.5, 5.0, 10.0]) {
    final step = m * mag;
    final units = step / unit;
    if (step >= r - 1e-9 && (units - units.round()).abs() < 1e-6) return step;
  }
  return 10 * mag;
}

class _Chart extends StatelessWidget {
  const _Chart({
    required this.points,
    required this.valueOf,
    required this.color,
    required this.decimals,
    required this.zones,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<HistoryPoint> points;
  final double Function(HistoryPoint p) valueOf;
  final Color color;
  final int decimals;
  final ThiZones? zones;
  final int? selectedIndex;
  final ValueChanged<int?> onSelect;

  @override
  Widget build(BuildContext context) {
    final values = [for (final p in points) valueOf(p)];
    final lo = values.reduce(math.min);
    final hi = values.reduce(math.max);
    final range = math.max(hi - lo, decimals == 0 ? 10.0 : 1.0);
    // Garis bantu di angka bulat (1/2/2,5/5 × 10^n), ±4 interval; batas
    // dibulatkan ke langkah itu dengan sedikit ruang di atas/bawah garis.
    final interval = _niceStep(range / 4, decimals);
    final minY = ((lo - range * 0.05) / interval).floorToDouble() * interval;
    final maxY = ((hi + range * 0.05) / interval).ceilToDouble() * interval;
    final last = points.length - 1;
    final mid = last ~/ 2;
    final labelStyle = DefaultTextStyle.of(
      context,
    ).style.merge(PitikText.caption.copyWith(height: 1.2));
    final scaler = MediaQuery.textScalerOf(context);

    // Lebar sumbu Y diukur dari label terpanjang (bukan angka tetap).
    String yLabel(double v) => v.toStringAsFixed(decimals);
    double measure(String s) {
      final tp = TextPainter(
        text: TextSpan(text: s, style: labelStyle),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      final w = tp.width;
      tp.dispose();
      return w;
    }

    final leftReserved =
        math.max(measure(yLabel(minY)), measure(yLabel(maxY))) + 10;
    final bottomReserved = scaler.scale(14) * 1.2 * 2 + 10;

    final spots = [
      for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), values[i]),
    ];
    final zone = zones;
    final reduced = PitikMotion.reduced(context);

    return LineChart(
      duration: reduced ? Duration.zero : const Duration(milliseconds: 150),
      LineChartData(
        minX: 0,
        maxX: math.max(1, last).toDouble(),
        minY: minY,
        maxY: maxY,
        clipData: const FlClipData.all(),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: Color(0xFFE9EBEF), strokeWidth: 1),
        ),
        rangeAnnotations: zone == null
            ? const RangeAnnotations()
            : RangeAnnotations(
                horizontalRangeAnnotations: [
                  HorizontalRangeAnnotation(
                    y1: minY,
                    y2: zone.normal.clamp(minY, maxY),
                    color: PitikColors.successSurface,
                  ),
                  HorizontalRangeAnnotation(
                    y1: zone.normal.clamp(minY, maxY),
                    y2: zone.danger.clamp(minY, maxY),
                    color: PitikColors.warningSurface,
                  ),
                  HorizontalRangeAnnotation(
                    y1: zone.danger.clamp(minY, maxY),
                    y2: maxY,
                    color: PitikColors.dangerSurface,
                  ),
                ],
              ),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            if (zone != null && zone.normal > minY && zone.normal < maxY)
              HorizontalLine(
                y: zone.normal,
                color: PitikColors.zoneWarningEdge,
                strokeWidth: 1.5,
                dashArray: const [6, 4],
              ),
            if (zone != null && zone.danger > minY && zone.danger < maxY)
              HorizontalLine(
                y: zone.danger,
                color: PitikColors.zoneDangerEdge,
                strokeWidth: 1.5,
                dashArray: const [6, 4],
              ),
          ],
          verticalLines: [
            if (selectedIndex != null)
              VerticalLine(
                x: selectedIndex!.toDouble(),
                color: const Color(0xFF9CA3AF),
                strokeWidth: 1.5,
              ),
          ],
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: leftReserved,
              interval: interval,
              minIncluded: false,
              maxIncluded: false,
              getTitlesWidget: (v, meta) => SideTitleWidget(
                meta: meta,
                space: 6,
                child: Text(yLabel(v), style: labelStyle),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: bottomReserved,
              interval: 1,
              getTitlesWidget: (v, meta) {
                final i = v.round();
                if (v != i.toDouble() ||
                    !(i == 0 || i == last || (i == mid && mid != 0))) {
                  return const SizedBox.shrink();
                }
                final p = points[i];
                return SideTitleWidget(
                  meta: meta,
                  space: 6,
                  fitInside: SideTitleFitInsideData.fromTitleMeta(
                    meta,
                    distanceFromEdge: 0,
                  ),
                  child: Text(
                    '${WibTime.shortDate(p.date)}\n${p.time}',
                    textAlign: TextAlign.center,
                    style: labelStyle,
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          handleBuiltInTouches: false,
          // Titik terdekat secara horizontal selalu dipilih.
          touchSpotThreshold: double.infinity,
          touchCallback: (event, response) {
            if (event is! FlTapUpEvent) return;
            final spot = response?.lineBarSpots?.firstOrNull;
            if (spot == null) return;
            onSelect(spot.spotIndex == selectedIndex ? null : spot.spotIndex);
          },
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: color,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: selectedIndex != null,
              checkToShowDot: (spot, _) => spot.x == selectedIndex,
              getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                radius: 6,
                color: Colors.white,
                strokeColor: color,
                strokeWidth: 3.5,
              ),
            ),
            belowBarData: BarAreaData(
              show: zone == null,
              color: color.withValues(alpha: 0.10),
            ),
          ),
        ],
      ),
    );
  }
}
