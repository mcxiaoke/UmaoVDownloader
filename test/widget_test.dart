import 'package:flutter_test/flutter_test.dart';

import 'package:umao_vdownloader/main.dart';
import 'package:umao_vdownloader/services/log_service.dart';
import 'package:umao_vdownloader/services/settings_service.dart';

void main() {
  testWidgets('app renders home page', (WidgetTester tester) async {
    await tester.pumpWidget(
      DViewerApp(log: LogService(), settings: SettingsService()),
    );

    expect(find.text('Umao VDownloader - 短视频下载'), findsOneWidget);
    expect(find.text('解析'), findsOneWidget);
  });
}
