// Helper tes: repository & DeviceState palsu (tanpa Firebase).

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitik_app/models/controls.dart';
import 'package:pitik_app/models/history_point.dart';
import 'package:pitik_app/models/sensor_data.dart';
import 'package:pitik_app/services/device_state.dart';
import 'package:pitik_app/services/pitik_repository.dart';

const fakeTs = 1_790_000_000;

/// Mencatat setiap perintah tulis ke /controls.
class FakeRepo extends Fake implements PitikRepository {
  final calls = <String>[];

  /// Opsional: dijalankan setelah perintah dicatat (mis. Completer untuk
  /// menahan penulisan, atau melempar error untuk simulasi gagal kirim).
  Future<void> Function()? onWrite;

  Future<void> _write(String call) async {
    calls.add(call);
    await onWrite?.call();
  }

  @override
  Future<void> setFan(bool on) => _write('fan=$on');

  @override
  Future<void> setPump(bool on) => _write('pump=$on');

  @override
  Future<void> setFanPump({required bool fan, required bool pump}) =>
      _write('fanpump=$fan,$pump');

  @override
  Future<void> setAutoMode(bool enabled) => _write('auto=$enabled');

  @override
  Future<void> triggerFeed() => _write('feed');

  @override
  Future<void> setThresholds(double normal, double danger) =>
      _write('thr=$normal,$danger');

  @override
  Future<void> setFeedSchedule(List<FeedTime> times) =>
      _write('feed_schedule=${times.join(',')}');

  /// Riwayat: diatur per tes (mis. Completer untuk mengatur urutan respons).
  Future<List<HistoryPoint>> Function(HistoryPeriod period)? onFetchHistory;
  final historyRequests = <HistoryPeriod>[];

  @override
  Future<List<HistoryPoint>> fetchHistory(HistoryPeriod period,
      {DateTime? now}) {
    historyRequests.add(period);
    final handler = onFetchHistory;
    if (handler == null) return Future.value(const []);
    return handler(period);
  }
}

/// Perangkat palsu: DeviceState + controller untuk mendorong data baru.
///
/// Controller broadcast agar bisa dilanggan ulang oleh `reconnect()`.
/// Controller sengaja tidak di-close: close() di dalam testWidgets
/// (FakeAsync) membuat tes menggantung. Cukup panggil `state.dispose()`.
class FakeDevice {
  FakeDevice({
    SensorData? sensor,
    Controls? controls = const Controls(), // null = /controls belum ada
    int ageSeconds = 10,
    Future<void> Function()? reconnectTransport,
  }) {
    state = DeviceState(
      sensorStream: () => sensorCtrl.stream,
      controlsStream: () => controlsCtrl.stream,
      serverConnectedStream: () => connectedCtrl.stream,
      reconnectTransport: () async {
        reconnectCalls++;
        await reconnectTransport?.call();
      },
      tick: const Duration(hours: 1),
      clock: () => DateTime.fromMillisecondsSinceEpoch(
          (fakeTs + ageSeconds) * 1000,
          isUtc: true),
    );
    if (sensor != null) sensorCtrl.add(sensor);
    if (controls != null) controlsCtrl.add(controls);
  }

  final sensorCtrl = StreamController<SensorData?>.broadcast();
  final controlsCtrl = StreamController<Controls>.broadcast();
  final connectedCtrl = StreamController<bool>.broadcast();
  late final DeviceState state;
  int reconnectCalls = 0;
}

/// DeviceState dengan data tetap; jam = [fakeTs] + [ageSeconds].
DeviceState fakeDeviceState({
  SensorData? sensor,
  Controls controls = const Controls(),
  int ageSeconds = 10,
}) =>
    FakeDevice(sensor: sensor, controls: controls, ageSeconds: ageSeconds)
        .state;
