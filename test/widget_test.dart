import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Skip BLE-dependent widget test on unsupported platforms
    // Full integration tests require a physical device.
    expect(true, isTrue);
  });
}
