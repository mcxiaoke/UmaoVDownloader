import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../douyin_parser.dart';
import 'video_downloader.dart';

/// Windows / macOS / Linux 桌面端下载器
///
/// 使用流式下载避免大文件占用过多内存。
class DesktopDownloader implements VideoDownloader {
  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
  static const _referer = 'https://www.douyin.com/';

  @override
  Future<String> downloadVideo(
    VideoInfo info, {
    String? directory,
    String? filename,
  }) async {
    final dir = directory ?? await getDefaultDirectory();
    final name = _sanitizeFilename(filename ?? info.title);
    final filePath = '$dir${Platform.pathSeparator}$name.mp4';

    final file = File(filePath);
    await file.parent.create(recursive: true);

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(info.videoUrl));
      request.headers.addAll({
        HttpHeaders.userAgentHeader: _userAgent,
        'Referer': _referer,
      });

      final streamed = await client.send(request);
      if (streamed.statusCode != 200) {
        throw Exception('下载请求失败，状态码: ${streamed.statusCode}');
      }

      await streamed.stream.pipe(file.openWrite());
      return filePath;
    } finally {
      client.close();
    }
  }

  @override
  Future<String> getDefaultDirectory() async {
    try {
      final dir = await getDownloadsDirectory();
      if (dir != null) return dir.path;
    } catch (_) {
      // path_provider 不可用时（如纯 Dart CLI）退回到当前目录
    }
    return Directory.current.path;
  }

  /// 过滤文件系统不允许的字符，防止路径注入
  String _sanitizeFilename(String name) {
    var result = name
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
        .trim()
        .replaceAll(RegExp(r'_+'), '_');
    if (result.length > 200) result = result.substring(0, 200);
    return result.isEmpty ? 'video' : result;
  }
}
