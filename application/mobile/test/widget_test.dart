import 'package:flutter_test/flutter_test.dart';

import 'package:nimna/main.dart';

void main() {
  testWidgets('scaffold boots and renders the wordmark', (tester) async {
    await tester.pumpWidget(const NimnaApp());
    expect(find.text('nimna'), findsOneWidget);
  });
}
