import 'package:flutter_test/flutter_test.dart';

import 'package:pitik_app/main.dart';
import 'package:pitik_app/models/history_point.dart';

void main() {
  test('App classes can be imported and instantiated', () {
    // Verify main app class compiles (does not require Firebase runtime)
    expect(PitikApp.new, isNotNull);
    expect(AuthWrapper.new, isNotNull);
    expect(MainNavigation.new, isNotNull);
  });

  test('HistoryPoint is instantiable', () {
    const data = HistoryPoint(
      date: '2026-09-30',
      time: '14:30',
      temperature: 28.0,
      humidity: 65.0,
      thi: 74.0,
      mq137Raw: 1200,
    );
    expect(data.isValid, isTrue);
  });
}
