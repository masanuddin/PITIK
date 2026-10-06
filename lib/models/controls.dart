// Model /controls — perintah & konfigurasi yang didengarkan ESP32 (firmware v8.4).
// lib/models/controls.dart

import 'json_parse.dart';

enum ThiLevel { normal, warning, danger }

class FeedTime {
  final int hour;
  final int minute;

  const FeedTime(this.hour, this.minute);

  bool get isValid => hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59;

  String get label =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is FeedTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() => label;
}

class Controls {
  static const double defaultThiNormal = 72;
  static const double defaultThiDanger = 78;
  static const double thiMin = 50;
  static const double thiMax = 100;
  static const List<FeedTime> defaultFeedTimes = [
    FeedTime(7, 0),
    FeedTime(12, 0),
    FeedTime(17, 0),
  ];

  /// Perintah kipas/pompa (bukan status aktual — lihat SensorData.relayFan/Pump).
  final bool fan;
  final bool pump;

  /// 0 / 100, ditulis ESP32, indikator saja.
  final int fanSpeed;

  /// app → true, ESP32 → false setelah dieksekusi (atau diabaikan bila tertinggal).
  final bool feedNow;

  /// Default false: saat boot ESP32 masuk mode MANUAL dan menulis auto_mode=false.
  final bool autoMode;

  final double thiNormal;
  final double thiDanger;

  /// Tepat 3 slot jadwal pakan (`feed_hour1..3` / `feed_min1..3`).
  final List<FeedTime> feedTimes;

  const Controls({
    this.fan = false,
    this.pump = false,
    this.fanSpeed = 0,
    this.feedNow = false,
    this.autoMode = false,
    this.thiNormal = defaultThiNormal,
    this.thiDanger = defaultThiDanger,
    this.feedTimes = defaultFeedTimes,
  });

  factory Controls.fromMap(Map<dynamic, dynamic>? data) {
    if (data == null) return const Controls();

    var normal = asDouble(data['thi_normal']) ?? defaultThiNormal;
    var danger = asDouble(data['thi_danger']) ?? defaultThiDanger;
    // Nilai tidak valid diabaikan firmware, yang tetap memakai nilai valid
    // TERAKHIR (belum tentu 72/78). App tidak tahu nilai itu, jadi di sini
    // ditampilkan default firmware sebagai perkiraan.
    if (validateThresholds(normal, danger) != null) {
      normal = defaultThiNormal;
      danger = defaultThiDanger;
    }

    final feedTimes = <FeedTime>[
      for (var i = 0; i < defaultFeedTimes.length; i++)
        _parseFeedTime(data, i + 1, defaultFeedTimes[i]),
    ];

    return Controls(
      fan: asBool(data['fan']) ?? false,
      pump: asBool(data['pump']) ?? false,
      fanSpeed: asInt(data['fan_speed']) ?? 0,
      feedNow: asBool(data['feed_now']) ?? false,
      autoMode: asBool(data['auto_mode']) ?? false,
      thiNormal: normal,
      thiDanger: danger,
      feedTimes: List.unmodifiable(feedTimes),
    );
  }

  static FeedTime _parseFeedTime(
      Map<dynamic, dynamic> data, int slot, FeedTime fallback) {
    final t = FeedTime(
      asInt(data['feed_hour$slot']) ?? fallback.hour,
      asInt(data['feed_min$slot']) ?? fallback.minute,
    );
    return t.isValid ? t : fallback;
  }

  /// Level THI sesuai logika firmware: kipas ON bila THI ≥ thi_normal,
  /// pompa ON bila THI ≥ thi_danger.
  ThiLevel levelFor(double thi) {
    if (thi < thiNormal) return ThiLevel.normal;
    if (thi < thiDanger) return ThiLevel.warning;
    return ThiLevel.danger;
  }

  /// Format ambang untuk UI: "72" atau "72.5".
  static String formatThi(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  /// Validasi ambang sesuai kontrak; null bila valid, selain itu pesan error.
  static String? validateThresholds(double normal, double danger) {
    if (normal < thiMin || normal > thiMax) {
      return 'Ambang normal harus di antara ${thiMin.toInt()}–${thiMax.toInt()}';
    }
    if (danger < thiMin || danger > thiMax) {
      return 'Ambang bahaya harus di antara ${thiMin.toInt()}–${thiMax.toInt()}';
    }
    if (normal >= danger) {
      return 'Ambang normal harus lebih kecil dari ambang bahaya';
    }
    return null;
  }

  /// Validasi jadwal pakan; null bila valid.
  static String? validateFeedTimes(List<FeedTime> times) {
    if (times.length != defaultFeedTimes.length) {
      return 'Jadwal pakan harus ${defaultFeedTimes.length} slot';
    }
    if (times.any((t) => !t.isValid)) return 'Jam pakan tidak valid';
    return null;
  }

  static Map<String, Object> thresholdsPayload(double normal, double danger) =>
      {'thi_normal': normal, 'thi_danger': danger};

  static Map<String, Object> feedSchedulePayload(List<FeedTime> times) => {
        for (var i = 0; i < times.length; i++) ...{
          'feed_hour${i + 1}': times[i].hour,
          'feed_min${i + 1}': times[i].minute,
        },
      };
}
