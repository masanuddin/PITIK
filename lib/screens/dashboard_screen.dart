// [INDO] Dashboard Screen — redesign batch 1 (referensi PitikDashboardV4).
// Semua data dari DeviceState: /sensor_data + ambang THI dari /controls.
//
// Tiga hal dibedakan di layar ini:
//   - koneksi app ↔ server (hasil "Sambungkan Ulang")
//   - umur data perangkat  (DeviceState.isOnline — logika existing)
//   - kesehatan sensor     (sensor_ok)
// Data lama tetap terbaca tetapi selalu ditandai "terakhir"; tidak pernah
// ditampilkan sebagai penilaian kondisi saat ini.
// lib/screens/dashboard_screen.dart

import 'package:flutter/material.dart';

import '../models/controls.dart';
import '../models/sensor_data.dart';
import '../services/device_state.dart';
import '../theme/pitik_tokens.dart';
import '../utils/wib_time.dart';
import '../widgets/connection_row.dart';
import '../widgets/metric_card.dart';
import '../widgets/pitik_card.dart';
import '../widgets/status_chip.dart';
import '../widgets/thi_gauge.dart';

/// Tingkat status untuk badge (Normal / Waspada / Bahaya). Copy UI saja.
enum _Lvl { normal, warning, danger }

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.deviceState});

  final DeviceState deviceState;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  /// Hasil "Sambungkan Ulang" terakhir (null = belum ada / sedang proses).
  ReconnectResult? _reconnectResult;

  /// Status `.info/connected` saat hasil diterima — untuk mendeteksi pulih.
  bool? _serverAtResult;

  DeviceState get _state => widget.deviceState;
  SensorData? get _sensor => _state.sensor;
  bool get isOnline => _state.isOnline;
  bool get _hasData => _sensor != null;

  /// Ada data, tapi sudah tidak terbaru → "data terakhir".
  bool get _stale => _hasData && !isOnline;

  /// Suhu/RH/THI valid pada laporan (terakhir) perangkat.
  bool get _climateOk => _sensor?.hasClimate ?? false;

  // Ambang THI dari /controls (default firmware 72/78 bila belum ada).
  Controls get _controls => _state.controlsOrDefault;
  double get _thiNormal => _controls.thiNormal;
  double get _thiDanger => _controls.thiDanger;

  _Lvl? get _thiLevel => !_climateOk
      ? null
      : switch (_controls.levelFor(_sensor!.thi!)) {
          ThiLevel.normal => _Lvl.normal,
          ThiLevel.warning => _Lvl.warning,
          ThiLevel.danger => _Lvl.danger,
        };

  // KETERBATASAN (existing, dipertahankan sementara): ambang suhu 26/30 °C dan
  // kelembapan 80 % adalah heuristik lama aplikasi, BUKAN bagian kontrak
  // firmware dan belum divalidasi. Hanya dipakai untuk badge KPI.
  _Lvl _tempLevel(double t) =>
      t > 30 ? _Lvl.danger : (t > 26 ? _Lvl.warning : _Lvl.normal);
  _Lvl _humidityLevel(double h) => h > 80 ? _Lvl.warning : _Lvl.normal;

  static String _label(_Lvl l) => switch (l) {
        _Lvl.normal => 'Normal',
        _Lvl.warning => 'Waspada',
        _Lvl.danger => 'Bahaya',
      };

  static PitikTone _tone(_Lvl l) => switch (l) {
        _Lvl.normal => PitikTone.success,
        _Lvl.warning => PitikTone.warning,
        _Lvl.danger => PitikTone.danger,
      };

  Color get _valueColor => _stale ? PitikColors.textMuted : PitikColors.text;

  /// Waktu laporan terakhir perangkat, mis. "30 Sep 12:49 WIB".
  String get _lastReportAt =>
      WibTime.dayMonthTime(_sensor?.timestamp) ?? 'waktu tidak diketahui';

  /// Status relay AKTUAL + mode aktif, mis. "Kipas mati · Pompa mati · Mode manual".
  String get _relaySummary {
    final s = _sensor;
    String w(bool on) => on ? 'menyala' : 'mati';
    final mode = (s?.autoMode ?? false) ? 'otomatis' : 'manual';
    return 'Kipas ${w(s?.relayFan ?? false)} · '
        'Pompa ${w(s?.relayPump ?? false)} · Mode $mode';
  }

  String _fmt(double? v, int decimals) =>
      v == null ? '--' : v.toStringAsFixed(decimals);

  // ════════════════════════════════════════════
  //  Sambungkan ulang (memakai DeviceState.reconnect yang sudah ada)
  // ════════════════════════════════════════════

  Future<void> _reconnect() async {
    // Cegah tap berulang: panggilan kedua saat proses tidak memulai apa pun.
    if (_state.isReconnecting) return;
    setState(() => _reconnectResult = null);
    final result = await _state.reconnect();
    if (!mounted) return;
    setState(() {
      _reconnectResult = result;
      _serverAtResult = _state.serverConnected;
    });
  }

  /// Hasil hanya ditampilkan selama masih sesuai kondisi sekarang.
  /// Koneksi server dan kesegaran data perangkat dinilai TERPISAH:
  ///  - serverError: kegagalan koneksi app ↔ server tetap tampil walau data
  ///    perangkat masih dinilai terbaru; hilang bila Firebase kemudian
  ///    melaporkan tersambung (atau saat reconnect berikutnya).
  ///  - deviceOnline: hanya selama data masih terbaru & server tidak terputus.
  ///  - deviceOffline: hanya selama data masih lama & server tidak terputus.
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
    // Rebuild tiap data baru & tiap tick Timer DeviceState (umur data).
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
        child: RefreshIndicator(
          onRefresh: () async => widget.deviceState.refresh(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
                PitikSpace.page, 4, PitikSpace.page, 24),
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
                if (!isOnline) ...[
                  _buildOfflineBanner(
                      serverOkNoData: visible == ReconnectResult.deviceOffline),
                  const SizedBox(height: PitikSpace.gap),
                ],
                _buildStatusCard(),
                if (_stale) ...[
                  const SizedBox(height: PitikSpace.gap),
                  _buildLastValuesNote(),
                ],
                const SizedBox(height: PitikSpace.gap),
                _buildKPIGrid(),
                const SizedBox(height: PitikSpace.gap),
                _buildAmoniaCard(),
                const SizedBox(height: PitikSpace.gap),
                _buildRelayStatus(),
                const SizedBox(height: PitikSpace.gap),
                _buildFeedCard(),
                const SizedBox(height: PitikSpace.gap),
                _buildTHISection(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════
  //  Header & banner
  // ════════════════════════════════════════════

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: PitikColors.accentTint,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/images/pitik.png',
                width: 38,
                height: 38,
                fit: BoxFit.contain,
                semanticLabel: 'Logo PITIK',
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 6,
              children: [
                Semantics(
                  header: true,
                  child: const Text('PITIK', style: PitikText.pageTitle),
                ),
                StatusPill(online: isOnline),
              ],
            ),
          ),
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
                  _hasData
                      ? 'Nilai di bawah adalah data terakhir, bukan kondisi saat ini.'
                      : 'Belum ada data dari perangkat.',
                  style: const TextStyle(
                      fontSize: 16, height: 1.45, color: PitikColors.dangerText),
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
                              TextSpan(children: [
                                TextSpan(
                                  text: 'Server terhubung, tetapi belum ada '
                                      'data baru dari perangkat. ',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                TextSpan(
                                    text: 'Periksa daya dan Wi-Fi ESP32 '
                                        'di kandang.'),
                              ]),
                              style: TextStyle(
                                  fontSize: 15,
                                  height: 1.45,
                                  color: PitikColors.dangerText),
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
  //  Kartu status THI
  // ════════════════════════════════════════════

  Widget _buildStatusCard() {
    // 1) Belum ada data sama sekali.
    if (!_hasData) {
      return _statusCardShell(
        icon: Icons.hourglass_empty_rounded,
        iconColor: PitikColors.textSecondary,
        iconBg: PitikColors.surfaceMuted,
        title: 'Menunggu data',
        titleColor: PitikColors.text,
        lines: [
          _state.error != null
              ? 'Belum terhubung ke server.'
              : 'Nilai akan muncul setelah perangkat mengirim laporan pertama.',
        ],
      );
    }

    // 2) Data lama: kondisi saat ini TIDAK tersedia. Tampilkan laporan
    //    terakhir apa adanya (termasuk bila saat itu sensor error).
    if (_stale) {
      final last = _climateOk
          ? 'Status terakhir: THI ${_label(_thiLevel!)} · $_lastReportAt'
          : 'Laporan terakhir: sensor error (DHT22) · $_lastReportAt';
      return _statusCardShell(
        icon: Icons.help_outline_rounded,
        iconColor: PitikColors.textSecondary,
        iconBg: PitikColors.surfaceMuted,
        title: 'Status saat ini tidak tersedia',
        titleColor: PitikColors.text,
        lines: [last, '$_relaySummary (terakhir)'],
      );
    }

    // 3) Data terbaru, tapi sensor DHT22 error.
    if (!_climateOk) {
      return _statusCardShell(
        icon: Icons.sensors_off_rounded,
        iconColor: PitikColors.dangerIcon,
        iconBg: PitikColors.dangerIconBg,
        color: PitikColors.dangerSurface,
        border: PitikColors.dangerBorder,
        title: 'Sensor error (DHT22)',
        titleColor: PitikColors.dangerStrong,
        chip: const StatusBadge(text: 'THI --', tone: PitikTone.neutral),
        lines: const [
          'Suhu, kelembapan & THI tidak tersedia. Periksa sensor DHT22.',
        ],
        lineColor: PitikColors.dangerText,
      );
    }

    // 4) Data terbaru & valid → penilaian saat ini.
    final level = _thiLevel!;
    final cmp = switch (level) {
      _Lvl.normal => 'THI < ${Controls.formatThi(_thiNormal)}',
      _Lvl.warning => 'THI ≥ ${Controls.formatThi(_thiNormal)}',
      _Lvl.danger => 'THI ≥ ${Controls.formatThi(_thiDanger)}',
    };
    final (surface, border, iconBg, iconColor, titleColor, icon) =
        switch (level) {
      _Lvl.normal => (
          PitikColors.successSurface,
          PitikColors.successBorder,
          PitikColors.successIconBg,
          PitikColors.arcNormal,
          PitikColors.successStrong,
          Icons.check_circle_rounded,
        ),
      _Lvl.warning => (
          PitikColors.warningSurface,
          PitikColors.warningBorder,
          PitikColors.warningIconBg,
          PitikColors.warning,
          PitikColors.warningStrong,
          Icons.info_rounded,
        ),
      _Lvl.danger => (
          PitikColors.dangerSurface,
          PitikColors.dangerBorder,
          PitikColors.dangerIconBg,
          PitikColors.dangerIcon,
          PitikColors.dangerStrong,
          Icons.warning_rounded,
        ),
    };
    return _statusCardShell(
      icon: icon,
      iconColor: iconColor,
      iconBg: iconBg,
      color: surface,
      border: border,
      title: 'THI ${_label(level)}',
      titleColor: titleColor,
      chip: _SolidChip(
        text: 'THI ${_fmt(_sensor!.thi, 1)}',
        color: _tone(level).solid,
      ),
      // Subjudul memakai relay AKTUAL, bukan tebakan dari THI.
      lines: ['$cmp · $_relaySummary'],
    );
  }

  Widget _statusCardShell({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required Color titleColor,
    required List<String> lines,
    Color color = PitikColors.surface,
    Color border = PitikColors.border,
    Color lineColor = PitikColors.textSecondary,
    Widget? chip,
  }) {
    return PitikCard(
      color: color,
      borderColor: border,
      shadow: color == PitikColors.surface,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconTile(
            icon: icon,
            color: iconColor,
            background: iconBg,
            size: 44,
            iconSize: 26,
            radius: 12,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                        color: titleColor,
                      ),
                    ),
                    ?chip,
                  ],
                ),
                for (final l in lines) ...[
                  const SizedBox(height: 4),
                  Text(l, style: PitikText.body.copyWith(color: lineColor)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLastValuesNote() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.history_rounded,
              size: 20, color: PitikColors.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Nilai sensor terakhir · $_lastReportAt',
              style: PitikText.body.copyWith(
                  fontWeight: FontWeight.w500, color: PitikColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  KPI
  // ════════════════════════════════════════════

  /// Badge suhu/RH/THI. Tidak pernah "Normal" untuk data error atau lama.
  StatusBadge _climateBadge(_Lvl? Function(SensorData s) levelOf) {
    if (!_hasData) {
      return const StatusBadge(text: 'Tidak ada data', tone: PitikTone.neutral);
    }
    if (!_climateOk) {
      return _stale
          ? const StatusBadge(
              text: 'Terakhir: sensor error', tone: PitikTone.neutral)
          : const StatusBadge(text: 'Sensor error', tone: PitikTone.danger);
    }
    final level = levelOf(_sensor!)!;
    return _stale
        ? StatusBadge(
            text: 'Terakhir: ${_label(level)}', tone: PitikTone.neutral)
        : StatusBadge(text: _label(level), tone: _tone(level));
  }

  Widget _buildKPIGrid() {
    final s = _sensor;
    final calibrated = s?.ammoniaCalibrated ?? false;
    final StatusBadge mqBadge = !_hasData
        ? const StatusBadge(text: 'Tidak ada data', tone: PitikTone.neutral)
        : StatusBadge(
            text: [
              if (_stale) 'Terakhir',
              calibrated ? 'ADC' : 'Belum dikalibrasi',
            ].join(' · '),
            tone: PitikTone.neutral,
          );
    return AdaptiveGrid(
      minItemWidth: 150,
      children: [
        MetricCard(
          icon: Icons.device_thermostat_rounded,
          iconColor: PitikColors.temp,
          iconBackground: PitikColors.tempBg,
          label: 'Suhu',
          value: _fmt(s?.temperature, 1),
          unit: '°C',
          valueColor: _valueColor,
          badge: _climateBadge((s) => _tempLevel(s.temperature!)),
        ),
        MetricCard(
          icon: Icons.water_drop_rounded,
          iconColor: PitikColors.humidity,
          iconBackground: PitikColors.humidityBg,
          label: 'Kelembapan',
          value: _fmt(s?.humidity, 0),
          unit: '%',
          valueColor: _valueColor,
          badge: _climateBadge((s) => _humidityLevel(s.humidity!)),
        ),
        MetricCard(
          icon: Icons.speed_rounded,
          iconColor: PitikColors.thi,
          iconBackground: PitikColors.thiBg,
          label: 'Indeks THI',
          value: _fmt(s?.thi, 1),
          valueColor: _valueColor,
          badge: _climateBadge((_) => _thiLevel),
        ),
        MetricCard(
          icon: Icons.cloud_rounded,
          iconColor: PitikColors.ammonia,
          iconBackground: PitikColors.ammoniaBg,
          // Amonia: ADC mentah MQ-137 (bukan ppm) — tanpa ambang/alert.
          label: 'Amonia (MQ-137)',
          value: s?.mq137Raw?.toString() ?? '--',
          unit: 'ADC',
          valueColor: _valueColor,
          badge: mqBadge,
        ),
      ],
    );
  }

  // Netral (tanpa status normal/bahaya): nilai ADC belum bisa dikonversi ke ppm.
  Widget _buildAmoniaCard() {
    final s = _sensor;
    final raw = s?.mq137Raw?.toString() ?? '--';
    final volt =
        s?.mq137Volt == null ? '' : ' · ${s!.mq137Volt!.toStringAsFixed(2)} V';
    final unitLabel = s?.ammoniaUnitLabel ?? 'ADC · belum dikalibrasi';
    return PitikCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const IconTile(
            icon: Icons.cloud_rounded,
            color: PitikColors.ammonia,
            background: PitikColors.ammoniaBg,
            size: 44,
            iconSize: 24,
            radius: 12,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  // "NH3" (bukan subskrip ₃): glyph subskrip tidak didukung
                  // font preview & belum diverifikasi di perangkat.
                  'Gas Amonia (NH3) · MQ-137',
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700, height: 1.3),
                ),
                const SizedBox(height: 4),
                Text(
                  '$raw ADC$volt',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                    color: _valueColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 4),
                Text('$unitLabel — nilai ppm belum tersedia',
                    style: PitikText.body),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  Status perangkat (relay aktual)
  // ════════════════════════════════════════════

  Widget _buildRelayStatus() {
    final subtitle = !_hasData
        ? 'Belum ada data dari perangkat'
        : isOnline
            ? 'Kondisi aktual dari perangkat'
            : 'Kondisi terakhir yang diketahui, bukan saat ini';
    return PitikCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            icon: Icons.power_settings_new_rounded,
            iconColor: PitikColors.accent,
            title: 'Status Perangkat',
            subtitle: subtitle,
          ),
          const SizedBox(height: 14),
          AdaptiveGrid(
            minItemWidth: 130,
            children: [
              _relayTile('Kipas', Icons.air_rounded, _sensor?.relayFan),
              _relayTile('Pompa', Icons.water_drop_rounded, _sensor?.relayPump),
            ],
          ),
        ],
      ),
    );
  }

  Widget _relayTile(String name, IconData icon, bool? on) {
    final current = isOnline && on == true;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: PitikColors.surfaceMuted,
        borderRadius: BorderRadius.circular(PitikRadius.tile),
      ),
      child: Row(
        children: [
          IconTile(
            icon: icon,
            color: current ? PitikColors.success : PitikColors.textSecondary,
            background: current ? PitikColors.successBg : PitikColors.surface,
            size: 40,
            radius: 12,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: PitikText.label.copyWith(height: 1.3)),
                Text(
                  on == null ? '--' : (on ? 'Menyala' : 'Mati'),
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                    color: current
                        ? PitikColors.success
                        : (_stale ? PitikColors.textMuted : PitikColors.text),
                  ),
                ),
                if (_stale)
                  const Text('terakhir diketahui', style: PitikText.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  Pakan
  // ════════════════════════════════════════════

  Widget _buildFeedCard() {
    final s = _sensor;
    final ts = s?.lastFeedTs;
    final at = WibTime.dayMonthTime(ts);
    final List<String> lastLines = at == null
        ? ['Belum ada catatan pakan']
        : [
            at,
            [
              if (s!.lastFeedSourceLabel != null) s.lastFeedSourceLabel!,
              WibTime.ago(_state.nowEpochUtc - ts!),
            ].join(' · '),
          ];
    final schedule = _controls.feedTimes.map((t) => t.label).join(' · ');
    return PitikCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            icon: Icons.restaurant_rounded,
            iconColor: PitikColors.temp,
            title: 'Pakan',
          ),
          const SizedBox(height: 6),
          _InfoRow(label: 'Terakhir', lines: lastLines, divider: true),
          _InfoRow(label: 'Jadwal', lines: ['$schedule WIB']),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  THI Monitor
  // ════════════════════════════════════════════

  Widget _buildTHISection() {
    final level = _thiLevel;
    final thresholds = 'ambang ${Controls.formatThi(_thiNormal)} / '
        '${Controls.formatThi(_thiDanger)}';
    final value = _climateOk ? 'THI ${_fmt(_sensor!.thi, 1)}' : null;
    final Widget status;
    // Nilai & ambang juga sebagai teks di LUAR grafik, mengikuti skala teks
    // penuh (angka di dalam gauge dibatasi 1.3× agar tetap di dalam busur).
    final String note;
    if (!_hasData) {
      status = const StatusBadge(
          text: 'Tidak ada data', tone: PitikTone.neutral, large: true);
      note = 'Ambang ${Controls.formatThi(_thiNormal)} / '
          '${Controls.formatThi(_thiDanger)}';
    } else if (_stale) {
      status = StatusBadge(
        text: _climateOk
            ? 'Status terakhir: ${_label(level!)}'
            : 'Laporan terakhir: sensor error',
        tone: PitikTone.neutral,
        large: true,
      );
      note = value != null
          ? 'Nilai terakhir: $value · $_lastReportAt'
          : 'Nilai terakhir · $_lastReportAt';
    } else if (!_climateOk) {
      status = const StatusBadge(
          text: 'Sensor error', tone: PitikTone.danger, large: true);
      note = 'THI tidak tersedia · $thresholds';
    } else {
      status =
          StatusBadge(text: _label(level!), tone: _tone(level), large: true);
      note = '$value · $thresholds';
    }

    return PitikCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      child: Column(
        children: [
          const SectionHeader(
            icon: Icons.speed_rounded,
            iconColor: PitikColors.thi,
            title: 'THI Monitor',
          ),
          const SizedBox(height: 8),
          // Grafik dikecualikan dari pembaca layar: nilai, status, dan ambang
          // dibacakan dari teks di bawahnya (skala penuh).
          ExcludeSemantics(
            child: THIGauge(
              style: THIGaugeStyle.pitik,
              value: _climateOk ? _sensor!.thi : null,
              muted: _stale,
              // Skala 50–100 = rentang ambang yang diizinkan firmware.
              minValue: Controls.thiMin,
              maxValue: Controls.thiMax,
              normalMax: _thiNormal,
              warningMax: _thiDanger,
            ),
          ),
          const SizedBox(height: 10),
          status,
          const SizedBox(height: 6),
          Text(note, style: PitikText.body, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          const Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            runSpacing: 6,
            children: [
              _Legend(
                  label: 'Normal',
                  fill: PitikColors.zoneNormal,
                  edge: PitikColors.zoneNormalEdge),
              _Legend(
                  label: 'Waspada',
                  fill: PitikColors.zoneWarning,
                  edge: PitikColors.zoneWarningEdge),
              _Legend(
                  label: 'Bahaya',
                  fill: PitikColors.zoneDanger,
                  edge: PitikColors.zoneDangerEdge),
            ],
          ),
        ],
      ),
    );
  }
}

class _SolidChip extends StatelessWidget {
  const _SolidChip({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          height: 1.3,
          color: Colors.white,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Baris label kiri — nilai kanan; nilai membungkus, tidak dipotong.
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.lines,
    this.divider = false,
  });

  final String label;
  final List<String> lines;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: divider
          ? const BoxDecoration(
              border: Border(bottom: BorderSide(color: PitikColors.divider)))
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: PitikText.body.copyWith(height: 1.4)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < lines.length; i++)
                  Text(
                    lines[i],
                    textAlign: TextAlign.right,
                    style: i == 0
                        ? const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w500,
                            height: 1.35,
                            color: PitikColors.text,
                            fontFeatures: [FontFeature.tabularFigures()],
                          )
                        : PitikText.body.copyWith(height: 1.35),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.label, required this.fill, required this.edge});

  final String label;
  final Color fill;
  final Color edge;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: fill,
            border: Border.all(color: edge, width: 1.5),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: PitikText.caption),
      ],
    );
  }
}
