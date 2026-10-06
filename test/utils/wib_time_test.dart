import 'package:flutter_test/flutter_test.dart';
import 'package:pitik_app/utils/wib_time.dart';

void main() {
  test('fromEpoch → jam dinding WIB (UTC+7)', () {
    // 1_790_000_000 = 2026-09-21 14:13:20 UTC
    final wib = WibTime.fromEpoch(1_790_000_000);
    expect(WibTime.dateKey(wib), '2026-09-21');
    expect(WibTime.hhmmss(wib), '21:13:20');
  });

  test('pergantian hari mengikuti WIB', () {
    final wib = WibTime.fromUtc(DateTime.utc(2026, 9, 30, 17, 0));
    expect(WibTime.dateKey(wib), '2026-10-01');
    expect(WibTime.hhmm(wib), '00:00');
  });

  test('toEpoch kebalikan fromEpoch', () {
    expect(WibTime.toEpoch(WibTime.fromEpoch(1_790_000_000)), 1_790_000_000);
  });

  test('clock menangani -1 (belum NTP)', () {
    expect(WibTime.clock(7, 5), '07:05');
    expect(WibTime.clock(-1, -1), '--:--');
    expect(WibTime.clock(24, 0), '--:--');
  });

  test('describeEpoch: jam saja bila hari sama (WIB), tanggal bila beda', () {
    const ts = 1_790_000_000; // 2026-09-21 21:13:20 WIB
    expect(WibTime.describeEpoch(ts, ts + 60), '21:13:20 WIB');
    // +3 jam → 22 Sep 00:13 WIB, sudah hari berikutnya
    expect(WibTime.describeEpoch(ts, ts + 3 * 3600), '21 Sep 21:13 WIB');
  });

  test('dayMonthTime: selalu tanggal + jam tanpa detik; 0/null → null', () {
    expect(WibTime.dayMonthTime(1_790_000_000), '21 Sep 21:13 WIB');
    // Melewati tengah malam UTC tetap tanggal WIB.
    final t = WibTime.toEpoch(DateTime.utc(2026, 10, 4, 16, 20));
    expect(WibTime.dayMonthTime(t), '4 Okt 16:20 WIB');
    expect(WibTime.dayMonthTime(0), isNull);
    expect(WibTime.dayMonthTime(null), isNull);
  });

  test('shortDate dari kunci tanggal riwayat', () {
    expect(WibTime.shortDate('2026-10-04'), '4 Okt');
    expect(WibTime.shortDate('2026-09-21'), '21 Sep');
    expect(WibTime.shortDate('rusak'), 'rusak');
  });

  test('ago', () {
    expect(WibTime.ago(0), 'baru saja');
    expect(WibTime.ago(-3), 'baru saja');
    expect(WibTime.ago(12), '12 detik lalu');
    expect(WibTime.ago(125), '2 menit lalu');
    expect(WibTime.ago(7200), '2 jam lalu');
    expect(WibTime.ago(3 * 86400), '3 hari lalu');
  });

  test('durationText', () {
    expect(WibTime.durationText(45), '45 detik');
    expect(WibTime.durationText(12 * 60), '12 menit');
    expect(WibTime.durationText(3 * 3600 + 5 * 60), '3 jam 5 menit');
    expect(WibTime.durationText(2 * 86400 + 4 * 3600 + 59), '2 hari 4 jam');
    expect(WibTime.durationText(86400), '1 hari');
  });

  test('epochToHhmm menangani 0 / null', () {
    expect(WibTime.epochToHhmm(0), '--:--');
    expect(WibTime.epochToHhmm(null), '--:--');
  });
}
