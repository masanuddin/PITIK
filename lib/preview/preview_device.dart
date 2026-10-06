// ═══════════════════════════════════════════════════════════════════════
//  KHUSUS PREVIEW VISUAL — TIDAK dipakai entrypoint produksi (lib/main.dart).
//  Perangkat simulasi: stream palsu + reconnect simulasi untuk DeviceState
//  yang SAMA dengan produksi. Tanpa Firebase, tanpa PitikRepository.
//  Perintah dari layar Kontrol (lewat PreviewRepository) hanya mengubah
//  stream palsu ini; "ESP32" simulasi menerapkannya setelah jeda.
//  Semua jeda simulasi hanya ada di file ini.
// ═══════════════════════════════════════════════════════════════════════
// lib/preview/preview_device.dart

import 'dart:async';

import '../models/controls.dart';
import '../models/sensor_data.dart';
import '../services/device_state.dart';
import '../utils/wib_time.dart';

enum PreviewScenario {
  online('Online · sensor valid'),
  stale('Offline / data lama'),
  sensorError('Sensor error · data baru'),
  staleSensorError('Data lama + sensor error'),
  noData('Belum ada data'),
  reconnecting('Reconnect sedang berjalan'),
  serverErrorFresh('Server error · data masih baru'),
  serverOkStale('Server tersambung · data tetap lama'),
  auto('Online · mode otomatis'),
  relayMismatch('Online · relay belum mengikuti permintaan'),
  feedPending('Online · feed_now aktif');

  const PreviewScenario(this.label);
  final String label;

  static PreviewScenario? byName(String? name) {
    for (final s in values) {
      if (s.name == name) return s;
    }
    return null;
  }
}

class PreviewDevice {
  PreviewDevice(this.scenario, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now {
    state = DeviceState(
      sensorStream: () => _sensor.stream,
      controlsStream: () => _controls.stream,
      serverConnectedStream: () => _connected.stream,
      reconnectTransport: _transport,
      clock: _clock,
    );
    _ctl = switch (scenario) {
      PreviewScenario.auto => _with(_ctl, autoMode: true),
      PreviewScenario.relayMismatch => _with(_ctl, fan: true),
      PreviewScenario.feedPending => _with(_ctl, feedNow: true),
      _ => _ctl,
    };
    _autoReported = scenario == PreviewScenario.auto;
    // Data awal dikirim setelah DeviceState berlangganan (stream broadcast).
    scheduleMicrotask(_emitInitial);
    if (_fresh) {
      // Simulasi keepalive ESP32 agar data tetap "terbaru" selama preview.
      _keepalive = Timer.periodic(const Duration(seconds: 5), (_) {
        _sensor.add(_reading(_now));
      });
    }
    if (scenario == PreviewScenario.reconnecting) {
      // Mulai reconnect (yang tidak pernah selesai) SETELAH data awal diterima,
      // seperti di aplikasi nyata — reconnect memutus langganan sementara.
      _startReconnect = Timer(const Duration(milliseconds: 300), () {
        if (!_disposed) state.reconnect();
      });
    }
  }

  final PreviewScenario scenario;
  final DateTime Function() _clock;
  late final DeviceState state;

  final _sensor = StreamController<SensorData?>.broadcast();
  final _controls = StreamController<Controls>.broadcast();
  final _connected = StreamController<bool>.broadcast();
  final _neverCompletes = Completer<void>();
  Timer? _keepalive;
  Timer? _startReconnect;
  Timer? _apply;

  // Kondisi "ESP32" simulasi.
  Controls _ctl = const Controls(); // default firmware 72/78, 07/12/17
  bool _relayFan = false;
  bool _relayPump = false;
  bool _autoReported = false;
  late int _lastFeedTs = _now - 3 * 3600 - 35 * 60;

  int get _now => _clock().millisecondsSinceEpoch ~/ 1000;

  bool get _fresh => const {
    PreviewScenario.online,
    PreviewScenario.auto,
    PreviewScenario.relayMismatch,
    PreviewScenario.feedPending,
    PreviewScenario.sensorError,
    PreviewScenario.reconnecting,
    PreviewScenario.serverErrorFresh,
  }.contains(scenario);

  bool get _sensorOk => !const {
    PreviewScenario.sensorError,
    PreviewScenario.staleSensorError,
  }.contains(scenario);

  /// Data lama: laporan terakhir 4 hari lalu.
  int get _staleTs => _now - 4 * 86400 - 3 * 3600;

  SensorData _reading(int ts) => SensorData(
    sensorOk: _sensorOk,
    temperature: _sensorOk ? 22.0 : null,
    humidity: _sensorOk ? 70 : null,
    thi: _sensorOk ? 69.3 : null,
    mq137Raw: 184,
    mq137Volt: 0.25,
    relayFan: _relayFan,
    relayPump: _relayPump,
    relaysEnabled: true,
    feederEnabled: true,
    autoMode: _autoReported,
    timestamp: ts,
    // Diagnostik simulasi (jelas bukan perangkat nyata).
    hour: WibTime.fromEpoch(ts).hour,
    minute: WibTime.fromEpoch(ts).minute,
    deviceId: 'SIMULASI-01',
    firmware: '8.4',
    uptimeSeconds: 2 * 3600 + 17 * 60,
    lastFeed: 'app',
    lastFeedTs: _fresh ? _lastFeedTs : ts - 3 * 3600 - 35 * 60,
  );

  void _emitInitial() {
    if (_disposed) return;
    _controls.add(_ctl);
    if (scenario != PreviewScenario.noData) {
      _sensor.add(_reading(_fresh ? _now - 5 : _staleTs));
    }
    // .info/connected simulasi.
    _connected.add(scenario != PreviewScenario.serverErrorFresh);
  }

  Future<void> _transport() async {
    switch (scenario) {
      case PreviewScenario.reconnecting:
        await _neverCompletes.future;
      case PreviewScenario.serverErrorFresh:
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        throw StateError('Simulasi: koneksi server gagal');
      default:
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        if (!_disposed) _connected.add(true);
    }
  }

  /// Perintah dari aplikasi (simulasi /controls). [apply] = "ESP32" ikut
  /// menerapkan; false → relay tetap (permintaan ≠ status perangkat).
  void command(Controls Function(Controls c) change, {required bool apply}) {
    if (_disposed) return;
    _ctl = change(_ctl);
    _controls.add(_ctl);
    _apply?.cancel();
    if (!apply || !_fresh) return;
    _apply = Timer(const Duration(milliseconds: 1500), _applyCommand);
  }

  void _applyCommand() {
    if (_disposed) return;
    _autoReported = _ctl.autoMode;
    if (_ctl.autoMode) {
      // Mode otomatis: THI 69.3 < ambang normal → kipas & pompa mati;
      // firmware menulis balik /controls.
      final thi = _sensorOk ? 69.3 : 0.0;
      _relayFan = thi >= _ctl.thiNormal;
      _relayPump = thi >= _ctl.thiDanger;
      _ctl = _with(_ctl, fan: _relayFan, pump: _relayPump);
    } else {
      _relayFan = _ctl.fan;
      _relayPump = _ctl.pump;
    }
    if (_ctl.feedNow) {
      _lastFeedTs = _now;
      _ctl = _with(_ctl, feedNow: false); // ESP32 yang mereset feed_now
    }
    _controls.add(_ctl);
    _sensor.add(_reading(_now));
  }

  /// Salinan [c] dengan field perintah yang diganti (model tidak punya
  /// copyWith; helper ini khusus preview).
  static Controls withValues(
    Controls c, {
    bool? fan,
    bool? pump,
    bool? autoMode,
    bool? feedNow,
    double? thiNormal,
    double? thiDanger,
    List<FeedTime>? feedTimes,
  }) => _with(
    c,
    fan: fan,
    pump: pump,
    autoMode: autoMode,
    feedNow: feedNow,
    thiNormal: thiNormal,
    thiDanger: thiDanger,
    feedTimes: feedTimes,
  );

  static Controls _with(
    Controls c, {
    bool? fan,
    bool? pump,
    bool? autoMode,
    bool? feedNow,
    double? thiNormal,
    double? thiDanger,
    List<FeedTime>? feedTimes,
  }) => Controls(
    fan: fan ?? c.fan,
    pump: pump ?? c.pump,
    fanSpeed: (fan ?? c.fan) ? 100 : 0,
    feedNow: feedNow ?? c.feedNow,
    autoMode: autoMode ?? c.autoMode,
    thiNormal: thiNormal ?? c.thiNormal,
    thiDanger: thiDanger ?? c.thiDanger,
    feedTimes: feedTimes ?? c.feedTimes,
  );

  bool _disposed = false;

  void dispose() {
    _disposed = true;
    _keepalive?.cancel();
    _startReconnect?.cancel();
    _apply?.cancel();
    state.dispose();
    _sensor.close();
    _controls.close();
    _connected.close();
  }
}
