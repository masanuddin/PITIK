// DeviceState — satu langganan realtime /sensor_data + /controls untuk
// seluruh aplikasi, plus status online yang dihitung ulang berkala.
// Dibuat sekali di MainNavigation, dibuang di dispose().
// lib/services/device_state.dart

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/controls.dart';
import '../models/sensor_data.dart';
import '../utils/wib_time.dart';
import 'pitik_repository.dart';

/// Hasil tombol "Sambungkan Ulang".
enum ReconnectResult {
  /// Server tersambung dan ESP32 mengirim data segar.
  deviceOnline,

  /// Server tersambung, tapi ESP32 belum mengirim data (mati / WiFi putus).
  deviceOffline,

  /// App gagal tersambung ke Firebase (internet HP / izin database).
  serverError,
}

class DeviceState extends ChangeNotifier {
  /// Stream diberikan sebagai *fungsi pembuat* agar bisa dilanggan ulang
  /// saat [reconnect].
  DeviceState({
    required Stream<SensorData?> Function() sensorStream,
    required Stream<Controls> Function() controlsStream,
    Stream<Duration> Function()? serverTimeOffsetStream,
    Stream<bool> Function()? serverConnectedStream,
    Future<void> Function()? reconnectTransport,
    Duration tick = const Duration(seconds: 5),
    DateTime Function()? clock,
  })  : _sensorStream = sensorStream,
        _controlsStream = controlsStream,
        _serverTimeOffsetStream = serverTimeOffsetStream,
        _serverConnectedStream = serverConnectedStream,
        _reconnectTransport = reconnectTransport,
        _clock = clock ?? DateTime.now {
    _subscribe();
    // Tanpa event baru (mis. ESP32 mati) status online tetap harus berubah.
    _timer = Timer.periodic(tick, (_) => refresh());
  }

  factory DeviceState.fromRepository(PitikRepository repository) =>
      DeviceState(
        sensorStream: repository.watchSensor,
        controlsStream: repository.watchControls,
        serverTimeOffsetStream: repository.watchServerTimeOffset,
        serverConnectedStream: repository.watchServerConnected,
        reconnectTransport: repository.reconnect,
      );

  final Stream<SensorData?> Function() _sensorStream;
  final Stream<Controls> Function() _controlsStream;
  final Stream<Duration> Function()? _serverTimeOffsetStream;
  final Stream<bool> Function()? _serverConnectedStream;
  final Future<void> Function()? _reconnectTransport;
  final DateTime Function() _clock;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  Timer? _timer;
  bool _disposed = false;

  SensorData? _sensor;
  Controls? _controls;
  Duration _serverOffset = Duration.zero;
  Object? _error;
  bool _isOnline = false;
  bool _reconnecting = false;
  bool? _serverConnected;

  /// Data sensor terakhir; null bila belum pernah diterima.
  SensorData? get sensor => _sensor;

  /// /controls terakhir; null bila belum pernah diterima.
  Controls? get controls => _controls;

  /// /controls, atau default firmware bila belum diterima.
  Controls get controlsOrDefault => _controls ?? const Controls();

  bool get hasSensor => _sensor != null;
  bool get hasControls => _controls != null;

  /// Error stream terakhir (mis. permission denied); hilang saat data masuk.
  Object? get error => _error;

  /// Online bila `timestamp != 0` dan umur data ≤ 60 s (lihat SensorData).
  bool get isOnline => _isOnline;

  /// Sedang menjalankan [reconnect].
  bool get isReconnecting => _reconnecting;

  /// Koneksi app ↔ server Firebase (`.info/connected`); null = belum diketahui.
  bool? get serverConnected => _serverConnected;

  /// Epoch detik UTC "sekarang" menurut jam server Firebase.
  int get nowEpochUtc =>
      _clock().toUtc().add(_serverOffset).millisecondsSinceEpoch ~/ 1000;

  /// Umur data sensor dalam detik; null bila belum ada data / belum NTP.
  int? get dataAgeSeconds => _sensor?.ageSeconds(nowEpochUtc);

  /// Teks "update terakhir" untuk UI, berdasarkan `timestamp` perangkat
  /// (bukan jam HP saat event diterima).
  String get lastUpdateText {
    final s = _sensor;
    if (s == null) {
      return _error != null
          ? 'Gagal terhubung ke server'
          : 'Menunggu data perangkat…';
    }
    if (!s.hasNtpTime) return 'Waktu perangkat belum sinkron (NTP)';
    final now = nowEpochUtc;
    return 'Update: ${WibTime.describeEpoch(s.timestamp, now)} · '
        '${WibTime.ago(now - s.timestamp)}';
  }

  /// Teks pakan terakhir dari `last_feed` + `last_feed_ts`, mis.
  /// "07:00:12 WIB · Jadwal 07:00 · 3 jam lalu".
  String get lastFeedText {
    final s = _sensor;
    final ts = s?.lastFeedTs;
    if (s == null || ts == null || ts <= 0) return 'Belum ada catatan pakan';
    final now = nowEpochUtc;
    return [
      WibTime.describeEpoch(ts, now),
      if (s.lastFeedSourceLabel != null) s.lastFeedSourceLabel!,
      WibTime.ago(now - ts),
    ].join(' · ');
  }

  /// Hitung ulang status online lalu beri tahu listener. Dipanggil Timer;
  /// selalu notify agar teks "x detik lalu" ikut bergerak.
  void refresh() {
    if (_disposed) return;
    _isOnline = _sensor?.isOnlineAt(nowEpochUtc) ?? false;
    notifyListeners();
  }

  // ════════════════════════════════════════════
  //  Sambungkan ulang
  // ════════════════════════════════════════════

  /// Putus-sambung koneksi app ↔ Firebase, langgan ulang semua stream, lalu
  /// tunggu data segar dari ESP32 hingga [waitFor].
  ///
  /// Hanya memulihkan sisi aplikasi. ESP32 yang mati / putus WiFi tidak bisa
  /// dinyalakan dari sini — hasilnya [ReconnectResult.deviceOffline].
  Future<ReconnectResult> reconnect({
    Duration waitFor = const Duration(seconds: 15),
  }) async {
    if (_reconnecting || _disposed) return ReconnectResult.serverError;
    _reconnecting = true;
    notifyListeners();
    try {
      _cancelSubscriptions();
      _error = null;
      await _reconnectTransport?.call();
      if (_disposed) return ReconnectResult.serverError;
      _subscribe();
      refresh();

      final online = await _waitUntilOnline(waitFor);
      if (online) return ReconnectResult.deviceOnline;
      // Server tidak tersambung (tanpa internet) atau stream error → sisi app.
      if (_error != null || _serverConnected == false) {
        return ReconnectResult.serverError;
      }
      // Server tersambung tapi data tidak segar → masalah di sisi ESP32.
      return ReconnectResult.deviceOffline;
    } catch (e) {
      debugPrint('[DeviceState] reconnect gagal: $e');
      _error = e;
      if (!_disposed && _subscriptions.isEmpty) _subscribe();
      return ReconnectResult.serverError;
    } finally {
      _reconnecting = false;
      refresh();
    }
  }

  Future<bool> _waitUntilOnline(Duration waitFor) {
    if (_isOnline) return Future.value(true);
    final completer = Completer<bool>();
    void check() {
      if (_isOnline && !completer.isCompleted) completer.complete(true);
    }

    final timer = Timer(waitFor, () {
      if (!completer.isCompleted) completer.complete(false);
    });
    addListener(check);
    return completer.future.whenComplete(() {
      timer.cancel();
      if (!_disposed) removeListener(check);
    });
  }

  // ════════════════════════════════════════════
  //  Langganan
  // ════════════════════════════════════════════

  void _subscribe() {
    _subscriptions.addAll([
      _sensorStream().listen(_onSensor, onError: _onError),
      _controlsStream().listen(_onControls, onError: _onError),
      if (_serverTimeOffsetStream != null)
        _serverTimeOffsetStream().listen(_onServerOffset, onError: _onError),
      if (_serverConnectedStream != null)
        _serverConnectedStream().listen(_onServerConnected, onError: _onError),
    ]);
  }

  void _onServerConnected(bool connected) {
    _serverConnected = connected;
    if (connected) _error = null;
    refresh();
  }

  void _cancelSubscriptions() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }

  void _onSensor(SensorData? data) {
    _sensor = data;
    _error = null;
    refresh();
  }

  void _onControls(Controls data) {
    _controls = data;
    _error = null;
    refresh();
  }

  void _onServerOffset(Duration offset) {
    _serverOffset = offset;
    refresh();
  }

  void _onError(Object error) {
    debugPrint('[DeviceState] stream error: $error');
    if (_disposed) return;
    _error = error;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _cancelSubscriptions();
    super.dispose();
  }
}
