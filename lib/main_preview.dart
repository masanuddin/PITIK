// ═══════════════════════════════════════════════════════════════════════
//  ENTRYPOINT PREVIEW VISUAL (redesign batch 1–4) — BUKAN aplikasi produksi.
//
//  - TIDAK memanggil Firebase.initializeApp.
//  - TIDAK membuat PitikRepository; tidak memakai Firebase Auth/Crashlytics.
//  - Data & reconnect disimulasikan (lib/preview/preview_device.dart);
//    riwayat & perintah /controls disimulasikan (lib/preview/
//    preview_history.dart, preview_repository.dart) — tidak ada tulisan nyata.
//  - Memakai DashboardScreen, HistoryScreen, ControlScreen, SettingsScreen
//    & PitikBottomNav yang SAMA dengan produksi.
//  - Catatan: tombol "Keluar"/"Masuk dengan No. HP" memanggil AuthService
//    produksi; tanpa Firebase.initializeApp panggilan itu gagal (tidak ada
//    efek ke akun mana pun).
//
//  Jalankan:  flutter run -d <perangkat web> -t lib/main_preview.dart
//  URL opsional:  ?scenario=stale&scale=1.5&ui=0&tab=1&history=slow
//    scenario = online|stale|sensorError|staleSensorError|noData|
//               reconnecting|serverErrorFresh|serverOkStale|
//               auto|relayMismatch|feedPending
//    scale    = 1.0 | 1.5 | 2.0  (skala teks; default = sistem)
//    ui=0     → sembunyikan panel kontrol preview (untuk tangkapan layar)
//    tab      = 0 (Dashboard) | 1 (Riwayat) | 2 (Kontrol) | 3 (Pengaturan)
//    history  = ok|slow|failOthers|empty|error
//    write    = ok|slow|error|noApply  (hasil perintah Kontrol simulasi)
//    guest=1  → Kontrol & Pengaturan hanya-lihat (simulasi tamu)
// ═══════════════════════════════════════════════════════════════════════
// lib/main_preview.dart

import 'package:flutter/material.dart';

// Hanya mengambil daftar tab; main() produksi TIDAK dijalankan.
import 'main.dart' show pitikNavItems;
import 'preview/preview_device.dart';
import 'preview/preview_history.dart';
import 'preview/preview_repository.dart';
import 'preview/preview_shell.dart';

void main() {
  final q = Uri.base.queryParameters;
  runApp(
    PreviewApp(
      initialScenario:
          PreviewScenario.byName(q['scenario']) ?? PreviewScenario.online,
      initialScale: double.tryParse(q['scale'] ?? ''),
      showControls: q['ui'] != '0',
      initialHistory: PreviewHistory.byName(q['history']) ?? PreviewHistory.ok,
      initialTab: (int.tryParse(q['tab'] ?? '') ?? 0).clamp(0, 3),
      initialWrite: PreviewWrite.byName(q['write']) ?? PreviewWrite.ok,
      initialGuest: q['guest'] == '1',
    ),
  );
}

class PreviewApp extends StatefulWidget {
  const PreviewApp({
    super.key,
    required this.initialScenario,
    this.initialScale,
    this.showControls = true,
    this.initialHistory = PreviewHistory.ok,
    this.initialTab = 0,
    this.initialWrite = PreviewWrite.ok,
    this.initialGuest = false,
  });

  final PreviewWrite initialWrite;
  final bool initialGuest;
  final PreviewScenario initialScenario;
  final PreviewHistory initialHistory;
  final int initialTab;

  /// null = ikuti skala teks sistem/browser.
  final double? initialScale;
  final bool showControls;

  @override
  State<PreviewApp> createState() => _PreviewAppState();
}

class _PreviewAppState extends State<PreviewApp> {
  late PreviewScenario _scenario = widget.initialScenario;
  late double? _scale = widget.initialScale;
  late bool _showControls = widget.showControls;
  late PreviewDevice _device = PreviewDevice(_scenario);
  late PreviewHistory _history = widget.initialHistory;
  late PreviewWrite _write = widget.initialWrite;
  late bool _guest = widget.initialGuest;
  late PreviewRepository _repo = _makeRepo();

  PreviewRepository _makeRepo() => PreviewRepository(
    device: _device,
    history: PreviewHistoryRepository(_history),
    write: _write,
  );

  void _setScenario(PreviewScenario s) {
    setState(() {
      _device.dispose();
      _scenario = s;
      _device = PreviewDevice(s);
      _repo = _makeRepo();
    });
  }

  @override
  void dispose() {
    _device.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PITIK — Preview (data simulasi)',
      debugShowCheckedModeBanner: false,
      // Salinan ThemeData produksi (lib/main.dart) agar tampilan setara.
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF007AFF),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F5F7),
        useMaterial3: true,
      ),
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: _scale == null
              ? mq
              : mq.copyWith(textScaler: TextScaler.linear(_scale!)),
          child: child!,
        );
      },
      home: Column(
        children: [
          if (_showControls) _controls(),
          Expanded(
            child: PreviewShell(
              key: ValueKey((_scenario, _history, _write, _guest)),
              device: _device,
              repository: _repo,
              navItems: pitikNavItems,
              initialIndex: widget.initialTab,
              readOnly: _guest,
            ),
          ),
        ],
      ),
    );
  }

  Widget _controls() {
    // Panel kontrol tidak ikut skala teks agar tetap ringkas.
    return MediaQuery.withNoTextScaling(
      child: Material(
        color: const Color(0xFF1F2937),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              children: [
                const Text(
                  'PREVIEW · data simulasi, tanpa Firebase',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                DropdownButton<PreviewScenario>(
                  value: _scenario,
                  dropdownColor: const Color(0xFF374151),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  items: [
                    for (final s in PreviewScenario.values)
                      DropdownMenuItem(value: s, child: Text(s.label)),
                  ],
                  onChanged: (s) => s == null ? null : _setScenario(s),
                ),
                DropdownButton<PreviewHistory>(
                  value: _history,
                  dropdownColor: const Color(0xFF374151),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  items: [
                    for (final h in PreviewHistory.values)
                      DropdownMenuItem(value: h, child: Text(h.label)),
                  ],
                  onChanged: (h) => h == null
                      ? null
                      : setState(() {
                          _history = h;
                          _repo = _makeRepo();
                        }),
                ),
                DropdownButton<PreviewWrite>(
                  value: _write,
                  dropdownColor: const Color(0xFF374151),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  items: [
                    for (final w in PreviewWrite.values)
                      DropdownMenuItem(value: w, child: Text(w.label)),
                  ],
                  onChanged: (w) => w == null
                      ? null
                      : setState(() {
                          _write = w;
                          _repo = _makeRepo();
                        }),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: _guest,
                      onChanged: (v) => setState(() => _guest = v ?? false),
                    ),
                    const Text(
                      'Tamu',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
                DropdownButton<double?>(
                  value: _scale,
                  dropdownColor: const Color(0xFF374151),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Teks: sistem')),
                    DropdownMenuItem(value: 1.0, child: Text('Teks 100%')),
                    DropdownMenuItem(value: 1.5, child: Text('Teks 150%')),
                    DropdownMenuItem(value: 2.0, child: Text('Teks 200%')),
                  ],
                  onChanged: (v) => setState(() => _scale = v),
                ),
                IconButton(
                  tooltip: 'Sembunyikan panel',
                  icon: const Icon(Icons.close, color: Colors.white, size: 18),
                  onPressed: () => setState(() => _showControls = false),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
