// History Screen — redesign batch 2 (referensi PitikRiwayat).
// Data: PitikRepository.fetchHistory (query/periode/sampling TIDAK diubah).
//
// Aturan tampilan:
//  - Periode TERPILIH (_selectedPeriod) dipisah dari periode DATA yang sedang
//    tampil (_dataPeriod). Grafik lama tidak pernah dilabeli periode baru.
//  - Respons lama diabaikan (_loadSeq) bila pengguna sudah memilih periode lain.
//  - "Salin CSV" hanya aktif bila data yang tampil = periode terpilih dan
//    tidak sedang memuat — CSV tidak pernah berisi data periode lain.
// lib/screens/history_screen.dart

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/controls.dart';
import '../models/history_point.dart';
import '../services/device_state.dart';
import '../services/pitik_repository.dart';
import '../theme/pitik_tokens.dart';
import '../widgets/history_chart_card.dart';
import '../widgets/pitik_card.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.repository,
    required this.deviceState,
  });

  final PitikRepository repository;

  /// Hanya untuk ambang THI (/controls) pada zona grafik.
  final DeviceState deviceState;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  PitikRepository get _repository => widget.repository;

  // Urutan = HistoryPeriod.values: 1 Jam, 24 Jam, 7 Hari, 30 Hari.
  static const _periods = ['1 Jam', '24 Jam', '7 Hari', '30 Hari'];
  static const _periodPhrase = ['1 jam', '24 jam', '7 hari', '30 hari'];

  /// Periode yang dipilih pengguna.
  int _selectedPeriod = 1;

  /// Periode dari data yang SEDANG ditampilkan (null = belum pernah termuat).
  int? _dataPeriod;

  List<HistoryPoint> _historyData = const [];
  HistoryStats? _stats;
  bool _isLoading = true;

  /// Error muatan terakhir untuk _selectedPeriod (null = tidak ada).
  Object? _error;

  /// Nomor muatan terakhir; respons lama (periode diganti cepat) diabaikan.
  int _loadSeq = 0;

  /// Titik terpilih per grafik (indeks pada daftar titik grafik tsb).
  final Map<String, int?> _selected = {};

  bool _copied = false;
  Timer? _copiedTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    final seq = ++_loadSeq;
    final period = _selectedPeriod;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final data = await _repository.fetchHistory(HistoryPeriod.values[period]);
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _historyData = data;
        _stats = HistoryStats.fromPoints(data);
        _dataPeriod = period;
        _isLoading = false;
        _selected.clear();
      });
    } catch (e) {
      if (!mounted || seq != _loadSeq) return;
      debugPrint('[HistoryScreen] gagal memuat ${_periods[period]}: $e');
      setState(() {
        _error = e;
        _isLoading = false;
      });
    }
  }

  void _selectPeriod(int index) {
    if (index == _selectedPeriod && _error == null) return;
    setState(() {
      _selectedPeriod = index;
      _copied = false;
    });
    _loadData();
  }

  // ════════════════════════════════════════════
  //  Keadaan turunan
  // ════════════════════════════════════════════

  bool get _hasShownData => _dataPeriod != null;

  /// Data yang tampil berasal dari periode lain / sedang diperbarui.
  bool get _showingOtherPeriod =>
      _hasShownData && _dataPeriod != _selectedPeriod;

  bool get _csvEnabled =>
      !_isLoading &&
      _error == null &&
      _dataPeriod == _selectedPeriod &&
      _historyData.isNotEmpty;

  String get _dataLabel => _hasShownData ? _periods[_dataPeriod!] : '';

  void _exportCsv() {
    if (!_csvEnabled) return;
    final csv = historyToCsv(_historyData);
    Clipboard.setData(ClipboardData(text: csv));
    _copiedTimer?.cancel();
    setState(() => _copied = true);
    _copiedTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _copied = false);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'CSV $_dataLabel disalin (${_historyData.length} baris). '
          'Tempel di Excel/Notepad.',
        ),
        backgroundColor: PitikColors.success,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PitikColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
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
                const SizedBox(height: PitikSpace.gap),
                _buildPeriodSelector(),
                _buildNotice(),
                const SizedBox(height: PitikSpace.gap),
                ..._buildBody(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════
  //  Header & pemilih periode
  // ════════════════════════════════════════════

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.start,
        spacing: 12,
        runSpacing: 10,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.show_chart_rounded,
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
                        'Riwayat Data',
                        style: PitikText.pageTitle,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Analisis tren suhu & kelembapan',
                      style: PitikText.body,
                    ),
                  ],
                ),
              ),
            ],
          ),
          _CsvButton(
            enabled: _csvEnabled,
            copied: _copied && _csvEnabled,
            onPressed: _exportCsv,
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: PitikColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PitikColors.border),
        boxShadow: PitikDecor.cardShadow,
      ),
      // IntrinsicHeight: tinggi semua tombol sama bila satu label turun baris.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < _periods.length; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(child: _periodButton(i)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _periodButton(int i) {
    final selected = i == _selectedPeriod;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Periode ${_periods[i]}',
      excludeSemantics: true,
      onTap: () => _selectPeriod(i),
      child: Material(
        color: selected ? PitikColors.accent : Colors.transparent,
        animationDuration: PitikMotion.of(context, kThemeChangeDuration),
        borderRadius: BorderRadius.circular(PitikRadius.control),
        child: InkWell(
          onTap: () => _selectPeriod(i),
          borderRadius: BorderRadius.circular(PitikRadius.control),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: PitikSpace.touch),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Text(
                  _periods[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.2,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? Colors.white : PitikColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Pemberitahuan saat data yang tampil BUKAN hasil muatan terbaru periode
  /// terpilih (sedang memuat / gagal) — selalu menyebut periode data.
  Widget _buildNotice() {
    Widget? notice;
    final target = _periods[_selectedPeriod];
    if (_hasShownData && _isLoading) {
      notice = _NoticeBox(
        busy: true,
        title: _showingOtherPeriod
            ? 'Memuat data $target…'
            : 'Memperbarui data $target…',
        body: 'Grafik di bawah masih data $_dataLabel.',
      );
    } else if (_hasShownData && _error != null) {
      notice = _NoticeBox(
        error: true,
        title: _showingOtherPeriod
            ? 'Gagal memuat data $target.'
            : 'Gagal memperbarui data $target.',
        body:
            'Grafik di bawah masih data $_dataLabel. '
            'Periksa koneksi internet ponsel, lalu coba lagi.',
        onRetry: _loadData,
      );
    }
    return Semantics(
      liveRegion: true,
      child: RevealSize(
        child: notice == null
            ? const SizedBox(width: double.infinity)
            : Padding(padding: const EdgeInsets.only(top: 10), child: notice),
      ),
    );
  }

  // ════════════════════════════════════════════
  //  Isi
  // ════════════════════════════════════════════

  List<Widget> _buildBody() {
    final target = _periods[_selectedPeriod];

    // Belum pernah ada data termuat.
    if (!_hasShownData) {
      if (_isLoading) return [_LoadingState(periodLabel: target)];
      if (_error != null) {
        return [_ErrorState(periodLabel: target, onRetry: _loadData)];
      }
    }

    // Dataset yang tampil kosong → keadaan kosong (bukan angka nol).
    if (_historyData.isEmpty) {
      // Frasa mengikuti periode DATA yang tampil (bukan yang sedang dimuat).
      return [
        _EmptyState(phrase: _periodPhrase[_dataPeriod ?? _selectedPeriod]),
      ];
    }

    return [
      ..._buildCharts(),
      const SizedBox(height: PitikSpace.gap),
      _buildStatisticsCard(),
    ];
  }

  String _f(double v, int d) => v.toStringAsFixed(d);

  List<Widget> _buildCharts() {
    final data = _historyData;
    final stats = _stats ?? HistoryStats.fromPoints(data);
    final period = _dataLabel;
    final mqPoints = [
      for (final p in data)
        if (p.mq137Raw != null) p,
    ];
    final thiValues = [for (final p in data) p.thi];

    Widget card({
      required String key,
      required String title,
      required IconData icon,
      required Color color,
      required Color tint,
      required List<HistoryPoint> points,
      required double Function(HistoryPoint) valueOf,
      required String unit,
      required int decimals,
      required List<ChartStat> chartStats,
      ThiZones? zones,
      Widget? footer,
      String? emptyText,
    }) => HistoryChartCard(
      key: ValueKey('chart-$key'),
      title: title,
      icon: icon,
      color: color,
      tint: tint,
      periodLabel: period,
      points: points,
      valueOf: valueOf,
      unit: unit,
      decimals: decimals,
      stats: chartStats,
      zones: zones,
      footer: footer,
      emptyText: emptyText ?? 'Tidak ada data pada periode ini.',
      selectedIndex: _selected[key],
      onSelect: (i) => setState(() => _selected[key] = i),
    );

    return [
      card(
        key: 'suhu',
        title: 'Suhu (°C)',
        icon: Icons.device_thermostat_rounded,
        color: PitikColors.temp,
        tint: PitikColors.tempBg,
        points: data,
        valueOf: (p) => p.temperature,
        unit: '°C',
        decimals: 1,
        chartStats: [
          ChartStat('Rata-rata', '${_f(stats.avgTemp, 1)}°C'),
          ChartStat('Minimum', '${_f(stats.minTemp, 1)}°C'),
          ChartStat('Maksimum', '${_f(stats.maxTemp, 1)}°C'),
        ],
      ),
      const SizedBox(height: PitikSpace.gap),
      card(
        key: 'rh',
        title: 'Kelembapan (%)',
        icon: Icons.water_drop_rounded,
        color: PitikColors.humidity,
        tint: PitikColors.humidityBg,
        points: data,
        valueOf: (p) => p.humidity,
        unit: '%',
        decimals: 1,
        chartStats: [
          ChartStat('Rata-rata', '${_f(stats.avgHumidity, 1)}%'),
          ChartStat('Minimum', '${_f(stats.minHumidity, 1)}%'),
          ChartStat('Maksimum', '${_f(stats.maxHumidity, 1)}%'),
        ],
      ),
      const SizedBox(height: PitikSpace.gap),
      // Zona & ambang dari /controls; rebuild bila ambang berubah.
      ListenableBuilder(
        listenable: widget.deviceState,
        builder: (context, _) {
          final controls = widget.deviceState.controlsOrDefault;
          final n = Controls.formatThi(controls.thiNormal);
          final d = Controls.formatThi(controls.thiDanger);
          return card(
            key: 'thi',
            title: 'Indeks THI',
            icon: Icons.speed_rounded,
            color: PitikColors.thi,
            tint: PitikColors.thiBg,
            points: data,
            valueOf: (p) => p.thi,
            unit: '',
            decimals: 1,
            zones: ThiZones(
              normal: controls.thiNormal,
              danger: controls.thiDanger,
            ),
            chartStats: [
              ChartStat('Rata-rata', _f(stats.avgThi, 1)),
              ChartStat('Minimum', _f(thiValues.reduce(math.min), 1)),
              ChartStat('Maksimum', _f(thiValues.reduce(math.max), 1)),
            ],
            footer: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ambang (Pengaturan): normal $n · bahaya $d',
                  style: PitikText.caption.copyWith(
                    color: PitikColors.textMuted,
                  ),
                ),
                const SizedBox(height: 8),
                const Wrap(
                  spacing: 16,
                  runSpacing: 6,
                  children: [
                    _Legend(
                      'Normal',
                      PitikColors.zoneNormal,
                      PitikColors.zoneNormalEdge,
                    ),
                    _Legend(
                      'Waspada',
                      PitikColors.zoneWarning,
                      PitikColors.zoneWarningEdge,
                    ),
                    _Legend(
                      'Bahaya',
                      PitikColors.zoneDanger,
                      PitikColors.zoneDangerEdge,
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
      const SizedBox(height: PitikSpace.gap),
      card(
        key: 'mq',
        title: 'Sensor gas MQ-137 (ADC)',
        icon: Icons.cloud_rounded,
        color: PitikColors.ammonia,
        tint: PitikColors.ammoniaBg,
        points: mqPoints,
        valueOf: (p) => p.mq137Raw!.toDouble(),
        unit: 'ADC',
        decimals: 0,
        emptyText: 'Tidak ada data MQ-137 pada periode ini.',
        chartStats: mqPoints.isEmpty
            ? const []
            : [
                ChartStat(
                  'Rata-rata',
                  '${stats.avgMq137Raw!.toStringAsFixed(0)} ADC',
                ),
                ChartStat(
                  'Minimum',
                  '${mqPoints.map((p) => p.mq137Raw!).reduce(math.min)} ADC',
                ),
                ChartStat(
                  'Maksimum',
                  '${mqPoints.map((p) => p.mq137Raw!).reduce(math.max)} ADC',
                ),
              ],
        footer: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: PitikColors.textSecondary,
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Belum dikalibrasi — bukan nilai ppm. ',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(text: 'Nilai mentah ADC 0–4095.'),
                  ],
                ),
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: PitikColors.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _buildStatisticsCard() {
    final stats = _stats ?? HistoryStats.fromPoints(_historyData);
    // 30 Hari memakai tiap titik ke-6 per hari (≈30 menit); periode lain ≈5 menit.
    final sampling = _dataPeriod == HistoryPeriod.last30Days.index
        ? '±30 menit'
        : '±5 menit';
    return PitikCard(
      key: const ValueKey('stats-card'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              const Icon(
                Icons.insert_chart_outlined_rounded,
                color: PitikColors.accent,
                size: 22,
              ),
              const Text('Statistik', style: PitikText.cardTitle),
              _PeriodPill(text: _dataLabel),
            ],
          ),
          const SizedBox(height: 4),
          _SummaryRow(
            icon: Icons.device_thermostat_rounded,
            color: PitikColors.temp,
            tint: PitikColors.tempBg,
            label: 'Rata-rata suhu',
            value: '${_f(stats.avgTemp, 1)}°C',
          ),
          _SummaryRow(
            icon: Icons.water_drop_rounded,
            color: PitikColors.humidity,
            tint: PitikColors.humidityBg,
            label: 'Rata-rata kelembapan',
            value: '${_f(stats.avgHumidity, 0)}%',
          ),
          _SummaryRow(
            icon: Icons.speed_rounded,
            color: PitikColors.thi,
            tint: PitikColors.thiBg,
            label: 'Rata-rata THI',
            value: _f(stats.avgThi, 1),
          ),
          // Perhitungan existing (transisi tidak-dingin → kipas/pompa ON per
          // sampel). Bergantung pada sampling → disajikan sebagai ESTIMASI.
          _SummaryRow(
            icon: Icons.ac_unit_rounded,
            color: PitikColors.accent,
            tint: PitikColors.accentSoft,
            label: 'Estimasi siklus pendinginan',
            value: '${stats.coolingEvents}×',
            caption:
                'Perkiraan berapa kali kipas/pompa mulai menyala, dihitung '
                'dari sampel riwayat (tiap $sampling). Bukan jumlah kejadian '
                'pasti.',
            last: true,
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════
//  Komponen kecil layar Riwayat
// ════════════════════════════════════════════

class _CsvButton extends StatelessWidget {
  const _CsvButton({
    required this.enabled,
    required this.copied,
    required this.onPressed,
  });

  final bool enabled;
  final bool copied;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: enabled ? onPressed : null,
      style: TextButton.styleFrom(
        backgroundColor: PitikColors.accentSoft,
        foregroundColor: PitikColors.accent,
        // Nonaktif tetap terbaca (kontras ≥ 4.5:1).
        disabledBackgroundColor: PitikColors.background,
        disabledForegroundColor: PitikColors.textSecondary,
        side: BorderSide(
          color: enabled ? PitikColors.accentSoftBorder : PitikColors.border,
        ),
        minimumSize: const Size(PitikSpace.touch, PitikSpace.touch),
        animationDuration: PitikMotion.of(context, kThemeChangeDuration),
        padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PitikRadius.control),
        ),
        textStyle: (Theme.of(context).textTheme.labelLarge ?? const TextStyle())
            .copyWith(fontSize: 15, fontWeight: FontWeight.w700, height: 1.25),
      ),
      icon: Icon(
        copied ? Icons.check_rounded : Icons.content_copy_rounded,
        size: 18,
      ),
      label: Text(copied ? 'Disalin' : 'Salin CSV'),
    );
  }
}

class _NoticeBox extends StatelessWidget {
  const _NoticeBox({
    required this.title,
    required this.body,
    this.busy = false,
    this.error = false,
    this.onRetry,
  });

  final String title;
  final String body;
  final bool busy;
  final bool error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final reduced = PitikMotion.reduced(context);
    final Widget lead = busy
        ? (reduced
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
                ))
        : const Icon(Icons.error_rounded, size: 18, color: PitikColors.danger);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: error ? PitikColors.dangerSurface : PitikColors.accentSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: error
              ? PitikColors.dangerBorder
              : PitikColors.accentSoftBorder,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: lead),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: PitikText.bodyStrong.copyWith(
                    color: error
                        ? PitikColors.dangerStrong
                        : const Color(0xFF1E3A8A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: PitikText.body.copyWith(
                    color: error
                        ? PitikColors.dangerText
                        : PitikColors.textMuted,
                  ),
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: 8),
                  _RetryButton(onPressed: onRetry!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RetryButton extends StatelessWidget {
  const _RetryButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: PitikColors.accentSoft,
        foregroundColor: PitikColors.accent,
        side: const BorderSide(color: PitikColors.accentSoftBorder),
        minimumSize: const Size(PitikSpace.touch, PitikSpace.touch),
        animationDuration: PitikMotion.of(context, kThemeChangeDuration),
        padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PitikRadius.control),
        ),
        textStyle: (Theme.of(context).textTheme.labelLarge ?? const TextStyle())
            .copyWith(fontSize: 15, fontWeight: FontWeight.w700, height: 1.25),
      ),
      icon: const Icon(Icons.refresh_rounded, size: 18),
      label: const Text('Coba Lagi'),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState({required this.periodLabel});
  final String periodLabel;

  @override
  Widget build(BuildContext context) {
    final reduced = PitikMotion.reduced(context);
    Widget block(double h, {double? w}) => Container(
      height: h,
      width: w,
      decoration: BoxDecoration(
        color: PitikColors.surfaceMuted,
        borderRadius: BorderRadius.circular(PitikRadius.control),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          child: Row(
            children: [
              reduced
                  ? const Icon(
                      Icons.hourglass_top_rounded,
                      size: 20,
                      color: PitikColors.accent,
                    )
                  : const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: PitikColors.accent,
                      ),
                    ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Memuat riwayat $periodLabel…',
                  style: PitikText.body.copyWith(
                    fontWeight: FontWeight.w500,
                    color: PitikColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: PitikSpace.gap),
        // Kerangka statis (tanpa animasi shimmer).
        for (var i = 0; i < 2; i++) ...[
          if (i > 0) const SizedBox(height: PitikSpace.gap),
          ExcludeSemantics(
            child: PitikCard(
              shadow: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      block(36, w: 36),
                      const SizedBox(width: 10),
                      block(16, w: 120),
                    ],
                  ),
                  const SizedBox(height: 14),
                  block(150),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(child: block(56)),
                      const SizedBox(width: 6),
                      Expanded(child: block(56)),
                      const SizedBox(width: 6),
                      Expanded(child: block(56)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.periodLabel, required this.onRetry});
  final String periodLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return PitikCard(
      borderColor: const Color(0xFFF3D3CD),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const IconTile(
                icon: Icons.cloud_off_rounded,
                color: PitikColors.dangerIcon,
                background: PitikColors.dangerSurface,
                size: 44,
                iconSize: 24,
                radius: 12,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gagal memuat riwayat $periodLabel',
                      style: PitikText.cardTitle,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Periksa koneksi internet ponsel Anda, lalu coba lagi.',
                      style: PitikText.body,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _RetryButton(onPressed: onRetry),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.phrase});

  final String phrase;

  @override
  Widget build(BuildContext context) {
    return PitikCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      child: Column(
        children: [
          const IconTile(
            icon: Icons.inbox_outlined,
            color: PitikColors.textSecondary,
            background: PitikColors.background,
            size: 56,
            iconSize: 30,
            radius: 16,
          ),
          const SizedBox(height: 12),
          Text(
            'Tidak ada data dalam $phrase terakhir',
            textAlign: TextAlign.center,
            style: PitikText.cardTitle,
          ),
          const SizedBox(height: 8),
          const Text(
            'Belum ada riwayat yang tersimpan untuk periode ini. '
            'Coba pilih periode lain.',
            textAlign: TextAlign.center,
            style: PitikText.body,
          ),
        ],
      ),
    );
  }
}

class _PeriodPill extends StatelessWidget {
  const _PeriodPill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: PitikColors.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: PitikColors.border),
      ),
      child: Text(
        text,
        style: PitikText.caption.copyWith(
          fontWeight: FontWeight.w500,
          color: PitikColors.textMuted,
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.color,
    required this.tint,
    required this.label,
    required this.value,
    this.caption,
    this.last = false,
  });

  final IconData icon;
  final Color color;
  final Color tint;
  final String label;
  final String value;
  final String? caption;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: last
          ? null
          : const BoxDecoration(
              border: Border(bottom: BorderSide(color: PitikColors.divider)),
            ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconTile(icon: icon, color: color, background: tint),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Lebar penuh agar nilai rata kanan (bila muat satu baris).
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
                          color: PitikColors.textMuted,
                        ),
                      ),
                      Text(
                        value,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                          color: PitikColors.text,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                if (caption != null) ...[
                  const SizedBox(height: 4),
                  Text(caption!, style: PitikText.caption),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.label, this.fill, this.edge);
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
