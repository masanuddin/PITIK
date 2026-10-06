// Navigasi bawah: satu baris bila label muat, grid 2×2 bila tidak.
// Label selalu skala penuh (tanpa FittedBox / batas skala / ellipsis).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitik_app/main.dart' show pitikNavItems;
import 'package:pitik_app/widgets/pitik_bottom_nav.dart';

Future<void> _pump(
  WidgetTester tester, {
  required double width,
  required double scale,
  List<PitikNavItem> items = pitikNavItems,
  int index = 0,
  ValueChanged<int>? onSelected,
}) async {
  tester.view.devicePixelRatio = 3.0;
  tester.view.physicalSize = Size(width * 3, 780 * 3);
  tester.view.padding = const FakeViewPadding(bottom: 24 * 3.0);
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(
      body: ListView(children: [
        for (var i = 0; i < 40; i++) ListTile(title: Text('Baris $i')),
      ]),
      bottomNavigationBar: PitikBottomNav(
        items: items,
        currentIndex: index,
        onSelected: onSelected ?? (_) {},
      ),
    ),
  ));
}

Finder _labelOf(String label) => find.descendant(
    of: find.byType(PitikBottomNav), matching: find.text(label));

void main() {
  for (final width in [360.0, 393.0]) {
    for (final scale in [1.0, 1.1, 1.3, 1.5, 2.0]) {
      testWidgets('${width.toInt()} dp · teks ${scale}x: mode sesuai pengukuran, '
          'label skala penuh & utuh', (tester) async {
        await _pump(tester, width: width, scale: scale);
        final rowMode = find.byKey(const ValueKey('pitik-nav-row'));
        final gridMode = find.byKey(const ValueKey('pitik-nav-grid'));
        expect(rowMode.evaluate().length + gridMode.evaluate().length, 1);

        // Mode = hasil pengukuran label sebenarnya pada lebar aktual.
        final layout = rowMode.evaluate().isNotEmpty ? rowMode : gridMode;
        final ctx = tester.element(layout);
        final expectRow = PitikBottomNav.labelsFit(
          ctx,
          labels: [for (final i in pitikNavItems) i.label],
          width: tester.getSize(layout).width,
          columns: pitikNavItems.length,
        );
        expect(rowMode, expectRow ? findsOneWidget : findsNothing);

        // Tidak ada pengecilan teks.
        expect(
            find.descendant(
                of: find.byType(PitikBottomNav),
                matching: find.byType(FittedBox)),
            findsNothing);
        for (final item in pitikNavItems) {
          final label = _labelOf(item.label);
          expect(label, findsOneWidget);
          expect(MediaQuery.textScalerOf(tester.element(label)).scale(1),
              scale);
          final text = tester.widget<Text>(label);
          expect(text.overflow, isNull);
          expect(text.maxLines, isNull);
          // Target sentuh tiap tab.
          final button = find.ancestor(
              of: label, matching: find.byType(InkWell)).first;
          final size = tester.getSize(button);
          expect(size.height, greaterThanOrEqualTo(64));
          expect(size.width, greaterThanOrEqualTo(48));
          // Label tidak melebihi tombolnya.
          expect(tester.getRect(label).width,
              lessThanOrEqualTo(tester.getRect(button).width));
        }

        if (!expectRow) {
          // Urutan grid: Dashboard | Riwayat / Kontrol | Pengaturan.
          final d = tester.getCenter(_labelOf('Dashboard'));
          final r = tester.getCenter(_labelOf('Riwayat'));
          final k = tester.getCenter(_labelOf('Kontrol'));
          final p = tester.getCenter(_labelOf('Pengaturan'));
          expect(d.dx, lessThan(r.dx));
          expect(k.dx, lessThan(p.dx));
          expect(k.dy, greaterThan(d.dy));
          expect(p.dy, greaterThan(r.dy));
        }

        // Navigasi tidak menutupi konten: body berakhir di atas navigasi.
        final navTop = tester.getTopLeft(find.byType(PitikBottomNav)).dy;
        final bodyBottom = tester.getBottomLeft(find.byType(ListView)).dy;
        expect(bodyBottom, lessThanOrEqualTo(navTop));
        tester.view.reset();
      });
    }
  }

  testWidgets('label pendek tetap satu baris walau teks 2.0×', (tester) async {
    await _pump(tester, width: 360, scale: 2.0, items: const [
      PitikNavItem(icon: Icons.home, activeIcon: Icons.home, label: 'A'),
      PitikNavItem(icon: Icons.home, activeIcon: Icons.home, label: 'B'),
      PitikNavItem(icon: Icons.home, activeIcon: Icons.home, label: 'C'),
      PitikNavItem(icon: Icons.home, activeIcon: Icons.home, label: 'D'),
    ]);
    expect(find.byKey(const ValueKey('pitik-nav-row')), findsOneWidget);
    expect(find.byKey(const ValueKey('pitik-nav-grid')), findsNothing);
    tester.view.reset();
  });

  testWidgets('label panjang di layar sempit → grid 2×2', (tester) async {
    await _pump(tester, width: 320, scale: 1.0, items: const [
      PitikNavItem(
          icon: Icons.home, activeIcon: Icons.home, label: 'Pengaturanxyz'),
      PitikNavItem(icon: Icons.home, activeIcon: Icons.home, label: 'B'),
      PitikNavItem(icon: Icons.home, activeIcon: Icons.home, label: 'C'),
      PitikNavItem(icon: Icons.home, activeIcon: Icons.home, label: 'D'),
    ]);
    expect(find.byKey(const ValueKey('pitik-nav-grid')), findsOneWidget);
    tester.view.reset();
  });

  testWidgets('grid: tap memilih tab & semantics selected', (tester) async {
    final handle = tester.ensureSemantics();
    var index = 0;
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(360 * 3.0, 780 * 3.0);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2.0)),
        child: child!,
      ),
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
    expect(find.byKey(const ValueKey('pitik-nav-grid')), findsOneWidget);
    await tester.tap(_labelOf('Pengaturan'));
    await tester.pump();
    expect(index, 3);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Pengaturan')),
      isSemantics(isButton: true, isSelected: true, hasTapAction: true),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Dashboard')),
      isSemantics(isButton: true, isSelected: false),
    );
    handle.dispose();
    tester.view.reset();
  });
}
