import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:umao_vdownloader/main.dart';
import 'package:umao_vdownloader/providers/providers.dart';
import 'package:umao_vdownloader/services/log_service.dart';
import 'package:umao_vdownloader/services/settings_service.dart';
import 'package:umao_vdownloader/constants/app_constants.dart';

// Mock 日志服务，避免文件系统操作
class MockLogService extends LogService {
  @override
  Future<void> init() async {
    // 不执行任何操作，避免文件系统访问
  }

  @override
  Future<void> close() async {
    // 不执行任何操作
  }
}

void main() {
  // 设置 SharedPreferences 的 mock 初始值，避免平台通道调用
  setUpAll(() {
    SharedPreferences.setMockInitialValues({
      kSettingKeyDownloadDir: '/mock/download/dir',
      kSettingKeyVerboseLog: false,
    });
  });

  testWidgets('app renders home page', (WidgetTester tester) async {
    // 创建并初始化 Mock 服务实例
    final log = MockLogService();
    await log.init();
    final settings = SettingsService();
    await settings.load(); // 现在会使用 mock 的 SharedPreferences，不会卡住

    // 初始化 Provider 服务单例
    initServiceProviders(logService: log, settingsService: settings);

    // 使用 ProviderScope 包装应用
    await tester.pumpWidget(const ProviderScope(child: DViewerApp()));

    expect(find.text('解析'), findsOneWidget);
  });
}
