import 'package:flutter_test/flutter_test.dart';
import 'package:pitik_app/models/history_point.dart';
import 'package:pitik_app/services/pitik_repository.dart';

void main() {
  group('HistoryPoint.fromEntry', () {
    test('membaca t/h/thi/mq137_raw/f/p/ts', () {
      final p = HistoryPoint.fromEntry('2026-09-30', '14:05', {
        't': 28.4,
        'h': 71,
        'thi': 77.9,
        'mq137_raw': 980,
        'f': 1,
        'p': 0,
        'ts': 1_790_000_000,
      })!;
      expect(p.date, '2026-09-30');
      expect(p.time, '14:05');
      expect(p.temperature, 28.4);
      expect(p.humidity, 71.0);
      expect(p.thi, 77.9);
      expect(p.mq137Raw, 980);
      expect(p.fan, isTrue);
      expect(p.pump, isFalse);
      expect(p.ts, 1_790_000_000);
      expect(p.isValid, isTrue);
    });

    test('field lama `a` tidak dibaca', () {
      final p = HistoryPoint.fromEntry(
          '2026-09-30', '14:05', {'t': 28, 'h': 70, 'thi': 77, 'a': 40})!;
      expect(p.mq137Raw, isNull);
    });

    test('bukan map / t-h-thi hilang → null', () {
      expect(HistoryPoint.fromEntry('d', '14:05', 12), isNull);
      expect(HistoryPoint.fromEntry('d', '14:05', {'t': 28, 'h': 70}), isNull);
    });

    test('kunci jam rusak → jam WIB dari ts', () {
      // 1_790_000_000 = 2026-09-21 14:13:20 UTC = 21:13 WIB
      final p = HistoryPoint.fromEntry('2026-09-21', 'xx',
          {'t': 28, 'h': 70, 'thi': 77, 'ts': 1_790_000_000})!;
      expect(p.time, '21:13');
    });

    test('epoch dari tanggal+jam WIB bila ts tidak ada', () {
      final p = HistoryPoint.fromEntry(
          '2026-09-21', '21:13', {'t': 28, 'h': 70, 'thi': 77})!;
      expect(p.epoch, 1_790_000_000 - 20); // detik :20 terpotong
    });

    test('isValid menolak nilai tidak masuk akal', () {
      HistoryPoint make(double t, double h, double thi) =>
          HistoryPoint(date: 'd', time: '00:00', temperature: t, humidity: h, thi: thi);
      expect(make(0, 65, 74).isValid, isFalse);
      expect(make(28, 0, 74).isValid, isFalse);
      expect(make(65, 65, 74).isValid, isFalse);
      expect(make(28, 65, 0).isValid, isFalse);
      expect(make(30, 80, 78).isValid, isTrue);
    });
  });

  test('HistoryStats.fromPoints', () {
    HistoryPoint p(double t, bool fan, int? mq) => HistoryPoint(
        date: 'd', time: '00:00', temperature: t, humidity: 70, thi: 75,
        fan: fan, mq137Raw: mq);
    final stats = HistoryStats.fromPoints(
        [p(26, false, 100), p(28, true, 300), p(30, true, null), p(27, false, 200), p(29, true, null)]);
    expect(stats.avgTemp, 28);
    expect(stats.minTemp, 26);
    expect(stats.maxTemp, 30);
    expect(stats.avgMq137Raw, 200);
    expect(stats.coolingEvents, 2);
    expect(HistoryStats.fromPoints(const []).avgMq137Raw, isNull);
  });

  test('historyToCsv memakai kolom mq137_raw', () {
    final csv = historyToCsv([
      const HistoryPoint(date: '2026-09-30', time: '14:05', temperature: 28.44,
          humidity: 70.6, thi: 77.91, mq137Raw: 980, fan: true, ts: 1),
    ]);
    expect(csv.split('\n')[0],
        'date,time,ts,temperature,humidity,thi,mq137_raw,fan,pump');
    expect(csv.split('\n')[1], '2026-09-30,14:05,1,28.4,71,77.9,980,1,0');
  });

  group('PitikRepository (logika murni riwayat)', () {
    test('parseHistoryDay mengurutkan jam dan membuang data invalid', () {
      final points = PitikRepository.parseHistoryDay('2026-09-30', {
        '14:10': {'t': 28, 'h': 70, 'thi': 77},
        '14:05': {'t': 27, 'h': 70, 'thi': 76},
        '14:15': {'t': 0, 'h': 0, 'thi': 0},
        '14:20': 'rusak',
      });
      expect(points.map((p) => p.time), ['14:05', '14:10']);
      expect(PitikRepository.parseHistoryDay('x', null), isEmpty);
    });

    test('kunci tanggal memakai WIB, bukan zona HP', () {
      // 2026-09-30 18:30 UTC = 2026-10-01 01:30 WIB
      final now = DateTime.utc(2026, 9, 30, 18, 30);
      expect(PitikRepository.historyDateKeys(HistoryPeriod.last24Hours, now),
          ['2026-09-30', '2026-10-01']);
      expect(PitikRepository.historyDateKeys(HistoryPeriod.last7Days, now).first,
          '2026-09-25');
    });

    test('selectPeriod lastHour memfilter berdasarkan epoch', () {
      final now = DateTime.utc(2026, 9, 30, 7, 0); // 14:00 WIB
      HistoryPoint at(String time) => HistoryPoint(
          date: '2026-09-30', time: time, temperature: 28, humidity: 70, thi: 77);
      final selected = PitikRepository.selectPeriod(
          [at('12:55'), at('13:00'), at('13:30'), at('14:00')],
          HistoryPeriod.lastHour,
          now);
      expect(selected.map((p) => p.time), ['13:00', '13:30', '14:00']);
    });
  });
}
