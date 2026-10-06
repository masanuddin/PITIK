import 'package:flutter_test/flutter_test.dart';
import 'package:pitik_app/models/controls.dart';

void main() {
  group('Controls.fromMap', () {
    test('null / kosong → default firmware (mode MANUAL, 72/78, 07/12/17)', () {
      for (final c in [Controls.fromMap(null), Controls.fromMap({})]) {
        expect(c.autoMode, isFalse);
        expect(c.fan, isFalse);
        expect(c.pump, isFalse);
        expect(c.feedNow, isFalse);
        expect(c.thiNormal, 72);
        expect(c.thiDanger, 78);
        expect(c.feedTimes, const [
          FeedTime(7, 0),
          FeedTime(12, 0),
          FeedTime(17, 0),
        ]);
      }
    });

    test('membaca semua field', () {
      final c = Controls.fromMap({
        'fan': true,
        'fan_speed': 100,
        'pump': true,
        'feed_now': true,
        'auto_mode': true,
        'thi_normal': 70,
        'thi_danger': 80.5,
        'feed_hour1': 6,
        'feed_min1': 30,
        'feed_hour2': 11,
        'feed_min2': 0,
        'feed_hour3': 18,
        'feed_min3': 45,
      });
      expect(c.fan, isTrue);
      expect(c.fanSpeed, 100);
      expect(c.pump, isTrue);
      expect(c.feedNow, isTrue);
      expect(c.autoMode, isTrue);
      expect(c.thiNormal, 70.0);
      expect(c.thiDanger, 80.5);
      expect(c.feedTimes.map((t) => t.label),
          ['06:30', '11:00', '18:45']);
    });

    test('ambang tidak valid → default (firmware mengabaikannya)', () {
      final c = Controls.fromMap({'thi_normal': 85, 'thi_danger': 80});
      expect(c.thiNormal, 72);
      expect(c.thiDanger, 78);
    });

    test('jam pakan di luar rentang → default slot tsb', () {
      final c = Controls.fromMap({'feed_hour2': 25, 'feed_min2': 0});
      expect(c.feedTimes[1], const FeedTime(12, 0));
    });
  });

  group('Controls.validateThresholds', () {
    test('valid', () {
      expect(Controls.validateThresholds(72, 78), isNull);
      expect(Controls.validateThresholds(50, 100), isNull);
    });

    test('di luar 50–100', () {
      expect(Controls.validateThresholds(49, 78), isNotNull);
      expect(Controls.validateThresholds(72, 101), isNotNull);
    });

    test('normal harus < danger', () {
      expect(Controls.validateThresholds(78, 78), isNotNull);
      expect(Controls.validateThresholds(80, 75), isNotNull);
    });
  });

  test('formatThi', () {
    expect(Controls.formatThi(72), '72');
    expect(Controls.formatThi(72.5), '72.5');
  });

  test('levelFor mengikuti ambang dari /controls', () {
    const c = Controls(thiNormal: 70, thiDanger: 76);
    expect(c.levelFor(69.9), ThiLevel.normal);
    expect(c.levelFor(70), ThiLevel.warning);
    expect(c.levelFor(76), ThiLevel.danger);
  });

  test('payload memakai nama field kontrak', () {
    expect(Controls.thresholdsPayload(71, 79),
        {'thi_normal': 71.0, 'thi_danger': 79.0});
    expect(
      Controls.feedSchedulePayload(Controls.defaultFeedTimes),
      {
        'feed_hour1': 7, 'feed_min1': 0,
        'feed_hour2': 12, 'feed_min2': 0,
        'feed_hour3': 17, 'feed_min3': 0,
      },
    );
  });
}
