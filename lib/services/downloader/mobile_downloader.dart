import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../douyin_parser.dart';
import 'video_downloader.dart';

/// Android / iOS 移动端下载器
///
/// Android 会先申请存储权限，再执行流式下载。
class MobileDownloader implements VideoDownloader {
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/120.0.0.0 Mobile Safari/537.36';
  static const _referer = 'https://www.douyin.com/';

  @override
  Future<String> downloadVideo(
    VideoInfo info, {
    String? directory,
    String? filename,
  }) async {
    await _ensureStoragePermission();

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
    // 优先使用外部存储（SD 卡或共享存储）
    final externalDir = await getExternalStorageDirectory();
    if (externalDir != null) {
      // 保存到 .../Download/dviewer/ 子目录
      return '${externalDir.path}${Platform.pathSeparator}Download';
    }
    // Fallback：App 专属文档目录
    return (await getApplicationDocumentsDirectory()).path;
  }

  /// 申请存储权限（Android 10 以下需要；Android 11+ 访问 App 专属目录不需要）
  Future<void> _ensureStoragePermission() async {
    if (!Platform.isAndroid) return;
    final status = await Permission.storage.status;
    if (!status.isGranted) {
      final result = await Permission.storage.request();
      if (!result.isGranted) {
        throw Exception('存储权限被拒绝，无法保存文件');
      }
    }
  }

  String _sanitizeFilename(String name) {
    var result = name
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
        .trim()
        .replaceAll(RegExp(r'_+'), '_');
    if (result.length > 200) result = result.substring(0, 200);
    return result.isEmpty ? 'video' : result;
  }
}
