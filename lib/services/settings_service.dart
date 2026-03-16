import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'parser_common.dart';
import '../constants/app_constants.dart';



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

  String get downloadDir => _downloadDir;
  bool get verboseLog => _verboseLog;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(kSettingKeyDownloadDir);
    if (saved != null && saved.isNotEmpty) {
      _downloadDir = saved;
    } else {
      _downloadDir = await _defaultDirAsync();
    }
    _verboseLog = prefs.getBool(kSettingKeyVerboseLog) ?? false;
    notifyListeners();
  }

  Future<void> setDownloadDir(String path) async {
    _downloadDir = path;
    // 同步更新调试输出目录
    debugOutputDir = path;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kSettingKeyDownloadDir, path);
    notifyListeners();
  }

  Future<void> setVerboseLog(bool enabled) async {
    _verboseLog = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kSettingKeyVerboseLog, enabled);
    notifyListeners();
  }

  /// Android 预设快捷目录（Pictures / Downloads / App私有）
  static Future<List<AndroidQuickDir>> androidQuickDirs() async {
    final appPrivate = await getExternalStorageDirectory();
    return [
      AndroidQuickDir('Pictures', kAndroidDefaultPicturesDir),
      AndroidQuickDir('Downloads', kAndroidDefaultDownloadsDir),
      if (appPrivate != null)
        AndroidQuickDir('AppPrivate', '${appPrivate.path}/umaovd'),
    ];
  }

  static Future<String> _defaultDirAsync() async {
    if (Platform.isAndroid) {
      // 默认存到 Pictures/umaovd
      return kAndroidDefaultPicturesDir;
    }
    if (Platform.isWindows) {
      final home =
          Platform.environment['USERPROFILE'] ??
          Platform.environment['HOME'] ??
          '';
      return home.isEmpty ? Directory.current.path : '$home\\Downloads\\umaovd';
    }
    if (Platform.isMacOS || Platform.isLinux) {
      final home = Platform.environment['HOME'] ?? '';
      return home.isEmpty ? Directory.current.path : '$home/Downloads/umaovd';
    }
    return Directory.current.path;
  }
}
