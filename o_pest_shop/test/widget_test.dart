import 'package:flutter_test/flutter_test.dart';

import 'package:o_pest_shop/app.dart';

void main() {
  testWidgets('App renders', (WidgetTester tester) async {
    await tester.pumpWidget(const App());
    expect(find.byType(App), findsOneWidget);
  });
}
