/// 全局应用日志系统 - 单例模式
/// 
/// 使用方式：
/// ```dart
/// import 'app_logger.dart';
/// 
/// AppLogger.info('普通信息');      // 始终打印
/// AppLogger.warn('警告信息');      // 始终打印
/// AppLogger.error('错误信息');     // 始终打印
/// AppLogger.debug('详细信息');     // 只在 verbose 模式下打印
/// ```
library;

import 'dart:developer' as developer;

import 'log_service.dart';

/// 日志级别
enum AppLogLevel {
  debug, // 详细日志，只在 verbose 模式输出
  info,  // 普通信息
  warn,  // 警告
  error, // 错误
}

/// 全局日志单例
/// 
/// 自动适配：
/// - 如果有 LogService，则写入内存列表和文件
/// - 否则输出到系统日志
class AppLogger {
  static LogService? _logService;
  static bool _verbose = false;
  static bool _initialized = false;

  /// 初始化日志系统
  /// 
  /// [logService] 可选的日志服务实例（用于 UI 显示和文件写入）
  /// [verbose] 是否启用详细日志模式
  static void init({LogService? logService, bool verbose = false}) {
    _logService = logService;
    _verbose = verbose;
    _initialized = true;
  }

  /// 更新 verbose 模式
  static void setVerbose(bool verbose) {
    _verbose = verbose;
  }

  /// 更新 LogService 实例
  static void setLogService(LogService? logService) {
    _logService = logService;
  }

  /// 检查是否已初始化
  static bool get isInitialized => _initialized;

  /// 检查是否处于详细模式
  static bool get isVerbose => _verbose;

  // ==================== 便捷方法 ====================

  /// 记录详细日志（只在 verbose 模式下输出）
  static void debug(String message) {
    _log(AppLogLevel.debug, message);
  }

  /// 记录普通信息（始终输出）
  static void info(String message) {
    _log(AppLogLevel.info, message);
  }

  /// 记录警告（始终输出）
  static void warn(String message) {
    _log(AppLogLevel.warn, message);
  }

  /// 记录错误（始终输出）
  static void error(String message) {
    _log(AppLogLevel.error, message);
  }

  // ==================== 核心实现 ====================

  static void _log(AppLogLevel level, String message) {
    // debug 级别在 verbose 模式或 debug build 时输出
    if (level == AppLogLevel.debug && !_verbose && !_isDebugMode) {
      return;
    }

    final prefix = _getPrefix(level);
    final formatted = '[$prefix] $message';

    // 1. 输出到系统日志（方便 adb logcat 查看）
    developer.log(
      formatted,
      name: 'dviewer',
      level: _toDeveloperLevel(level),
    );

    // 2. 如果有 LogService，写入内存和文件
    if (_logService != null) {
      _writeToLogService(level, message);
    }

    // 3. Debug 模式下也打印到控制台（非生产环境）
    if (_isDebugMode) {
      // ignore: avoid_print
      print(formatted);
    }
  }

  /// 检测是否为调试模式（使用 assert 技巧）
  static bool get _isDebugMode {
    bool isDebug = false;
    assert(() {
      isDebug = true;
      return true;
    }());
    return isDebug || !bool.fromEnvironment('dart.vm.product');
  }

  static String _getPrefix(AppLogLevel level) {
    return switch (level) {
      AppLogLevel.debug => 'DEBUG',
      AppLogLevel.info => 'INFO',
      AppLogLevel.warn => 'WARN',
      AppLogLevel.error => 'ERROR',
    };
  }

  static int _toDeveloperLevel(AppLogLevel level) {
    return switch (level) {
      AppLogLevel.debug => 500,
      AppLogLevel.info => 800,
      AppLogLevel.warn => 900,
      AppLogLevel.error => 1000,
    };
  }

  static void _writeToLogService(AppLogLevel level, String message) {
    try {
      switch (level) {
        case AppLogLevel.debug:
        case AppLogLevel.info:
          _logService!.info(message);
        case AppLogLevel.warn:
          _logService!.warn(message);
        case AppLogLevel.error:
          _logService!.error(message);
      }
    } catch (e) {
      // LogService 写入失败不影响主流程
      developer.log('写入 LogService 失败: $e', name: 'dviewer', level: 1000);
    }
  }
}

// ==================== 扩展方法（便于替换现有代码） ====================

/// 为 String 添加日志扩展
extension StringLogExtension on String {
  /// 作为 debug 日志输出
  void get logDebug => AppLogger.debug(this);

  /// 作为 info 日志输出
  void get logInfo => AppLogger.info(this);

  /// 作为 warn 日志输出
  void get logWarn => AppLogger.warn(this);

  /// 作为 error 日志输出
  void get logError => AppLogger.error(this);
}
