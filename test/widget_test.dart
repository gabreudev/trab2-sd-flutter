import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:camera_test_app/main.dart';

void main() {
  testWidgets('CameraTestApp smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const CameraTestApp());

    // Verify that title and buttons are rendered.
    expect(find.text('Detecção de Objetos (Sockets)'), findsWidgets);
    expect(find.text('Tirar e Analisar'), findsOneWidget);
    expect(find.byIcon(Icons.settings), findsOneWidget);
  });
}
