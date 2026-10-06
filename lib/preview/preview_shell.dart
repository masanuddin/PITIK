// ═══════════════════════════════════════════════════════════════════════
//  KHUSUS PREVIEW VISUAL — struktur sama dengan MainNavigation produksi
//  (Scaffold + IndexedStack + PitikBottomNav) dengan DashboardScreen,
//  HistoryScreen, ControlScreen dan SettingsScreen ASLI.
//  Nomor HP preview sintetis (bukan data pribadi).
// ═══════════════════════════════════════════════════════════════════════
// lib/preview/preview_shell.dart

import 'package:flutter/material.dart';

import '../screens/control_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/history_screen.dart';
import '../screens/settings_screen.dart';
import '../services/pitik_repository.dart';
import '../widgets/pitik_bottom_nav.dart';
import 'preview_device.dart';

/// Nomor sintetis untuk preview (format +62, bukan nomor nyata).
const previewPhoneNumber = '+6281200001234';

class PreviewShell extends StatefulWidget {
  const PreviewShell({
    super.key,
    required this.device,
    required this.repository,
    required this.navItems,
    this.initialIndex = 0,
    this.readOnly = false,
  });

  final PreviewDevice device;

  /// Repository simulasi (lib/preview/preview_repository.dart).
  final PitikRepository repository;
  final int initialIndex;
  final List<PitikNavItem> navItems;

  /// Simulasi tamu (anonim): Kontrol & Pengaturan hanya-lihat.
  final bool readOnly;

  @override
  State<PreviewShell> createState() => _PreviewShellState();
}

class _PreviewShellState extends State<PreviewShell> {
  late int _index = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          DashboardScreen(deviceState: widget.device.state),
          HistoryScreen(
            repository: widget.repository,
            deviceState: widget.device.state,
          ),
          ControlScreen(
            repository: widget.repository,
            deviceState: widget.device.state,
            readOnly: widget.readOnly,
          ),
          SettingsScreen(
            repository: widget.repository,
            deviceState: widget.device.state,
            isGuest: widget.readOnly,
            phoneNumber: widget.readOnly ? null : previewPhoneNumber,
          ),
        ],
      ),
      bottomNavigationBar: PitikBottomNav(
        items: widget.navItems,
        currentIndex: _index,
        onSelected: (i) => setState(() => _index = i),
      ),
    );
  }
}
