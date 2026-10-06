// Tes layar Pengaturan (redesign batch 4). Perilaku simpan/validasi/reset/
// picker sama dengan sebelum redesign. Tanpa Firebase.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitik_app/main.dart' show pitikNavItems;
import 'package:pitik_app/models/controls.dart';
import 'package:pitik_app/models/sensor_data.dart';
import 'package:pitik_app/screens/settings_screen.dart';
import 'package:pitik_app/widgets/pitik_bottom_nav.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fakes.dart';

class _Harness {
  _Harness(this.repo, this.device, this.cleanup);
  final FakeRepo repo;
  final FakeDevice device;
  final Future<void> Function() cleanup;
}

const _diagSensor = SensorData(
  sensorOk: true,
  timestamp: fakeTs,
  deviceId: 'PITIK-01',
  firmware: '8.4',
  hour: 21,
  minute: 13,
  uptimeSeconds: 3 * 3600 + 5 * 60,
);

Future<_Harness> _pump(
  WidgetTester tester, {
  bool isGuest = false,
  String? phone = '+628123456789',
  Controls controls = const Controls(thiNormal: 70, thiDanger: 80),
  SensorData sensor = const SensorData(sensorOk: true, timestamp: fakeTs),
  int ageSeconds = 10,
  Map<String, Object> prefs = const {},
  double width = 540,
  double height = 3500,
  double textScale = 1.0,
  bool reducedMotion = false,
  bool withNav = false,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final repo = FakeRepo();
  final device = FakeDevice(
    sensor: sensor,
    controls: controls,
    ageSeconds: ageSeconds,
  );

  tester.view.devicePixelRatio = 2.0;
  tester.view.physicalSize = Size(width * 2, height * 2);
  tester.view.padding = const FakeViewPadding(bottom: 24 * 2.0);
  final screen = SettingsScreen(
    repository: repo,
    deviceState: device.state,
    isGuest: isGuest,
    phoneNumber: isGuest ? null : phone,
  );
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reducedMotion,
        ),
        child: child!,
      ),
      home: withNav
          ? Scaffold(
              body: screen,
              bottomNavigationBar: PitikBottomNav(
                items: pitikNavItems,
                currentIndex: 3,
                onSelected: (_) {},
              ),
            )
          : screen,
    ),
  );
  await tester.pump();
  await tester.pump();

  return _Harness(repo, device, () async {
    await tester.pumpWidget(const SizedBox());
    device.state.dispose();
    tester.view.reset();
  });
}

Finder get _saveButton => find.byWidgetPredicate((w) => w is ElevatedButton);

Slider _slider(WidgetTester tester, int i) =>
    tester.widget<Slider>(find.byType(Slider).at(i));

const _saved = 'Perubahan disimpan.';
const _saving = 'Menyimpan perubahan…';
const _failed = 'Gagal menyimpan perubahan. Periksa koneksi.';
const _helper = 'Perangkat akan menggunakan pengaturan ini saat tersambung.';

void main() {
  group('nomor HP disamarkan', () {
    test('format +62', () {
      expect(
        SettingsScreen.maskPhoneNumber('+628123456789'),
        '+62 812-••••-6789',
      );
      expect(
        SettingsScreen.maskPhoneNumber('+6281298761234'),
        '+62 812-••••-1234',
      );
    });
    test('format lain / pendek tetap disamarkan', () {
      expect(SettingsScreen.maskPhoneNumber('08123456789'), '••••-6789');
      expect(SettingsScreen.maskPhoneNumber('123'), '••••');
    });
  });

  group('akun', () {
    testWidgets('peternak: nomor disamarkan + Terverifikasi', (tester) async {
      final h = await _pump(tester);
      expect(find.text('+62 812-••••-6789'), findsOneWidget);
      expect(find.text('+628123456789'), findsNothing);
      expect(find.text('Terverifikasi'), findsOneWidget);
      expect(find.text('Verified'), findsNothing);
      await h.cleanup();
    });

    testWidgets('tanpa nomor dari auth → tanpa klaim terverifikasi', (
      tester,
    ) async {
      final h = await _pump(tester, phone: null);
      expect(find.text('Terverifikasi'), findsNothing);
      expect(find.text('Akun peternak'), findsOneWidget);
      await h.cleanup();
    });

    testWidgets('tamu: Mode tamu + aksi masuk existing', (tester) async {
      final h = await _pump(tester, isGuest: true);
      expect(find.text('Mode tamu'), findsOneWidget);
      expect(find.text('Terverifikasi'), findsNothing);
      expect(find.text('Masuk dengan No. HP'), findsOneWidget);
      await h.cleanup();
    });
  });

  group('ambang THI (perilaku sama dengan sebelum redesign)', () {
    testWidgets('slider membaca /controls & reset → simpan', (tester) async {
      final h = await _pump(tester);
      // Nilai dari /controls (70/80), bukan default lokal.
      expect(find.text('70'), findsOneWidget);
      expect(find.text('80'), findsOneWidget);
      expect(find.text('Tidak ada perubahan'), findsOneWidget);
      expect(
        tester.widget<ElevatedButton>(_saveButton).onPressed,
        isNull,
        reason: 'belum ada perubahan',
      );
      // Rentang & langkah existing (50–100, 0,5).
      expect(_slider(tester, 0).min, Controls.thiMin);
      expect(_slider(tester, 0).max, Controls.thiMax);
      expect(_slider(tester, 0).divisions, 100);

      await tester.tap(find.text('Reset ke Default (72/78)'));
      await tester.pump();
      expect(find.text('Belum disimpan'), findsOneWidget);
      expect(
        find.text('Nilai tersimpan: normal 70 · bahaya 80'),
        findsOneWidget,
      );
      expect(h.repo.calls, isEmpty, reason: 'reset hanya mengubah draft');
      await tester.tap(find.text('Simpan perubahan'));
      await tester.pump();
      expect(h.repo.calls, ['thr=72.0,78.0']);
      expect(find.text(_saved), findsOneWidget);
      // Tanpa klaim penerapan/konfirmasi perangkat.
      expect(
        find.textContaining(
          RegExp(
            'berhasil|diterapkan|Diterapkan|menerapkan|Menunggu perangkat',
          ),
        ),
        findsNothing,
      );
      // Sukses ±5 detik, lalu kembali ke status stabil.
      await tester.pump(const Duration(seconds: 4));
      expect(find.text(_saved), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text(_saved), findsNothing);
      expect(find.text('Tidak ada perubahan'), findsOneWidget);
      await h.cleanup();
    });

    testWidgets('Batal mengembalikan draft ke nilai tersimpan', (tester) async {
      final h = await _pump(tester);
      _slider(tester, 0).onChanged!(71.5);
      await tester.pump();
      expect(find.text('71.5'), findsOneWidget);
      expect(find.text('Belum disimpan'), findsOneWidget);
      await tester.tap(find.text('Batal'));
      await tester.pump();
      expect(find.text('Tidak ada perubahan'), findsOneWidget);
      expect(find.text('70'), findsOneWidget);
      await h.cleanup();
    });

    testWidgets('validasi normal < bahaya → pesan & simpan nonaktif', (
      tester,
    ) async {
      final h = await _pump(tester);
      _slider(tester, 0).onChanged!(85);
      await tester.pump();
      expect(find.text(Controls.validateThresholds(85, 80)!), findsOneWidget);
      expect(tester.widget<ElevatedButton>(_saveButton).onPressed, isNull);
      await h.cleanup();
    });

    testWidgets(
      'menyimpan → Menyimpan perubahan…; gagal → pesan, draft tetap',
      (tester) async {
        final h = await _pump(tester);
        final write = Completer<void>();
        h.repo.onWrite = () => write.future;
        _slider(tester, 1).onChanged!(82);
        await tester.pump();
        await tester.tap(find.text('Simpan perubahan'));
        await tester.pump();
        expect(find.text(_saving), findsNWidgets(2)); // badge + tombol
        expect(tester.widget<ElevatedButton>(_saveButton).onPressed, isNull);

        write.completeError(Exception('permission-denied'));
        await tester.pump();
        await tester.pump();
        expect(find.text(_failed), findsOneWidget);
        expect(find.text('Belum disimpan'), findsOneWidget);
        expect(find.text('82'), findsOneWidget);
        // Tanpa retry otomatis.
        await tester.pump(const Duration(seconds: 10));
        expect(h.repo.calls, ['thr=70.0,82.0']);
        expect(tester.widget<ElevatedButton>(_saveButton).onPressed, isNotNull);
        // Error tetap terlihat sampai input berubah.
        expect(find.text(_failed), findsOneWidget);
        _slider(tester, 1).onChanged!(83);
        await tester.pump();
        expect(find.text(_failed), findsNothing);
        await h.cleanup();
      },
    );

    testWidgets('offline tetap boleh simpan; helper statis, bukan status', (
      tester,
    ) async {
      final h = await _pump(tester, ageSeconds: 4 * 86400);
      _slider(tester, 0).onChanged!(71);
      await tester.pump();
      await tester.tap(find.text('Simpan perubahan'));
      await tester.pump();
      expect(h.repo.calls, ['thr=71.0,80.0']);
      expect(find.text(_saved), findsOneWidget);
      // Penjelasan domain statis: ambang + jadwal, tampil terlepas dari status.
      expect(find.text(_helper), findsNWidgets(2));
      await tester.pump(const Duration(seconds: 6));
      expect(find.text(_saved), findsNothing);
      expect(find.text(_helper), findsNWidgets(2));
      await h.cleanup();
    });

    testWidgets('tamu: ambang & jadwal pakan read-only', (tester) async {
      final h = await _pump(tester, isGuest: true);
      expect(find.text('Mode tamu — hanya melihat'), findsOneWidget);
      expect(find.text('Masuk untuk mengubah ambang THI'), findsOneWidget);
      expect(find.text('Masuk untuk mengubah jadwal pakan'), findsOneWidget);

      // Nilai tetap terlihat, tapi slider nonaktif & tombol simpan/reset tidak ada.
      expect(find.text('70'), findsOneWidget);
      for (final slider in tester.widgetList<Slider>(find.byType(Slider))) {
        expect(slider.onChanged, isNull);
      }
      expect(_saveButton, findsNothing);
      expect(find.textContaining('Reset ke Default'), findsNothing);

      // Tap slot pakan tidak membuka time picker.
      await tester.tap(find.text('Pakan 1'));
      await tester.pump();
      expect(find.byType(Dialog), findsNothing);
      expect(h.repo.calls, isEmpty);

      // Logout tetap tersedia.
      expect(find.text('Keluar dari Akun'), findsOneWidget);
      await h.cleanup();
    });
  });

  group('perangkat & koneksi', () {
    testWidgets('kartu Perangkat memakai data diagnostik /sensor_data', (
      tester,
    ) async {
      final h = await _pump(tester, sensor: _diagSensor);
      expect(find.text('PITIK-01'), findsOneWidget);
      expect(find.text('v8.4'), findsOneWidget);
      expect(find.text('21:13 WIB'), findsOneWidget);
      expect(find.text('3 jam 5 menit'), findsOneWidget);
      expect(find.text('Terhubung'), findsOneWidget);
      // Interval Update disembunyikan (keputusan desain batch 4).
      expect(find.text('5 detik'), findsNothing);
      expect(find.textContaining('laporan terakhir'), findsNothing);
      // Nilai hardcode lama tidak ada lagi.
      expect(find.text('ESP32-01'), findsNothing);
      expect(find.text('Connected'), findsNothing);
      // Nama kandang = label tampilan aplikasi (bukan data ESP32).
      expect(find.text('Kandang 1'), findsOneWidget);
      expect(find.text('Label tampilan aplikasi'), findsOneWidget);
      await h.cleanup();
    });

    testWidgets('hour/minute = -1 → belum sinkron NTP', (tester) async {
      final h = await _pump(
        tester,
        sensor: const SensorData(sensorOk: true, timestamp: 0),
      );
      expect(find.text('--:-- (belum sinkron NTP)'), findsOneWidget);
      expect(find.text('Waktu perangkat belum sinkron (NTP)'), findsOneWidget);
      await h.cleanup();
    });

    testWidgets('data lama + server terhubung: konteks laporan terakhir; '
        'reconnect tidak membuat Online', (tester) async {
      final h = await _pump(tester, sensor: _diagSensor, ageSeconds: 4 * 86400);
      h.device.connectedCtrl.add(true);
      await tester.pump();
      expect(
        find.textContaining('Nilai dari laporan terakhir perangkat · '),
        findsOneWidget,
      );
      expect(find.text('Offline'), findsOneWidget);
      expect(find.text('Terhubung'), findsOneWidget);
      expect(find.text('Sambungkan Ulang'), findsOneWidget);
      expect(
        find.textContaining(
          'ESP32 yang mati/putus WiFi harus dicek '
          'langsung.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Sambungkan Ulang'));
      await tester.pump();
      expect(h.device.reconnectCalls, 1);
      h.device.connectedCtrl.add(true);
      await tester.pump(const Duration(seconds: 16));
      await tester.pump();
      expect(
        find.text(
          'Server terhubung, tetapi belum ada data baru dari '
          'perangkat. Periksa daya dan Wi-Fi ESP32 di kandang.',
        ),
        findsOneWidget,
      );
      expect(find.text('Offline'), findsOneWidget);
      expect(find.text('Online'), findsNothing);
      expect(h.repo.calls, isEmpty);
      await h.cleanup();
    });
  });

  group('jadwal pakan', () {
    testWidgets('slot pakan membuka time picker 24 jam', (tester) async {
      final h = await _pump(tester);
      expect(find.text('07:00 WIB'), findsOneWidget);
      await tester.tap(find.text('Pakan 1'));
      await tester.pumpAndSettle();
      expect(find.text('Jam Pakan 1 (WIB)'), findsOneWidget);
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
      expect(h.repo.calls, isEmpty);
      await h.cleanup();
    });

    testWidgets('reset jadwal memakai konfirmasi existing → simpan', (
      tester,
    ) async {
      final h = await _pump(
        tester,
        controls: const Controls(
          feedTimes: [FeedTime(6, 30), FeedTime(12, 0), FeedTime(18, 0)],
        ),
      );
      expect(find.text('Pakan terakhir'), findsOneWidget);
      await tester.tap(find.text('Reset ke Default (07:00, 12:00, 17:00)'));
      await tester.pumpAndSettle();
      expect(find.text('Reset Jadwal Pakan'), findsOneWidget);
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      expect(h.repo.calls, ['feed_schedule=07:00,12:00,17:00']);
      expect(find.text(_saved), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
      expect(find.text(_saved), findsNothing);
      await h.cleanup();
    });

    testWidgets('gagal simpan jadwal → pesan existing', (tester) async {
      final h = await _pump(
        tester,
        controls: const Controls(
          feedTimes: [FeedTime(6, 30), FeedTime(12, 0), FeedTime(18, 0)],
        ),
      );
      h.repo.onWrite = () async => throw Exception('x');
      await tester.tap(find.text('Reset ke Default (07:00, 12:00, 17:00)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      expect(find.text(_failed), findsOneWidget);
      await h.cleanup();
    });
  });

  group('preferensi placeholder', () {
    testWidgets('tetap ada, nonaktif, berlabel Belum tersedia', (tester) async {
      final h = await _pump(tester, prefs: {'pushNotification': false});
      for (final label in [
        'Push Notification',
        'Suara Peringatan',
        'Email Alert',
        'Bahasa',
        'Tema',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('Belum tersedia'), findsNWidgets(5));
      final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
      expect(switches, hasLength(3));
      for (final s in switches) {
        expect(s.onChanged, isNull);
      }
      // Nilai tersimpan lokal tetap dibaca (tidak diubah).
      expect(switches.first.value, isFalse);
      expect(find.text('Pilihan tersimpan: Indonesia'), findsOneWidget);

      // Bahasa tidak membuka dialog.
      await tester.tap(find.text('Bahasa'));
      await tester.pump();
      expect(find.byType(Dialog), findsNothing);
      // Interval Update disembunyikan dari tampilan (opsi A).
      expect(find.text('Interval Update'), findsNothing);
      expect(find.textContaining('Ditentukan firmware'), findsNothing);
      await h.cleanup();
    });
  });

  group('info & keluar', () {
    testWidgets('Keluar dari Akun memakai konfirmasi existing', (tester) async {
      final h = await _pump(tester);
      await tester.tap(find.text('Keluar dari Akun'));
      await tester.pumpAndSettle();
      expect(
        find.text('Apakah Anda yakin ingin keluar dari akun?'),
        findsOneWidget,
      );
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('PITIK v1.0.0'), findsOneWidget);
      expect(find.text('Tentang Aplikasi'), findsOneWidget);
      expect(find.text('Bantuan'), findsOneWidget);
      expect(find.text('Kebijakan Privasi'), findsOneWidget);
      await h.cleanup();
    });
  });

  group('aksesibilitas', () {
    testWidgets('semantics slider, jam pakan, placeholder, keluar', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final h = await _pump(tester);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Ambang normal (kipas)')),
        isSemantics(value: 'THI 70', isEnabled: true, hasIncreaseAction: true),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel(RegExp('^Pakan 1'))),
        isSemantics(
          isButton: true,
          isEnabled: true,
          hint: 'Ketuk untuk mengubah jam',
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(
          find.bySemanticsLabel(RegExp('^Push Notification')),
        ),
        isSemantics(hint: 'Fitur belum tersedia'),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Keluar dari Akun')),
        isSemantics(isButton: true, hasTapAction: true),
      );
      handle.dispose();
      await h.cleanup();
    });

    testWidgets('tamu: slider nonaktif membacakan alasan', (tester) async {
      final handle = tester.ensureSemantics();
      final h = await _pump(tester, isGuest: true);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Ambang bahaya (pompa)')),
        isSemantics(isEnabled: false, hint: 'Mode tamu — hanya melihat'),
      );
      handle.dispose();
      await h.cleanup();
    });

    for (final width in [360.0, 393.0]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        for (final state in ['peternak', 'tamu-offline']) {
          testWidgets(
            '${width.toInt()} dp · teks ${scale}x · $state: tanpa overflow, '
            'footer & keluar di atas navigasi',
            (tester) async {
              final h = await _pump(
                tester,
                width: width,
                height: 780,
                textScale: scale,
                withNav: true,
                isGuest: state == 'tamu-offline',
                ageSeconds: state == 'tamu-offline' ? 4 * 86400 : 10,
                sensor: _diagSensor,
              );
              final pos = tester
                  .state<ScrollableState>(find.byType(Scrollable).first)
                  .position;
              pos.jumpTo(pos.maxScrollExtent);
              await tester.pump();
              final navTop = tester.getTopLeft(find.byType(PitikBottomNav)).dy;
              expect(
                tester.getRect(find.text('BINUS University © 2026')).bottom,
                lessThanOrEqualTo(navTop),
              );
              final logout = find.text('Keluar dari Akun');
              expect(tester.getRect(logout).bottom, lessThanOrEqualTo(navTop));
              await h.cleanup();
            },
          );
        }
      }
    }

    testWidgets('reduced motion: menyimpan tanpa spinner berputar', (
      tester,
    ) async {
      final h = await _pump(tester, reducedMotion: true);
      final write = Completer<void>();
      h.repo.onWrite = () => write.future;
      await tester.tap(find.text('Reset ke Default (72/78)'));
      await tester.pump();
      await tester.tap(find.text('Simpan perubahan'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pump(const Duration(seconds: 1)); // riak sentuhan selesai
      expect(tester.binding.transientCallbackCount, 0);
      // RTDB memantulkan tulisan lokal ke /controls sebelum Future selesai.
      h.device.controlsCtrl.add(const Controls());
      await tester.pump();
      write.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pump(const Duration(seconds: 9));
      await h.cleanup();
    });
  });
}
