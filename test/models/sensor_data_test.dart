import 'package:flutter_test/flutter_test.dart';
import 'package:pitik_app/models/sensor_data.dart';

void main() {
  // Contoh payload firmware v8.4.
  Map<String, Object?> payload({Map<String, Object?> override = const {}}) => {
        'sensor_ok': true,
        'temperature': 29.5,
        'humidity': 70, // RTDB bisa mengirim int untuk float bulat
        'thi': 78.3,
        'mq137_raw': 1234,
        'mq137_volt': 0.99,
        'ammonia_calibrated': false,
        'relay_fan': true,
        'relay_pump': false,
        'relays_enabled': true,
        'feeder_enabled': true,
        'auto_mode': false,
        'online': true,
        'timestamp': 1_790_000_000,
        'hour': 14,
        'minute': 5,
        'uptime_s': 3600,
        'device_id': 'PITIK-01',
        'fw': '8.4',
        'last_feed': 'nextion',
        'last_feed_ts': 1_789_990_000,
        ...override,
      };

  group('SensorData.fromMap', () {
    test('membaca semua field kontrak', () {
      final s = SensorData.fromMap(payload());
      expect(s.sensorOk, isTrue);
      expect(s.temperature, 29.5);
      expect(s.humidity, 70.0);
      expect(s.thi, 78.3);
      expect(s.mq137Raw, 1234);
      expect(s.mq137Volt, 0.99);
      expect(s.ammoniaCalibrated, isFalse);
      expect(s.relayFan, isTrue);
      expect(s.relayPump, isFalse);
      expect(s.relaysEnabled, isTrue);
      expect(s.feederEnabled, isTrue);
      expect(s.autoMode, isFalse);
      expect(s.timestamp, 1_790_000_000);
      expect(s.clockString, '14:05');
      expect(s.uptimeSeconds, 3600);
      expect(s.deviceId, 'PITIK-01');
      expect(s.firmware, '8.4');
      expect(s.hasClimate, isTrue);
    });

    test('sensor_ok=false → suhu/RH/THI null walau nilai lama tersisa', () {
      final s = SensorData.fromMap(payload(override: {'sensor_ok': false}));
      expect(s.sensorOk, isFalse);
      expect(s.temperature, isNull);
      expect(s.humidity, isNull);
      expect(s.thi, isNull);
      expect(s.hasClimate, isFalse);
      // Data lain tetap dibaca.
      expect(s.mq137Raw, 1234);
    });

    test('field lama ammonia/amonia diabaikan, mq137_raw tidak ada → null', () {
      final data = payload()
        ..remove('mq137_raw')
        ..['ammonia'] = 55;
      expect(SensorData.fromMap(data).mq137Raw, isNull);
    });

    test('label amonia: ADC · belum dikalibrasi selama ammonia_calibrated=false', () {
      expect(SensorData.fromMap(payload()).ammoniaUnitLabel,
          'ADC · belum dikalibrasi');
      expect(
        SensorData.fromMap(payload(override: {'ammonia_calibrated': true}))
            .ammoniaUnitLabel,
        'ADC',
      );
    });

    test('payload kosong → nilai aman', () {
      final s = SensorData.fromMap({});
      expect(s.sensorOk, isFalse);
      expect(s.timestamp, 0);
      expect(s.hour, -1);
      expect(s.minute, -1);
      expect(s.relaysEnabled, isFalse);
      expect(s.feederEnabled, isFalse);
      expect(s.autoMode, isFalse);
    });

    test('hour/minute -1 → "--:--"', () {
      final s = SensorData.fromMap(payload(override: {'hour': -1, 'minute': -1}));
      expect(s.clockString, '--:--');
    });
  });

  group('SensorData status online', () {
    final s = SensorData.fromMap(payload());
    const ts = 1_790_000_000;

    test('umur ≤ 60 s → online', () {
      expect(s.isOnlineAt(ts + 60), isTrue);
      expect(s.ageSeconds(ts + 60), 60);
    });

    test('umur > 60 s → offline', () {
      expect(s.isOnlineAt(ts + 61), isFalse);
    });

    test('timestamp 0 → offline walau online=true', () {
      final noNtp = SensorData.fromMap(payload(override: {'timestamp': 0}));
      expect(noNtp.isOnlineAt(ts), isFalse);
      expect(noNtp.ageSeconds(ts), isNull);
    });
  });

  group('SensorData pakan terakhir', () {
    String? label(Object? src) =>
        SensorData.fromMap(payload(override: {'last_feed': src}))
            .lastFeedSourceLabel;

    test('label sumber pakan', () {
      expect(label('07:00'), 'Jadwal 07:00');
      expect(label('nextion'), 'Nextion');
      expect(label('app'), 'Aplikasi');
      expect(label(null), isNull);
    });

    test('last_feed_ts dikonversi ke WIB', () {
      // 1_789_990_000 = 2026-09-21 11:26:40 UTC = 18:26 WIB
      expect(SensorData.fromMap(payload()).lastFeedTimeString, '18:26');
      expect(
        SensorData.fromMap(payload(override: {'last_feed_ts': 0}))
            .lastFeedTimeString,
        '--:--',
      );
    });
  });
}
