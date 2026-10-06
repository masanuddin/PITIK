// Model /sensor_data — ditulis ESP32 (firmware v8.4), app hanya membaca.
// lib/models/sensor_data.dart

import '../utils/wib_time.dart';
import 'json_parse.dart';

class SensorData {
  /// Umur data maksimum sebelum perangkat dianggap offline.
  /// (ESP32 mengirim keepalive tiap 30 s.)
  static const int onlineMaxAgeSeconds = 60;

  /// `sensor_ok` — DHT22 valid.
  final bool sensorOk;

  /// Suhu/RH/THI bernilai null bila `sensor_ok == false`: firmware tidak
  /// mengirim field tsb dan nilai lama yang tersisa di DB tidak valid.
  final double? temperature;
  final double? humidity;
  final double? thi;

  /// ADC 0–4095 MQ-137 — BUKAN ppm.
  final int? mq137Raw;
  final double? mq137Volt;
  final bool ammoniaCalibrated;

  /// Status relay aktual.
  final bool relayFan;
  final bool relayPump;

  /// Saklar keamanan firmware; bila false perintah ON ditolak.
  final bool relaysEnabled;
  final bool feederEnabled;

  /// Salinan mode yang sedang aktif di ESP32.
  final bool autoMode;

  /// Epoch detik UTC; `0` = ESP32 belum dapat waktu NTP.
  final int timestamp;

  /// Jam WIB dari ESP32; `-1` = belum NTP.
  final int hour;
  final int minute;

  final int? uptimeSeconds;
  final String? deviceId;
  final String? firmware;

  /// Sumber pakan terakhir: "07:00" (jadwal), "nextion", "app".
  final String? lastFeed;

  /// Epoch detik UTC pakan terakhir.
  final int? lastFeedTs;

  const SensorData({
    required this.sensorOk,
    this.temperature,
    this.humidity,
    this.thi,
    this.mq137Raw,
    this.mq137Volt,
    this.ammoniaCalibrated = false,
    this.relayFan = false,
    this.relayPump = false,
    this.relaysEnabled = false,
    this.feederEnabled = false,
    this.autoMode = false,
    this.timestamp = 0,
    this.hour = -1,
    this.minute = -1,
    this.uptimeSeconds,
    this.deviceId,
    this.firmware,
    this.lastFeed,
    this.lastFeedTs,
  });

  factory SensorData.fromMap(Map<dynamic, dynamic> data) {
    final sensorOk = asBool(data['sensor_ok']) ?? false;
    return SensorData(
      sensorOk: sensorOk,
      temperature: sensorOk ? asDouble(data['temperature']) : null,
      humidity: sensorOk ? asDouble(data['humidity']) : null,
      thi: sensorOk ? asDouble(data['thi']) : null,
      mq137Raw: asInt(data['mq137_raw']),
      mq137Volt: asDouble(data['mq137_volt']),
      ammoniaCalibrated: asBool(data['ammonia_calibrated']) ?? false,
      relayFan: asBool(data['relay_fan']) ?? false,
      relayPump: asBool(data['relay_pump']) ?? false,
      // Default aman: tanpa info dari firmware, anggap perintah akan ditolak.
      relaysEnabled: asBool(data['relays_enabled']) ?? false,
      feederEnabled: asBool(data['feeder_enabled']) ?? false,
      autoMode: asBool(data['auto_mode']) ?? false,
      timestamp: asInt(data['timestamp']) ?? 0,
      hour: asInt(data['hour']) ?? -1,
      minute: asInt(data['minute']) ?? -1,
      uptimeSeconds: asInt(data['uptime_s']),
      deviceId: asString(data['device_id']),
      firmware: asString(data['fw']),
      lastFeed: asString(data['last_feed']),
      lastFeedTs: asInt(data['last_feed_ts']),
    );
    // Field `online` sengaja tidak dibaca: firmware selalu mengirim true.
  }

  /// Suhu, RH, dan THI tersedia dan valid.
  bool get hasClimate =>
      sensorOk && temperature != null && humidity != null && thi != null;

  /// Label satuan amonia. Firmware hanya mengirim ADC mentah (bukan ppm);
  /// ambang/alert ppm dinonaktifkan sampai sensor dikalibrasi.
  String get ammoniaUnitLabel =>
      ammoniaCalibrated ? 'ADC' : 'ADC · belum dikalibrasi';

  bool get hasNtpTime => timestamp > 0;

  /// "HH:MM" WIB dari ESP32, atau "--:--" bila belum NTP.
  String get clockString => WibTime.clock(hour, minute);

  /// Umur data (detik) terhadap [nowEpochUtc]; null bila belum NTP.
  int? ageSeconds(int nowEpochUtc) =>
      hasNtpTime ? nowEpochUtc - timestamp : null;

  /// Online bila `timestamp != 0` dan umur data ≤ [onlineMaxAgeSeconds].
  bool isOnlineAt(int nowEpochUtc) {
    final age = ageSeconds(nowEpochUtc);
    return age != null && age <= onlineMaxAgeSeconds;
  }

  /// Label sumber pakan terakhir untuk UI, null bila belum pernah.
  String? get lastFeedSourceLabel {
    final src = lastFeed;
    if (src == null || src.isEmpty) return null;
    return switch (src) {
      'nextion' => 'Nextion',
      'app' => 'Aplikasi',
      _ => 'Jadwal $src',
    };
  }

  /// "HH:MM" WIB pakan terakhir, atau "--:--".
  String get lastFeedTimeString => WibTime.epochToHhmm(lastFeedTs);
}
