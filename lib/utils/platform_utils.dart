import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

/// 平台相关工具方法
class PlatformUtils {
  PlatformUtils._();

  /// 打开目录（仅支持桌面平台）
  static void openDirectory(String path) {
    if (Platform.isWindows) {
      Process.run('explorer', [path]);
    } else if (Platform.isMacOS) {
      Process.run('open', [path]);
    }
  }

  /// 打开 URL
  /// 桌面平台使用系统命令，移动端使用 url_launcher
  static Future<void> openUrl(String url) async {
    if (Platform.isWindows) {
      Process.run('start', [url], runInShell: true);
    } else if (Platform.isMacOS) {
      Process.run('open', [url]);
    } else if (Platform.isLinux) {
      Process.run('xdg-open', [url]);
    } else {
      // 移动端使用 url_launcher
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }
}
