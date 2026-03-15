import 'package:flutter/material.dart';

import 'services/app_logger.dart';
import 'services/log_service.dart';
import 'services/settings_service.dart';
import 'ui/home_page.dart';

/// 全局日志服务实例
final _log = LogService();

/// 全局设置服务实例
final _settings = SettingsService();

/// 应用程序入口函数
///
/// 初始化Flutter绑定，加载必要的配置和服务，然后启动应用程序
Future<void> main() async {
  // 确保Flutter绑定已初始化
  WidgetsFlutterBinding.ensureInitialized();

  // 并行初始化日志服务和设置服务
  await Future.wait([_log.init(), _settings.load()]);

  // 初始化全局日志系统
  AppLogger.init(logService: _log, verbose: _settings.verboseLog);

  // 启动应用程序，传入日志和设置服务实例
  runApp(DViewerApp(log: _log, settings: _settings));
}

/// 应用程序根组件
///
/// 配置应用程序的主题、标题和主页面
class DViewerApp extends StatelessWidget {
  /// 日志服务实例
  final LogService log;

  /// 设置服务实例
  final SettingsService settings;

  const DViewerApp({super.key, required this.log, required this.settings});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // 应用程序标题
      title: 'Umao VDownloader',

      // 隐藏调试横幅
      debugShowCheckedModeBanner: false,

      // 应用程序主题配置
      theme: ThemeData(
        // 基于种子颜色生成色彩方案
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1976D2)),

        // 使用Material Design 3
        useMaterial3: true,

        // 设置中文字体
        fontFamily: 'Microsoft YaHei UI',

        // 应用栏主题配置
        appBarTheme: const AppBarTheme(
          scrolledUnderElevation: 0,        // 滚动时不显示阴影
          surfaceTintColor: Colors.transparent, // 表面色调透明
        ),
      ),

      // 设置主页面
      home: HomePage(log: log, settings: settings),
    );
  }
}
