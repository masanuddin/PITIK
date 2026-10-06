// [INDO] THI Gauge Widget
// Ambang dinamis dari /controls (bukan hardcode 72/78).
// Dua gaya:
//   - classic (default): tampilan lama — dipertahankan untuk kompatibilitas.
//   - pitik: redesign 2026-10 — tick & label di ambang, nilai di tengah busur,
//            abu-abu untuk "data terakhir" (muted).
// Animasi hanya berjalan saat NILAI/ambang berubah (tidak saat timestamp
// diperbarui) dan dilewati bila sistem meminta "kurangi animasi".

import 'package:flutter/material.dart';
import 'dart:math' as math;

import '../theme/pitik_tokens.dart';

enum THIGaugeStyle { classic, pitik }

class THIGauge extends StatefulWidget {
  /// null = THI tidak tersedia (mis. sensor error) → tampil "--".
  final double? value;
  final double minValue;
  final double maxValue;
  final double normalMax;
  final double warningMax;

  /// Label status saat [value] null.
  final String unavailableLabel;

  final THIGaugeStyle style;

  /// Gaya pitik: busur & angka abu-abu untuk nilai terakhir (perangkat offline).
  final bool muted;

  /// Gaya classic: tampilkan badge status di dalam gauge.
  final bool showStatusLabel;

  /// Label status [normal, warning, danger] untuk gaya classic.
  final List<String> statusLabels;

  const THIGauge({
    super.key,
    required this.value,
    this.minValue = 60,
    this.maxValue = 100,
    this.normalMax = 72.0,
    this.warningMax = 78.0,
    this.unavailableLabel = 'TIDAK ADA DATA',
    this.style = THIGaugeStyle.classic,
    this.muted = false,
    this.showStatusLabel = true,
    this.statusLabels = const ['NORMAL', 'WARNING', 'DANGER'],
  });

  @override
  State<THIGauge> createState() => _THIGaugeState();
}

class _THIGaugeState extends State<THIGauge> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late CurvedAnimation _curve;
  late Animation<double> _animation;
  double _currentValue = 0;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    // Satu listener & satu CurvedAnimation seumur widget. Sebelumnya tiap
    // perubahan nilai menambah listener baru ke controller (bocor).
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..addListener(() {
        setState(() => _currentValue = _animation.value);
      });
    _curve = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery (reduced motion) baru tersedia di sini, bukan di initState.
    if (!_started) {
      _started = true;
      _updateAnimation();
    }
  }

  @override
  void didUpdateWidget(THIGauge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value ||
        oldWidget.normalMax != widget.normalMax ||
        oldWidget.warningMax != widget.warningMax) {
      _updateAnimation();
    }
  }

  bool get _reduceMotion => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  void _updateAnimation() {
    final target = widget.value ?? _currentValue;
    if (_reduceMotion) {
      _controller.stop();
      _currentValue = target; // langsung ke nilai akhir, tanpa animasi
      return;
    }
    _animation = Tween<double>(
      begin: _currentValue,
      end: target,
    ).animate(_curve);
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  Color _getValueColor() {
    if (_currentValue < widget.normalMax) {
      return const Color(0xFF34C759);
    } else if (_currentValue < widget.warningMax) {
      return const Color(0xFFFF9500);
    } else {
      return const Color(0xFFFF3B30);
    }
  }

  String _getStatusText() {
    if (_currentValue < widget.normalMax) {
      return widget.statusLabels[0];
    } else if (_currentValue < widget.warningMax) {
      return widget.statusLabels[1];
    } else {
      return widget.statusLabels[2];
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.style == THIGaugeStyle.pitik) return _buildPitik(context);
    final hasValue = widget.value != null;
    final valueColor = hasValue ? _getValueColor() : const Color(0xFF8E8E93);
    return SizedBox(
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 0,
            child: CustomPaint(
              size: const Size(240, 140),
              painter: _GaugePainter(
                value: hasValue ? _currentValue : null,
                minValue: widget.minValue,
                maxValue: widget.maxValue,
                normalMax: widget.normalMax,
                warningMax: widget.warningMax,
              ),
            ),
          ),
          Positioned(
            top: 70,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  hasValue ? _currentValue.toStringAsFixed(1) : '--',
                  style: TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.bold,
                    color: valueColor,
                    height: 1.0,
                  ),
                ),
                if (widget.showStatusLabel) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: valueColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    hasValue ? _getStatusText() : widget.unavailableLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: valueColor,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  Gaya pitik (redesign)
  // ════════════════════════════════════════════
  Widget _buildPitik(BuildContext context) {
    final hasValue = widget.value != null;
    // Angka & label di dalam grafik dibatasi skalanya agar tetap di dalam
    // busur; status & penjelasan di luar gauge tetap ikut skala teks penuh.
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
    final valueColor = !hasValue
        ? PitikColors.textSecondary
        : (widget.muted ? PitikColors.textMuted : PitikColors.text);

    return LayoutBuilder(builder: (context, constraints) {
      final maxW = constraints.maxWidth.isFinite ? constraints.maxWidth : 280.0;
      final w = math.min(maxW, 280.0);
      final h = w * 150 / 240;
      return SizedBox(
        width: w,
        height: h,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _PitikGaugePainter(
                  value: hasValue ? _currentValue : null,
                  minValue: widget.minValue,
                  maxValue: widget.maxValue,
                  normalMax: widget.normalMax,
                  warningMax: widget.warningMax,
                  muted: widget.muted,
                  textScaler: scaler,
                  // Label skala/ambang memakai font yang sama dengan teks lain.
                  baseStyle: DefaultTextStyle.of(context).style,
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: h * 0.12,
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.3,
                child: Text(
                  hasValue ? _currentValue.toStringAsFixed(1) : '--',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 46,
                    fontWeight: FontWeight.w700,
                    height: 1,
                    letterSpacing: -0.4,
                    color: valueColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}

/// Geometri mengikuti prototipe (viewBox 240×150, pusat (120,128), r=100).
class _PitikGaugePainter extends CustomPainter {
  _PitikGaugePainter({
    required this.value,
    required this.minValue,
    required this.maxValue,
    required this.normalMax,
    required this.warningMax,
    required this.muted,
    required this.textScaler,
    required this.baseStyle,
  });

  final double? value;
  final double minValue;
  final double maxValue;
  final double normalMax;
  final double warningMax;
  final bool muted;
  final TextScaler textScaler;
  final TextStyle baseStyle;

  double _angle(double v) {
    final ratio = ((v - minValue) / (maxValue - minValue)).clamp(0.0, 1.0);
    return math.pi + math.pi * ratio;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 240;
    final center = Offset(120 * s, 128 * s);
    final radius = 100 * s;
    final rect = Rect.fromCircle(center: center, radius: radius);

    Paint band(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16 * s;

    // Zona (tetap berwarna walau data lama; hanya busur nilai yang abu-abu).
    void zone(double from, double to, Color c) {
      final a = _angle(from), b = _angle(to);
      if (b > a) canvas.drawArc(rect, a, b - a, false, band(c));
    }

    zone(minValue, normalMax, PitikColors.zoneNormal);
    zone(normalMax, warningMax, PitikColors.zoneWarning);
    zone(warningMax, maxValue, PitikColors.zoneDanger);

    final v = value;
    if (v != null) {
      final arcColor = muted
          ? PitikColors.arcMuted
          : v < normalMax
              ? PitikColors.arcNormal
              : v < warningMax
                  ? PitikColors.arcWarning
                  : PitikColors.arcDanger;
      final end = _angle(v);
      canvas.drawArc(rect, math.pi, end - math.pi, false, band(arcColor));
      final knob = center + Offset(math.cos(end), math.sin(end)) * radius;
      canvas.drawCircle(knob, 10 * s, Paint()..color = Colors.white);
      canvas.drawCircle(
        knob,
        10 * s,
        Paint()
          ..color = arcColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4 * s,
      );
    }

    // Pemisah putih di posisi ambang.
    final sep = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.5 * s;
    for (final t in [normalMax, warningMax]) {
      final a = _angle(t);
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(center + dir * (91 * s), center + dir * (109 * s), sep);
    }

    // Label skala & ambang.
    final style = baseStyle.copyWith(
      fontSize: 12 * s,
      fontWeight: FontWeight.w500,
      color: PitikColors.textSecondary,
      height: 1,
    );
    void label(String text, Offset at) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout();
      tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
    }

    String fmt(double x) =>
        x == x.roundToDouble() ? x.toInt().toString() : x.toStringAsFixed(1);

    label(fmt(minValue), Offset(20 * s, 143 * s));
    label(fmt(maxValue), Offset(220 * s, 143 * s));
    final aN = _angle(normalMax), aW = _angle(warningMax);
    if ((aW - aN).abs() < 0.16) {
      // Ambang berdekatan → satu label gabungan agar tidak bertumpuk.
      final mid = (aN + aW) / 2;
      label('${fmt(normalMax)}/${fmt(warningMax)}',
          center + Offset(math.cos(mid), math.sin(mid)) * (118 * s));
    } else {
      for (final t in [normalMax, warningMax]) {
        final a = _angle(t);
        label(fmt(t), center + Offset(math.cos(a), math.sin(a)) * (118 * s));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PitikGaugePainter old) =>
      old.value != value ||
      old.minValue != minValue ||
      old.maxValue != maxValue ||
      old.normalMax != normalMax ||
      old.warningMax != warningMax ||
      old.muted != muted ||
      old.textScaler != textScaler ||
      old.baseStyle != baseStyle;
}

class _GaugePainter extends CustomPainter {
  /// null → busur nilai tidak digambar (hanya zona).
  final double? value;
  final double minValue;
  final double maxValue;
  final double normalMax;
  final double warningMax;

  _GaugePainter({
    required this.value,
    required this.minValue,
    required this.maxValue,
    required this.normalMax,
    required this.warningMax,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height);
    final radius = size.width / 2 - 20;

    final bgPaint = Paint()
      ..color = const Color(0xFFE5E5EA)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi,
      math.pi,
      false,
      bgPaint,
    );

    _drawZoneArc(canvas, center, radius, minValue, normalMax, const Color(0xFF34C759).withValues(alpha: 0.25));
    _drawZoneArc(canvas, center, radius, normalMax, warningMax, const Color(0xFFFF9500).withValues(alpha: 0.25));
    _drawZoneArc(canvas, center, radius, warningMax, maxValue, const Color(0xFFFF3B30).withValues(alpha: 0.25));

    final v = value;
    if (v != null) {
      final valueRatio = (v.clamp(minValue, maxValue) - minValue) / (maxValue - minValue);
      final sweepAngle = math.pi * valueRatio;

      Color arcColor;
      if (v < normalMax) {
        arcColor = const Color(0xFF34C759);
      } else if (v < warningMax) {
        arcColor = const Color(0xFFFF9500);
      } else {
        arcColor = const Color(0xFFFF3B30);
      }

      final valuePaint = Paint()
        ..color = arcColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        math.pi,
        sweepAngle,
        false,
        valuePaint,
      );
    }

    _drawTicks(canvas, center, radius);
    _drawLabels(canvas, center, radius, size);
  }

  void _drawZoneArc(Canvas canvas, Offset center, double radius, double start, double end, Color color) {
    final startRatio = (start - minValue) / (maxValue - minValue);
    final endRatio = (end - minValue) / (maxValue - minValue);
    final startAngle = math.pi + (math.pi * startRatio);
    final sweepAngle = math.pi * (endRatio - startRatio);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      paint,
    );
  }

  void _drawTicks(Canvas canvas, Offset center, double radius) {
    final tickPaint = Paint()
      ..color = const Color(0xFFAEAEB2)
      ..strokeWidth = 2;

    for (var i = 0; i <= 4; i++) {
      final angle = math.pi + (math.pi * i / 4);
      final innerRadius = radius - 28;
      final outerRadius = radius - 20;

      final innerPoint = Offset(
        center.dx + innerRadius * math.cos(angle),
        center.dy + innerRadius * math.sin(angle),
      );
      final outerPoint = Offset(
        center.dx + outerRadius * math.cos(angle),
        center.dy + outerRadius * math.sin(angle),
      );

      canvas.drawLine(innerPoint, outerPoint, tickPaint);
    }
  }

  void _drawLabels(Canvas canvas, Offset center, double radius, Size size) {
    final textStyle = const TextStyle(
      color: Color(0xFF8E8E93),
      fontSize: 11,
      fontWeight: FontWeight.w600,
    );

    final minLabel = minValue.toInt().toString();
    final maxLabel = maxValue.toInt().toString();

    final minPainter = TextPainter(
      text: TextSpan(text: minLabel, style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    minPainter.paint(canvas, Offset(8, size.height - 5));

    final maxPainter = TextPainter(
      text: TextSpan(text: maxLabel, style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    maxPainter.paint(canvas, Offset(size.width - 30, size.height - 5));
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.normalMax != normalMax ||
        oldDelegate.warningMax != warningMax;
  }
}
