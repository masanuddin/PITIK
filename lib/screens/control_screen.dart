// [INDO] Control Screen — redesign batch 3 (referensi PitikKontrol).
// Satu sumber kebenaran:
//   - Posisi switch kipas/pompa/mode = PERINTAH di /controls (fan, pump,
//     auto_mode) via DeviceState. Tidak ada state optimistis: ESP32/Nextion
//     yang menulis balik (mis. setelah reboot auto_mode=false) langsung tampil.
//   - Status relay AKTUAL dari /sensor_data (relay_fan/relay_pump) ditampilkan
//     sebagai indikator terpisah ("Status perangkat").
//   - Semua tulisan lewat PitikRepository (hanya ke /controls).
//
// Empat hal dibedakan secara visual:
//   1. Permintaan (nilai /controls)          → switch + baris "Permintaan"
//   2. Penulisan sedang berjalan (_sending)  → strip "Mengirim perintah…",
//                                              semua kontrol dikunci (seperti sebelumnya)
//   3. Hasil penulisan di sisi aplikasi      → strip "Permintaan disimpan…" / "Gagal mengirim…"
//   4. Status relay terakhir dari perangkat  → baris "Status perangkat"
//   Permintaan ≠ status perangkat → "Menunggu perubahan status perangkat."
//   (BUKAN konfirmasi; tidak mengunci kontrol lain).
// lib/screens/control_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/controls.dart';
import '../models/sensor_data.dart';
import '../services/auth_service.dart';
import '../services/device_state.dart';
import '../services/pitik_repository.dart';
import '../theme/pitik_tokens.dart';
import '../utils/wib_time.dart';
import '../widgets/connection_row.dart';
import '../widgets/guest_banner.dart';
import '../widgets/metric_card.dart';
import '../widgets/pitik_card.dart';
import '../widgets/status_chip.dart';

class ControlScreen extends StatefulWidget {
  const ControlScreen({
    super.key,
    required this.repository,
    required this.deviceState,
    this.readOnly = false,
  });

  final PitikRepository repository;
  final DeviceState deviceState;

  /// Tamu (anonim): semua kontrol dikunci, hanya melihat.
  final bool readOnly;

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

/// Target perintah — hanya untuk menempatkan umpan balik di kartu yang benar.
enum _Cmd { mode, fan, pump, preset, feed }

enum _WriteResult { ok, error }

class _ControlScreenState extends State<ControlScreen> {
  /// Perintah sedang dikirim → cegah tap ganda (semua kontrol dikunci).
  bool _sending = false;

  /// Target perintah yang sedang/terakhir dikirim + hasilnya di sisi aplikasi.
  _Cmd? _target;
  _WriteResult? _result;
  Timer? _resultTimer;

  /// Preset terakhir yang ditekan (indikator memuat di tombol itu saja).
  String? _lastPreset;

  // Hasil "Sambungkan Ulang" (pola sama dengan Dashboard).
  ReconnectResult? _reconnectResult;
  bool? _serverAtResult;

  // Data sensor & status online dari DeviceState.
  DeviceState get _state => widget.deviceState;
  SensorData? get _sensor => _state.sensor;
  bool get isOnline => _state.isOnline;
  bool get relayFanActual => _sensor?.relayFan ?? false;
  bool get relayPumpActual => _sensor?.relayPump ?? false;

  // Perintah dari /controls.
  Controls get _controls => _state.controlsOrDefault;
  bool get isFanOn => _controls.fan;
  bool get isPumpOn => _controls.pump;
  bool get autoMode => _controls.autoMode;
  bool get feedNow => _controls.feedNow;

  // null bila sensor_ok == false atau belum ada data → tampil "--".
  double? get temperature => _sensor?.temperature;
  double? get humidity => _sensor?.humidity;
  double? get thi => _sensor?.thi;
  bool get _sensorError => _sensor != null && !_sensor!.hasClimate;

  String _fmt(double? v, int decimals) =>
      v == null ? '--' : v.toStringAsFixed(decimals);
  // Amonia: ADC mentah MQ-137 (bukan ppm).
  int? get mq137Raw => _sensor?.mq137Raw;
  String get ammoniaUnitLabel =>
      _sensor?.ammoniaUnitLabel ?? 'ADC · belum dikalibrasi';

  bool get _ready => _state.hasSensor && _state.hasControls;

  @override
  void dispose() {
    _resultTimer?.cancel();
    super.dispose();
  }

  // ════════════════════════════════════════════
  //  Aturan aktif/nonaktif — null = boleh, selain itu alasan untuk UI.
  //  (TIDAK diubah dari versi sebelum redesign.)
  // ════════════════════════════════════════════

  static const String _guestReason = 'Mode tamu — hanya melihat';
  static const String _busyReason = 'Tunggu perintah sebelumnya selesai';

  /// Kipas, pompa, dan preset.
  String? get _relayBlockReason {
    if (widget.readOnly) return _guestReason;
    if (!_ready) return 'Menunggu data perangkat…';
    if (!isOnline) return 'Perangkat offline';
    if (!(_sensor?.relaysEnabled ?? false)) {
      return 'Relay dinonaktifkan di perangkat';
    }
    // Firmware menimpa perintah manual selama mode otomatis aktif.
    if (autoMode) return 'Dikendalikan otomatis';
    return null;
  }

  /// Tombol pakan. feed_now yang tertinggal saat offline tidak dijalankan
  /// firmware, jadi tombol dikunci saat offline.
  String? get _feedBlockReason {
    if (widget.readOnly) return _guestReason;
    if (!_ready) return 'Menunggu data perangkat…';
    if (!isOnline) return 'Perangkat offline';
    if (!(_sensor?.feederEnabled ?? false)) {
      return 'Pemberi pakan dinonaktifkan di perangkat';
    }
    if (feedNow) return 'Menunggu perangkat…';
    return null;
  }

  /// Switch mode otomatis. Dikunci saat offline: bila ESP32 reboot,
  /// firmware selalu menulis auto_mode=false sehingga perintah bisa hilang.
  String? get _autoBlockReason {
    if (widget.readOnly) return _guestReason;
    if (!_ready) return 'Menunggu data perangkat…';
    if (!isOnline) return 'Perangkat offline';
    return null;
  }

  /// Alasan yang ditampilkan untuk sebuah kartu: aturan di atas, atau —
  /// hanya selama penulisan berjalan — kartu lain menunggu perintah itu.
  String? _shownReason(String? rule, Set<_Cmd> own) {
    if (rule != null) return rule;
    if (_sending && !own.contains(_target)) return _busyReason;
    return null;
  }

  // ════════════════════════════════════════════
  //  Kirim perintah — satu perintah sekaligus (perilaku sebelumnya).
  //  Tanpa retry, tanpa antrean, tanpa timeout tambahan.
  // ════════════════════════════════════════════

  Future<void> _send(_Cmd target, Future<void> Function() action) async {
    if (_sending) return;
    _resultTimer?.cancel();
    setState(() {
      _sending = true;
      _target = target;
      _result = null;
    });
    var result = _WriteResult.ok;
    try {
      await action();
    } catch (e) {
      debugPrint('[ControlScreen] gagal mengirim perintah: $e');
      result = _WriteResult.error;
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _result = result;
        });
        // "Terkirim ke server" hanya sementara; error tetap sampai perintah
        // berikutnya agar sempat terbaca.
        if (result == _WriteResult.ok) {
          _resultTimer = Timer(const Duration(seconds: 4), () {
            if (mounted) setState(() => _result = null);
          });
        }
      }
    }
  }

  void _triggerFeeding() => _send(_Cmd.feed, widget.repository.triggerFeed);

  // ════════════════════════════════════════════
  //  Sambungkan ulang (DeviceState.reconnect yang sudah ada)
  // ════════════════════════════════════════════

  Future<void> _reconnect() async {
    if (_state.isReconnecting) return;
    setState(() => _reconnectResult = null);
    final result = await _state.reconnect();
    if (!mounted) return;
    setState(() {
      _reconnectResult = result;
      _serverAtResult = _state.serverConnected;
    });
  }

  /// Hasil reconnect hanya ditampilkan selama masih sesuai kondisi sekarang
  /// (aturan sama dengan Dashboard). Server tersambung ≠ perangkat online.
  ReconnectResult? get _visibleResult {
    final r = _reconnectResult;
    if (r == null || _state.isReconnecting) return null;
    final server = _state.serverConnected;
    return switch (r) {
      ReconnectResult.serverError =>
        (server == true && _serverAtResult != true) ? null : r,
      ReconnectResult.deviceOnline => (isOnline && server != false) ? r : null,
      ReconnectResult.deviceOffline =>
        (!isOnline && server != false) ? r : null,
    };
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild tiap data baru & tiap tick Timer DeviceState (status online).
    return ListenableBuilder(
      listenable: widget.deviceState,
      builder: (context, _) => _buildScaffold(),
    );
  }

  Widget _buildScaffold() {
    final visible = _visibleResult;
    return Scaffold(
      backgroundColor: PitikColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            PitikSpace.page,
            4,
            PitikSpace.page,
            24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const SizedBox(height: 8),
              ConnectionRow(
                deviceState: _state,
                onReconnect: _reconnect,
                result: visible == ReconnectResult.deviceOffline
                    ? null
                    : visible,
              ),
              const SizedBox(height: PitikSpace.gap),
              // Satu-satunya pesan offline di layar ini.
              if (!isOnline) ...[
                _buildOfflineBanner(
                  serverOkNoData: visible == ReconnectResult.deviceOffline,
                ),
                const SizedBox(height: PitikSpace.gap),
              ],
              if (widget.readOnly) ...[
                GuestBanner(
                  message:
                      'Kontrol kipas, pompa & pakan hanya untuk '
                      'peternak yang masuk dengan nomor HP.',
                  onLogin: AuthService.signOut,
                ),
                const SizedBox(height: PitikSpace.gap),
              ],
              _buildSensorMonitor(),
              const SizedBox(height: PitikSpace.gap),
              _buildAutoModeSection(),
              const SizedBox(height: PitikSpace.gap),
              _buildControlSection(),
              const SizedBox(height: PitikSpace.gap),
              _buildPresetsSection(),
              const SizedBox(height: PitikSpace.gap),
              _buildFeederSection(),
            ],
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════
  //  Header & banner offline
  // ════════════════════════════════════════════

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.tune_rounded,
                  color: PitikColors.accent,
                  size: 30,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: const Text(
                        'Kontrol Perangkat',
                        style: PitikText.pageTitle,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Atur kipas, pompa, dan pakan',
                      style: PitikText.body,
                    ),
                  ],
                ),
              ),
            ],
          ),
          StatusPill(online: isOnline),
        ],
      ),
    );
  }

  Widget _buildOfflineBanner({required bool serverOkNoData}) {
    return PitikCard(
      color: PitikColors.dangerSurface,
      borderColor: PitikColors.dangerBorder,
      shadow: false,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const IconTile(
            icon: Icons.cloud_off_rounded,
            color: PitikColors.dangerIcon,
            background: PitikColors.dangerIconBg,
            size: 40,
            radius: 12,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Perangkat offline',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                    color: PitikColors.dangerStrong,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _state.hasSensor
                      ? 'Status di bawah adalah kondisi terakhir yang '
                            'dilaporkan. Kontrol tidak tersedia sampai perangkat '
                            'mengirim data baru.'
                      : 'Belum ada data dari perangkat. Kontrol tidak tersedia '
                            'sampai perangkat mengirim data.',
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.45,
                    color: PitikColors.dangerText,
                  ),
                ),
                Semantics(
                  liveRegion: true,
                  child: RevealSize(
                    child: !serverOkNoData
                        ? const SizedBox(width: double.infinity)
                        : Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(top: 10),
                            padding: const EdgeInsets.only(top: 10),
                            decoration: const BoxDecoration(
                              border: Border(
                                top: BorderSide(color: Color(0xFFF3D3CD)),
                              ),
                            ),
                            child: const Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text:
                                        'Server terhubung, tetapi belum ada '
                                        'data baru dari perangkat. ',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  TextSpan(
                                    text:
                                        'Periksa daya dan Wi-Fi ESP32 di '
                                        'kandang.',
                                  ),
                                ],
                              ),
                              style: TextStyle(
                                fontSize: 15,
                                height: 1.45,
                                color: PitikColors.dangerText,
                              ),
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  Sensor Monitor (ringkas)
  // ════════════════════════════════════════════

  Widget _buildSensorMonitor() {
    final stale = _state.hasSensor && !isOnline;
    return PitikCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              const Icon(
                Icons.sensors_rounded,
                color: PitikColors.accent,
                size: 22,
              ),
              Semantics(
                header: true,
                child: const Text('Sensor Monitor', style: PitikText.cardTitle),
              ),
              if (stale)
                const StatusBadge(
                  text: 'Nilai terakhir',
                  tone: PitikTone.neutral,
                ),
            ],
          ),
          const SizedBox(height: 12),
          AdaptiveGrid(
            minItemWidth: 140,
            children: [
              _SensorTile(
                label: 'Suhu',
                value: _fmt(temperature, 1),
                unit: '°C',
                icon: Icons.device_thermostat_rounded,
                color: PitikColors.temp,
                tint: PitikColors.tempBg,
              ),
              _SensorTile(
                label: 'Kelembapan',
                value: _fmt(humidity, 0),
                unit: '%',
                icon: Icons.water_drop_rounded,
                color: PitikColors.humidity,
                tint: PitikColors.humidityBg,
              ),
              _SensorTile(
                label: 'THI',
                value: _fmt(thi, 1),
                unit: '',
                icon: Icons.speed_rounded,
                color: PitikColors.thi,
                tint: PitikColors.thiBg,
              ),
              _SensorTile(
                label: 'MQ-137',
                value: '${mq137Raw ?? '--'}',
                unit: 'ADC',
                icon: Icons.cloud_rounded,
                color: PitikColors.ammonia,
                tint: PitikColors.ammoniaBg,
              ),
            ],
          ),
          if (_sensorError) ...[
            const SizedBox(height: 10),
            const _Note(
              icon: Icons.sensors_off_rounded,
              color: PitikColors.danger,
              text:
                  'Sensor error (DHT22) — suhu, kelembapan & THI tidak '
                  'tersedia',
              strong: true,
            ),
          ],
          const SizedBox(height: 10),
          _Note(
            icon: Icons.info_outline_rounded,
            color: PitikColors.textSecondary,
            text: 'Amonia MQ-137: $ammoniaUnitLabel (bukan ppm)',
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  Mode otomatis — mengikuti controls/auto_mode (ESP32 menulis false saat
  //  boot & saat tombol manual Nextion ditekan).
  // ════════════════════════════════════════════

  Widget _buildAutoModeSection() {
    final rule = _autoBlockReason;
    final enabled = rule == null && !_sending;
    final reason = _shownReason(rule, {_Cmd.mode});
    final reported = _sensor?.autoMode;
    // sensor_data.auto_mode = mode yang benar-benar aktif di ESP32.
    final pending =
        isOnline &&
        _sensor != null &&
        _state.hasControls &&
        _sensor!.autoMode != autoMode;
    String word(bool auto) => auto ? 'Otomatis' : 'Manual';

    return PitikCard(
      key: const ValueKey('card-mode'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            icon: Icons.auto_awesome_rounded,
            iconColor: PitikColors.thi,
            title: 'Mode Iklim',
          ),
          const SizedBox(height: 10),
          _SwitchRow(
            label: 'Mode otomatis',
            value: autoMode,
            enabled: enabled,
            disabledReason: reason,
            onChanged: (value) =>
                _send(_Cmd.mode, () => widget.repository.setAutoMode(value)),
          ),
          const SizedBox(height: 6),
          _KeyValue(label: 'Permintaan', value: word(autoMode)),
          _ReportedValue(
            value: reported == null ? null : word(reported),
            on: reported ?? false,
            stale: !isOnline,
            timestamp: _sensor?.timestamp,
          ),
          _strip(
            target: _Cmd.mode,
            pending: pending,
            requested: word(autoMode),
            reported: reported == null ? '--' : word(reported),
          ),
          const SizedBox(height: 12),
          Text(
            'Pengaturan THI untuk mode Otomatis (dari Pengaturan)',
            style: PitikText.caption.copyWith(color: PitikColors.textMuted),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              StatusBadge(
                text: 'Kipas: THI ≥ ${Controls.formatThi(_controls.thiNormal)}',
                tone: PitikTone.success,
              ),
              StatusBadge(
                text: 'Pompa: THI ≥ ${Controls.formatThi(_controls.thiDanger)}',
                tone: PitikTone.danger,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            autoMode
                ? 'ESP32 menyalakan/mematikan kipas & pompa berdasarkan THI. '
                      'Perintah manual akan ditimpa.'
                : 'Kipas & pompa dikendalikan dari aplikasi atau layar Nextion. '
                      'Setelah perangkat restart, mode selalu kembali ke Manual.',
            style: PitikText.body,
          ),
          if (reason != null) _LockNote(reason: reason),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  Kipas & pompa
  // ════════════════════════════════════════════

  Widget _buildControlSection() {
    final rule = _relayBlockReason;
    final enabled = rule == null && !_sending;
    final reason = _shownReason(rule, {_Cmd.fan, _Cmd.pump});
    return PitikCard(
      key: const ValueKey('card-relays'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            icon: Icons.power_settings_new_rounded,
            iconColor: PitikColors.success,
            title: 'Kipas & Pompa',
          ),
          if (reason != null) _LockNote(reason: reason),
          const SizedBox(height: 12),
          _buildRelayTile(
            cmd: _Cmd.fan,
            label: 'Kipas utama',
            subtitle: 'Sirkulasi udara kandang',
            icon: Icons.air_rounded,
            isOn: isFanOn,
            actualOn: relayFanActual,
            enabled: enabled,
            reason: reason,
            onChanged: (value) =>
                _send(_Cmd.fan, () => widget.repository.setFan(value)),
          ),
          const SizedBox(height: 10),
          _buildRelayTile(
            cmd: _Cmd.pump,
            label: 'Pompa air / misting',
            subtitle: 'Semprotkan kabut',
            icon: Icons.water_drop_rounded,
            isOn: isPumpOn,
            actualOn: relayPumpActual,
            enabled: enabled,
            reason: reason,
            onChanged: (value) =>
                _send(_Cmd.pump, () => widget.repository.setPump(value)),
          ),
        ],
      ),
    );
  }

  Widget _buildRelayTile({
    required _Cmd cmd,
    required String label,
    required String subtitle,
    required IconData icon,
    required bool isOn,
    required bool actualOn,
    required bool enabled,
    required String? reason,
    required ValueChanged<bool> onChanged,
  }) {
    // Perintah (switch) ≠ relay aktual → ESP32 belum/tidak menjalankannya.
    final pending = isOnline && _sensor != null && actualOn != isOn;
    final hasData = _sensor != null;
    final liveOn = hasData && actualOn && isOnline;
    String word(bool on) => on ? 'Menyala' : 'Mati';
    return Container(
      key: ValueKey('relay-${cmd.name}'),
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      decoration: BoxDecoration(
        color: PitikColors.surfaceMuted,
        borderRadius: BorderRadius.circular(PitikRadius.tile),
        border: Border.all(color: PitikColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Nama + keterangan + switch dibaca sebagai SATU kontrol.
          // Teks besar / layar sempit: switch turun ke baris sendiri agar
          // nama tidak terjepit (tanpa mengecilkan huruf).
          MergeSemantics(
            child: LayoutBuilder(
              builder: (context, c) {
                final scale = MediaQuery.textScalerOf(context).scale(1);
                final stacked = c.maxWidth < 240 * scale;
                final iconTile = IconTile(
                  icon: icon,
                  color: liveOn
                      ? PitikColors.success
                      : PitikColors.textSecondary,
                  background: liveOn
                      ? PitikColors.successBg
                      : PitikColors.neutralBg,
                );
                final texts = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: PitikText.bodyStrong),
                    Text(subtitle, style: PitikText.caption),
                  ],
                );
                final sw = _PitikSwitch(
                  value: isOn,
                  enabled: enabled,
                  disabledReason: reason,
                  onChanged: onChanged,
                );
                if (stacked) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          iconTile,
                          const SizedBox(width: 12),
                          Expanded(child: texts),
                        ],
                      ),
                      Align(alignment: Alignment.centerRight, child: sw),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    iconTile,
                    const SizedBox(width: 12),
                    Expanded(child: texts),
                    sw,
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Column(
              children: [
                _KeyValue(label: 'Permintaan', value: word(isOn)),
                _ReportedValue(
                  value: hasData ? word(actualOn) : null,
                  on: actualOn,
                  stale: !isOnline,
                  timestamp: _sensor?.timestamp,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _strip(
              target: cmd,
              pending: pending,
              requested: word(isOn),
              reported: hasData ? word(actualOn) : '--',
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  Preset — kipas & pompa ditulis atomik (satu update)
  // ════════════════════════════════════════════

  Widget _buildPresetsSection() {
    final rule = _relayBlockReason;
    final enabled = rule == null && !_sending;
    final reason = _shownReason(rule, {_Cmd.preset});
    void preset(String key, bool fan, bool pump) {
      _lastPreset = key;
      _send(
        _Cmd.preset,
        () => widget.repository.setFanPump(fan: fan, pump: pump),
      );
    }

    final busy = _sending && _target == _Cmd.preset;
    Widget button(
      String key,
      String label,
      String scope,
      IconData icon,
      Color tile,
      Color ic,
      bool fan,
      bool pump,
    ) => _PresetButton(
      label: label,
      scope: scope,
      icon: icon,
      tile: tile,
      iconColor: ic,
      enabled: enabled,
      busy: busy && _lastPreset == key,
      disabledReason: reason,
      onTap: () => preset(key, fan, pump),
    );

    return PitikCard(
      key: const ValueKey('card-presets'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            icon: Icons.bolt_rounded,
            iconColor: PitikColors.warning,
            title: 'Preset Cepat',
          ),
          if (reason != null) _LockNote(reason: reason),
          const SizedBox(height: 12),
          button(
            'off',
            'Semua mati',
            'Kipas dan pompa dimatikan',
            Icons.power_settings_new_rounded,
            PitikColors.neutralBg,
            PitikColors.textSecondary,
            false,
            false,
          ),
          const SizedBox(height: 8),
          button(
            'fan',
            'Kipas saja',
            'Kipas menyala, pompa mati',
            Icons.air_rounded,
            PitikColors.successBg,
            PitikColors.success,
            true,
            false,
          ),
          const SizedBox(height: 8),
          button(
            'both',
            'Kipas + pompa',
            'Kipas dan pompa menyala',
            Icons.ac_unit_rounded,
            PitikColors.humidityBg,
            PitikColors.accent,
            true,
            true,
          ),
          // Status relay hasil preset tampil di kartu Kipas & Pompa.
          _strip(target: _Cmd.preset, pending: false),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  Pakan — feed_now: app → true, ESP32 → false (app tidak pernah menulis false)
  // ════════════════════════════════════════════

  Widget _buildFeederSection() {
    final rule = _feedBlockReason;
    final enabled = rule == null && !_sending;
    final reason = _shownReason(rule, {_Cmd.feed});
    final busy = _sending && _target == _Cmd.feed;
    final reduced = PitikMotion.reduced(context);
    final times = _controls.feedTimes.map((t) => t.label).join(' · ');

    return PitikCard(
      key: const ValueKey('card-feed'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            icon: Icons.restaurant_rounded,
            iconColor: PitikColors.temp,
            title: 'Pemberi Pakan',
          ),
          const SizedBox(height: 10),
          _KeyValue(
            label: 'Pakan terakhir',
            value: widget.deviceState.lastFeedText,
          ),
          _KeyValue(label: 'Jadwal', value: '$times WIB'),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'Ubah di Pengaturan',
              style: PitikText.caption.copyWith(color: PitikColors.textMuted),
            ),
          ),
          if (reason != null) _LockNote(reason: reason),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: enabled ? _triggerFeeding : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: PitikColors.accent,
                foregroundColor: Colors.white,
                // Nonaktif tetap terbaca; saat mengirim tetap biru.
                disabledBackgroundColor: busy
                    ? PitikColors.accent
                    : const Color(0xFFE5E7EB),
                disabledForegroundColor: busy
                    ? Colors.white
                    : PitikColors.textSecondary,
                minimumSize: const Size.fromHeight(52),
                elevation: 0,
                animationDuration: PitikMotion.of(
                  context,
                  kThemeChangeDuration,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(PitikRadius.control),
                ),
                textStyle:
                    (Theme.of(context).textTheme.labelLarge ??
                            const TextStyle())
                        .copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
              ),
              icon: busy
                  ? (reduced
                        ? const Icon(Icons.hourglass_top_rounded, size: 20)
                        : const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          ))
                  : const Icon(Icons.restaurant_rounded, size: 20),
              // Alasan nonaktif ikut dibacakan pada node tombol.
              label: Semantics(
                hint: reason,
                child: Text(
                  busy ? 'Mengirim perintah…' : 'Beri Pakan Sekarang',
                ),
              ),
            ),
          ),
          _strip(target: _Cmd.feed, pending: false, showSending: false),
          if (feedNow && !isOnline)
            const _LockNote(
              reason:
                  'Perintah pakan yang tertunda tidak akan dijalankan '
                  'saat perangkat tersambung lagi.',
              icon: Icons.warning_amber_rounded,
              color: PitikColors.warning,
            ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  Strip umpan balik per kartu
  // ════════════════════════════════════════════

  Widget _strip({
    required _Cmd target,
    required bool pending,
    String requested = '',
    String reported = '',
    bool showSending = true,
  }) {
    final mine = _target == target;
    final feed = target == _Cmd.feed;
    _StripData? data;
    if (_sending && mine && showSending) {
      data = _StripData.sending(feed);
    } else if (!_sending && mine && _result == _WriteResult.error) {
      data = _StripData.error(feed);
    } else if (pending) {
      data = _StripData.pending(requested, reported);
    } else if (!_sending && mine && _result == _WriteResult.ok) {
      data = _StripData.ok(feed);
    }
    return Semantics(
      liveRegion: true,
      child: RevealSize(
        child: data == null
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: const EdgeInsets.only(top: 10),
                child: _FeedbackStrip(data: data),
              ),
      ),
    );
  }
}

// ════════════════════════════════════════════
//  Komponen kecil layar Kontrol
// ════════════════════════════════════════════

enum _StripKind { sending, pending, ok, error }

class _StripData {
  const _StripData(this.kind, this.title, [this.sub]);

  factory _StripData.sending(bool feed) => _StripData(
    _StripKind.sending,
    'Mengirim perintah…',
    'Kontrol lain dinonaktifkan sementara.',
  );

  /// Permintaan ≠ status perangkat. Sengaja BUKAN "berhasil"/"dikonfirmasi".
  factory _StripData.pending(String requested, String reported) => _StripData(
    _StripKind.pending,
    'Menunggu perubahan status perangkat.',
    'Permintaan: $requested · Status perangkat: $reported',
  );

  /// Hasil penulisan di sisi aplikasi saja (bukan konfirmasi perangkat).
  factory _StripData.ok(bool feed) => _StripData(
    _StripKind.ok,
    feed
        ? 'Permintaan pakan disimpan. Menunggu perangkat.'
        : 'Permintaan disimpan. Menunggu status perangkat.',
  );

  factory _StripData.error(bool feed) =>
      _StripData(_StripKind.error, 'Gagal mengirim perintah. Periksa koneksi.');

  final _StripKind kind;
  final String title;
  final String? sub;
}

class _FeedbackStrip extends StatelessWidget {
  const _FeedbackStrip({required this.data});
  final _StripData data;

  @override
  Widget build(BuildContext context) {
    final reduced = PitikMotion.reduced(context);
    final (bg, border, fg, Widget lead) = switch (data.kind) {
      _StripKind.sending => (
        PitikColors.accentSoft,
        PitikColors.accentSoftBorder,
        const Color(0xFF1E3A8A),
        reduced
            ? const Icon(
                Icons.hourglass_top_rounded,
                size: 18,
                color: PitikColors.accent,
              )
            : const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: PitikColors.accent,
                  backgroundColor: PitikColors.accentSoftBorder,
                ),
              ),
      ),
      _StripKind.pending => (
        PitikColors.warningSurface,
        PitikColors.warningBorder,
        PitikColors.warningStrong,
        const Icon(
          Icons.hourglass_top_rounded,
          size: 18,
          color: PitikColors.warning,
        ),
      ),
      _StripKind.ok => (
        PitikColors.surface,
        PitikColors.border,
        PitikColors.text,
        const Icon(
          Icons.cloud_done_rounded,
          size: 18,
          color: PitikColors.textSecondary,
        ),
      ),
      _StripKind.error => (
        PitikColors.dangerSurface,
        PitikColors.dangerBorder,
        PitikColors.dangerStrong,
        const Icon(
          Icons.error_rounded,
          size: 18,
          color: PitikColors.dangerIcon,
        ),
      ),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(PitikRadius.control),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: lead),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.title,
                  style: PitikText.bodyStrong.copyWith(color: fg),
                ),
                if (data.sub != null)
                  Text(
                    data.sub!,
                    style: PitikText.caption.copyWith(
                      color: data.kind == _StripKind.error
                          ? PitikColors.dangerText
                          : PitikColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Alasan kontrol tidak tersedia — teks penuh, warna terbaca, ikon kunci/info.
class _LockNote extends StatelessWidget {
  const _LockNote({required this.reason, this.icon, this.color});

  final String reason;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c =
        color ??
        switch (reason) {
          'Dikendalikan otomatis' => PitikColors.thi,
          'Perangkat offline' ||
          'Relay dinonaktifkan di perangkat' ||
          'Pemberi pakan dinonaktifkan di perangkat' => PitikColors.danger,
          'Menunggu perangkat…' => PitikColors.warning,
          _ => PitikColors.textSecondary,
        };
    final i =
        icon ??
        switch (reason) {
          'Dikendalikan otomatis' => Icons.auto_awesome_rounded,
          'Perangkat offline' => Icons.cloud_off_rounded,
          _ControlScreenState._guestReason => Icons.visibility_rounded,
          'Menunggu perangkat…' ||
          'Menunggu data perangkat…' ||
          _ControlScreenState._busyReason => Icons.hourglass_top_rounded,
          _ => Icons.lock_rounded,
        };
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(i, color: c, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              reason,
              style: TextStyle(
                fontSize: 15,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: c,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({
    required this.icon,
    required this.color,
    required this.text,
    this.strong = false,
  });

  final IconData icon;
  final Color color;
  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
              color: strong ? color : PitikColors.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}

class _SensorTile extends StatelessWidget {
  const _SensorTile({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
    required this.tint,
  });

  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: PitikColors.surfaceMuted,
        borderRadius: BorderRadius.circular(PitikRadius.control),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconTile(
            icon: icon,
            color: color,
            background: tint,
            size: 32,
            iconSize: 18,
            radius: 9,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: PitikText.caption),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: 4,
                  children: [
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                        color: PitikColors.text,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (unit.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          unit,
                          style: PitikText.caption.copyWith(
                            color: PitikColors.textMuted,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Label kiri, nilai kanan; turun baris (tanpa potong) bila tidak muat.
class _KeyValue extends StatelessWidget {
  const _KeyValue({required this.label, required this.value, this.lead});

  final String label;
  final String value;
  final Widget? lead;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 2,
          children: [
            Text(label, style: PitikText.body),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (lead != null) ...[lead!, const SizedBox(width: 6)],
                Flexible(
                  child: Text(
                    value,
                    style: PitikText.bodyStrong.copyWith(
                      color: PitikColors.text,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// "Status perangkat" = nilai terakhir yang DILAPORKAN perangkat
/// (/sensor_data). Saat data lama: "Terakhir dilaporkan" + waktunya.
class _ReportedValue extends StatelessWidget {
  const _ReportedValue({
    required this.value,
    required this.on,
    required this.stale,
    required this.timestamp,
  });

  /// null = belum ada laporan.
  final String? value;
  final bool on;
  final bool stale;
  final int? timestamp;

  @override
  Widget build(BuildContext context) {
    final when = WibTime.dayMonthTime(timestamp);
    final dotColor = value == null
        ? PitikColors.arcMuted
        : on
        ? (stale ? PitikColors.navInactive : PitikColors.successDot)
        : PitikColors.navInactive;
    final dot = Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: on && value != null ? dotColor : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(color: dotColor, width: 2),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _KeyValue(
          label: stale ? 'Terakhir dilaporkan' : 'Status perangkat',
          value: value ?? '--',
          lead: dot,
        ),
        if (value == null)
          Text('Belum ada laporan perangkat', style: PitikText.caption)
        else if (stale && when != null)
          Text(when, style: PitikText.caption),
      ],
    );
  }
}

/// Baris label + switch (mode otomatis).
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.enabled,
    required this.disabledReason,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final bool enabled;
  final String? disabledReason;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Row(
        children: [
          Expanded(child: Text(label, style: PitikText.bodyStrong)),
          _PitikSwitch(
            value: value,
            enabled: enabled,
            disabledReason: disabledReason,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// Switch dengan alasan nonaktif untuk pembaca layar (label dari teks di
/// sebelahnya lewat MergeSemantics).
class _PitikSwitch extends StatelessWidget {
  const _PitikSwitch({
    required this.value,
    required this.enabled,
    required this.disabledReason,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final String? disabledReason;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      hint: enabled ? null : disabledReason,
      child: Switch(
        value: value,
        // Nonaktif dibedakan jelas (warna prototipe), tanpa memudarkan kartu.
        thumbColor: WidgetStateProperty.resolveWith((s) {
          final on = s.contains(WidgetState.selected);
          if (s.contains(WidgetState.disabled)) {
            return on ? const Color(0xFFFAFAFB) : const Color(0xFFC9CED6);
          }
          return on ? Colors.white : PitikColors.navInactive;
        }),
        trackColor: WidgetStateProperty.resolveWith((s) {
          final on = s.contains(WidgetState.selected);
          if (s.contains(WidgetState.disabled)) {
            return on ? const Color(0xFFAFC1EC) : const Color(0xFFF1F2F4);
          }
          return on ? PitikColors.accent : const Color(0xFFE5E7EB);
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((s) {
          final on = s.contains(WidgetState.selected);
          if (s.contains(WidgetState.disabled)) {
            return on ? const Color(0xFFAFC1EC) : const Color(0xFFC9CED6);
          }
          return on ? PitikColors.accent : const Color(0xFF8B93A1);
        }),
        onChanged: enabled ? onChanged : null,
      ),
    );
  }
}

class _PresetButton extends StatelessWidget {
  const _PresetButton({
    required this.label,
    required this.scope,
    required this.icon,
    required this.tile,
    required this.iconColor,
    required this.enabled,
    required this.busy,
    required this.disabledReason,
    required this.onTap,
  });

  final String label;
  final String scope;
  final IconData icon;
  final Color tile;
  final Color iconColor;
  final bool enabled;
  final bool busy;
  final String? disabledReason;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final reduced = PitikMotion.reduced(context);
    final Widget lead = busy
        ? SizedBox(
            width: 36,
            height: 36,
            child: Center(
              child: reduced
                  ? const Icon(
                      Icons.hourglass_top_rounded,
                      size: 20,
                      color: PitikColors.accent,
                    )
                  : const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: PitikColors.accent,
                      ),
                    ),
            ),
          )
        : IconTile(
            icon: icon,
            color: enabled ? iconColor : const Color(0xFF9CA3AF),
            background: enabled ? tile : const Color(0xFFF1F2F4),
          );
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Preset $label. $scope',
      hint: enabled ? null : disabledReason,
      excludeSemantics: true,
      onTap: enabled ? onTap : null,
      child: Material(
        color: enabled ? PitikColors.surface : const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(PitikRadius.control),
        animationDuration: PitikMotion.of(context, kThemeChangeDuration),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(PitikRadius.control),
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(PitikRadius.control),
              border: Border.all(
                color: enabled ? PitikColors.border : PitikColors.divider,
              ),
            ),
            child: Row(
              children: [
                lead,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: PitikText.bodyStrong.copyWith(
                          color: enabled
                              ? PitikColors.text
                              : PitikColors.textSecondary,
                        ),
                      ),
                      Text(
                        scope,
                        style: PitikText.caption.copyWith(
                          color: enabled
                              ? PitikColors.textSecondary
                              : PitikColors.navInactive,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
