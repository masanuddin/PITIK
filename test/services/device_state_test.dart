import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitik_app/models/controls.dart';
import 'package:pitik_app/models/sensor_data.dart';
import 'package:pitik_app/services/device_state.dart';

void main() {
  late StreamController<SensorData?> sensor;
  late StreamController<Controls> controls;
  late StreamController<Duration> offset;
  late StreamController<bool> connected;
  late DateTime now;
  late DeviceState state;
  late int subscribeCount;
  late int transportCalls;
  Object? transportError;

  const ts = 1_790_000_000;
  DateTime at(int epoch) =>
      DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true);
  Future<void> flush() => Future<void>.delayed(Duration.zero);

  setUp(() {
    // Broadcast agar bisa dilanggan ulang oleh reconnect().
    sensor = StreamController.broadcast();
    controls = StreamController.broadcast();
    offset = StreamController.broadcast();
    connected = StreamController.broadcast();
    subscribeCount = 0;
    transportCalls = 0;
    transportError = null;
    now = at(ts + 10);
    state = DeviceState(
      sensorStream: () {
        subscribeCount++;
        return sensor.stream;
      },
      controlsStream: () => controls.stream,
      serverTimeOffsetStream: () => offset.stream,
      serverConnectedStream: () => connected.stream,
      reconnectTransport: () async {
        transportCalls++;
        if (transportError != null) throw transportError!;
      },
      tick: const Duration(hours: 1), // refresh() dipanggil manual di tes
      clock: () => now,
    );
  });

  tearDown(() {
    state.dispose();
    sensor.close();
    controls.close();
    offset.close();
    connected.close();
  });

  test('sebelum ada data: offline, controls default mode MANUAL', () {
    expect(state.hasSensor, isFalse);
    expect(state.isOnline, isFalse);
    expect(state.controlsOrDefault.autoMode, isFalse);
  });

  test('data baru → online; tanpa event baru jadi offline setelah 60 s', () async {
    sensor.add(const SensorData(sensorOk: true, timestamp: ts));
    await flush();
    expect(state.isOnline, isTrue);
    expect(state.dataAgeSeconds, 10);

    now = at(ts + 61);
    state.refresh(); // yang dipanggil Timer
    expect(state.isOnline, isFalse);
  });

  test('timestamp 0 → offline', () async {
    sensor.add(const SensorData(sensorOk: true, timestamp: 0));
    await flush();
    expect(state.isOnline, isFalse);
  });

  test('serverTimeOffset mengoreksi jam HP yang meleset', () async {
    sensor.add(const SensorData(sensorOk: true, timestamp: ts));
    now = at(ts + 300); // jam HP 5 menit terlalu cepat
    offset.add(const Duration(minutes: -5));
    await flush();
    expect(state.isOnline, isTrue);
  });

  test('controls mengikuti stream (mis. ESP32 reboot menulis auto_mode=false)',
      () async {
    controls.add(Controls.fromMap({'auto_mode': true}));
    await flush();
    expect(state.controlsOrDefault.autoMode, isTrue);

    controls.add(Controls.fromMap({'auto_mode': false, 'fan': false, 'pump': false}));
    await flush();
    expect(state.controlsOrDefault.autoMode, isFalse);
  });

  test('error stream dicatat lalu hilang saat data masuk', () async {
    sensor.addError(Exception('permission-denied'));
    await flush();
    expect(state.error, isNotNull);

    sensor.add(const SensorData(sensorOk: true, timestamp: ts));
    await flush();
    expect(state.error, isNull);
  });

  test('lastUpdateText', () async {
    expect(state.lastUpdateText, 'Menunggu data perangkat…');

    sensor.add(const SensorData(sensorOk: true, timestamp: 0));
    await flush();
    expect(state.lastUpdateText, 'Waktu perangkat belum sinkron (NTP)');

    sensor.add(const SensorData(sensorOk: true, timestamp: ts));
    await flush();
    // ts = 21:13:20 WIB, jam sekarang ts + 10
    expect(state.lastUpdateText, 'Update: 21:13:20 WIB · 10 detik lalu');
  });

  test('lastFeedText', () async {
    expect(state.lastFeedText, 'Belum ada catatan pakan');

    sensor.add(const SensorData(sensorOk: true, timestamp: ts, lastFeedTs: 0));
    await flush();
    expect(state.lastFeedText, 'Belum ada catatan pakan');

    // Pakan dari Nextion 1 jam sebelum ts (20:13:20 WIB), jam sekarang ts + 10.
    sensor.add(const SensorData(
        sensorOk: true, timestamp: ts, lastFeed: 'nextion', lastFeedTs: ts - 3600));
    await flush();
    expect(state.lastFeedText, '20:13:20 WIB · Nextion · 1 jam lalu');
  });

  test('notifyListeners dipanggil pada data dan tick', () async {
    var count = 0;
    state.addListener(() => count++);
    sensor.add(const SensorData(sensorOk: true, timestamp: ts));
    await flush();
    state.refresh();
    expect(count, 2);
  });

  group('reconnect', () {
    const wait = Duration(milliseconds: 50);

    Future<void> staleData() async {
      now = at(ts + 100); // data 100 s lalu → offline
      sensor.add(const SensorData(sensorOk: true, timestamp: ts));
      await flush();
      expect(state.isOnline, isFalse);
    }

    test('langgan ulang stream lalu online saat data segar masuk', () async {
      await staleData();
      final future = state.reconnect(waitFor: const Duration(seconds: 2));
      await flush();
      expect(state.isReconnecting, isTrue);
      expect(transportCalls, 1);
      expect(subscribeCount, 2, reason: 'stream dilanggan ulang');

      sensor.add(const SensorData(sensorOk: true, timestamp: ts + 95));
      expect(await future, ReconnectResult.deviceOnline);
      expect(state.isReconnecting, isFalse);
      expect(state.isOnline, isTrue);
    });

    test('server tersambung tapi ESP32 diam → deviceOffline', () async {
      connected.add(true);
      await staleData();
      expect(await state.reconnect(waitFor: wait), ReconnectResult.deviceOffline);
    });

    test('tanpa internet (.info/connected=false) → serverError', () async {
      connected.add(false);
      await staleData();
      expect(await state.reconnect(waitFor: wait), ReconnectResult.serverError);
      expect(state.serverConnected, isFalse);
    });

    test('transport gagal → serverError, langganan tetap dipulihkan', () async {
      await staleData();
      transportError = Exception('network');
      expect(await state.reconnect(waitFor: wait), ReconnectResult.serverError);
      expect(state.error, isNotNull);

      // Data tetap mengalir setelah kegagalan.
      sensor.add(const SensorData(sensorOk: true, timestamp: ts + 95));
      await flush();
      expect(state.isOnline, isTrue);
      expect(state.error, isNull);
    });

    test('sudah online → langsung deviceOnline', () async {
      sensor.add(const SensorData(sensorOk: true, timestamp: ts));
      await flush();
      expect(await state.reconnect(waitFor: wait), ReconnectResult.deviceOnline);
    });
  });
}
