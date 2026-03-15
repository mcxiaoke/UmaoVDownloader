/// 媒体 URL 可用性验证工具
///
/// 用法：
///   dart run tool/run_tests.dart                    # 验证所有缓存数据的媒体 URL
///   dart run tool/run_tests.dart --verbose          # 详细输出
///   dart run tool/run_tests.dart --cache backend/tests/cache  # 指定缓存目录
///
/// 功能：
///   • 从缓存 JSON 读取解析结果
///   • 对媒体 URL 发送 HEAD 请求检测可用性
///   • 检测 401、403、404 等不可用状态
///   • 报告哪些 URL 已失效
library;

import 'dart:io' as io;
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

// ── 配置 ──────────────────────────────────────────────────────────────────────
const _defaultCacheDir = 'backend/tests/cache';
const _timeout = Duration(seconds: 10);
// 与 lib/services/downloader/base_downloader.dart 保持一致
const _userAgent =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) '
    'Version/16.6 Mobile/15E148 Safari/604.1';

// ── URL 检测结果 ──────────────────────────────────────────────────────────────
class UrlCheckResult {
  final String url;
  final int? statusCode;
  final String? error;
  bool get isOk => statusCode != null && statusCode! < 400;
  bool get isForbidden => statusCode == 403 || statusCode == 401;
  bool get isNotFound => statusCode == 404;
  bool get isMethodNotAllowed => statusCode == 405; // HEAD 不支持，URL 可能仍可用

  UrlCheckResult({required this.url, this.statusCode, this.error});

  String get statusLabel {
    if (error != null) return 'ERROR: $error';
    if (isForbidden) return 'FORBIDDEN ($statusCode)';
    if (isNotFound) return 'NOT_FOUND ($statusCode)';
    if (isMethodNotAllowed) return 'UNKNOWN (405)';
    if (isOk) return 'OK ($statusCode)';
    return 'STATUS $statusCode';
  }
}

// ── 缓存文件解析 ──────────────────────────────────────────────────────────────
class MediaUrls {
  final String platform;
  final String id;
  final String? videoUrl;
  final List<String> imageUrls;
  final List<String> livePhotoUrls;
  final String? coverUrl;
  final String? musicUrl;

  MediaUrls({
    required this.platform,
    required this.id,
    this.videoUrl,
    this.imageUrls = const [],
    this.livePhotoUrls = const [],
    this.coverUrl,
    this.musicUrl,
  });

  List<(String type, String url)> get allUrls {
    final urls = <(String, String)>[];
    if (videoUrl != null && videoUrl!.isNotEmpty) {
      urls.add(('video', videoUrl!));
    }
    for (var i = 0; i < imageUrls.length; i++) {
      urls.add(('image[$i]', imageUrls[i]));
    }
    for (var i = 0; i < livePhotoUrls.length; i++) {
      urls.add(('livephoto[$i]', livePhotoUrls[i]));
    }
    if (coverUrl != null && coverUrl!.isNotEmpty) {
      urls.add(('cover', coverUrl!));
    }
    if (musicUrl != null && musicUrl!.isNotEmpty) {
      urls.add(('music', musicUrl!));
    }
    return urls;
  }
}

MediaUrls? parseCacheFile(String filePath) {
  final file = io.File(filePath);
  if (!file.existsSync()) return null;

  final fileName = path.basenameWithoutExtension(filePath);
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

  if (fileName.startsWith('dy_')) {
    return _parseDouyinCache(fileName, json);
  } else if (fileName.startsWith('xhs_')) {
    return _parseXiaohongshuCache(fileName, json);
  }
  return null;
}

MediaUrls _parseDouyinCache(String id, Map<String, dynamic> json) {
  String? videoUrl;
  final imageUrls = <String>[];

  // 判断类型：aweme_type 2 是图文，4 是视频
  final awemeType = json['aweme_type'];
  final isImagePost = awemeType == 2;

  if (!isImagePost) {
    // 视频
    final playAddr = json['video']?['play_addr'];
    if (playAddr is Map) {
      final urlList = playAddr['url_list'] as List?;
      if (urlList != null && urlList.isNotEmpty) {
        videoUrl = urlList.first.toString();
      }
    }
  }

  // 图片
  final images = json['images'] as List?;
  if (images != null) {
    for (final img in images) {
      if (img is! Map) continue;
      final urlList = img['url_list'] as List?;
      if (urlList != null && urlList.isNotEmpty) {
        imageUrls.add(urlList.first.toString());
      }
    }
  }

  // 封面
  String? coverUrl;
  final cover = json['video']?['cover'];
  if (cover is Map) {
    final urlList = cover['url_list'] as List?;
    if (urlList != null && urlList.isNotEmpty) {
      coverUrl = urlList.first.toString();
    }
  }

  // 音乐
  String? musicUrl;
  final music = json['music'];
  if (music is Map) {
    musicUrl = music['play_url']?.toString();
  }

  return MediaUrls(
    platform: 'douyin',
    id: id,
    videoUrl: videoUrl,
    imageUrls: imageUrls,
    coverUrl: coverUrl,
    musicUrl: musicUrl,
  );
}

MediaUrls _parseXiaohongshuCache(String id, Map<String, dynamic> json) {
  String? videoUrl;
  final imageUrls = <String>[];
  final livePhotoUrls = <String>[];

  final type = json['type']?.toString();

  if (type == 'video') {
    // 视频：stream 是对象 {h264: [...], h265: [...]}
    final stream = json['video']?['media']?['stream'];
    if (stream is Map) {
      // 优先使用 h264
      final h264 = stream['h264'] as List?;
      final h265 = stream['h265'] as List?;

      List? targetStream = h264;
      if (h264 == null || h264.isEmpty) {
        targetStream = h265;
      }

      if (targetStream != null && targetStream.isNotEmpty) {
        videoUrl = targetStream.first['masterUrl']?.toString();
      }
    }
  } else {
    // 图文/实况图
    final imageList = json['imageList'] as List?;
    if (imageList != null) {
      for (final img in imageList) {
        if (img is! Map) continue;

        final livePhoto = img['livePhoto'] == true;
        final url = img['urlDefault']?.toString() ?? img['url']?.toString();

        if (livePhoto) {
          // 实况图视频
          final liveUrl = img['livePhotoUrl']?.toString();
          if (liveUrl != null && liveUrl.isNotEmpty) {
            livePhotoUrls.add(liveUrl);
          }
        }

        if (url != null && url.isNotEmpty) {
          imageUrls.add(url);
        }
      }
    }
  }

  // 封面
  String? coverUrl = json['imageList']?.first?['urlDefault']?.toString();

  return MediaUrls(
    platform: 'xiaohongshu',
    id: id,
    videoUrl: videoUrl,
    imageUrls: imageUrls,
    livePhotoUrls: livePhotoUrls,
    coverUrl: coverUrl,
  );
}

// ── URL 检测 ──────────────────────────────────────────────────────────────────
Future<UrlCheckResult> checkUrl(String url) async {
  try {
    final uri = Uri.parse(url);
    final request = http.Request('HEAD', uri)
      ..headers['User-Agent'] = _userAgent;

    final response = await http.Client().send(request).timeout(_timeout);
    final statusCode = response.statusCode;

    return UrlCheckResult(url: url, statusCode: statusCode);
  } on http.ClientException catch (e) {
    return UrlCheckResult(url: url, error: '网络错误: ${e.message}');
  } on io.SocketException catch (e) {
    return UrlCheckResult(url: url, error: '连接失败: ${e.message}');
  } catch (e) {
    return UrlCheckResult(url: url, error: e.toString());
  }
}

// ── 主入口 ───────────────────────────────────────────────────────────────────
Future<void> main(List<String> args) async {
  bool verbose = args.contains('--verbose') || args.contains('-v');
  String cacheDir = _defaultCacheDir;

  for (final arg in args) {
    if (arg.startsWith('--cache=')) {
      cacheDir = arg.substring('--cache='.length);
    } else if (arg == '--cache' && args.indexOf(arg) + 1 < args.length) {
      cacheDir = args[args.indexOf(arg) + 1];
    }
  }

  final cacheDirectory = io.Directory(cacheDir);
  if (!cacheDirectory.existsSync()) {
    print('缓存目录不存在: $cacheDir');
    io.exit(1);
  }

  // 扫描缓存文件
  final cacheFiles = <io.File>[];
  await for (final entity in cacheDirectory.list()) {
    if (entity is io.File && entity.path.endsWith('.json')) {
      cacheFiles.add(entity);
    }
  }

  if (cacheFiles.isEmpty) {
    print('缓存目录中没有 JSON 文件: $cacheDir');
    io.exit(1);
  }

  print('媒体 URL 可用性验证');
  print('缓存目录: $cacheDir');
  print('文件数量: ${cacheFiles.length}');
  print('');

  int totalUrls = 0;
  int okUrls = 0;
  int unknownUrls = 0; // 405 等，HEAD 不支持但 URL 可能可用
  int failedUrls = 0;
  int forbiddenUrls = 0;

  final failedItems =
      <(String platform, String id, String type, String url, String status)>[];

  for (final file in cacheFiles) {
    final media = parseCacheFile(file.path);
    if (media == null) continue;

    final fileName = path.basename(file.path);
    final platformIcon = media.platform == 'douyin' ? '🎵' : '📕';
    print('$platformIcon ${media.id}');

    for (final (type, url) in media.allUrls) {
      totalUrls++;

      if (verbose) {
        print('  检测 $type …');
      }

      final result = await checkUrl(url);

      if (result.isOk) {
        okUrls++;
        if (verbose) {
          print('    ✓ ${result.statusLabel}');
        }
      } else if (result.isMethodNotAllowed) {
        // 405: HEAD 不支持，URL 可能仍可用
        unknownUrls++;
        if (verbose) {
          print('    ? ${result.statusLabel}');
        }
      } else {
        failedUrls++;
        if (result.isForbidden) {
          forbiddenUrls++;
        }
        print('    ✗ $type: ${result.statusLabel}');
        failedItems.add((
          media.platform,
          media.id,
          type,
          url,
          result.statusLabel,
        ));
      }

      // 避免请求过快
      await Future.delayed(const Duration(milliseconds: 1000));
    }
  }

  // ── 汇总 ───────────────────────────────────────────────────────────────
  print('');
  print('=' * 60);
  print('检测结果汇总');
  print('=' * 60);
  print('总 URL 数: $totalUrls');
  print('可用: $okUrls');
  if (unknownUrls > 0) {
    print('未知 (405): $unknownUrls');
  }
  print('不可用: $failedUrls');
  if (forbiddenUrls > 0) {
    print('  其中 401/403: $forbiddenUrls');
  }
  print('');

  if (failedItems.isNotEmpty) {
    print('不可用 URL 列表:');
    print('-' * 60);
    for (final (platform, id, type, url, status) in failedItems) {
      final shortUrl = url.length > 60 ? '${url.substring(0, 57)}...' : url;
      print('[$platform] $id / $type: $status');
      if (verbose) {
        print('  $shortUrl');
      }
    }
  }

  if (failedUrls > 0) {
    io.exit(1);
  }
}
