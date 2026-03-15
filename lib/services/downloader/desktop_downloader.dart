import 'dart:io';

import 'base_downloader.dart';

/// Windows / macOS / Linux 桌面端下载器
class DesktopDownloader extends BaseDownloader {
  @override
  List<String> get downloadUserAgents => const [
    kUaIphoneSafari,
    // kUaEdge,
    // kUaIosWechat,
  ];

  @override
  Future<String> getDefaultDirectory() async {
    if (Platform.isWindows) {
      final home =
          Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
      if (home != null) return 'F:\\Downloads\\TikTok';
    } else if (Platform.isMacOS || Platform.isLinux) {
      final home = Platform.environment['HOME'];
      if (home != null) return '$home/Downloads';
    }
    return Directory.current.path;
  }
}
