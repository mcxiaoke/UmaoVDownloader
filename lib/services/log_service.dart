import 'dart:io';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

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
class LogService extends ChangeNotifier {
  static const _maxInMemory = 500;

  final List<LogEntry> entries = [];
  IOSink? _fileSink;
  String? _logFilePath;

  String? get logFilePath => _logFilePath;

  /// 初始化文件日志，写到系统临时目录
  Future<void> init() async {
    try {
      final dir = await getTemporaryDirectory();
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
      debugPrint('LogService init failed: $e');
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
    notifyListeners();
  }

  Future<void> close() async {
    await _fileSink?.flush();
    await _fileSink?.close();
  }

  String _p2(int n) => n.toString().padLeft(2, '0');
}
