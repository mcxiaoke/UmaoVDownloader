import 'dart:io';

import 'package:http/http.dart' as http;

import '../douyin_parser.dart';
import 'video_downloader.dart';

/// Windows / macOS / Linux 桌面端下载器
///
/// 使用流式下载避免大文件占用过多内存。
class DesktopDownloader implements VideoDownloader {
  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/145.0.0.0 Safari/537.36 Edg/145.0.0.0';

  @override
  Future<String> downloadVideo(
    VideoInfo info, {
    VideoQuality? quality,
    String? directory,
    String? filename,
  }) async {
    final dir = directory ?? await getDefaultDirectory();
    final resolvedQuality = quality ?? VideoQuality.p1080;
    final qualityLabel = resolvedQuality.ratio;
    // 文件名：优先用短链 shareId（可助找回原始视频页），其次 videoId
    final prefix = info.shareId ?? info.videoId;
    final titlePart = info.title.length > 30
        ? info.title.substring(0, 30)
        : info.title;
    final now = DateTime.now();
    final stamp =
        '${now.year}${_p2(now.month)}${_p2(now.day)}'
        '_${_p2(now.hour)}${_p2(now.minute)}${_p2(now.second)}';
    final name = _sanitizeFilename(filename ?? '${prefix}_$titlePart');
    final filePath =
        '$dir${Platform.pathSeparator}${name}_${qualityLabel}_$stamp.mp4';

    final file = File(filePath);
    await file.parent.create(recursive: true);

    final downloadUrl = info.urlFor(resolvedQuality);
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(downloadUrl));
      request.headers.addAll({
        HttpHeaders.userAgentHeader: _userAgent,
        // 不发送 Referer：douyinvod CDN 对来自 douyin.com 的 Referer 做防盗链拦截
        // 无 Referer 时可正常通过，see tool/debug_download.py (403 vs 200 对比)
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
    // 用环境变量定位系统下载目录，不依赖 Flutter 专属的 path_provider
    if (Platform.isWindows) {
      final home =
          Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
      if (home != null) return 'F:\\Downloads\\test';
    } else if (Platform.isMacOS || Platform.isLinux) {
      final home = Platform.environment['HOME'];
      if (home != null) return '$home/Downloads';
    }
    return Directory.current.path;
  }

  /// 过滤文件系统不允许的字符（含 # @ 等），防止路径注入
  String _sanitizeFilename(String name) {
    var result = name
        .replaceAll(RegExp(r'[<>:"/\\|?*#@\x00-\x1f]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (result.length > 120) result = result.substring(0, 120).trim();
    return result.isEmpty ? 'video' : result;
  }

  String _p2(int n) => n.toString().padLeft(2, '0');
}
