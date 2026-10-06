// Tes layar Riwayat (redesign batch 2).
// Semua data dari FakeRepo.onFetchHistory — tanpa Firebase.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitik_app/main.dart' show pitikNavItems;
import 'package:pitik_app/models/controls.dart';
import 'package:pitik_app/models/history_point.dart';
import 'package:pitik_app/screens/history_screen.dart';
import 'package:pitik_app/services/device_state.dart';
import 'package:pitik_app/services/pitik_repository.dart';
import 'package:pitik_app/widgets/history_chart_card.dart';
import 'package:pitik_app/widgets/pitik_bottom_nav.dart';

import '../helpers/fakes.dart';

HistoryPoint _pt(String time, double t, double h, double thi,
        {int? mq, bool fan = false, bool pump = false, String date = '2026-10-04'}) =>
    HistoryPoint(
        date: date,
        time: time,
        temperature: t,
        humidity: h,
        thi: thi,
        mq137Raw: mq,
        fan: fan,
        pump: pump);

/// Dataset 24 Jam: suhu 24.0–27.0, MQ 180–220, satu siklus pendinginan.
final _day = [
  _pt('10:00', 24.0, 70, 70.1, mq: 180),
  _pt('10:05', 25.5, 72, 72.4, mq: 200, fan: true),
  _pt('10:10', 27.0, 75, 75.3, mq: 220, fan: true),
];

/// Dataset 7 Hari: nilai berbeda agar mudah dibedakan.
final _week = [
  _pt('08:00', 30.0, 60, 77.0, mq: 300, date: '2026-09-28'),
  _pt('08:00', 31.0, 62, 78.5, mq: 310, date: '2026-10-04'),
];

final _hour = [_pt('09:55', 22.0, 65, 67.0, mq: 150)];

Finder _inChart(String key, Finder matching) =>
    find.descendant(of: find.byKey(ValueKey('chart-$key')), matching: matching);

/// Teks chip periode data pada semua kartu grafik & statistik.
Set<String> _shownPeriods(WidgetTester tester) {
  final labels = <String>{};
  for (final card in find.byType(HistoryChartCard).evaluate()) {
    final w = card.widget as HistoryChartCard;
    labels.add(w.periodLabel);
  }
  return labels;
}

/// DeviceState yang dibuat/dipakai tes; dibuang di akhir tiap tes (timer).
final _owned = <DeviceState>[];

/// testWidgets + pembersihan (widget tree & timer DeviceState).
void _t(String name, Future<void> Function(WidgetTester tester) body) =>
    testWidgets(name, (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox());
      for (final s in _owned) {
        s.dispose();
      }
      _owned.clear();
    });

/// Gulir ke ujung bawah daftar.
Future<void> _scrollToEnd(WidgetTester tester) async {
  final pos =
      tester.state<ScrollableState>(find.byType(Scrollable).first).position;
  pos.jumpTo(pos.maxScrollExtent);
  await tester.pump();
}

Future<void> _pump(
  WidgetTester tester, {
  required FakeRepo repo,
  DeviceState? state,
  double width = 393,
  double height = 900,
  double textScale = 1.0,
  bool reducedMotion = false,
  bool withNav = false,
}) async {
  tester.view.devicePixelRatio = 3.0;
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.padding = const FakeViewPadding(bottom: 24 * 3.0);
  addTearDown(tester.view.reset);
  final device = state ?? fakeDeviceState();
  _owned.add(device);
  final screen = HistoryScreen(repository: repo, deviceState: device);
  await tester.pumpWidget(MaterialApp(
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
                items: pitikNavItems, currentIndex: 1, onSelected: (_) {}),
          )
        : screen,
  ));
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  group('periode & keadaan', () {
    _t('default memuat 24 Jam; memilih periode memuat periode itu',
        (tester) async {
      final repo = FakeRepo()
        ..onFetchHistory = (p) async => switch (p) {
              HistoryPeriod.last7Days => _week,
              HistoryPeriod.lastHour => _hour,
              _ => _day,
            };
      await _pump(tester, repo: repo);
      await _settle(tester);

      expect(repo.historyRequests, [HistoryPeriod.last24Hours]);
      expect(_shownPeriods(tester), {'24 Jam'});
      expect(
        tester.getSemantics(find.bySemanticsLabel('Periode 24 Jam')),
        isSemantics(isButton: true, isSelected: true),
      );

      await tester.tap(find.bySemanticsLabel('Periode 7 Hari'));
      await _settle(tester);
      expect(repo.historyRequests.last, HistoryPeriod.last7Days);
      expect(_shownPeriods(tester), {'7 Hari'});
      expect(_inChart('suhu', find.text('31.0°C')), findsOneWidget); // maks
      expect(
        tester.getSemantics(find.bySemanticsLabel('Periode 7 Hari')),
        isSemantics(isButton: true, isSelected: true),
      );

      await tester.tap(find.bySemanticsLabel('Periode 1 Jam'));
      await _settle(tester);
      expect(repo.historyRequests.last, HistoryPeriod.lastHour);
      expect(_shownPeriods(tester), {'1 Jam'});
    });

    _t('memuat awal: kerangka + teks periode, tanpa angka',
        (tester) async {
      final c = Completer<List<HistoryPoint>>();
      final repo = FakeRepo()..onFetchHistory = (_) => c.future;
      await _pump(tester, repo: repo);
      await tester.pump();

      expect(find.text('Memuat riwayat 24 Jam…'), findsOneWidget);
      expect(find.byType(HistoryChartCard), findsNothing);
      expect(find.text('Rata-rata'), findsNothing);

      c.complete(_day);
      await _settle(tester);
      expect(find.text('Memuat riwayat 24 Jam…'), findsNothing);
      expect(find.byType(HistoryChartCard), findsNWidgets(4));
    });

    _t('kosong: pesan kosong, bukan angka nol', (tester) async {
      final repo = FakeRepo()..onFetchHistory = (_) async => const [];
      await _pump(tester, repo: repo);
      await _settle(tester);

      expect(find.text('Tidak ada data dalam 24 jam terakhir'), findsOneWidget);
      expect(find.byType(HistoryChartCard), findsNothing);
      expect(find.textContaining('0.0'), findsNothing);
      expect(find.text('0×'), findsNothing);
      expect(find.byKey(const ValueKey('stats-card')), findsNothing);
    });

    _t('error awal: pesan + Coba Lagi memuat ulang', (tester) async {
      var fail = true;
      final repo = FakeRepo()
        ..onFetchHistory = (_) async {
          if (fail) throw Exception('network');
          return _day;
        };
      await _pump(tester, repo: repo);
      await _settle(tester);

      expect(find.text('Gagal memuat riwayat 24 Jam'), findsOneWidget);
      expect(find.byType(HistoryChartCard), findsNothing);

      fail = false;
      await tester.tap(find.text('Coba Lagi'));
      await _settle(tester);
      expect(repo.historyRequests.length, 2);
      expect(find.text('Gagal memuat riwayat 24 Jam'), findsNothing);
      expect(_shownPeriods(tester), {'24 Jam'});
    });
  });

  group('pergantian periode', () {
    _t('saat memuat periode baru, data lama tetap dilabeli periodenya',
        (tester) async {
      final week = Completer<List<HistoryPoint>>();
      final repo = FakeRepo()
        ..onFetchHistory = (p) =>
            p == HistoryPeriod.last7Days ? week.future : Future.value(_day);
      await _pump(tester, repo: repo);
      await _settle(tester);

      await tester.tap(find.bySemanticsLabel('Periode 7 Hari'));
      await tester.pump();

      // Tombol periode sudah 7 Hari, tetapi grafik masih (dan dilabeli) 24 Jam.
      expect(
        tester.getSemantics(find.bySemanticsLabel('Periode 7 Hari')),
        isSemantics(isSelected: true),
      );
      expect(find.text('Memuat data 7 Hari…'), findsOneWidget);
      expect(find.text('Grafik di bawah masih data 24 Jam.'), findsOneWidget);
      expect(_shownPeriods(tester), {'24 Jam'});
      expect(_inChart('suhu', find.text('27.0°C')), findsOneWidget);

      week.complete(_week);
      await _settle(tester);
      expect(find.text('Memuat data 7 Hari…'), findsNothing);
      expect(_shownPeriods(tester), {'7 Hari'});
    });

    _t('respons lama yang terlambat tidak menimpa pilihan terbaru',
        (tester) async {
      final week = Completer<List<HistoryPoint>>();
      final month = Completer<List<HistoryPoint>>();
      final repo = FakeRepo()
        ..onFetchHistory = (p) => switch (p) {
              HistoryPeriod.last7Days => week.future,
              HistoryPeriod.last30Days => month.future,
              _ => Future.value(_day),
            };
      await _pump(tester, repo: repo);
      await _settle(tester);

      await tester.tap(find.bySemanticsLabel('Periode 7 Hari'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Periode 30 Hari'));
      await tester.pump();

      final monthData = [_pt('12:00', 28.0, 66, 74.0, mq: 260)];
      month.complete(monthData);
      await _settle(tester);
      expect(_shownPeriods(tester), {'30 Hari'});

      // 7 Hari datang belakangan → diabaikan.
      week.complete(_week);
      await _settle(tester);
      expect(_shownPeriods(tester), {'30 Hari'});
      expect(_inChart('suhu', find.text('28.0°C')), findsWidgets);
      expect(_inChart('suhu', find.text('31.0°C')), findsNothing);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Periode 30 Hari')),
        isSemantics(isSelected: true),
      );
    });

    _t('gagal ganti periode: data lama tetap + penjelasan + Coba Lagi',
        (tester) async {
      var failWeek = true;
      final repo = FakeRepo()
        ..onFetchHistory = (p) async {
          if (p == HistoryPeriod.last7Days) {
            if (failWeek) throw Exception('timeout');
            return _week;
          }
          return _day;
        };
      await _pump(tester, repo: repo);
      await _settle(tester);

      await tester.tap(find.bySemanticsLabel('Periode 7 Hari'));
      await _settle(tester);
      expect(find.text('Gagal memuat data 7 Hari.'), findsOneWidget);
      expect(find.textContaining('Grafik di bawah masih data 24 Jam.'),
          findsOneWidget);
      expect(_shownPeriods(tester), {'24 Jam'});
      expect(find.byType(HistoryChartCard), findsNWidgets(4));

      failWeek = false;
      await tester.tap(find.text('Coba Lagi'));
      await _settle(tester);
      expect(find.text('Gagal memuat data 7 Hari.'), findsNothing);
      expect(_shownPeriods(tester), {'7 Hari'});
    });
  });

  group('CSV', () {
    late List<String> copied;

    setUp(() {
      copied = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    TextButton csvButton(WidgetTester tester) => tester.widget<TextButton>(
        find.ancestor(
            of: find.text('Salin CSV'), matching: find.byType(TextButton)));

    _t('isi CSV = dataset periode yang tampil', (tester) async {
      final repo = FakeRepo()..onFetchHistory = (_) async => _day;
      await _pump(tester, repo: repo);
      await _settle(tester);

      expect(csvButton(tester).onPressed, isNotNull);
      await tester.tap(find.text('Salin CSV'));
      await tester.pump();
      expect(copied, [historyToCsv(_day)]);
      expect(find.textContaining('CSV 24 Jam disalin (3 baris)'), findsOneWidget);
      expect(find.text('Disalin'), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      expect(find.text('Salin CSV'), findsOneWidget);
    });

    _t('nonaktif saat ganti periode, kosong, atau gagal',
        (tester) async {
      final week = Completer<List<HistoryPoint>>();
      final repo = FakeRepo()
        ..onFetchHistory = (p) => switch (p) {
              HistoryPeriod.last7Days => week.future,
              HistoryPeriod.lastHour => Future.value(const <HistoryPoint>[]),
              HistoryPeriod.last30Days => Future.error(Exception('x')),
              _ => Future.value(_day),
            };
      await _pump(tester, repo: repo);
      await _settle(tester);
      expect(csvButton(tester).onPressed, isNotNull);

      // Sedang memuat 7 Hari, grafik masih 24 Jam → tidak bisa salin.
      await tester.tap(find.bySemanticsLabel('Periode 7 Hari'));
      await tester.pump();
      expect(csvButton(tester).onPressed, isNull);
      await tester.tap(find.text('Salin CSV'), warnIfMissed: false);
      expect(copied, isEmpty);

      week.complete(_week);
      await _settle(tester);
      expect(csvButton(tester).onPressed, isNotNull);
      await tester.tap(find.text('Salin CSV'));
      await tester.pump();
      expect(copied, [historyToCsv(_week)]);

      // Gagal memuat 30 Hari → data 7 Hari tetap tampil, CSV nonaktif.
      await tester.pump(const Duration(seconds: 4));
      await tester.tap(find.bySemanticsLabel('Periode 30 Hari'));
      await _settle(tester);
      expect(_shownPeriods(tester), {'7 Hari'});
      expect(csvButton(tester).onPressed, isNull);

      // Kosong → nonaktif.
      await tester.tap(find.bySemanticsLabel('Periode 1 Jam'));
      await _settle(tester);
      expect(find.text('Tidak ada data dalam 1 jam terakhir'), findsOneWidget);
      expect(csvButton(tester).onPressed, isNull);
      expect(copied.length, 1);
    });
  });

  group('isi grafik', () {
    _t('satuan: °C, %, THI tanpa satuan, MQ-137 ADC (bukan ppm)',
        (tester) async {
      final repo = FakeRepo()..onFetchHistory = (_) async => _day;
      await _pump(tester, repo: repo);
      await _settle(tester);

      expect(find.text('Suhu (°C)'), findsOneWidget);
      expect(_inChart('suhu', find.text('24.0°C')), findsOneWidget);
      expect(_inChart('suhu', find.text('27.0°C')), findsOneWidget);
      expect(find.text('Kelembapan (%)'), findsOneWidget);
      expect(_inChart('rh', find.text('75.0%')), findsOneWidget);
      expect(_inChart('thi', find.text('70.1')), findsOneWidget);
      expect(_inChart('thi', find.text('75.3')), findsOneWidget);

      await tester.scrollUntilVisible(
          _inChart('mq', find.text('220 ADC')), 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Sensor gas MQ-137 (ADC)'), findsOneWidget);
      expect(_inChart('mq', find.text('200 ADC')), findsOneWidget); // rata-rata
      expect(_inChart('mq', find.text('180 ADC')), findsOneWidget);
      expect(find.textContaining('Belum dikalibrasi — bukan nilai ppm.',
          findRichText: true), findsOneWidget);
      // Tidak ada nilai berlabel ppm.
      expect(find.textContaining(RegExp(r'\d\s*ppm')), findsNothing);
    });

    _t('MQ-137 tanpa data: pesan kosong, statistik tidak nol',
        (tester) async {
      final repo = FakeRepo()
        ..onFetchHistory = (_) async => [
              _pt('10:00', 24.0, 70, 70.1),
              _pt('10:05', 25.0, 71, 71.0),
            ];
      await _pump(tester, repo: repo);
      await _settle(tester);
      await tester.scrollUntilVisible(
          find.text('Tidak ada data MQ-137 pada periode ini.'), 300,
          scrollable: find.byType(Scrollable).first);
      expect(_inChart('mq', find.text('Rata-rata')), findsNothing);
      // Hanya judul & catatan kalibrasi yang menyebut ADC — tanpa angka.
      expect(_inChart('mq', find.textContaining('ADC')), findsNWidgets(2));
      expect(_inChart('mq', find.textContaining(RegExp(r'^\d+ ADC$'))),
          findsNothing);
    });

    _t('zona & ambang THI mengikuti /controls (bukan 72/78)',
        (tester) async {
      final device = FakeDevice(
          controls: const Controls(thiNormal: 70, thiDanger: 76));
      final repo = FakeRepo()..onFetchHistory = (_) async => _day;
      await _pump(tester, repo: repo, state: device.state);
      await _settle(tester);

      final card = tester.widget<HistoryChartCard>(
          find.byKey(const ValueKey('chart-thi')));
      expect(card.zones!.normal, 70);
      expect(card.zones!.danger, 76);
      expect(find.text('Ambang (Pengaturan): normal 70 · bahaya 76'),
          findsOneWidget);

      // Ambang berubah dari /controls → grafik ikut.
      device.controlsCtrl
          .add(const Controls(thiNormal: 73.5, thiDanger: 80));
      await tester.pump();
      await tester.pump();
      expect(find.text('Ambang (Pengaturan): normal 73.5 · bahaya 80'),
          findsOneWidget);
      expect(
          tester
              .widget<HistoryChartCard>(find.byKey(const ValueKey('chart-thi')))
              .zones!
              .danger,
          80);
    });

    _t('statistik: siklus pendinginan disajikan sebagai estimasi',
        (tester) async {
      final repo = FakeRepo()..onFetchHistory = (_) async => _day;
      await _pump(tester, repo: repo);
      await _settle(tester);
      final stats = find.byKey(const ValueKey('stats-card'));
      await tester.scrollUntilVisible(stats, 300,
          scrollable: find.byType(Scrollable).first);

      Finder inStats(Finder f) => find.descendant(of: stats, matching: f);
      expect(inStats(find.text('Estimasi siklus pendinginan')), findsOneWidget);
      // Algoritme existing: 1 transisi (false → true, true).
      expect(inStats(find.text('${HistoryStats.fromPoints(_day).coolingEvents}×')),
          findsOneWidget);
      expect(inStats(find.text('1×')), findsOneWidget);
      expect(inStats(find.textContaining('Bukan jumlah kejadian pasti')),
          findsOneWidget);
      expect(inStats(find.text('24 Jam')), findsOneWidget);
      expect(inStats(find.text('25.5°C')), findsOneWidget); // rata-rata suhu
    });

    _t('ketuk grafik: readout memakai tanggal/jam & nilai titik asli',
        (tester) async {
      final repo = FakeRepo()..onFetchHistory = (_) async => _day;
      await _pump(tester, repo: repo);
      await _settle(tester);

      expect(_inChart('suhu', find.text('Ketuk grafik untuk melihat nilai')),
          findsOneWidget);
      final chart = _inChart('suhu', find.byType(SizedBox)).evaluate().firstWhere(
          (e) => (e.widget as SizedBox).height == 190);
      final box = chart.renderObject as RenderBox;
      final center = box.localToGlobal(box.size.center(Offset.zero));
      await tester.tapAt(center);
      await tester.pump();

      expect(_inChart('suhu', find.text('Ketuk grafik untuk melihat nilai')),
          findsNothing);
      final when = _inChart('suhu',
              find.textContaining(RegExp(r'^4 Okt \d\d:\d\d WIB$')))
          .evaluate()
          .map((e) => (e.widget as Text).data!)
          .single;
      final time = RegExp(r'\d\d:\d\d').firstMatch(when)!.group(0);
      final point = _day.firstWhere((p) => p.time == time);
      // Nilai readout = suhu titik itu (muncul di readout; bisa juga di statistik).
      expect(_inChart('suhu', find.text('${point.temperature.toStringAsFixed(1)}°C')),
          findsWidgets);
    });
  });

  group('aksesibilitas', () {
    for (final width in [360.0, 393.0]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        _t(
            '${width.toInt()} dp · teks ${scale}x: tanpa overflow, '
            'konten terakhir di atas navigasi', (tester) async {
          final repo = FakeRepo()..onFetchHistory = (_) async => _day;
          await _pump(tester,
              repo: repo,
              width: width,
              height: 780,
              textScale: scale,
              withNav: true);
          await _settle(tester);

          // Tombol periode & CSV ≥ 48 dp.
          for (final label in ['1 Jam', '24 Jam', '7 Hari', '30 Hari']) {
            final h = tester
                .getSize(find.bySemanticsLabel('Periode $label'))
                .height;
            expect(h, greaterThanOrEqualTo(48));
          }
          expect(
              tester
                  .getSize(find.ancestor(
                      of: find.text('Salin CSV'),
                      matching: find.byType(TextButton)))
                  .height,
              greaterThanOrEqualTo(48));

          final last = find.textContaining('Bukan jumlah kejadian pasti');
          await _scrollToEnd(tester);
          final navTop = tester.getTopLeft(find.byType(PitikBottomNav)).dy;
          expect(tester.getRect(last).bottom, lessThanOrEqualTo(navTop));
        });

        _t(
            '${width.toInt()} dp · teks ${scale}x: keadaan ganti periode & '
            'error tanpa overflow', (tester) async {
          final week = Completer<List<HistoryPoint>>();
          final repo = FakeRepo()
            ..onFetchHistory = (p) => switch (p) {
                  HistoryPeriod.last7Days => week.future,
                  HistoryPeriod.last30Days => Future.error(Exception('x')),
                  _ => Future.value(_day),
                };
          await _pump(tester,
              repo: repo,
              width: width,
              height: 780,
              textScale: scale,
              withNav: true);
          await _settle(tester);
          await tester.tap(find.bySemanticsLabel('Periode 7 Hari'));
          await tester.pump();
          expect(find.text('Memuat data 7 Hari…'), findsOneWidget);
          await tester.tap(find.bySemanticsLabel('Periode 30 Hari'));
          await _settle(tester);
          expect(find.text('Gagal memuat data 30 Hari.'), findsOneWidget);
          week.complete(_week);
          await _settle(tester);
        });
      }
    }

    _t('reduced motion: tanpa spinner berputar & tanpa animasi',
        (tester) async {
      final c = Completer<List<HistoryPoint>>();
      final repo = FakeRepo()..onFetchHistory = (_) => c.future;
      await _pump(tester, repo: repo, reducedMotion: true);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
      expect(tester.binding.hasScheduledFrame, isFalse);

      c.complete(_day);
      await tester.pump();
      await tester.pump();
      expect(find.byType(HistoryChartCard), findsNWidgets(4));
      // Animasi berdurasi 0 selesai dalam satu frame; tidak ada transisi
      // tombol/warna yang terus berjalan.
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);

      // Pilih titik & ganti periode: tetap tanpa animasi.
      // Ganti periode: indikator memuat statis; setelah riak sentuhan
      // Material (umpan balik tap standar) selesai, tidak ada animasi lagi.
      await tester.tap(find.bySemanticsLabel('Periode 7 Hari'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });
}
