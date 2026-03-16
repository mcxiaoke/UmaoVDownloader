import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/providers.dart';
import 'services/app_logger.dart';
import 'services/log_service.dart';
import 'services/parser_common.dart';
import 'services/settings_service.dart';
import 'ui/home_page.dart';

/// 全局日志服务实例
///
/// 在 main() 中初始化，通过 Provider 注入到组件树。
/// 使用全局实例可以确保日志服务在整个应用生命周期内只初始化一次。
final _log = LogService();

/// 全局设置服务实例
///
/// 继承自 ChangeNotifier，支持响应式更新。
/// 在 main() 中初始化，通过 Provider 注入到组件树。
final _settings = SettingsService();

/// 应用程序入口函数
///
/// 初始化 Flutter 绑定，加载必要的配置和服务，然后启动应用程序。
///
/// 初始化流程：
/// 1. 确保 Flutter 绑定已初始化
/// 2. 并行初始化日志服务和设置服务
/// 3. 初始化全局日志系统
/// 4. 初始化 Provider 服务单例
/// 5. 启动 Riverpod ProviderScope 包装的应用
void main() async {
  // 确保 Flutter 绑定已初始化
  WidgetsFlutterBinding.ensureInitialized();

  // 并行初始化日志服务和设置服务
  await Future.wait([_log.init(), _settings.load()]);

  // 设置调试 JSON 输出目录（使用用户配置的下载目录）
  debugOutputDir = _settings.downloadDir;

  // 初始化全局日志系统
  AppLogger.init(logService: _log, verbose: _settings.verboseLog);

  // 初始化 Provider 服务单例
  // 必须在 ProviderScope 创建之前调用
  initServiceProviders(logService: _log, settingsService: _settings);

  // 启动应用程序
  runApp(const ProviderScope(child: DViewerApp()));
}

/// 应用程序根组件
///
/// 配置应用程序的主题、标题和主页面。
/// 使用 ConsumerWidget 以支持 Riverpod 的响应式更新。
class DViewerApp extends ConsumerWidget {
  const DViewerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 监听设置服务的变化，当设置变化时触发 UI 重建
    // SettingsService 是 ChangeNotifier，但通过 Provider 访问时
    // 需要手动监听变化。这里使用 addListener 来实现响应式更新。
    // 注意：由于 settingsServiceProvider 是 Provider 而非 ChangeNotifierProvider，
    // 我们需要手动处理监听。这里通过在 build 中读取设置来确保 UI 响应。
    // 实际的响应式更新通过 SettingsService 自身的 notifyListeners 机制，
    // 配合 setState 或其他状态管理方式实现。

    return MaterialApp(
      // 应用程序标题
      title: 'Umao VDownloader',

      // 隐藏调试横幅
      debugShowCheckedModeBanner: false,

      // 应用程序主题配置
      theme: ThemeData(
        // 基于种子颜色生成色彩方案
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1976D2)),

        // 使用 Material Design 3
        useMaterial3: true,

        // 设置中文字体
        fontFamily: 'Microsoft YaHei UI',

        // 应用栏主题配置
        appBarTheme: const AppBarTheme(
          scrolledUnderElevation: 0, // 滚动时不显示阴影
          surfaceTintColor: Colors.transparent, // 表面色调透明
        ),
      ),

      // 设置主页面
      home: const HomePage(),
    );
  }
}
