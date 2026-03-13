import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kDownloadDir = 'download_dir';
const _kVerboseLog = 'verbose_log';
const _kParserStrategy = 'parser_strategy';
const _kCompareParsers = 'compare_parsers';

enum ParserStrategy {
  auto,
  dartOnly,
  jsOnly;

  String get value => switch (this) {
    ParserStrategy.auto => 'auto',
    ParserStrategy.dartOnly => 'dart_only',
    ParserStrategy.jsOnly => 'js_only',
  };

  static ParserStrategy fromValue(String? value) {
    return switch (value) {
      'dart_only' => ParserStrategy.dartOnly,
      'js_only' => ParserStrategy.jsOnly,
      // 向后兼容旧值，统一落到自动模式。
      'webview_then_dart' => ParserStrategy.auto,
      'dart_then_webview' => ParserStrategy.auto,
      _ => ParserStrategy.auto,
    };
  }
}

/// Android 上可供用户快速切换的预设目录
class AndroidQuickDir {
  final String label;
  final String path;
  const AndroidQuickDir(this.label, this.path);
}

/// 持久化设置服务，目前只保存下载目录。
class SettingsService extends ChangeNotifier {
  String _downloadDir = '';
  bool _verboseLog = false;
  bool _compareParsers = true;
  ParserStrategy _parserStrategy = ParserStrategy.auto;

  String get downloadDir => _downloadDir;
  bool get verboseLog => _verboseLog;
  bool get compareParsers => _compareParsers;
  ParserStrategy get parserStrategy => _parserStrategy;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kDownloadDir);
    if (saved != null && saved.isNotEmpty) {
      _downloadDir = saved;
    } else {
      _downloadDir = await _defaultDirAsync();
    }
    _verboseLog = prefs.getBool(_kVerboseLog) ?? false;
    _compareParsers = prefs.getBool(_kCompareParsers) ?? true;
    _parserStrategy = ParserStrategy.fromValue(
      prefs.getString(_kParserStrategy),
    );
    notifyListeners();
  }

  Future<void> setDownloadDir(String path) async {
    _downloadDir = path;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDownloadDir, path);
    notifyListeners();
  }

  Future<void> setVerboseLog(bool enabled) async {
    _verboseLog = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kVerboseLog, enabled);
    notifyListeners();
  }

  Future<void> setCompareParsers(bool enabled) async {
    _compareParsers = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kCompareParsers, enabled);
    notifyListeners();
  }

  Future<void> setParserStrategy(ParserStrategy strategy) async {
    _parserStrategy = strategy;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kParserStrategy, strategy.value);
    notifyListeners();
  }

  /// Android 预设快捷目录（Movies / Downloads / App私有）
  static Future<List<AndroidQuickDir>> androidQuickDirs() async {
    const base = '/storage/emulated/0';
    final appPrivate = await getExternalStorageDirectory();
    return [
      AndroidQuickDir('Movies', '$base/Movies/umaov'),
      AndroidQuickDir('Downloads', '$base/Download/umaov'),
      if (appPrivate != null)
        AndroidQuickDir('App私有', '${appPrivate.path}/umaov'),
    ];
  }

  static Future<String> _defaultDirAsync() async {
    if (Platform.isAndroid) {
      // 默认存到 Movies/umaov
      return '/storage/emulated/0/Movies/umaov';
    }
    if (Platform.isWindows) {
      final home =
          Platform.environment['USERPROFILE'] ??
          Platform.environment['HOME'] ??
          '';
      return home.isEmpty ? Directory.current.path : '$home\\Downloads';
    }
    if (Platform.isMacOS || Platform.isLinux) {
      final home = Platform.environment['HOME'] ?? '';
      return home.isEmpty ? Directory.current.path : '$home/Downloads';
    }
    return Directory.current.path;
  }
}
