// Responsif & aksesibilitas Dashboard + navigasi bawah.
// Lebar 360/393 dp × skala teks 1.0/1.5/2.0 × keadaan data.
// Overflow (RenderFlex overflowed) otomatis menggagalkan tes.
// Semua data dari FakeDevice — tanpa Firebase.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitik_app/main.dart' show pitikNavItems;
import 'package:pitik_app/models/sensor_data.dart';
import 'package:pitik_app/screens/dashboard_screen.dart';
import 'package:pitik_app/services/device_state.dart';
import 'package:pitik_app/widgets/connection_row.dart';
import 'package:pitik_app/widgets/pitik_bottom_nav.dart';

import '../helpers/fakes.dart';

const _ts = fakeTs;

enum _Kind { online, stale, sensorError, staleSensorError, noData }

FakeDevice _device(_Kind kind) {
  const ok = SensorData(
    sensorOk: true,
    temperature: 25,
    humidity: 70,
    thi: 70,
    timestamp: _ts,
    mq137Raw: 1200,
    mq137Volt: 0.97,
    lastFeed: 'nextion',
    lastFeedTs: _ts - 3600,
  );
  const err = SensorData(sensorOk: false, timestamp: _ts, mq137Raw: 1200);
  return switch (kind) {
    _Kind.online => FakeDevice(sensor: ok),
    _Kind.stale => FakeDevice(sensor: ok, ageSeconds: 4 * 86400),
    _Kind.sensorError => FakeDevice(sensor: err),
    _Kind.staleSensorError => FakeDevice(sensor: err, ageSeconds: 4 * 86400),
    _Kind.noData => FakeDevice(sensor: null),
  };
}

/// Struktur sama dengan MainNavigation (Scaffold + PitikBottomNav), tanpa
/// Firebase. Mengembalikan pembersih.
Future<Future<void> Function()> _pumpApp(
  WidgetTester tester, {
  required double width,
  required double textScale,
  required DeviceState state,
  double height = 780,
}) async {
  tester.view.devicePixelRatio = 3.0;
  tester.view.physicalSize = Size(width * 3, height * 3);
  // Simulasikan gesture-nav bar Android (safe area bawah).
  tester.view.padding = const FakeViewPadding(bottom: 24 * 3.0);
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      body: DashboardScreen(deviceState: state),
      bottomNavigationBar: PitikBottomNav(
        items: pitikNavItems,
        currentIndex: 0,
        onSelected: (_) {},
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  return () async {
    await tester.pumpWidget(const SizedBox());
    state.dispose();
    tester.view.reset();
  };
}

void main() {
  for (final width in [360.0, 393.0]) {
    for (final scale in [1.0, 1.1, 1.3, 1.5, 2.0]) {
      for (final kind in _Kind.values) {
        testWidgets(
            '${width.toInt()} dp · teks ${scale}x · ${kind.name}: '
            'tanpa overflow, konten terakhir terlihat di atas navigasi',
            (tester) async {
          final cleanup = await _pumpApp(tester,
              width: width, textScale: scale, state: _device(kind).state);

          // Tombol reconnect selalu ada & minimal 48 dp.
          final btn = find.byWidgetPredicate((w) => w is TextButton);
          expect(btn, findsOneWidget);
          expect(tester.getSize(btn).height, greaterThanOrEqualTo(48));

          // Baris koneksi: dua baris bila sempit / teks besar, satu baris
          // bila cukup lebar (konten 393−32 = 361 dp ≥ 340 × skala).
          final firstInfoText = find
              .descendant(
                  of: find.byType(ConnectionRow), matching: find.byType(Text))
              .first;
          final expectTwoRows = (width - 32) < 340 * scale;
          final btnTop = tester.getTopLeft(btn).dy;
          final infoBottom = tester.getBottomLeft(firstInfoText).dy;
          if (expectTwoRows) {
            expect(btnTop, greaterThanOrEqualTo(infoBottom),
                reason: 'tombol harus turun ke baris kedua');
          } else {
            expect(btnTop, lessThan(infoBottom),
                reason: 'tombol sebaris dengan info update');
          }

          // Konten paling bawah (legenda "Bahaya") bisa di-scroll hingga
          // terlihat utuh DI ATAS navigasi bawah.
          final last = find.text('Bahaya').last;
          await tester.scrollUntilVisible(last, 300,
              scrollable: find.byType(Scrollable).first);
          await tester.pump();
          final navTop = tester.getTopLeft(find.byType(PitikBottomNav)).dy;
          expect(tester.getRect(last).bottom, lessThanOrEqualTo(navTop));

          // Navigasi: tinggi ≥ 64 + safe area, label tidak terpotong.
          final navHeight = tester.getSize(find.byType(PitikBottomNav)).height;
          expect(navHeight, greaterThanOrEqualTo(64 + 24));
          for (final item in pitikNavItems) {
            expect(find.text(item.label), findsOneWidget);
          }
          await cleanup();
        });
      }
    }
  }

  testWidgets('navigasi: semantics tombol + selected, tap memilih tab',
      (tester) async {
    final handle = tester.ensureSemantics();
    var index = 0;
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(360 * 3.0, 780 * 3.0);
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(
        builder: (context, setState) => Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: PitikBottomNav(
            items: pitikNavItems,
            currentIndex: index,
            onSelected: (i) => setState(() => index = i),
          ),
        ),
      ),
    ));

    expect(
      tester.getSemantics(find.bySemanticsLabel('Dashboard')),
      isSemantics(isButton: true, isSelected: true, hasTapAction: true),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Pengaturan')),
      isSemantics(isButton: true, isSelected: false, hasTapAction: true),
    );

    await tester.tap(find.text('Riwayat'));
    await tester.pump();
    expect(index, 1);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Riwayat')),
      isSemantics(isButton: true, isSelected: true),
    );
    handle.dispose();
    tester.view.reset();
  });

  testWidgets('IndexedStack: posisi scroll Dashboard tetap setelah pindah tab',
      (tester) async {
    final state = _device(_Kind.online).state;
    var index = 0;
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(393 * 3.0, 780 * 3.0);
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(
        builder: (context, setState) => Scaffold(
          body: IndexedStack(index: index, children: [
            DashboardScreen(deviceState: state),
            const Center(child: Text('Tab lain')),
          ]),
          bottomNavigationBar: PitikBottomNav(
            items: pitikNavItems.take(2).toList(),
            currentIndex: index,
            onSelected: (i) => setState(() => index = i),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));

    final scrollable = find.byType(Scrollable).first;
    await tester.drag(scrollable, const Offset(0, -500));
    await tester.pumpAndSettle();
    final offset = tester.state<ScrollableState>(scrollable).position.pixels;
    expect(offset, greaterThan(0));

    await tester.tap(find.text('Riwayat'));
    await tester.pump();
    await tester.tap(find.text('Dashboard'));
    await tester.pump();
    expect(tester.state<ScrollableState>(scrollable).position.pixels, offset);

    await tester.pumpWidget(const SizedBox());
    state.dispose();
    tester.view.reset();
  });
}
