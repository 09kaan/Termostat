import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termostat_app/models/heating_feedback.dart';
import 'package:termostat_app/widgets/heating_status.dart';

void main() {
  testWidgets('No device report must not invent a heating confirmation',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: HeatingStatus(feedback: HeatingFeedback()))));
    expect(find.text('Doğrulanamıyor'), findsOneWidget);
    expect(find.text('Röle açık'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('heating-status')));
    await tester.pumpAndSettle();
    expect(find.text('ESP32 · Doğrulanamıyor'), findsOneWidget);
    expect(find.text('ESP8266 · Doğrulanamıyor'), findsOneWidget);
  });
}
