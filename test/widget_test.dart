import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:umao_vdownloader/main.dart';
import 'package:umao_vdownloader/providers/providers.dart';
import 'package:umao_vdownloader/services/log_service.dart';
import 'package:umao_vdownloader/services/settings_service.dart';

void main() {
  testWidgets('app renders home page', (WidgetTester tester) async {
    // 创建并初始化服务实例
    final log = LogService();
    await log.init();
    final settings = SettingsService();
    await settings.load();

    // 初始化 Provider 服务单例
    initServiceProviders(logService: log, settingsService: settings);

    // 使用 ProviderScope 包装应用
    await tester.pumpWidget(const ProviderScope(child: DViewerApp()));

    // 验证主页元素存在
    expect(find.text('Umao VDownloader - 短视频下载'), findsOneWidget);
    expect(find.text('解析'), findsOneWidget);
  });
}
