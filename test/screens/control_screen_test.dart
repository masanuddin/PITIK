// Tes layar Kontrol (redesign batch 3). Aturan blokir, satu-perintah-sekaligus,
// dan pemisahan permintaan (/controls) vs status perangkat (/sensor_data)
// sama dengan versi sebelum redesign. Tanpa Firebase.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitik_app/main.dart' show pitikNavItems;
import 'package:pitik_app/models/controls.dart';
import 'package:pitik_app/models/sensor_data.dart';
import 'package:pitik_app/screens/control_screen.dart';
import 'package:pitik_app/widgets/pitik_bottom_nav.dart';

import '../helpers/fakes.dart';

SensorData _sensor({
  bool sensorOk = true,
  bool relaysEnabled = true,
  bool feederEnabled = true,
  bool relayFan = false,
  bool relayPump = false,
  bool autoMode = false,
  int timestamp = fakeTs,
}) => SensorData(
  sensorOk: sensorOk,
  temperature: sensorOk ? 29 : null,
  humidity: sensorOk ? 70 : null,
  thi: sensorOk ? 75 : null,
  mq137Raw: 1200,
  timestamp: timestamp,
  relaysEnabled: relaysEnabled,
  feederEnabled: feederEnabled,
  relayFan: relayFan,
  relayPump: relayPump,
  autoMode: autoMode,
);

class _Harness {
  _Harness(this.repo, this.device, this.cleanup);
  final FakeRepo repo;
  final FakeDevice device;
  final Future<void> Function() cleanup;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  SensorData? sensor,
  Controls controls = const Controls(),
  int ageSeconds = 10,
  bool readOnly = false,
  double width = 540,
  double height = 2500,
  double textScale = 1.0,
  bool reducedMotion = false,
  bool withNav = false,
}) async {
  final repo = FakeRepo();
  final device = FakeDevice(
    sensor: sensor ?? _sensor(),
    controls: controls,
    ageSeconds: ageSeconds,
  );

  tester.view.devicePixelRatio = 2.0;
  tester.view.physicalSize = Size(width * 2, height * 2);
  tester.view.padding = const FakeViewPadding(bottom: 24 * 2.0);
  final screen = ControlScreen(
    repository: repo,
    deviceState: device.state,
    readOnly: readOnly,
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
                currentIndex: 2,
                onSelected: (_) {},
              ),
            )
          : screen,
    ),
  );
  await tester.pump();

  return _Harness(repo, device, () async {
    await tester.pumpWidget(const SizedBox());
    device.state.dispose();
    tester.view.reset();
  });
}

// Urutan switch di layar: [0] mode otomatis, [1] kipas, [2] pompa.
Switch _switch(WidgetTester tester, int index) =>
    tester.widget<Switch>(find.byType(Switch).at(index));

ElevatedButton _feedButton(WidgetTester tester) => tester
    .widget<ElevatedButton>(find.byWidgetPredicate((w) => w is ElevatedButton));

Finder _in(String key, Finder matching) =>
    find.descendant(of: find.byKey(ValueKey(key)), matching: matching);

/// Semua jalur tulis aktif / nonaktif.
void _expectAllLocked(WidgetTester tester, {required bool locked}) {
  for (var i = 0; i < 3; i++) {
    expect(_switch(tester, i).onChanged == null, locked, reason: 'switch $i');
  }
  expect(_feedButton(tester).onPressed == null, locked, reason: 'pakan');
}

void main() {
  group('aturan blokir (sama dengan sebelum redesign)', () {
    testWidgets('mode manual & online → kipas bisa dinyalakan', (tester) async {
      final h = await _pump(tester);
      expect(_switch(tester, 0).value, isFalse);
      await tester.tap(find.byType(Switch).at(1));
      await tester.pump();
      expect(h.repo.calls, ['fan=true']);
      await h.cleanup();
    });

    testWidgets('setelah reboot (auto_mode=false di /controls) tampil Manual', (
      tester,
    ) async {
      final h = await _pump(
        tester,
        controls: Controls.fromMap({
          'auto_mode': false,
          'fan': false,
          'pump': false,
        }),
      );
      expect(_switch(tester, 0).value, isFalse);
      // Permintaan & status perangkat sama-sama Manual.
      expect(_in('card-mode', find.text('Manual')), findsNWidgets(2));
      expect(find.text('Otomatis'), findsNothing);
      expect(
        find.textContaining(
          'Setelah perangkat restart, mode selalu kembali ke Manual.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('layar Nextion'), findsOneWidget);
      await h.cleanup();
    });

    testWidgets('mode otomatis → kipas/pompa/preset dikunci', (tester) async {
      final h = await _pump(
        tester,
        sensor: _sensor(autoMode: true),
        controls: const Controls(autoMode: true),
      );
      expect(_in('card-mode', find.text('Otomatis')), findsNWidgets(2));
      expect(
        find.text('Dikendalikan otomatis'),
        findsNWidgets(2),
      ); // kontrol + preset
      expect(
        find.textContaining('Perintah manual akan ditimpa.'),
        findsOneWidget,
      );
      expect(_switch(tester, 1).onChanged, isNull);
      expect(_switch(tester, 2).onChanged, isNull);
      await tester.tap(find.text('Kipas + pompa'));
      await tester.pump();
      expect(h.repo.calls, isEmpty);
      // Switch mode tetap bisa dipakai untuk kembali ke Manual.
      expect(_switch(tester, 0).onChanged, isNotNull);
      expect(_feedButton(tester).onPressed, isNotNull);
      await h.cleanup();
    });

    testWidgets(
      'offline → semua kontrol dikunci; satu banner & satu reconnect',
      (tester) async {
        final h = await _pump(tester, ageSeconds: 61);
        _expectAllLocked(tester, locked: true);
        expect(
          _in('card-feed', find.text('Perangkat offline')),
          findsOneWidget,
        );
        // Banner + alasan singkat per kartu (mode, kipas&pompa, preset, pakan).
        expect(find.text('Perangkat offline'), findsNWidgets(5));
        expect(
          find.textContaining('Kontrol tidak tersedia sampai perangkat'),
          findsOneWidget,
        );
        expect(find.text('Sambungkan Ulang'), findsOneWidget);
        // Status relay = laporan terakhir, bukan kondisi sekarang.
        expect(
          _in('relay-fan', find.text('Terakhir dilaporkan')),
          findsOneWidget,
        );
        expect(find.text('Status perangkat'), findsNothing);
        expect(find.text('Nilai terakhir'), findsOneWidget);
        await h.cleanup();
      },
    );

    testWidgets('feed_now=true → tombol pakan menunggu perangkat', (
      tester,
    ) async {
      final h = await _pump(tester, controls: const Controls(feedNow: true));
      expect(
        _in('card-feed', find.text('Menunggu perangkat…')),
        findsOneWidget,
      );
      expect(_feedButton(tester).onPressed, isNull);
      // Kontrol lain tidak ikut terkunci.
      expect(_switch(tester, 1).onChanged, isNotNull);
      await h.cleanup();
    });

    testWidgets('offline + feed_now tertinggal → peringatan tidak dijalankan', (
      tester,
    ) async {
      final h = await _pump(
        tester,
        controls: const Controls(feedNow: true),
        ageSeconds: 61,
      );
      expect(find.textContaining('tidak akan dijalankan'), findsOneWidget);
      await h.cleanup();
    });

    testWidgets('relays_enabled=false → kipas/pompa dikunci', (tester) async {
      final h = await _pump(tester, sensor: _sensor(relaysEnabled: false));
      expect(find.text('Relay dinonaktifkan di perangkat'), findsNWidgets(2));
      expect(_switch(tester, 1).onChanged, isNull);
      expect(_switch(tester, 2).onChanged, isNull);
      expect(_feedButton(tester).onPressed, isNotNull);
      await h.cleanup();
    });

    testWidgets('feeder_enabled=false → tombol pakan dikunci', (tester) async {
      final h = await _pump(tester, sensor: _sensor(feederEnabled: false));
      expect(
        find.text('Pemberi pakan dinonaktifkan di perangkat'),
        findsOneWidget,
      );
      expect(_feedButton(tester).onPressed, isNull);
      expect(_switch(tester, 1).onChanged, isNotNull);
      await h.cleanup();
    });

    testWidgets(
      'tombol pakan & preset mengirim perintah (tanpa feed_now=false)',
      (tester) async {
        final h = await _pump(tester);
        await tester.tap(find.text('Beri Pakan Sekarang'));
        await tester.pump();
        await tester.tap(find.text('Kipas + pompa'));
        await tester.pump();
        expect(h.repo.calls, ['feed', 'fanpump=true,true']);
        await h.cleanup();
      },
    );

    testWidgets('preset Semua mati & Kipas saja menulis atomik', (
      tester,
    ) async {
      final h = await _pump(tester);
      await tester.tap(find.text('Semua mati'));
      await tester.pump();
      await tester.tap(find.text('Kipas saja'));
      await tester.pump();
      expect(h.repo.calls, ['fanpump=false,false', 'fanpump=true,false']);
      await h.cleanup();
    });

    testWidgets('tamu → semua kontrol dikunci walau online & manual', (
      tester,
    ) async {
      final h = await _pump(tester, readOnly: true);
      expect(find.text('Mode tamu — hanya melihat'), findsWidgets);
      expect(find.text('Masuk dengan No. HP'), findsOneWidget);
      _expectAllLocked(tester, locked: true);
      await tester.tap(find.text('Kipas + pompa'));
      await tester.pump();
      expect(h.repo.calls, isEmpty);
      // Data tetap terlihat.
      expect(find.text('75.0'), findsOneWidget);
      expect(find.text('Sambungkan Ulang'), findsOneWidget);
      await h.cleanup();
    });

    testWidgets(
      'sensor error → "--" + catatan; kontrol tetap mengikuti aturan',
      (tester) async {
        final h = await _pump(tester, sensor: _sensor(sensorOk: false));
        expect(find.text('--'), findsNWidgets(3)); // suhu, RH, THI
        expect(find.textContaining('Sensor error (DHT22)'), findsOneWidget);
        expect(find.text('1200'), findsOneWidget); // MQ-137 tetap ada
        expect(
          find.text('Amonia MQ-137: ADC · belum dikalibrasi (bukan ppm)'),
          findsOneWidget,
        );
        expect(_switch(tester, 1).onChanged, isNotNull);
        await h.cleanup();
      },
    );
  });

  group('permintaan vs status perangkat', () {
    testWidgets('perintah ON tapi relay OFF → menunggu perubahan status', (
      tester,
    ) async {
      final h = await _pump(
        tester,
        sensor: _sensor(relayFan: false),
        controls: const Controls(fan: true),
      );
      expect(_switch(tester, 1).value, isTrue); // switch = permintaan
      expect(
        _in('relay-fan', find.text('Menunggu perubahan status perangkat.')),
        findsOneWidget,
      );
      expect(
        _in(
          'relay-fan',
          find.text('Permintaan: Menyala · Status perangkat: Mati'),
        ),
        findsOneWidget,
      );
      expect(
        _in('relay-pump', find.text('Menunggu perubahan status perangkat.')),
        findsNothing,
      );
      // Bukan klaim keberhasilan / konfirmasi perangkat.
      expect(
        find.textContaining(
          RegExp(
            'Berhasil|berhasil|dikonfirmasi|sudah aktif|diperbarui|terkirim ke server',
          ),
        ),
        findsNothing,
      );
      // Mismatch tidak mengunci kontrol lain.
      _expectAllLocked(tester, locked: false);
      await h.cleanup();
    });

    testWidgets('relay menyusul → strip menunggu hilang', (tester) async {
      final h = await _pump(
        tester,
        sensor: _sensor(relayFan: false),
        controls: const Controls(fan: true),
      );
      h.device.sensorCtrl.add(_sensor(relayFan: true));
      await tester.pump();
      await tester.pump();
      expect(find.text('Menunggu perubahan status perangkat.'), findsNothing);
      expect(_in('relay-fan', find.text('Menyala')), findsNWidgets(2));
      await h.cleanup();
    });

    testWidgets('mode diminta Otomatis, perangkat masih Manual → menunggu', (
      tester,
    ) async {
      final h = await _pump(
        tester,
        sensor: _sensor(autoMode: false),
        controls: const Controls(autoMode: true),
      );
      expect(
        _in('card-mode', find.text('Menunggu perubahan status perangkat.')),
        findsOneWidget,
      );
      expect(
        _in(
          'card-mode',
          find.text('Permintaan: Otomatis · Status perangkat: Manual'),
        ),
        findsOneWidget,
      );
      await h.cleanup();
    });

    testWidgets('mismatch tidak ditampilkan saat offline (data lama)', (
      tester,
    ) async {
      final h = await _pump(
        tester,
        sensor: _sensor(relayFan: false),
        controls: const Controls(fan: true),
        ageSeconds: 61,
      );
      expect(find.text('Menunggu perubahan status perangkat.'), findsNothing);
      await h.cleanup();
    });
  });

  group('penulisan', () {
    testWidgets('sedang mengirim → semua dikunci, satu perintah sekaligus', (
      tester,
    ) async {
      final h = await _pump(tester);
      final write = Completer<void>();
      h.repo.onWrite = () => write.future;

      await tester.tap(find.byType(Switch).at(1));
      await tester.pump();
      expect(_in('relay-fan', find.text('Mengirim perintah…')), findsOneWidget);
      expect(
        _in('relay-fan', find.text('Kontrol lain dinonaktifkan sementara.')),
        findsOneWidget,
      );
      _expectAllLocked(tester, locked: true);
      expect(find.text('Tunggu perintah sebelumnya selesai'), findsNWidgets(3));

      // Tap lain selama mengirim tidak memulai perintah kedua.
      await tester.tap(find.byType(Switch).at(2));
      await tester.tap(find.text('Kipas + pompa'));
      await tester.tap(find.text('Beri Pakan Sekarang'), warnIfMissed: false);
      await tester.pump();
      expect(h.repo.calls, ['fan=true']);

      write.complete();
      await tester.pump();
      _expectAllLocked(tester, locked: false);
      expect(
        _in(
          'relay-fan',
          find.text('Permintaan disimpan. Menunggu status perangkat.'),
        ),
        findsOneWidget,
      );
      expect(find.text('Tunggu perintah sebelumnya selesai'), findsNothing);
      // Tulis selesai ≠ relay aktif: status perangkat tetap laporan terakhir.
      expect(find.textContaining('terkirim ke server'), findsNothing);
      expect(_in('relay-fan', find.text('Menyala')), findsNothing);

      // Catatan sisi-aplikasi hanya sementara.
      await tester.pump(const Duration(seconds: 5));
      expect(
        find.text('Permintaan disimpan. Menunggu status perangkat.'),
        findsNothing,
      );
      await h.cleanup();
    });

    testWidgets('gagal kirim → pesan di kartu, switch tetap nilai /controls', (
      tester,
    ) async {
      final h = await _pump(tester);
      h.repo.onWrite = () async => throw Exception('permission-denied');

      await tester.tap(find.byType(Switch).at(1));
      await tester.pump();
      await tester.pump();
      expect(
        _in(
          'relay-fan',
          find.text('Gagal mengirim perintah. Periksa koneksi.'),
        ),
        findsOneWidget,
      );
      expect(_switch(tester, 1).value, isFalse); // tanpa state optimistis
      _expectAllLocked(tester, locked: false); // tanpa retry/lock tambahan
      expect(h.repo.calls, ['fan=true']);

      // Error tetap terbaca sampai perintah berikutnya.
      await tester.pump(const Duration(seconds: 10));
      expect(
        find.text('Gagal mengirim perintah. Periksa koneksi.'),
        findsOneWidget,
      );
      h.repo.onWrite = null;
      await tester.tap(find.byType(Switch).at(2));
      await tester.pump();
      expect(
        find.text('Gagal mengirim perintah. Periksa koneksi.'),
        findsNothing,
      );
      expect(h.repo.calls, ['fan=true', 'pump=true']);
      await h.cleanup();
    });

    testWidgets('pakan: mengirim → permintaan disimpan; gagal → pesan gagal', (
      tester,
    ) async {
      final h = await _pump(tester);
      final write = Completer<void>();
      h.repo.onWrite = () => write.future;
      await tester.tap(find.text('Beri Pakan Sekarang'));
      await tester.pump();
      expect(_in('card-feed', find.text('Mengirim perintah…')), findsOneWidget);
      expect(_feedButton(tester).onPressed, isNull);
      write.complete();
      await tester.pump();
      expect(
        _in(
          'card-feed',
          find.text('Permintaan pakan disimpan. Menunggu perangkat.'),
        ),
        findsOneWidget,
      );

      await tester.pump(const Duration(seconds: 5));
      h.repo.onWrite = () async => throw Exception('x');
      await tester.tap(find.text('Beri Pakan Sekarang'));
      await tester.pump();
      await tester.pump();
      expect(
        _in(
          'card-feed',
          find.text('Gagal mengirim perintah. Periksa koneksi.'),
        ),
        findsOneWidget,
      );
      expect(h.repo.calls, ['feed', 'feed']);
      await h.cleanup();
    });

    testWidgets(
      'penulisan selesai tetapi relay belum berubah → tidak mengunci',
      (tester) async {
        final h = await _pump(tester);
        await tester.tap(find.byType(Switch).at(1));
        await tester.pump();
        // Server memantulkan /controls; perangkat belum mengubah relay.
        h.device.controlsCtrl.add(const Controls(fan: true));
        await tester.pump();
        expect(
          find.text('Menunggu perubahan status perangkat.'),
          findsOneWidget,
        );
        _expectAllLocked(tester, locked: false);
        await h.cleanup();
      },
    );
  });

  group('koneksi', () {
    testWidgets(
      'reconnect memakai DeviceState.reconnect; tidak membuat Online',
      (tester) async {
        final h = await _pump(tester, ageSeconds: 61);
        await tester.tap(find.text('Sambungkan Ulang'));
        await tester.pump();
        expect(h.device.reconnectCalls, 1);
        expect(find.text('Menyambungkan…'), findsOneWidget);
        h.device.connectedCtrl.add(true);
        await tester.pump(const Duration(seconds: 16));
        await tester.pump();
        // Server tersambung, tetapi perangkat tetap offline & kontrol terkunci.
        expect(
          find.textContaining(
            'Server terhubung, tetapi belum ada',
            findRichText: true,
          ),
          findsOneWidget,
        );
        expect(find.textContaining('Kontrol tidak tersedia'), findsOneWidget);
        _expectAllLocked(tester, locked: true);
        expect(h.repo.calls, isEmpty);
        await h.cleanup();
      },
    );
  });

  group('aksesibilitas', () {
    testWidgets('semantics switch, preset, tombol pakan & alasan nonaktif', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final h = await _pump(
        tester,
        sensor: _sensor(autoMode: true),
        controls: const Controls(autoMode: true, feedNow: true),
      );

      expect(
        tester.getSemantics(find.bySemanticsLabel(RegExp('^Kipas utama'))),
        isSemantics(
          hasToggledState: true,
          isToggled: false,
          hasEnabledState: true,
          isEnabled: false,
          hint: 'Dikendalikan otomatis',
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel(RegExp('^Mode otomatis'))),
        isSemantics(
          hasToggledState: true,
          isToggled: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(
          find.bySemanticsLabel(
            'Preset Kipas + pompa. Kipas dan pompa menyala',
          ),
        ),
        isSemantics(
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
          hint: 'Dikendalikan otomatis',
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Beri Pakan Sekarang')),
        isSemantics(
          isButton: true,
          isEnabled: false,
          hint: 'Menunggu perangkat…',
        ),
      );
      handle.dispose();
      await h.cleanup();
    });

    for (final width in [360.0, 393.0]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        for (final state in ['manual', 'offline-tamu', 'otomatis-mismatch']) {
          testWidgets(
            '${width.toInt()} dp · teks ${scale}x · $state: tanpa overflow, '
            'tombol pakan di atas navigasi',
            (tester) async {
              final h = await _pump(
                tester,
                width: width,
                height: 780,
                textScale: scale,
                withNav: true,
                readOnly: state == 'offline-tamu',
                ageSeconds: state == 'offline-tamu' ? 4 * 86400 : 10,
                sensor: state == 'otomatis-mismatch'
                    ? _sensor(autoMode: false, relayFan: true)
                    : null,
                controls: state == 'otomatis-mismatch'
                    ? const Controls(autoMode: true, feedNow: true)
                    : const Controls(),
              );
              // Target sentuh ≥ 48 dp.
              for (final f in [
                find.byType(Switch),
                find.byWidgetPredicate((w) => w is ElevatedButton),
                find.ancestor(
                  of: find.text('Sambungkan Ulang'),
                  matching: find.byType(TextButton),
                ),
              ]) {
                for (final e in f.evaluate()) {
                  final box = e.renderObject! as RenderBox;
                  expect(
                    box.size.height,
                    greaterThanOrEqualTo(48),
                    reason: '$e',
                  );
                }
              }
              final pos = tester
                  .state<ScrollableState>(find.byType(Scrollable).first)
                  .position;
              pos.jumpTo(pos.maxScrollExtent);
              await tester.pump();
              final navTop = tester.getTopLeft(find.byType(PitikBottomNav)).dy;
              final feed = find.byWidgetPredicate((w) => w is ElevatedButton);
              expect(tester.getRect(feed).bottom, lessThanOrEqualTo(navTop));
              await h.cleanup();
            },
          );
        }
      }
    }

    testWidgets('reduced motion: indikator mengirim statis, tanpa animasi', (
      tester,
    ) async {
      final h = await _pump(tester, reducedMotion: true);
      final write = Completer<void>();
      h.repo.onWrite = () => write.future;
      await tester.tap(find.text('Kipas saja'));
      await tester.pump();
      expect(find.text('Mengirim perintah…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.hourglass_top_rounded), findsWidgets);
      await tester.pump(const Duration(seconds: 1)); // riak sentuhan selesai
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);

      write.complete();
      await tester.pump();
      // Animasi berdurasi 0 selesai dalam 2 frame (32 ms); transisi standar
      // (≥100 ms, mis. warna tombol/switch) masih akan terdeteksi di sini.
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pump(const Duration(seconds: 5));
      await h.cleanup();
    });
  });
}
