// [INDO] Settings Screen — redesign batch 4 (referensi PitikPengaturan).
// Ambang THI dibaca dari /controls (DeviceState) dan ditulis ke
// controls/thi_normal + controls/thi_danger lewat PitikRepository.
// Tamu (anonim) hanya melihat: ambang & jadwal pakan dikunci.
//
// Perilaku simpan/validasi/reset/picker TIDAK diubah oleh redesign; hasil
// simpan kini tampil di dalam kartu (bukan snackbar). "Perubahan disimpan." =
// penulisan ke /controls selesai, BUKAN bukti ESP32 sudah menerapkan
// (firmware tidak mengirim konfirmasi ambang/jadwal).
// lib/screens/settings_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/controls.dart';
import '../models/sensor_data.dart';
import '../services/auth_service.dart';
import '../services/device_state.dart';
import '../services/pitik_repository.dart';
import '../theme/pitik_tokens.dart';
import '../utils/wib_time.dart';
import '../widgets/connection_row.dart';
import '../widgets/guest_banner.dart';
import '../widgets/pitik_card.dart';
import '../widgets/status_chip.dart';
import 'info_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.repository,
    required this.deviceState,
    this.isGuest = false,
    this.phoneNumber,
  });

  final PitikRepository repository;
  final DeviceState deviceState;

  /// Tamu (anonim): pengaturan perangkat read-only.
  final bool isGuest;
  final String? phoneNumber;

  /// Nomor HP untuk tampilan: "+62 812-••••-1234". Data auth asli tidak diubah.
  static String maskPhoneNumber(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 5) return '••••';
    final last4 = digits.substring(digits.length - 4);
    if (raw.trim().startsWith('+62') && digits.length >= 9) {
      final rest = digits.substring(2); // tanpa kode negara 62
      return '+62 ${rest.substring(0, 3)}-••••-$last4';
    }
    return '••••-$last4';
  }

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

/// Hasil simpan terakhir (sisi aplikasi).
enum _SaveResult { saved, error }

/// Lama "Perubahan disimpan." tampil sebelum kembali ke status stabil.
const _savedVisible = Duration(seconds: 5);

class _SettingsScreenState extends State<SettingsScreen> {
  // Ambang THI: draft lokal selama diedit; null = ikut nilai /controls
  // (realtime, termasuk bila diubah dari perangkat lain).
  double? _draftNormal;
  double? _draftDanger;
  bool _savingThresholds = false;
  bool _savingSchedule = false;

  // Umpan balik simpan di dalam kartu (pengganti snackbar).
  _SaveResult? _thrResult;
  _SaveResult? _schedResult;
  Timer? _thrTimer;
  Timer? _schedTimer;

  // Hasil "Sambungkan Ulang" (pola sama dengan Dashboard & Kontrol).
  ReconnectResult? _reconnectResult;
  bool? _serverAtResult;

  Controls get _deviceControls => widget.deviceState.controlsOrDefault;
  double get _thiNormal => _draftNormal ?? _deviceControls.thiNormal;
  double get _thiDanger => _draftDanger ?? _deviceControls.thiDanger;
  bool get _thresholdsDirty =>
      _thiNormal != _deviceControls.thiNormal ||
      _thiDanger != _deviceControls.thiDanger;
  String? get _thresholdError =>
      Controls.validateThresholds(_thiNormal, _thiDanger);

  /// Tamu tidak boleh mengubah /controls.
  bool get _canEdit => !widget.isGuest;

  // Notification settings (placeholder — belum terhubung ke fitur apa pun)
  bool pushNotification = true;
  bool soundAlert = true;
  bool emailAlert = false;

  // App settings (placeholder)
  String language = 'Indonesia';
  String theme = 'Light';

  // Status online dari umur `timestamp` (DeviceState), bukan field `online`.
  bool get _espOnline => widget.deviceState.isOnline;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _thrTimer?.cancel();
    _schedTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      pushNotification = prefs.getBool('pushNotification') ?? true;
      soundAlert = prefs.getBool('soundAlert') ?? true;
      emailAlert = prefs.getBool('emailAlert') ?? false;
      language = prefs.getString('language') ?? 'Indonesia';
      theme = prefs.getString('theme') ?? 'Light';
    });
  }

  Future<void> _saveSettings() async {
    // Ambang THI TIDAK disimpan lokal — sumbernya /controls.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pushNotification', pushNotification);
    await prefs.setBool('soundAlert', soundAlert);
    await prefs.setBool('emailAlert', emailAlert);
    await prefs.setString('language', language);
    await prefs.setString('theme', theme);
  }

  // Dipertahankan untuk saat preferensi tersedia; kontrolnya kini nonaktif
  // ("Belum tersedia"), jadi belum dipanggil dari UI.
  // ignore: unused_element
  void _updateSetting(VoidCallback change) {
    setState(() {
      change();
      _saveSettings();
    });
  }

  void _setDraft({double? normal, double? danger, bool clear = false}) {
    setState(() {
      if (clear) {
        _draftNormal = null;
        _draftDanger = null;
      } else {
        _draftNormal = normal ?? _draftNormal;
        _draftDanger = danger ?? _draftDanger;
      }
      _thrTimer?.cancel();
      _thrResult = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild saat status online / data perangkat berubah.
    return ListenableBuilder(
      listenable: widget.deviceState,
      builder: (context, _) => _buildScaffold(),
    );
  }

  Widget _buildScaffold() {
    return Scaffold(
      backgroundColor: PitikColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
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
              _Section(title: 'Akun', child: _buildUserCard()),
              _Section(title: 'Perangkat', child: _buildDeviceCard()),
              _Section(title: 'Koneksi', child: _buildConnectionCard()),
              if (widget.isGuest) ...[
                const SizedBox(height: 20),
                const GuestBanner(
                  message:
                      'Ambang THI & jadwal pakan hanya bisa diubah oleh '
                      'peternak yang masuk dengan nomor HP.',
                  onLogin: AuthService.signOut,
                ),
              ],
              _Section(title: 'Ambang THI', child: _buildThresholdCard()),
              _Section(title: 'Jadwal Pakan', child: _buildFeedScheduleCard()),
              _Section(title: 'Notifikasi', child: _buildNotificationCard()),
              _Section(title: 'Aplikasi', child: _buildAppSettingsCard()),
              _Section(title: 'Info', child: _buildAboutCard()),
              const SizedBox(height: 20),
              _buildLogoutButton(),
              const SizedBox(height: 24),
              _buildVersionInfo(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.settings_rounded,
              color: PitikColors.accent,
              size: 30,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: const Text('Pengaturan', style: PitikText.pageTitle),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Konfigurasi aplikasi dan perangkat',
                  style: PitikText.body,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  Akun
  // ════════════════════════════════════════════

  Widget _buildUserCard() {
    final isGuest = widget.isGuest;
    final phone = widget.phoneNumber ?? '';
    // "Terverifikasi" hanya bila akun non-tamu benar-benar punya nomor HP
    // dari Firebase Auth (login OTP).
    final verified = !isGuest && phone.isNotEmpty;
    final title = isGuest
        ? 'Mode tamu'
        : phone.isNotEmpty
        ? SettingsScreen.maskPhoneNumber(phone)
        : 'Akun peternak';
    return PitikCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconTile(
            icon: isGuest ? Icons.person_outline_rounded : Icons.person_rounded,
            color: isGuest ? PitikColors.textSecondary : PitikColors.accent,
            background: isGuest
                ? PitikColors.neutralBg
                : PitikColors.accentTint,
            size: 48,
            iconSize: 26,
            radius: 24,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  label: isGuest ? null : 'Nomor HP disamarkan',
                  child: Text(
                    title,
                    style: PitikText.cardTitle.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                if (verified)
                  const StatusBadge(
                    text: 'Terverifikasi',
                    tone: PitikTone.success,
                  )
                else
                  Text(
                    isGuest
                        ? 'Anda dapat melihat pengaturan, tetapi tidak dapat '
                              'mengubahnya.'
                        : 'Masuk dengan nomor HP',
                    style: PitikText.body,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  Perangkat (diagnostik /sensor_data)
  // ════════════════════════════════════════════

  SensorData? get _sensor => widget.deviceState.sensor;

  /// Status koneksi app ↔ Firebase (bukan status ESP32).
  (String, Color) get _serverStatus {
    final s = widget.deviceState;
    if (s.isReconnecting) return ('Menyambungkan…', PitikColors.textSecondary);
    if (s.error != null) return ('Gagal terhubung', PitikColors.danger);
    // .info/connected bila tersedia; selain itu dari ada/tidaknya data.
    final connected = s.serverConnected ?? (s.hasSensor || s.hasControls);
    if (connected) return ('Terhubung', PitikColors.success);
    return s.serverConnected == false
        ? ('Tidak terhubung', PitikColors.danger)
        : ('Menghubungkan…', PitikColors.textSecondary);
  }

  Widget _buildDeviceCard() {
    final s = _sensor;
    final stale = s != null && !_espOnline;
    final reportedAt = WibTime.dayMonthTime(s?.timestamp);
    return PitikCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Data diagnostik berasal dari laporan perangkat; saat data lama,
          // nilainya adalah laporan terakhir — bukan kondisi saat ini.
          if (stale)
            _CardNote(
              icon: Icons.history_rounded,
              text: reportedAt == null
                  ? 'Nilai dari laporan terakhir perangkat'
                  : 'Nilai dari laporan terakhir perangkat · $reportedAt',
            ),
          const _InfoRow(
            icon: Icons.label_outline_rounded,
            label: 'Nama Kandang',
            value: 'Kandang 1',
            sub: 'Label tampilan aplikasi',
          ),
          const _Divider(),
          // Diagnostik dari /sensor_data (device_id, fw, uptime_s, hour/minute).
          _InfoRow(
            icon: Icons.memory_rounded,
            label: 'Device ID',
            value: s?.deviceId ?? '--',
          ),
          const _Divider(),
          _InfoRow(
            icon: Icons.system_update_alt_rounded,
            label: 'Firmware',
            value: s?.firmware != null ? 'v${s!.firmware}' : '--',
          ),
          const _Divider(),
          _InfoRow(
            icon: Icons.schedule_rounded,
            label: 'Jam Perangkat',
            // hour/minute = -1 → ESP32 belum dapat waktu NTP.
            value: s == null
                ? '--:--'
                : (s.hour < 0 || s.minute < 0)
                ? '--:-- (belum sinkron NTP)'
                : '${s.clockString} WIB',
          ),
          const _Divider(),
          _InfoRow(
            icon: Icons.timelapse_rounded,
            label: 'Uptime',
            value: s?.uptimeSeconds != null
                ? WibTime.durationText(s!.uptimeSeconds!)
                : '--',
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  Koneksi — satu lokasi reconnect, hasil inline
  // ════════════════════════════════════════════

  Future<void> _reconnect() async {
    final s = widget.deviceState;
    if (s.isReconnecting) return;
    setState(() => _reconnectResult = null);
    final result = await s.reconnect();
    if (!mounted) return;
    setState(() {
      _reconnectResult = result;
      _serverAtResult = s.serverConnected;
    });
  }

  /// Hasil hanya ditampilkan selama masih sesuai kondisi sekarang
  /// (aturan sama dengan Dashboard). Server tersambung ≠ perangkat online.
  ReconnectResult? get _visibleResult {
    final r = _reconnectResult;
    final s = widget.deviceState;
    if (r == null || s.isReconnecting) return null;
    final server = s.serverConnected;
    return switch (r) {
      ReconnectResult.serverError =>
        (server == true && _serverAtResult != true) ? null : r,
      ReconnectResult.deviceOnline =>
        (_espOnline && server != false) ? r : null,
      ReconnectResult.deviceOffline =>
        (!_espOnline && server != false) ? r : null,
    };
  }

  Widget _buildConnectionCard() {
    final server = _serverStatus;
    final visible = _visibleResult;
    final feedback = switch (visible) {
      ReconnectResult.deviceOnline => const _Feedback(
        kind: _FeedbackKind.ok,
        text: 'Server terhubung · data perangkat masih terbaru',
      ),
      ReconnectResult.serverError => const _Feedback(
        kind: _FeedbackKind.error,
        text: 'Belum terhubung ke server. Periksa internet ponsel.',
      ),
      ReconnectResult.deviceOffline => const _Feedback(
        kind: _FeedbackKind.warning,
        text:
            'Server terhubung, tetapi belum ada data baru dari perangkat. '
            'Periksa daya dan Wi-Fi ESP32 di kandang.',
      ),
      null => null,
    };
    return PitikCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _InfoRow(
            icon: Icons.wifi_rounded,
            label: 'Status Koneksi',
            sub: widget.deviceState.lastUpdateText,
            value: _espOnline ? 'Online' : 'Offline',
            valueColor: _espOnline ? PitikColors.success : PitikColors.danger,
          ),
          const _Divider(),
          _InfoRow(
            icon: Icons.link_rounded,
            label: 'Server (Firebase)',
            value: server.$1,
            valueColor: server.$2,
          ),
          const _Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ReconnectAction(
                  busy: widget.deviceState.isReconnecting,
                  onPressed: _reconnect,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Sambungkan ulang aplikasi ke server bila data tidak '
                  'masuk. ESP32 yang mati/putus WiFi harus dicek langsung.',
                  style: PitikText.caption,
                ),
                Semantics(
                  liveRegion: true,
                  child: RevealSize(
                    child: feedback == null
                        ? const SizedBox(width: double.infinity)
                        : Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: feedback,
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
  //  Ambang THI
  // ════════════════════════════════════════════

  Widget _buildThresholdCard() {
    final dirty = _thresholdsDirty;
    final error = _thresholdError;
    return PitikCard(
      key: const ValueKey('card-thresholds'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_canEdit)
            const _LockLine(text: 'Masuk untuk mengubah ambang THI'),
          if (!widget.deviceState.hasControls) ...[
            const Text(
              'Menunggu data dari perangkat — menampilkan default firmware.',
              style: PitikText.caption,
            ),
            const SizedBox(height: 12),
          ],
          // Ambang normal → kipas (histeresis firmware: OFF di normal − 2)
          _ThresholdControl(
            label: 'Ambang normal (kipas)',
            value: _thiNormal,
            color: PitikColors.success,
            track: PitikColors.successBg,
            description:
                'Mode otomatis: kipas ON bila THI ≥ '
                '${Controls.formatThi(_thiNormal)}, OFF bila ≤ '
                '${Controls.formatThi(_thiNormal - 2)}',
            disabledReason: _canEdit ? null : 'Mode tamu — hanya melihat',
            onChanged: _canEdit ? (value) => _setDraft(normal: value) : null,
          ),
          const SizedBox(height: 18),
          // Ambang bahaya → pompa (histeresis firmware: OFF di bahaya − 3)
          _ThresholdControl(
            label: 'Ambang bahaya (pompa)',
            value: _thiDanger,
            color: PitikColors.danger,
            track: PitikColors.dangerBg,
            description:
                'Mode otomatis: pompa ON bila THI ≥ '
                '${Controls.formatThi(_thiDanger)}, OFF bila ≤ '
                '${Controls.formatThi(_thiDanger - 3)}',
            disabledReason: _canEdit ? null : 'Mode tamu — hanya melihat',
            onChanged: _canEdit ? (value) => _setDraft(danger: value) : null,
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            _Feedback(kind: _FeedbackKind.error, text: error),
          ],
          if (_canEdit) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Semantics(
                  liveRegion: true,
                  child: StatusBadge(
                    text: _savingThresholds
                        ? 'Menyimpan perubahan…'
                        : dirty
                        ? 'Belum disimpan'
                        : 'Tidak ada perubahan',
                    tone: _savingThresholds
                        ? PitikTone.accent
                        : dirty
                        ? PitikTone.warning
                        : PitikTone.neutral,
                  ),
                ),
                if (dirty)
                  Text(
                    'Nilai tersimpan: normal '
                    '${Controls.formatThi(_deviceControls.thiNormal)} · bahaya '
                    '${Controls.formatThi(_deviceControls.thiDanger)}',
                    style: PitikText.caption,
                  ),
              ],
            ),
          ],
          if (_canEdit) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _TextAction(
                  label:
                      'Reset ke Default '
                      '(${Controls.formatThi(Controls.defaultThiNormal)}/'
                      '${Controls.formatThi(Controls.defaultThiDanger)})',
                  onPressed: _savingThresholds
                      ? null
                      : () => _setDraft(
                          normal: Controls.defaultThiNormal,
                          danger: Controls.defaultThiDanger,
                        ),
                ),
                if (dirty)
                  _TextAction(
                    label: 'Batal',
                    muted: true,
                    onPressed: _savingThresholds
                        ? null
                        : () => _setDraft(clear: true),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // Tidak dikunci saat offline: nilai tersimpan di /controls dan
            // dibaca ESP32 lewat stream saat tersambung.
            _PrimaryButton(
              label: _savingThresholds
                  ? 'Menyimpan perubahan…'
                  : 'Simpan perubahan',
              icon: Icons.cloud_upload_rounded,
              busy: _savingThresholds,
              onPressed: dirty && error == null && !_savingThresholds
                  ? _saveThresholds
                  : null,
            ),
            _ResultLine(result: _thrResult),
            const _HelperText(),
          ],
          if (!_canEdit)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Dipakai oleh Mode otomatis.',
                style: PitikText.caption,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _saveThresholds() async {
    final normal = _thiNormal;
    final danger = _thiDanger;
    _thrTimer?.cancel();
    setState(() {
      _savingThresholds = true;
      _thrResult = null;
    });
    try {
      await widget.repository.setThresholds(normal, danger);
      if (!mounted) return;
      // /controls sudah memuat nilai baru → draft tidak diperlukan lagi.
      setState(() {
        _draftNormal = null;
        _draftDanger = null;
        _thrResult = _SaveResult.saved;
      });
      _thrTimer = Timer(_savedVisible, () {
        if (mounted) setState(() => _thrResult = null);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _thrResult = _SaveResult.error);
    } finally {
      if (mounted) setState(() => _savingThresholds = false);
    }
  }

  // ════════════════════════════════════════════
  //  JADWAL PAKAN — controls/feed_hour1..3 & feed_min1..3
  //  Pilih jam lewat time picker → langsung disimpan (picker = konfirmasi).
  // ════════════════════════════════════════════

  Widget _buildFeedScheduleCard() {
    final times = _deviceControls.feedTimes;
    final canTap = _canEdit && !_savingSchedule;
    return PitikCard(
      key: const ValueKey('card-schedule'),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_canEdit)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _LockLine(text: 'Masuk untuk mengubah jadwal pakan'),
            ),
          for (var i = 0; i < times.length; i++) ...[
            if (i > 0) const _Divider(),
            _InfoRow(
              icon: Icons.restaurant_rounded,
              label: 'Pakan ${i + 1}',
              value: '${times[i].label} WIB',
              valueColor: PitikColors.text,
              chevron: _canEdit,
              semanticsHint: !_canEdit
                  ? 'Mode tamu — hanya melihat'
                  : _savingSchedule
                  ? 'Sedang menyimpan jadwal'
                  : 'Ketuk untuk mengubah jam',
              onTap: canTap ? () => _pickFeedTime(i) : null,
            ),
          ],
          const _Divider(),
          _InfoRow(
            icon: Icons.history_rounded,
            label: 'Pakan terakhir',
            sub: widget.deviceState.lastFeedText,
          ),
          if (_canEdit)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TextAction(
                    label:
                        'Reset ke Default '
                        '(${Controls.defaultFeedTimes.map((t) => t.label).join(', ')})',
                    onPressed:
                        _savingSchedule ||
                            _sameTimes(times, Controls.defaultFeedTimes)
                        ? null
                        : _confirmResetFeedSchedule,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ResultLine(
                          result: _schedResult,
                          busy: _savingSchedule,
                        ),
                        const _HelperText(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static bool _sameTimes(List<FeedTime> a, List<FeedTime> b) =>
      a.length == b.length &&
      Iterable.generate(a.length).every((i) => a[i] == b[i]);

  Future<void> _pickFeedTime(int slot) async {
    final current = _deviceControls.feedTimes[slot];
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
      helpText: 'Jam Pakan ${slot + 1} (WIB)',
      cancelText: 'Batal',
      confirmText: 'Simpan',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    final updated = [..._deviceControls.feedTimes];
    updated[slot] = FeedTime(picked.hour, picked.minute);
    if (updated[slot] == current) return;
    await _saveFeedSchedule(updated);
  }

  void _confirmResetFeedSchedule() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reset Jadwal Pakan'),
        content: Text(
          'Kembalikan jadwal ke '
          '${Controls.defaultFeedTimes.map((t) => t.label).join(', ')} WIB?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(
              'Batal',
              style: TextStyle(color: PitikColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _saveFeedSchedule(Controls.defaultFeedTimes);
            },
            child: const Text(
              'Reset',
              style: TextStyle(
                color: PitikColors.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveFeedSchedule(List<FeedTime> times) async {
    _schedTimer?.cancel();
    setState(() {
      _savingSchedule = true;
      _schedResult = null;
    });
    try {
      await widget.repository.setFeedSchedule(times);
      if (!mounted) return;
      setState(() => _schedResult = _SaveResult.saved);
      _schedTimer = Timer(_savedVisible, () {
        if (mounted) setState(() => _schedResult = null);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _schedResult = _SaveResult.error);
    } finally {
      if (mounted) setState(() => _savingSchedule = false);
    }
  }

  // ════════════════════════════════════════════
  //  Preferensi placeholder — dipertahankan, tetapi NONAKTIF
  //  (belum terhubung ke fitur apa pun). Nilai tersimpan lokal tetap dibaca.
  // ════════════════════════════════════════════

  Widget _buildNotificationCard() {
    return PitikCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PlaceholderRow(
            icon: Icons.notifications_active_outlined,
            label: 'Push Notification',
            subtitle: 'Terima notifikasi peringatan',
            switchValue: pushNotification,
          ),
          const _Divider(),
          _PlaceholderRow(
            icon: Icons.volume_up_outlined,
            label: 'Suara Peringatan',
            subtitle: 'Bunyi saat kondisi bahaya',
            switchValue: soundAlert,
          ),
          const _Divider(),
          _PlaceholderRow(
            icon: Icons.email_outlined,
            label: 'Email Alert',
            subtitle: 'Kirim laporan via email',
            switchValue: emailAlert,
          ),
        ],
      ),
    );
  }

  Widget _buildAppSettingsCard() {
    return PitikCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PlaceholderRow(
            icon: Icons.language_rounded,
            label: 'Bahasa',
            subtitle: 'Pilihan tersimpan: $language',
          ),
          const _Divider(),
          _PlaceholderRow(
            icon: Icons.palette_rounded,
            label: 'Tema',
            subtitle: 'Pilihan tersimpan: $theme',
          ),
        ],
      ),
    );
  }

  // "Interval Update" (5 detik) disembunyikan dari tampilan (keputusan
  // desain batch 4); baris lama dipertahankan di sini, tidak dipanggil.
  // ignore: unused_element
  Widget _buildIntervalUpdateRow() => const _InfoRow(
    icon: Icons.timer_rounded,
    label: 'Interval Update',
    value: '5 detik',
  );

  Widget _buildAboutCard() {
    return PitikCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _InfoRow(
            icon: Icons.info_outline_rounded,
            label: 'Tentang Aplikasi',
            chevron: true,
            onTap: _showAboutDialog,
          ),
          const _Divider(),
          _InfoRow(
            icon: Icons.help_outline_rounded,
            label: 'Bantuan',
            chevron: true,
            // navigate ke InfoScreen tab Bantuan
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const InfoScreen(initialTab: 0),
              ),
            ),
          ),
          const _Divider(),
          _InfoRow(
            icon: Icons.privacy_tip_outlined,
            label: 'Kebijakan Privasi',
            chevron: true,
            // navigate ke InfoScreen tab Kebijakan Privasi
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const InfoScreen(initialTab: 1),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoutButton() {
    return Semantics(
      button: true,
      label: 'Keluar dari Akun',
      excludeSemantics: true,
      onTap: _showLogoutDialog,
      child: Material(
        color: PitikColors.surface,
        borderRadius: BorderRadius.circular(PitikRadius.card),
        child: InkWell(
          onTap: _showLogoutDialog,
          borderRadius: BorderRadius.circular(PitikRadius.card),
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(PitikRadius.card),
              border: Border.all(color: PitikColors.dangerBorder),
            ),
            child: const Row(
              children: [
                IconTile(
                  icon: Icons.logout_rounded,
                  color: PitikColors.dangerIcon,
                  background: PitikColors.dangerSurface,
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Keluar dari Akun',
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: PitikColors.danger,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: PitikColors.danger,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Keluar dari Akun'),
        content: const Text('Apakah Anda yakin ingin keluar dari akun?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Batal',
              style: TextStyle(color: PitikColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await AuthService.signOut();
              // AuthWrapper akan auto redirect ke Login
            },
            child: const Text(
              'Keluar',
              style: TextStyle(
                color: PitikColors.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVersionInfo() {
    // Versi = pubspec (1.0.0+1); belum dibaca otomatis karena tidak ada paket
    // info aplikasi di dependensi.
    return const Center(
      child: Column(
        children: [
          Text('PITIK v1.0.0', style: PitikText.caption),
          SizedBox(height: 4),
          Text(
            'BINUS University © 2026',
            style: TextStyle(fontSize: 13, color: PitikColors.textSecondary),
          ),
        ],
      ),
    );
  }

  // Dipertahankan (placeholder Bahasa) — belum dipanggil dari UI.
  // ignore: unused_element
  void _showLanguageDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Pilih Bahasa'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('🇮🇩 Indonesia'),
              onTap: () {
                _updateSetting(() => language = 'Indonesia');
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('🇬🇧 English'),
              onTap: () {
                _updateSetting(() => language = 'English');
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  // Dipertahankan (placeholder Tema) — belum dipanggil dari UI.
  // ignore: unused_element
  void _showThemeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Pilih Tema'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.light_mode),
              title: const Text('Light'),
              onTap: () {
                _updateSetting(() => theme = 'Light');
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.dark_mode),
              title: const Text('Dark'),
              onTap: () {
                _updateSetting(() => theme = 'Dark');
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF007AFF).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('🐦', style: TextStyle(fontSize: 24)),
            ),
            const SizedBox(width: 12),
            const Text('PITIK'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Puyuh IoT Technology & Intelligent Kontrol',
              style: TextStyle(fontSize: 13),
            ),
            SizedBox(height: 16),
            Text('Developers:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('• Ricky Rudiansyah'),
            Text('• Marcellino Asanuddin'),
            SizedBox(height: 12),
            Text('Supervisor:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('• Prof. Dr. Ir. Widodo Budiharto'),
            SizedBox(height: 12),
            Text('Version: 1.0.0'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════
//  Komponen kecil layar Pengaturan
// ════════════════════════════════════════════

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.3,
                  fontWeight: FontWeight.w700,
                  color: PitikColors.textSecondary,
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => const Divider(
    height: 1,
    thickness: 1,
    indent: 64,
    color: PitikColors.divider,
  );
}

/// Baris pengaturan: ikon + label (+ sub) + nilai / trailing / chevron.
/// Teks tidak dipotong; nilai turun baris bila tidak muat.
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    this.value,
    this.valueColor,
    this.sub,
    this.chevron = false,
    this.onTap,
    this.semanticsHint,
  });

  final IconData icon;
  final String label;
  final String? value;
  final Color? valueColor;
  final String? sub;
  final bool chevron;
  final VoidCallback? onTap;
  final String? semanticsHint;

  @override
  Widget build(BuildContext context) {
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            Icon(icon, color: PitikColors.textSecondary, size: 24),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 2,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            fontSize: 16,
                            height: 1.35,
                            color: PitikColors.text,
                          ),
                        ),
                        if (value != null && value!.isNotEmpty)
                          Text(
                            value!,
                            style: TextStyle(
                              fontSize: 16,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                              color: valueColor ?? PitikColors.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (sub != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(sub!, style: PitikText.caption),
                    ),
                ],
              ),
            ),
            if (chevron)
              Icon(
                Icons.chevron_right_rounded,
                color: onTap == null
                    ? PitikColors.arcMuted
                    : PitikColors.textSecondary,
                size: 24,
              ),
          ],
        ),
      ),
    );
    if (onTap == null && semanticsHint == null) {
      return MergeSemantics(child: content);
    }
    return MergeSemantics(
      child: Semantics(
        button: chevron,
        enabled: onTap != null,
        hint: semanticsHint,
        child: InkWell(onTap: onTap, child: content),
      ),
    );
  }
}

/// Preferensi yang belum berfungsi: label tetap terbaca, kontrol nonaktif,
/// alasan "Belum tersedia" terlihat & dibacakan.
class _PlaceholderRow extends StatelessWidget {
  const _PlaceholderRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    this.switchValue,
  });

  final IconData icon;
  final String label;
  final String subtitle;

  /// null = baris pilihan (Bahasa/Tema), selain itu switch nonaktif.
  final bool? switchValue;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Semantics(
        hint: 'Fitur belum tersedia',
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(
              children: [
                Icon(icon, color: PitikColors.navInactive, size: 24),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            label,
                            style: const TextStyle(
                              fontSize: 16,
                              height: 1.35,
                              color: PitikColors.textMuted,
                            ),
                          ),
                          const StatusBadge(
                            text: 'Belum tersedia',
                            tone: PitikTone.neutral,
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(subtitle, style: PitikText.caption),
                      ),
                    ],
                  ),
                ),
                if (switchValue != null)
                  Switch(
                    value: switchValue!,
                    onChanged: null,
                    thumbColor: const WidgetStatePropertyAll(Color(0xFFFAFAFB)),
                    trackColor: WidgetStatePropertyAll(
                      switchValue!
                          ? const Color(0xFFAFC1EC)
                          : const Color(0xFFF1F2F4),
                    ),
                    trackOutlineColor: WidgetStatePropertyAll(
                      switchValue!
                          ? const Color(0xFFAFC1EC)
                          : const Color(0xFFC9CED6),
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

class _CardNote extends StatelessWidget {
  const _CardNote({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: PitikColors.surfaceMuted,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(PitikRadius.card),
        ),
        border: Border(bottom: BorderSide(color: PitikColors.divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 18, color: PitikColors.textSecondary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: PitikText.caption.copyWith(color: PitikColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _LockLine extends StatelessWidget {
  const _LockLine({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              Icons.lock_rounded,
              size: 18,
              color: PitikColors.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 15,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: PitikColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Satu ambang: label + nilai besar + slider (rentang & langkah existing).
class _ThresholdControl extends StatelessWidget {
  const _ThresholdControl({
    required this.label,
    required this.value,
    required this.color,
    required this.track,
    required this.description,
    required this.disabledReason,
    required this.onChanged,
  });

  final String label;
  final double value;
  final Color color;
  final Color track;
  final String description;
  final String? disabledReason;
  final ValueChanged<double>? onChanged; // null = read-only (tamu)

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label & nilai dibacakan lewat slider (label + "THI x").
        ExcludeSemantics(
          child: SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 2,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(child: Text(label, style: PitikText.bodyStrong)),
                  ],
                ),
                Text(
                  Controls.formatThi(value),
                  style: TextStyle(
                    fontSize: 32,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                    color: onChanged == null ? PitikColors.text : color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        // Rentang slider = rentang kontrak firmware (thiMin–thiMax), langkah 0,5.
        MergeSemantics(
          child: Semantics(
            label: label,
            hint: disabledReason,
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: color,
                inactiveTrackColor: track,
                thumbColor: color,
                overlayColor: color.withValues(alpha: 0.12),
                disabledActiveTrackColor: PitikColors.arcMuted,
                disabledInactiveTrackColor: PitikColors.neutralBg,
                disabledThumbColor: PitikColors.navInactive,
                trackHeight: 6,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11),
              ),
              child: Slider(
                value: value.clamp(Controls.thiMin, Controls.thiMax),
                min: Controls.thiMin,
                max: Controls.thiMax,
                divisions: ((Controls.thiMax - Controls.thiMin) * 2).round(),
                semanticFormatterCallback: (v) =>
                    'THI ${Controls.formatThi(v)}',
                onChanged: onChanged,
              ),
            ),
          ),
        ),
        Text(description, style: PitikText.caption),
      ],
    );
  }
}

class _TextAction extends StatelessWidget {
  const _TextAction({
    required this.label,
    required this.onPressed,
    this.muted = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: muted ? PitikColors.textSecondary : PitikColors.accent,
        disabledForegroundColor: PitikColors.navInactive,
        minimumSize: const Size(PitikSpace.touch, PitikSpace.touch),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        animationDuration: PitikMotion.of(context, kThemeChangeDuration),
        textStyle: (Theme.of(context).textTheme.labelLarge ?? const TextStyle())
            .copyWith(fontSize: 15, fontWeight: FontWeight.w600, height: 1.3),
      ),
      child: Text(label),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.icon,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final reduced = PitikMotion.reduced(context);
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: PitikColors.accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: busy
              ? PitikColors.accent
              : const Color(0xFFE5E7EB),
          disabledForegroundColor: busy
              ? Colors.white
              : PitikColors.textSecondary,
          minimumSize: const Size.fromHeight(52),
          elevation: 0,
          animationDuration: PitikMotion.of(context, kThemeChangeDuration),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PitikRadius.control),
          ),
          textStyle:
              (Theme.of(context).textTheme.labelLarge ?? const TextStyle())
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
            : Icon(icon, size: 20),
        label: Text(label),
      ),
    );
  }
}

enum _FeedbackKind { ok, warning, error, busy }

class _Feedback extends StatelessWidget {
  const _Feedback({required this.kind, required this.text});

  final _FeedbackKind kind;
  final String text;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color fg, Color bg, Color border) = switch (kind) {
      _FeedbackKind.ok => (
        Icons.cloud_done_rounded,
        PitikColors.textSecondary,
        PitikColors.surfaceMuted,
        PitikColors.border,
      ),
      _FeedbackKind.warning => (
        Icons.info_rounded,
        PitikColors.warning,
        PitikColors.warningSurface,
        PitikColors.warningBorder,
      ),
      _FeedbackKind.error => (
        Icons.error_rounded,
        PitikColors.dangerIcon,
        PitikColors.dangerSurface,
        PitikColors.dangerBorder,
      ),
      _FeedbackKind.busy => (
        Icons.hourglass_top_rounded,
        PitikColors.accent,
        PitikColors.accentSoft,
        PitikColors.accentSoftBorder,
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
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 18, color: fg),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: PitikText.bodyStrong.copyWith(
                color: kind == _FeedbackKind.error
                    ? PitikColors.dangerStrong
                    : PitikColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Hasil simpan di sisi aplikasi (bukan konfirmasi perangkat).
class _ResultLine extends StatelessWidget {
  const _ResultLine({required this.result, this.busy = false});

  final _SaveResult? result;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final Widget? child = busy
        ? const _Feedback(
            kind: _FeedbackKind.busy,
            text: 'Menyimpan perubahan…',
          )
        : switch (result) {
            _SaveResult.saved => const _Feedback(
              kind: _FeedbackKind.ok,
              text: 'Perubahan disimpan.',
            ),
            _SaveResult.error => const _Feedback(
              kind: _FeedbackKind.error,
              text: 'Gagal menyimpan perubahan. Periksa koneksi.',
            ),
            null => null,
          };
    return Semantics(
      liveRegion: true,
      child: RevealSize(
        child: child == null
            ? const SizedBox(width: double.infinity)
            : Padding(padding: const EdgeInsets.only(top: 10), child: child),
      ),
    );
  }
}

/// Penjelasan domain STATIS (bukan status/konfirmasi perangkat).
class _HelperText extends StatelessWidget {
  const _HelperText();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 8),
      child: Text(
        'Perangkat akan menggunakan pengaturan ini saat tersambung.',
        style: PitikText.caption,
      ),
    );
  }
}
