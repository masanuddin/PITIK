// Model /history/{YYYY-MM-DD}/{HH:MM} — ditulis ESP32 tiap 5 menit.
// Field: t, h, thi, mq137_raw, f, p, ts (epoch UTC).
// lib/models/history_point.dart

import '../utils/wib_time.dart';
import 'json_parse.dart';

class HistoryPoint {
  /// Tanggal WIB "YYYY-MM-DD" (kunci node tanggal).
  final String date;

  /// Jam WIB "HH:MM".
  final String time;

  final double temperature;
  final double humidity;
  final double thi;

  /// ADC 0–4095 — BUKAN ppm.
  final int? mq137Raw;

  final bool fan;
  final bool pump;

  /// Epoch detik UTC dari ESP32 (bisa null pada data lama).
  final int? ts;

  const HistoryPoint({
    required this.date,
    required this.time,
    required this.temperature,
    required this.humidity,
    required this.thi,
    this.mq137Raw,
    this.fan = false,
    this.pump = false,
    this.ts,
  });

  static final RegExp _timeKeyPattern = RegExp(r'^\d{2}:\d{2}$');

  /// Parse satu entry; null bila bukan map atau t/h/thi tidak ada.
  static HistoryPoint? fromEntry(String date, String timeKey, Object? entry) {
    if (entry is! Map) return null;
    final t = asDouble(entry['t']);
    final h = asDouble(entry['h']);
    final thi = asDouble(entry['thi']);
    if (t == null || h == null || thi == null) return null;

    final ts = asInt(entry['ts']);
    var time = timeKey;
    if (!_timeKeyPattern.hasMatch(timeKey) && ts != null && ts > 0) {
      time = WibTime.epochToHhmm(ts);
    }

    return HistoryPoint(
      date: date,
      time: time,
      temperature: t,
      humidity: h,
      thi: thi,
      mq137Raw: asInt(entry['mq137_raw']),
      fan: asBool(entry['f']) ?? false,
      pump: asBool(entry['p']) ?? false,
      ts: ts,
    );
  }

  /// Epoch UTC titik ini: `ts` bila ada, selain itu dari tanggal+jam WIB.
  int? get epoch {
    if (ts != null && ts! > 0) return ts;
    final d = DateTime.tryParse('${date}T$time:00Z');
    return d == null ? null : WibTime.toEpoch(d);
  }

  /// Filter defensif untuk nilai sensor yang tidak masuk akal.
  /// Dengan T > 5 °C dan RH > 5 %, THI minimum ≈ 41 → batas bawah 30.
  bool get isValid =>
      temperature > 5.0 &&
      temperature < 60.0 &&
      humidity > 5.0 &&
      humidity <= 100.0 &&
      thi > 30.0 &&
      thi < 110.0;
}

class HistoryStats {
  final double avgTemp;
  final double minTemp;
  final double maxTemp;
  final double avgHumidity;
  final double minHumidity;
  final double maxHumidity;
  final double avgThi;

  /// Rata-rata ADC MQ-137; null bila tidak ada data.
  final double? avgMq137Raw;

  /// Jumlah transisi dari "tidak mendinginkan" ke kipas/pompa ON.
  final int coolingEvents;

  const HistoryStats({
    required this.avgTemp,
    required this.minTemp,
    required this.maxTemp,
    required this.avgHumidity,
    required this.minHumidity,
    required this.maxHumidity,
    required this.avgThi,
    required this.avgMq137Raw,
    required this.coolingEvents,
  });

  static const HistoryStats empty = HistoryStats(
    avgTemp: 0,
    minTemp: 0,
    maxTemp: 0,
    avgHumidity: 0,
    minHumidity: 0,
    maxHumidity: 0,
    avgThi: 0,
    avgMq137Raw: null,
    coolingEvents: 0,
  );

  factory HistoryStats.fromPoints(List<HistoryPoint> points) {
    final valid = points.where((p) => p.isValid).toList();
    if (valid.isEmpty) return empty;

    double sumTemp = 0, sumHum = 0, sumThi = 0;
    double minTemp = double.infinity, maxTemp = double.negativeInfinity;
    double minHum = double.infinity, maxHum = double.negativeInfinity;
    int sumMq = 0, countMq = 0, coolingEvents = 0;
    bool wasCooling = false;

    for (final p in valid) {
      sumTemp += p.temperature;
      sumHum += p.humidity;
      sumThi += p.thi;
      if (p.temperature < minTemp) minTemp = p.temperature;
      if (p.temperature > maxTemp) maxTemp = p.temperature;
      if (p.humidity < minHum) minHum = p.humidity;
      if (p.humidity > maxHum) maxHum = p.humidity;
      if (p.mq137Raw != null) {
        sumMq += p.mq137Raw!;
        countMq++;
      }
      final cooling = p.fan || p.pump;
      if (cooling && !wasCooling) coolingEvents++;
      wasCooling = cooling;
    }

    final n = valid.length;
    return HistoryStats(
      avgTemp: sumTemp / n,
      minTemp: minTemp,
      maxTemp: maxTemp,
      avgHumidity: sumHum / n,
      minHumidity: minHum,
      maxHumidity: maxHum,
      avgThi: sumThi / n,
      avgMq137Raw: countMq == 0 ? null : sumMq / countMq,
      coolingEvents: coolingEvents,
    );
  }
}

/// Ekspor CSV riwayat (tanggal & jam WIB, mq137_raw dalam ADC).
String historyToCsv(List<HistoryPoint> points) {
  final buf =
      StringBuffer('date,time,ts,temperature,humidity,thi,mq137_raw,fan,pump\n');
  for (final p in points) {
    buf.writeln([
      p.date,
      p.time,
      p.ts ?? '',
      p.temperature.toStringAsFixed(1),
      p.humidity.toStringAsFixed(0),
      p.thi.toStringAsFixed(1),
      p.mq137Raw ?? '',
      p.fan ? 1 : 0,
      p.pump ? 1 : 0,
    ].join(','));
  }
  return buf.toString();
}
