// ═══════════════════════════════════════════════════════════════════════
//  KHUSUS PREVIEW VISUAL — TIDAK dipakai entrypoint produksi (lib/main.dart).
//  Repository riwayat simulasi untuk HistoryScreen ASLI:
//   - Hanya fetchHistory yang diimplementasikan; semua method lain (termasuk
//     SEMUA penulisan /controls) melempar UnsupportedError.
//   - Tidak membuat FirebaseDatabase; tidak ada akses jaringan.
//   - Data sintetis deterministik (bukan data prototipe, bukan data pribadi)
//     dengan resolusi seperti firmware: 5 menit; 30 Hari tiap titik ke-6.
//   - Jeda simulasi hanya ada di file ini.
// ═══════════════════════════════════════════════════════════════════════
// lib/preview/preview_history.dart

import 'dart:math' as math;

import '../models/history_point.dart';
import '../services/pitik_repository.dart';
import '../utils/wib_time.dart';

enum PreviewHistory {
  ok('Riwayat: ada data'),
  slow('Riwayat: periode lain lambat (5 dtk)'),
  failOthers('Riwayat: periode lain gagal'),
  empty('Riwayat: kosong'),
  error('Riwayat: gagal dimuat');

  const PreviewHistory(this.label);
  final String label;

  static PreviewHistory? byName(String? name) {
    for (final h in values) {
      if (h.name == name) return h;
    }
    return null;
  }
}

class PreviewHistoryRepository implements PitikRepository {
  PreviewHistoryRepository(
    this.mode, {
    DateTime Function()? clock,
    this.delay = const Duration(milliseconds: 700),
  }) : _clock = clock ?? DateTime.now;

  final PreviewHistory mode;
  final DateTime Function() _clock;
  final Duration delay;

  @override
  Future<List<HistoryPoint>> fetchHistory(
    HistoryPeriod period, {
    DateTime? now,
  }) async {
    final other = period != HistoryPeriod.last24Hours;
    await Future<void>.delayed(
      mode == PreviewHistory.slow && other ? const Duration(seconds: 5) : delay,
    );
    switch (mode) {
      case PreviewHistory.error:
        throw StateError('Simulasi: gagal memuat riwayat');
      case PreviewHistory.failOthers when other:
        throw StateError('Simulasi: gagal memuat riwayat');
      case PreviewHistory.empty:
        return const [];
      default:
        return generate(period, (now ?? _clock()).toUtc());
    }
  }

  /// Titik sintetis: siklus harian suhu/kelembapan, THI dari rumus firmware,
  /// kipas/pompa dengan histeresis mode otomatis (72/70, 78/75).
  static List<HistoryPoint> generate(HistoryPeriod period, DateTime nowUtc) {
    const step = 300; // 5 menit
    final nowEpoch = nowUtc.millisecondsSinceEpoch ~/ 1000;
    final end = nowEpoch - nowEpoch % step;
    final (span, every) = switch (period) {
      HistoryPeriod.lastHour => (3600, 1),
      HistoryPeriod.last24Hours => (24 * 3600, 1),
      HistoryPeriod.last7Days => (7 * 86400, 1),
      HistoryPeriod.last30Days => (30 * 86400, 6),
    };
    final points = <HistoryPoint>[];
    var fan = false, pump = false;
    var i = 0;
    for (var t = end - span + step; t <= end; t += step, i++) {
      final wib = WibTime.fromEpoch(t);
      final hour = wib.hour + wib.minute / 60;
      final day = math.sin(2 * math.pi * (hour - 9) / 24);
      final noise = math.sin(t / 1300.0) * 0.4 + math.sin(t / 517.0) * 0.25;
      final temp = 26.5 + 3.2 * day + noise;
      final rh = (76 - 9 * day + noise * 3).clamp(40, 98).toDouble();
      final thi = 0.8 * temp + (rh / 100) * (temp - 14.4) + 46.4;
      if (thi >= 72) fan = true;
      if (thi <= 70) fan = false;
      if (thi >= 78) pump = true;
      if (thi <= 75) pump = false;
      if (i % every != 0) continue;
      points.add(
        HistoryPoint(
          date: WibTime.dateKey(wib),
          time: WibTime.hhmm(wib),
          temperature: double.parse(temp.toStringAsFixed(1)),
          humidity: double.parse(rh.toStringAsFixed(1)),
          thi: double.parse(thi.toStringAsFixed(1)),
          mq137Raw: (190 + 35 * day + 12 * math.sin(t / 900.0)).round(),
          fan: fan,
          pump: pump,
          ts: t,
        ),
      );
    }
    return points;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Preview: hanya fetchHistory yang tersedia (${invocation.memberName}).',
  );
}
