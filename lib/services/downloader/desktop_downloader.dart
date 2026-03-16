import 'dart:io';

import 'base_downloader.dart';
import '../../constants/app_constants.dart';

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
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (home != null) return '$home/Downloads';
    return Directory.current.path;
  }
}
