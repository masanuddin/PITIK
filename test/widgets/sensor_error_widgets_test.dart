import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitik_app/widgets/kpi_card.dart';
import 'package:pitik_app/widgets/thi_gauge.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('THIGauge tanpa nilai → "--" + label, bukan 0.0 NORMAL',
      (tester) async {
    await tester.pumpWidget(_wrap(
      const THIGauge(value: null, unavailableLabel: 'SENSOR ERROR'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('--'), findsOneWidget);
    expect(find.text('SENSOR ERROR'), findsOneWidget);
    expect(find.text('NORMAL'), findsNothing);
  });

  testWidgets('THIGauge dengan nilai menampilkan status', (tester) async {
    await tester.pumpWidget(_wrap(const THIGauge(value: 80)));
    await tester.pumpAndSettle();
    expect(find.text('80.0'), findsOneWidget);
    expect(find.text('DANGER'), findsOneWidget);
  });

  testWidgets('KPICard badgeLabel menggantikan badge status', (tester) async {
    await tester.pumpWidget(_wrap(const SizedBox(
      width: 200,
      height: 80,
      child: KPICard(
        icon: Icons.thermostat_rounded,
        label: 'Suhu',
        value: '--',
        status: 'normal',
        badgeLabel: 'Sensor error',
        badgeColor: Color(0xFFFF3B30),
        color: Color(0xFFFF9500),
      ),
    )));
    expect(find.text('--'), findsOneWidget);
    expect(find.text('Sensor error'), findsOneWidget);
    expect(find.text('NORMAL'), findsNothing);
  });
}
