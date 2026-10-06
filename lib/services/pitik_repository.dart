// PitikRepository — SATU-SATUNYA akses Firebase RTDB di aplikasi.
// Kontrak data: CLAUDE.md §2 (firmware v8.4).
//   - Baca : /sensor_data, /controls, /history, .info/serverTimeOffset
//   - Tulis: HANYA /controls (app tidak pernah menulis /sensor_data,
//            /history, /control_log)
// lib/services/pitik_repository.dart

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;

import '../models/controls.dart';
import '../models/history_point.dart';
import '../models/json_parse.dart';
import '../models/sensor_data.dart';
import '../utils/wib_time.dart';

enum HistoryPeriod { lastHour, last24Hours, last7Days, last30Days }

class PitikRepository {
  PitikRepository({FirebaseDatabase? database})
      : _database = database ?? FirebaseDatabase.instance;

  final FirebaseDatabase _database;

  static const String sensorPath = 'sensor_data';
  static const String controlsPath = 'controls';
  static const String historyPath = 'history';

  DatabaseReference get _controlsRef => _database.ref(controlsPath);

  // ════════════════════════════════════════════
  //  STREAM (realtime)
  // ════════════════════════════════════════════

  /// `/sensor_data`; null bila node kosong.
  Stream<SensorData?> watchSensor() =>
      _database.ref(sensorPath).onValue.map((event) {
        final raw = event.snapshot.value;
        return raw is Map ? SensorData.fromMap(raw) : null;
      });

  /// `/controls`; node kosong → nilai default firmware.
  Stream<Controls> watchControls() =>
      _database.ref(controlsPath).onValue.map((event) {
        final raw = event.snapshot.value;
        return Controls.fromMap(raw is Map ? raw : null);
      });

  /// Selisih jam server Firebase terhadap jam HP. Dipakai untuk menghitung
  /// umur `timestamp` agar status online tidak salah bila jam HP meleset.
  Stream<Duration> watchServerTimeOffset() =>
      _database.ref('.info/serverTimeOffset').onValue.map(
            (event) =>
                Duration(milliseconds: asInt(event.snapshot.value) ?? 0),
          );

  /// Status koneksi app ↔ server Firebase (`.info/connected`). Bukan status
  /// ESP32 — tanpa internet Firebase tidak mengirim error, hanya diam.
  Stream<bool> watchServerConnected() =>
      _database.ref('.info/connected').onValue.map(
            (event) => asBool(event.snapshot.value) ?? false,
          );

  /// Putus lalu sambung ulang koneksi app ↔ Firebase (tidak menulis data).
  /// Tidak bisa membuat ESP32 tersambung — ESP32 punya koneksi sendiri.
  Future<void> reconnect() async {
    await _database.goOffline();
    await _database.goOnline();
  }

  // ════════════════════════════════════════════
  //  TULIS — hanya /controls
  // ════════════════════════════════════════════

  Future<void> setFan(bool on) => _controlsRef.update({'fan': on});

  Future<void> setPump(bool on) => _controlsRef.update({'pump': on});

  /// Preset: kipas & pompa ditulis atomik dalam satu update.
  Future<void> setFanPump({required bool fan, required bool pump}) =>
      _controlsRef.update({'fan': fan, 'pump': pump});

  Future<void> setAutoMode(bool enabled) =>
      _controlsRef.update({'auto_mode': enabled});

  /// Memicu pakan sekali. ESP32 yang mereset `feed_now` ke false —
  /// app tidak pernah menulis false.
  Future<void> triggerFeed() => _controlsRef.update({'feed_now': true});

  /// Menulis `thi_normal` & `thi_danger` atomik setelah divalidasi.
  Future<void> setThresholds(double normal, double danger) {
    final error = Controls.validateThresholds(normal, danger);
    if (error != null) throw ArgumentError(error);
    return _controlsRef.update(Controls.thresholdsPayload(normal, danger));
  }

  /// Menulis `feed_hour1..3` / `feed_min1..3` atomik setelah divalidasi.
  Future<void> setFeedSchedule(List<FeedTime> times) {
    final error = Controls.validateFeedTimes(times);
    if (error != null) throw ArgumentError(error);
    return _controlsRef.update(Controls.feedSchedulePayload(times));
  }

  // ════════════════════════════════════════════
  //  RIWAYAT (baca sekali)
  // ════════════════════════════════════════════

  /// Semua titik valid pada satu tanggal WIB, urut jam.
  Future<List<HistoryPoint>> fetchHistoryDay(String dateKey) async {
    final snapshot = await _database.ref('$historyPath/$dateKey').get();
    return parseHistoryDay(dateKey, snapshot.value);
  }

  /// Riwayat untuk [period], dihitung terhadap waktu WIB (bukan zona HP).
  Future<List<HistoryPoint>> fetchHistory(HistoryPeriod period,
      {DateTime? now}) async {
    final nowUtc = (now ?? DateTime.now()).toUtc();
    final dates = historyDateKeys(period, nowUtc);
    final perDay = await Future.wait(dates.map(fetchHistoryDay));
    return selectPeriod(perDay.expand((d) => d).toList(), period, nowUtc);
  }

  @visibleForTesting
  static List<HistoryPoint> parseHistoryDay(String dateKey, Object? raw) {
    if (raw is! Map) return const [];
    final keys = raw.keys.map((k) => k.toString()).toList()..sort();
    final result = <HistoryPoint>[];
    var skipped = 0;
    for (final key in keys) {
      final point = HistoryPoint.fromEntry(dateKey, key, raw[key]);
      if (point != null && point.isValid) {
        result.add(point);
      } else {
        skipped++;
      }
    }
    if (skipped > 0) {
      debugPrint('[PitikRepository] $dateKey: $skipped entry dilewati');
    }
    return result;
  }

  /// Tanggal WIB yang perlu diambil, dari terlama ke terbaru.
  @visibleForTesting
  static List<String> historyDateKeys(HistoryPeriod period, DateTime nowUtc) {
    final days = switch (period) {
      HistoryPeriod.lastHour || HistoryPeriod.last24Hours => 2,
      HistoryPeriod.last7Days => 7,
      HistoryPeriod.last30Days => 30,
    };
    final todayWib = WibTime.fromUtc(nowUtc);
    return [
      for (var i = days - 1; i >= 0; i--)
        WibTime.dateKey(todayWib.subtract(Duration(days: i))),
    ];
  }

  @visibleForTesting
  static List<HistoryPoint> selectPeriod(
      List<HistoryPoint> points, HistoryPeriod period, DateTime nowUtc) {
    final nowEpoch = nowUtc.millisecondsSinceEpoch ~/ 1000;
    List<HistoryPoint> since(int seconds) => points.where((p) {
          final e = p.epoch;
          return e != null && e >= nowEpoch - seconds && e <= nowEpoch + 300;
        }).toList();

    switch (period) {
      case HistoryPeriod.lastHour:
        return since(3600);
      case HistoryPeriod.last24Hours:
        return since(24 * 3600);
      case HistoryPeriod.last7Days:
        return points;
      case HistoryPeriod.last30Days:
        // Ambil tiap titik ke-6 per hari (≈ resolusi 30 menit).
        final result = <HistoryPoint>[];
        String? day;
        var index = 0;
        for (final p in points) {
          if (p.date != day) {
            day = p.date;
            index = 0;
          }
          if (index % 6 == 0) result.add(p);
          index++;
        }
        return result;
    }
  }
}
