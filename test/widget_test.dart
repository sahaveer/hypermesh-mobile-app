import 'package:flutter_test/flutter_test.dart';
import 'package:hypermesh_player/main.dart';

void main() {
  testWidgets('HypermeshApp builds smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const HypermeshApp());
    expect(find.text('HYPERMESH'), findsOneWidget);
  });
}
