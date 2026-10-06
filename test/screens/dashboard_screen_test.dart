import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitik_app/models/controls.dart';
import 'package:pitik_app/models/sensor_data.dart';
import 'package:pitik_app/screens/dashboard_screen.dart';
import 'package:pitik_app/widgets/status_chip.dart';
import 'package:pitik_app/widgets/thi_gauge.dart';

import '../helpers/fakes.dart';

const _ts = fakeTs; // 21 Sep 2026 21:13:20 WIB

SensorData _sensor({
  bool ok = true,
  double temp = 25,
  double rh = 70,
  double thi = 75,
  bool fan = false,
  bool pump = false,
  bool auto = false,
  int timestamp = _ts,
}) =>
    SensorData(
      sensorOk: ok,
      temperature: ok ? temp : null,
      humidity: ok ? rh : null,
      thi: ok ? thi : null,
      relayFan: fan,
      relayPump: pump,
      autoMode: auto,
      timestamp: timestamp,
      mq137Raw: 1200,
    );

/// Pasang Dashboard dengan DeviceState palsu (tanpa Firebase).
Future<Future<void> Function()> _pump(
  WidgetTester tester, {
  SensorData? sensor,
  Controls? controls,
  int ageSeconds = 10,
  FakeDevice? device,
  bool reduceMotion = false,
  bool settle = true,
}) async {
  final state = (device ??
          FakeDevice(sensor: sensor, controls: controls, ageSeconds: ageSeconds))
      .state;

  tester.view.physicalSize = const Size(1080, 6000);
  tester.view.devicePixelRatio = 2.0;
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
      child: child!,
    ),
    home: DashboardScreen(deviceState: state),
  ));
  await tester.pump();
  if (settle) await tester.pump(const Duration(seconds: 1)); // animasi gauge

  return () async {
    await tester.pumpWidget(const SizedBox());
    state.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  };
}

Finder get _reconnectButton =>
    find.byWidgetPredicate((w) => w is TextButton);

// Badge status (bukan legenda gauge, yang selalu memuat kata "Normal").
Finder _badgeExact(String text) =>
    find.descendant(of: find.byType(StatusBadge), matching: find.text(text));
Finder _badgeContaining(String text) => find.descendant(
    of: find.byType(StatusBadge), matching: find.textContaining(text));

void main() {
  group('status THI & ambang', () {
    testWidgets('mengikuti ambang /controls, bukan hardcode 72/78',
        (tester) async {
      // THI 75 dengan ambang 76/80 → Normal (hardcode 72/78 akan Waspada).
      final cleanup = await _pump(tester,
          sensor: _sensor(thi: 75),
          controls: const Controls(thiNormal: 76, thiDanger: 80));
      expect(find.text('THI Normal'), findsOneWidget);
      expect(find.textContaining('THI < 76'), findsOneWidget);
      expect(find.text('THI Waspada'), findsNothing);
      await cleanup();
    });

    testWidgets('default firmware 72/78 bila /controls belum ada',
        (tester) async {
      final cleanup = await _pump(tester, sensor: _sensor(thi: 79));
      expect(find.text('THI Bahaya'), findsOneWidget);
      expect(find.textContaining('THI ≥ 78'), findsOneWidget);
      await cleanup();
    });

    testWidgets('status memakai relay aktual & mode, bukan tebakan dari THI',
        (tester) async {
      // THI tinggi tapi mode manual & relay mati → tidak boleh klaim "pendinginan aktif".
      final cleanup = await _pump(tester,
          sensor: _sensor(thi: 79, fan: false, pump: false, auto: false));
      expect(find.textContaining('Kipas mati · Pompa mati · Mode manual'),
          findsOneWidget);
      expect(find.textContaining('Pendinginan Aktif'), findsNothing);
      await cleanup();
    });

    testWidgets('legenda gauge Normal / Waspada / Bahaya', (tester) async {
      final cleanup = await _pump(tester, sensor: _sensor(thi: 70));
      expect(find.text('Waspada'), findsOneWidget);
      expect(find.text('Bahaya'), findsOneWidget);
      expect(find.text('Warning'), findsNothing);
      expect(find.text('Danger'), findsNothing);
      await cleanup();
    });
  });

  group('keadaan data', () {
    testWidgets('online & valid: penilaian saat ini + label Kelembapan',
        (tester) async {
      final cleanup = await _pump(tester, sensor: _sensor(thi: 70));
      expect(find.text('Online'), findsOneWidget);
      expect(find.text('Perangkat offline'), findsNothing);
      expect(find.text('THI Normal'), findsOneWidget);
      expect(find.text('Kelembapan'), findsOneWidget);
      expect(find.text('Kelembaban'), findsNothing);
      expect(find.text('Kondisi aktual dari perangkat'), findsOneWidget);
      expect(find.text('Update 10 detik lalu'), findsOneWidget);
      expect(find.text('21 Sep 21:13 WIB'), findsOneWidget);
      await cleanup();
    });

    testWidgets('sensor_ok=false (online) → Sensor error, bukan angka/Normal',
        (tester) async {
      final cleanup = await _pump(tester, sensor: _sensor(ok: false));
      expect(find.text('Sensor error (DHT22)'), findsOneWidget);
      // 3 KPI (suhu/RH/THI) + pill di bawah gauge.
      expect(find.text('Sensor error'), findsNWidgets(4));
      expect(find.text('THI --'), findsOneWidget);
      expect(find.text('--'), findsWidgets);
      expect(_badgeContaining('Normal'), findsNothing);
      await cleanup();
    });

    testWidgets('data > 60 s → offline, data lama jelas "terakhir", tidak redup',
        (tester) async {
      final cleanup =
          await _pump(tester, sensor: _sensor(thi: 70), ageSeconds: 100);
      expect(find.text('Perangkat offline'), findsOneWidget);
      expect(find.text('Offline'), findsOneWidget); // pill header
      expect(find.text('Status saat ini tidak tersedia'), findsOneWidget);
      expect(find.text('Status terakhir: THI Normal · 21 Sep 21:13 WIB'),
          findsOneWidget);
      expect(find.text('Nilai sensor terakhir · 21 Sep 21:13 WIB'),
          findsOneWidget);
      expect(find.text('Terakhir: Normal'), findsNWidgets(3));
      expect(find.text('Status terakhir: Normal'), findsOneWidget);
      expect(find.text('terakhir diketahui'), findsNWidgets(2));
      // Tidak ada penilaian "Normal" seolah kondisi saat ini.
      expect(_badgeExact('Normal'), findsNothing);
      expect(find.text('THI Normal'), findsNothing);
      // Nilai tetap tampil & tidak diredupkan seluruh kartu.
      expect(find.text('70.0'), findsWidgets);
      expect(
          find.byWidgetPredicate((w) => w is Opacity && w.opacity < 1),
          findsNothing);
      await cleanup();
    });

    testWidgets('offline + sensor error → laporan terakhir, bukan Normal',
        (tester) async {
      final cleanup =
          await _pump(tester, sensor: _sensor(ok: false), ageSeconds: 100);
      expect(find.text('Perangkat offline'), findsOneWidget);
      expect(find.text('Status saat ini tidak tersedia'), findsOneWidget);
      expect(
          find.text(
              'Laporan terakhir: sensor error (DHT22) · 21 Sep 21:13 WIB'),
          findsOneWidget);
      expect(find.text('Terakhir: sensor error'), findsNWidgets(3));
      expect(find.text('Laporan terakhir: sensor error'), findsOneWidget);
      expect(_badgeContaining('Normal'), findsNothing);
      expect(find.textContaining('THI Normal'), findsNothing);
      // Bukan error "saat ini" (badge merah) — itu laporan lama.
      expect(find.text('Sensor error'), findsNothing);
      expect(find.text('Sensor error (DHT22)'), findsNothing);
      await cleanup();
    });

    testWidgets('belum ada data sama sekali', (tester) async {
      final cleanup = await _pump(tester, sensor: null);
      expect(find.text('Offline'), findsOneWidget);
      expect(find.text('Menunggu data'), findsOneWidget);
      expect(find.text('Belum ada data dari perangkat.'), findsOneWidget);
      // 4 KPI + pill gauge.
      expect(find.text('Tidak ada data'), findsNWidgets(5));
      expect(find.text('Menunggu data perangkat…'), findsOneWidget);
      expect(_badgeContaining('Normal'), findsNothing);
      expect(find.textContaining('THI Normal'), findsNothing);
      await cleanup();
    });

    testWidgets('pakan terakhir & jadwal dari /controls', (tester) async {
      final cleanup = await _pump(
        tester,
        sensor: const SensorData(
          sensorOk: true,
          timestamp: _ts,
          lastFeed: '07:00',
          lastFeedTs: _ts - 7200, // 19:13 WIB
        ),
        controls: const Controls(feedTimes: [
          FeedTime(6, 30),
          FeedTime(12, 0),
          FeedTime(18, 15),
        ]),
      );
      expect(find.text('21 Sep 19:13 WIB'), findsOneWidget);
      expect(find.text('Jadwal 07:00 · 2 jam lalu'), findsOneWidget);
      expect(find.text('06:30 · 12:00 · 18:15 WIB'), findsOneWidget);
      await cleanup();
    });
  });

  group('Sambungkan Ulang', () {
    testWidgets('tersedia saat online; hasil menyebut data masih terbaru',
        (tester) async {
      final device = FakeDevice(sensor: _sensor(thi: 70));
      final cleanup = await _pump(tester, device: device);
      expect(find.text('Sambungkan Ulang'), findsOneWidget);

      await tester.tap(find.text('Sambungkan Ulang'));
      await tester.pump();
      await tester.pump();
      expect(device.reconnectCalls, 1);
      expect(find.text('Server terhubung · data perangkat masih terbaru'),
          findsOneWidget);
      await cleanup();
    });

    testWidgets('offline → loading → data segar masuk → online', (tester) async {
      final device = FakeDevice(sensor: _sensor(), ageSeconds: 100);
      final cleanup = await _pump(tester, device: device);
      expect(find.text('Perangkat offline'), findsOneWidget);
      // Tidak ada tombol duplikat di banner offline.
      expect(find.text('Sambungkan Ulang'), findsOneWidget);

      await tester.tap(find.text('Sambungkan Ulang'));
      await tester.pump();
      expect(find.text('Menyambungkan…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.widget<TextButton>(_reconnectButton).onPressed, isNull);
      expect(device.reconnectCalls, 1);

      device.sensorCtrl.add(_sensor(timestamp: _ts + 95));
      await tester.pump();
      await tester.pump();
      expect(find.text('Server terhubung · data perangkat masih terbaru'),
          findsOneWidget);
      expect(find.text('Perangkat offline'), findsNothing);
      expect(find.text('Sambungkan Ulang'), findsOneWidget);
      await cleanup();
    });

    testWidgets('tap berulang saat proses tidak memulai reconnect kedua',
        (tester) async {
      final device = FakeDevice(sensor: _sensor(), ageSeconds: 100);
      final cleanup = await _pump(tester, device: device);
      await tester.tap(find.text('Sambungkan Ulang'));
      await tester.pump();
      await tester.tap(_reconnectButton, warnIfMissed: false);
      await tester.pump();
      await tester.tap(_reconnectButton, warnIfMissed: false);
      await tester.pump();
      expect(device.reconnectCalls, 1);
      await tester.pump(const Duration(seconds: 16));
      expect(device.reconnectCalls, 1);
      await cleanup();
    });

    testWidgets('server tersambung tapi ESP32 diam → penjelasan di banner',
        (tester) async {
      final device = FakeDevice(sensor: _sensor(), ageSeconds: 100);
      final cleanup = await _pump(tester, device: device);
      device.connectedCtrl.add(true);
      await tester.pump();

      await tester.tap(find.text('Sambungkan Ulang'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 16)); // batas tunggu 15 s
      expect(
          find.textContaining(
              'Server terhubung, tetapi belum ada data baru dari perangkat.',
              findRichText: true),
          findsOneWidget);
      // Status perangkat TETAP offline — Firebase tersambung bukan bukti ESP32 pulih.
      expect(find.text('Offline'), findsOneWidget);
      expect(find.text('Online'), findsNothing);
      expect(find.textContaining('data perangkat masih terbaru'), findsNothing);
      await cleanup();
    });

    testWidgets('tanpa internet → "Belum terhubung ke server"', (tester) async {
      final device = FakeDevice(sensor: _sensor(), ageSeconds: 100);
      final cleanup = await _pump(tester, device: device);
      device.connectedCtrl.add(false);
      await tester.pump();

      await tester.tap(find.text('Sambungkan Ulang'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 16));
      expect(find.text('Belum terhubung ke server. Periksa internet ponsel.'),
          findsOneWidget);
      expect(find.text('Offline'), findsOneWidget);
      await cleanup();
    });

    testWidgets(
        'data masih fresh + serverError → kegagalan server tetap terlihat, '
        'status perangkat tetap Online', (tester) async {
      final device = FakeDevice(
        sensor: _sensor(thi: 70),
        reconnectTransport: () async => throw Exception('jaringan putus'),
      );
      final cleanup = await _pump(tester, device: device);
      expect(find.text('Online'), findsOneWidget);

      await tester.tap(find.text('Sambungkan Ulang'));
      await tester.pump();
      await tester.pump();
      expect(device.reconnectCalls, 1);
      // Hasil koneksi server ditampilkan walau data masih dinilai terbaru…
      expect(find.text('Belum terhubung ke server. Periksa internet ponsel.'),
          findsOneWidget);
      // …dan kesegaran data perangkat tetap dinilai terpisah (aturan isOnline
      // tidak berubah).
      expect(find.text('Online'), findsOneWidget);
      expect(find.text('Update 10 detik lalu'), findsOneWidget);
      expect(find.textContaining('data perangkat masih terbaru'), findsNothing);

      // Firebase kemudian melaporkan tersambung → pesan gagal hilang.
      device.connectedCtrl.add(true);
      await tester.pump();
      expect(find.text('Belum terhubung ke server. Periksa internet ponsel.'),
          findsNothing);
      await cleanup();
    });

    testWidgets('hasil "masih terbaru" hilang saat data kemudian menjadi lama',
        (tester) async {
      final device = FakeDevice(sensor: _sensor(thi: 70));
      final cleanup = await _pump(tester, device: device);
      await tester.tap(find.text('Sambungkan Ulang'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Server terhubung · data perangkat masih terbaru'),
          findsOneWidget);

      device.sensorCtrl.add(_sensor(thi: 70, timestamp: _ts - 200));
      await tester.pump();
      expect(find.text('Perangkat offline'), findsOneWidget);
      expect(find.text('Server terhubung · data perangkat masih terbaru'),
          findsNothing);
      await cleanup();
    });
  });

  group('aksesibilitas & motion', () {
    testWidgets('semantics: tombol reconnect & pill status berlabel',
        (tester) async {
      final handle = tester.ensureSemantics();
      final device = FakeDevice(sensor: _sensor(), ageSeconds: 100);
      final cleanup = await _pump(tester, device: device);

      expect(
        tester.getSemantics(_reconnectButton),
        isSemantics(
            label: 'Sambungkan Ulang',
            isButton: true,
            isEnabled: true,
            hasTapAction: true),
      );
      expect(find.bySemanticsLabel('Status perangkat: Offline'), findsOneWidget);
      expect(find.bySemanticsLabel('Logo PITIK'), findsOneWidget);

      await tester.tap(_reconnectButton);
      await tester.pump();
      expect(
        tester.getSemantics(_reconnectButton),
        isSemantics(
            label: 'Menyambungkan…', isButton: true, isEnabled: false),
      );
      await tester.pump(const Duration(seconds: 16));
      await cleanup();
      handle.dispose();
    });

    testWidgets(
        'nilai & ambang THI tersedia sebagai teks di luar grafik, '
        'mengikuti skala teks penuh', (tester) async {
      final state = FakeDevice(sensor: _sensor(thi: 70)).state;
      tester.view.physicalSize = const Size(1080, 9000);
      tester.view.devicePixelRatio = 2.0;
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2.0)),
          child: child!,
        ),
        home: DashboardScreen(deviceState: state),
      ));
      await tester.pump(const Duration(seconds: 1));

      final note = find.text('THI 70.0 · ambang 72 / 78');
      expect(note, findsOneWidget);
      expect(find.descendant(of: find.byType(THIGauge), matching: note),
          findsNothing);
      expect(MediaQuery.textScalerOf(tester.element(note)).scale(1), 2.0);
      // Status di bawah gauge juga skala penuh.
      final status = _badgeExact('Normal').last;
      expect(MediaQuery.textScalerOf(tester.element(status)).scale(1), 2.0);

      await tester.pumpWidget(const SizedBox());
      state.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    testWidgets('reduced motion: gauge langsung ke nilai, tanpa spinner',
        (tester) async {
      final device = FakeDevice(sensor: _sensor(thi: 79), ageSeconds: 100);
      final cleanup =
          await _pump(tester, device: device, reduceMotion: true, settle: false);
      expect(find.text('79.0'), findsWidgets); // tanpa animasi 0 → 79
      expect(tester.hasRunningAnimations, isFalse);

      await tester.tap(find.text('Sambungkan Ulang'));
      await tester.pump();
      expect(find.text('Menyambungkan…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
      // Setelah ripple sentuh bawaan Material selesai, proses masih berjalan
      // tetapi tidak ada animasi berulang apa pun (tidak ada spinner).
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Menyambungkan…'), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pump(const Duration(seconds: 16));
      await cleanup();
    });

    testWidgets('tanpa reduced motion gauge beranimasi sekali, '
        'tidak diputar ulang saat hanya timestamp berubah', (tester) async {
      final device = FakeDevice(sensor: _sensor(thi: 79));
      final cleanup = await _pump(tester, device: device, settle: false);
      expect(tester.hasRunningAnimations, isTrue); // animasi awal 0 → 79
      await tester.pump(const Duration(seconds: 1));
      expect(tester.hasRunningAnimations, isFalse);

      device.sensorCtrl.add(_sensor(thi: 79, timestamp: _ts + 5));
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
      expect(find.text('79.0'), findsWidgets);
      await cleanup();
    });
  });
}
