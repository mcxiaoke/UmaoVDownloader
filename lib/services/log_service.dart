import 'dart:io';
import 'dart:developer' as developer;

/// 无参回调类型（兼容 Flutter VoidCallback）
typedef VoidCallback = void Function();

/// 可监听接口（兼容 Flutter Listenable）
abstract class Listenable {
  void addListener(VoidCallback listener);
  void removeListener(VoidCallback listener);
}

/// 日志条目
class LogEntry {
  final DateTime time;
  final LogLevel level;
  final String message;

  LogEntry(this.level, this.message) : time = DateTime.now();

  String get timeStr {
    final t = time;
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}';
  }

  @override
  String toString() => '[$timeStr][${level.name.toUpperCase()}] $message';
}

enum LogLevel { info, warn, error }

/// 全局日志服务：维护内存列表，同时追加写入日志文件。
/// 实现 Listenable 接口以支持 Flutter UI 绑定。
class LogService implements Listenable {
  static const _maxInMemory = 500;

  final List<LogEntry> entries = [];
  final List<VoidCallback> _listeners = [];
  IOSink? _fileSink;
  String? _logFilePath;

  String? get logFilePath => _logFilePath;

  /// 初始化文件日志，写到系统临时目录
  Future<void> init() async {
    try {
      final dir = Directory.systemTemp;
      final logDir = Directory(
        '${dir.path}${Platform.pathSeparator}umao_vdownloader_logs',
      );
      await logDir.create(recursive: true);

      final now = DateTime.now();
      final stamp =
          '${now.year}${_p2(now.month)}${_p2(now.day)}_${_p2(now.hour)}${_p2(now.minute)}${_p2(now.second)}';
      _logFilePath =
          '${logDir.path}${Platform.pathSeparator}umao_vdownloader_$stamp.log';
      _fileSink = File(_logFilePath!).openWrite(mode: FileMode.append);
      _append(LogLevel.info, 'LogService 初始化，日志文件: $_logFilePath');
    } catch (e) {
      // 文件日志初始化失败不影响主流程
      print('LogService init failed: $e');
    }
  }

  void info(String msg) => _append(LogLevel.info, msg);
  void warn(String msg) => _append(LogLevel.warn, msg);
  void error(String msg) => _append(LogLevel.error, msg);

  void _append(LogLevel level, String msg) {
    final entry = LogEntry(level, msg);
    if (entries.length >= _maxInMemory) entries.removeAt(0);
    entries.add(entry);
    _fileSink?.writeln(entry.toString());
    // 同步到系统日志，方便通过 adb logcat 直接查看。
    developer.log(
      entry.toString(),
      name: 'dviewer',
      level: switch (level) {
        LogLevel.info => 800,
        LogLevel.warn => 900,
        LogLevel.error => 1000,
      },
    );
    // Debug 模式下也打印到控制台
    if (_isDebugMode) {
      // ignore: avoid_print
      print(entry.toString());
    }
    _notifyListeners();
  }

  /// 检测是否为调试模式
  static bool get _isDebugMode {
    bool isDebug = false;
    assert(() {
      isDebug = true;
      return true;
    }());
    return isDebug || !bool.fromEnvironment('dart.vm.product');
  }

  // Listenable 接口实现
  @override
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  void _notifyListeners() {
    for (final listener in _listeners) {
      listener();
    }
  }

  Future<void> close() async {
    await _fileSink?.flush();
    await _fileSink?.close();
  }

  String _p2(int n) => n.toString().padLeft(2, '0');
}
