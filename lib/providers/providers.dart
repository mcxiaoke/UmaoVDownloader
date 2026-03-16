import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/log_service.dart';
import '../services/settings_service.dart';

// 导出状态类和 Notifier
export 'download_notifier.dart';
export 'download_state.dart';
export 'video_notifier.dart';
export 'video_state.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 服务 Provider
//
// 提供全局服务的 Provider。
// 服务实例在 main.dart 中作为全局单例初始化，Provider 直接引用这些单例。
//
// 注意：使用 Provider 而非 ChangeNotifierProvider，因为服务实例已经是全局单例。
// SettingsService 本身是 ChangeNotifier，当设置变化时会自动通知监听者。
// ─────────────────────────────────────────────────────────────────────────────

/// 全局日志服务实例
///
/// 由 main.dart 在应用启动时初始化。
/// 必须在 main() 中调用 init() 完成初始化。
LogService? _logService;

/// 全局设置服务实例
///
/// 由 main.dart 在应用启动时初始化。
/// 必须在 main() 中调用 load() 完成初始化。
SettingsService? _settingsService;

/// 初始化服务单例
///
/// 由 main.dart 在应用启动时调用，设置全局服务实例。
/// 必须在使用任何 Provider 之前调用。
void initServiceProviders({
  required LogService logService,
  required SettingsService settingsService,
}) {
  _logService = logService;
  _settingsService = settingsService;
}

/// 日志服务 Provider
///
/// 提供全局日志服务的访问入口。
///
/// 使用方式：
/// ```dart
/// final log = ref.read(logServiceProvider);
/// log.info('message');
/// ```
final logServiceProvider = Provider<LogService>((ref) {
  return _logService!;
});

/// 设置服务 Provider
///
/// 提供全局设置服务的访问入口。
/// SettingsService 继承自 ChangeNotifier，设置变化时会自动通知监听者。
///
/// 使用方式：
/// ```dart
/// // 读取设置
/// final settings = ref.read(settingsServiceProvider);
/// print(settings.downloadDir);
///
/// // 更新设置
/// await ref.read(settingsServiceProvider).setDownloadDir(path);
/// ```
final settingsServiceProvider = Provider<SettingsService>((ref) {
  return _settingsService!;
});

/// 详细日志开关 Provider
///
/// 便捷访问 settings.verboseLog。
/// 注意：由于使用 Provider 而非 ChangeNotifierProvider，此值不会自动响应设置变化。
/// 如需响应变化，请在组件中使用 ref.listen 监听 settingsServiceProvider。
final verboseLogProvider = Provider<bool>((ref) {
  return ref.watch(settingsServiceProvider).verboseLog;
});

/// 下载目录 Provider
///
/// 便捷访问 settings.downloadDir。
/// 注意：由于使用 Provider 而非 ChangeNotifierProvider，此值不会自动响应设置变化。
/// 如需响应变化，请在组件中使用 ref.listen 监听 settingsServiceProvider。
final downloadDirProvider = Provider<String>((ref) {
  return ref.watch(settingsServiceProvider).downloadDir;
});
