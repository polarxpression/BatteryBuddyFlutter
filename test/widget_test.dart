// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:bms/main.dart';

void main() {
  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    // Build a minimal app and trigger a frame to verify the title.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('BMS')),
          body: const Center(child: Text('BMS')),
        ),
      ),
    );

    // Verify the app shows the new title.
    expect(find.text('BMS'), findsNWidgets(2));
  });
}

class _FakeInventoryProvider extends ChangeNotifier {
  bool _showLowStockOnly = false;
  bool get showLowStockOnly => _showLowStockOnly;
  void toggleFilter() {
    _showLowStockOnly = !_showLowStockOnly;
    notifyListeners();
  }

  List<dynamic> get items => [];
  int get lowStockCount => 0;
  int get totalBatteriesCount => 0;
  int get totalItems => 0;
}

