// ═══════════════════════════════════════════════════════════════════════
//  KHUSUS PREVIEW VISUAL — TIDAK dipakai entrypoint produksi (lib/main.dart).
//  Repository simulasi untuk HistoryScreen & ControlScreen ASLI:
//   - fetchHistory → data sintetis (preview_history.dart).
//   - Perintah /controls → hanya mengubah stream palsu PreviewDevice.
//   - Ambang THI & jadwal pakan (Pengaturan) → hanya mengubah /controls palsu.
//   - Method lain melempar UnsupportedError.
//   - Tidak membuat FirebaseDatabase; tidak ada akses jaringan.
//   - Jeda simulasi hanya ada di file preview.
// ═══════════════════════════════════════════════════════════════════════
// lib/preview/preview_repository.dart

import '../models/controls.dart';
import '../models/history_point.dart';
import '../services/pitik_repository.dart';
import 'preview_device.dart';
import 'preview_history.dart';

/// Hasil penulisan /controls yang disimulasikan.
enum PreviewWrite {
  ok('Tulis: berhasil, perangkat menerapkan'),
  slow('Tulis: lambat (4 dtk)'),
  error('Tulis: gagal'),
  noApply('Tulis: berhasil, relay tidak berubah');

  const PreviewWrite(this.label);
  final String label;

  static PreviewWrite? byName(String? name) {
    for (final w in values) {
      if (w.name == name) return w;
    }
    return null;
  }
}

class PreviewRepository implements PitikRepository {
  PreviewRepository({
    required this.device,
    required this.history,
    this.write = PreviewWrite.ok,
  });

  final PreviewDevice device;
  final PreviewHistoryRepository history;
  final PreviewWrite write;

  @override
  Future<List<HistoryPoint>> fetchHistory(
    HistoryPeriod period, {
    DateTime? now,
  }) => history.fetchHistory(period, now: now);

  Future<void> _command(
    Controls Function(Controls c) change, {
    bool relayCommand = true,
  }) async {
    await Future<void>.delayed(
      write == PreviewWrite.slow
          ? const Duration(seconds: 4)
          : const Duration(milliseconds: 600),
    );
    if (write == PreviewWrite.error) {
      throw StateError('Simulasi: penulisan /controls gagal');
    }
    device.command(
      change,
      apply: relayCommand && write != PreviewWrite.noApply,
    );
  }

  @override
  Future<void> setFan(bool on) =>
      _command((c) => PreviewDevice.withValues(c, fan: on));

  @override
  Future<void> setPump(bool on) =>
      _command((c) => PreviewDevice.withValues(c, pump: on));

  @override
  Future<void> setFanPump({required bool fan, required bool pump}) =>
      _command((c) => PreviewDevice.withValues(c, fan: fan, pump: pump));

  @override
  Future<void> setAutoMode(bool enabled) =>
      _command((c) => PreviewDevice.withValues(c, autoMode: enabled));

  @override
  Future<void> triggerFeed() =>
      _command((c) => PreviewDevice.withValues(c, feedNow: true));

  @override
  Future<void> setThresholds(double normal, double danger) => _command(
    (c) => PreviewDevice.withValues(c, thiNormal: normal, thiDanger: danger),
    relayCommand: false,
  );

  @override
  Future<void> setFeedSchedule(List<FeedTime> times) => _command(
    (c) => PreviewDevice.withValues(c, feedTimes: List.unmodifiable(times)),
    relayCommand: false,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Preview: ${invocation.memberName} tidak tersedia.',
  );
}
