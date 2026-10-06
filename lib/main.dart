// PITIK Mobile App

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'firebase_options.dart';
import 'screens/dashboard_screen.dart';
import 'screens/history_screen.dart';
import 'screens/control_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'services/device_state.dart';
import 'services/pitik_repository.dart';
import 'widgets/pitik_bottom_nav.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  FlutterError.onError = (errorDetails) {
    FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
  };

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(const PitikApp());
}

class PitikApp extends StatelessWidget {
  const PitikApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PITIK',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF007AFF),
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF1D1D1F),
          elevation: 0,
          centerTitle: true,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          color: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F5F7),
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
    );
  }
}

// ============================================================
// AUTH WRAPPER - Cek status login
// ============================================================
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _SplashLoading();
        }

        final user = snapshot.data;
        if (user != null) {
          // Key per uid: ganti akun → DeviceState & tab dibuat ulang.
          return MainNavigation(
            key: ValueKey(user.uid),
            isGuest: user.isAnonymous,
            phoneNumber: user.phoneNumber,
          );
        }

        return const LoginScreen();
      },
    );
  }
}

// ============================================================
// SPLASH LOADING (simple)
// ============================================================
class _SplashLoading extends StatelessWidget {
  const _SplashLoading();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: const Color(0xFF007AFF),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF007AFF).withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Icon(
                Icons.sensors_rounded,
                color: Colors.white,
                size: 50,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'PITIK',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1D1D1F),
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'IoT Climate Control',
              style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 48),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF007AFF)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// MAIN NAVIGATION
// ============================================================
class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key, required this.isGuest, this.phoneNumber});

  /// Tamu (login anonim) hanya boleh melihat: Kontrol & Pengaturan read-only.
  final bool isGuest;
  final String? phoneNumber;

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  // Satu repository (akses RTDB) + satu langganan realtime untuk semua tab.
  final PitikRepository _repository = PitikRepository();
  late final DeviceState _deviceState = DeviceState.fromRepository(_repository);

  late final List<Widget> _screens = [
    DashboardScreen(deviceState: _deviceState),
    HistoryScreen(repository: _repository, deviceState: _deviceState),
    ControlScreen(
      repository: _repository,
      deviceState: _deviceState,
      readOnly: widget.isGuest,
    ),
    SettingsScreen(
      repository: _repository,
      deviceState: _deviceState,
      isGuest: widget.isGuest,
      phoneNumber: widget.phoneNumber,
    ),
  ];

  @override
  void dispose() {
    _deviceState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack: tiap tab tetap hidup → posisi scroll & state terjaga.
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: PitikBottomNav(
        items: pitikNavItems,
        currentIndex: _currentIndex,
        onSelected: (i) => setState(() => _currentIndex = i),
      ),
    );
  }
}

/// Urutan tab = urutan [_MainNavigationState._screens].
const List<PitikNavItem> pitikNavItems = [
  PitikNavItem(
      icon: Icons.dashboard_outlined,
      activeIcon: Icons.dashboard_rounded,
      label: 'Dashboard'),
  PitikNavItem(
      icon: Icons.show_chart_rounded,
      activeIcon: Icons.show_chart_rounded,
      label: 'Riwayat'),
  PitikNavItem(
      icon: Icons.tune_rounded,
      activeIcon: Icons.tune_rounded,
      label: 'Kontrol'),
  PitikNavItem(
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings_rounded,
      label: 'Pengaturan'),
];
