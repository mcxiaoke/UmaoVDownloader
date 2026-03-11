import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kDownloadDir = 'download_dir';

/// 持久化设置服务，目前只保存下载目录。
class SettingsService extends ChangeNotifier {
  String _downloadDir = '';

  String get downloadDir => _downloadDir;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kDownloadDir);
    if (saved != null && saved.isNotEmpty) {
      _downloadDir = saved;
    } else {
      _downloadDir = _defaultDir();
    }
    notifyListeners();
  }

  Future<void> setDownloadDir(String path) async {
    _downloadDir = path;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDownloadDir, path);
    notifyListeners();
  }

  static String _defaultDir() {
    if (Platform.isWindows) {
      final home =
          Platform.environment['USERPROFILE'] ??
          Platform.environment['HOME'] ??
          '';
      return home.isEmpty ? Directory.current.path : '$home\\Downloads';
    } else if (Platform.isMacOS || Platform.isLinux) {
      final home = Platform.environment['HOME'] ?? '';
      return home.isEmpty ? Directory.current.path : '$home/Downloads';
    }
    return Directory.current.path;
  }
}
