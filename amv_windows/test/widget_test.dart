import 'package:flutter_test/flutter_test.dart';

import 'package:amv_windows/main.dart';

void main() {
  testWidgets('应用可以正常构建出主界面', (WidgetTester tester) async {
    await tester.pumpWidget(const AmvApp());
    expect(find.text('视频转 AMV · Windows'), findsOneWidget);
  });
}
