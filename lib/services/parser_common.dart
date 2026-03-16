/// 解析器公共模块 - 抖音和小红书解析器共享的代码
library;

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import 'app_logger.dart';
import 'url_extractor.dart';

// ==================== 常量定义 ====================

/// 调试 JSON 输出目录（可在 app 启动时设置）
String? debugOutputDir;

/// 获取调试 JSON 输出目录
///
/// 优先级：
/// 1. 用户设置的下载目录 (debugOutputDir)
/// 2. 系统临时目录
String getDebugOutputDir() {
  // 优先使用设置的路径
  if (debugOutputDir != null && debugOutputDir!.isNotEmpty) {
    return debugOutputDir!;
  }
  // 回退到系统临时目录
  return Directory.systemTemp.path;
}

// ==================== 枚举定义 ====================

/// 视频清晰度枚举（ratio 参数值即为实际传参字符串）
enum VideoQuality {
  p720('720p'),
  p1080('1080p'),
  p2160('2160p');

  final String ratio;
  const VideoQuality(this.ratio);

  @override
  String toString() => ratio;

  static VideoQuality? fromRatio(String ratio) {
    for (final q in VideoQuality.values) {
      if (q.ratio == ratio) return q;
    }
    return null;
  }
}

/// 媒体类型枚举
enum MediaType {
  video, // 普通视频
  image, // 图文/图集
  livePhoto, // 实况图/动图
}

/// 支持的视频平台类型枚举
enum ParserPlatform {
  douyin, // 抖音平台
  xiaohongshu, // 小红书平台
  unknown // 未知平台
  ;

  /// 根据URL判断平台类型
  static ParserPlatform fromUrl(String url) {
    if (url.contains('douyin.com') || url.contains('iesdouyin.com')) {
      return ParserPlatform.douyin;
    }
    if (url.contains('xiaohongshu.com') || url.contains('xhslink.com')) {
      return ParserPlatform.xiaohongshu;
    }
    return ParserPlatform.unknown;
  }

  /// 获取文件名前缀
  String get filePrefix => switch (this) {
    ParserPlatform.douyin => 'DY_',
    ParserPlatform.xiaohongshu => 'XHS_',
    ParserPlatform.unknown => '',
  };
}

// ==================== 数据模型 ====================

/// 解析视频信息的结果 - 统一的数据模型
class VideoInfo {
  /// 作品ID (抖音: aweme_id, 小红书: noteId)
  final String itemId;
  final String title;

  /// 来源平台
  final ParserPlatform platform;

  /// video_id 参数（用于构造 play URL，如 v0200fg10000xxxxxx）
  final String videoFileId;

  /// 视频播放 URL（有水印，已自动选择最高质量）
  /// 这是确保可用的原始 URL
  final String videoUrl;

  /// 无水印视频 URL（备用）
  /// 可能无水印，但不保证可用性
  /// 下载失败时可回退到 [videoUrl]
  final String? videoUrlNoWatermark;

  final String? coverUrl;

  /// 原始短链接中的分享 ID
  /// 每条视频唯一，可直接拼回原始分享页，优先用于文件命名
  final String? shareId;

  /// 视频原始宽高（像素）
  final int? width;
  final int? height;

  /// 视频码率（kbps）
  final int? bitrateKbps;

  /// 图文作品的图片 URL 列表（按原始顺序，已去除头像等无关项）
  final List<String> imageUrls;

  /// 图文作品的缩略图 URL 列表（用于预览显示）
  final List<String> imageThumbUrls;

  /// 图文作品背景音乐的直连 CDN URL（MP3），无背景音乐或视频作品时为 null
  final String? musicUrl;

  /// 背景音乐标题，null 表示无音乐或未能解析
  final String? musicTitle;

  /// 背景音乐作者，null 表示无音乐或未能解析
  final String? musicAuthor;

  /// 实况图视频 URL 列表（小红书 Live Photo）
  ///
  /// 索引与 [imageUrls] 对应，非实况图的项为空字符串。
  ///
  /// 注意：小红书支持「实况图+静态图」混合的作品，即部分图片有实况视频，部分没有。
  /// 例如 3 张图片中只有第 2 张是实况图：
  /// - imageUrls = [img1, img2, img3]
  /// - livePhotoUrls = ['', video2, '']
  /// UI 需要根据 livePhotoUrls[i].isNotEmpty 来判断是否显示 MP4 下载按钮。
  /// // http://xhslink.com/o/1YCJtCHOnmf 这个只有一个是动图，其它的是静态图
  final List<String> livePhotoUrls;

  /// 媒体类型
  final MediaType mediaType;

  // ─── 作者信息 ─────────────────────────────────────────────────────────────

  /// 作者唯一标识（抖音: unique_id/short_id, 小红书: userId）
  final String? authorId;

  /// 作者昵称
  final String? authorName;

  /// 作者头像 URL
  final String? authorAvatar;

  // ─── 统计信息 ─────────────────────────────────────────────────────────────

  /// 发布时间戳（秒，抖音；毫秒，小红书）
  final int? createTime;

  /// 点赞数
  final int? likeCount;

  /// 收藏数
  final int? collectCount;

  /// 评论数
  final int? commentCount;

  /// 分享数
  final int? shareCount;

  const VideoInfo({
    required this.itemId,
    required this.title,
    required this.videoFileId,
    required this.videoUrl,
    required this.mediaType,
    required this.platform,
    this.videoUrlNoWatermark,
    this.coverUrl,
    this.shareId,
    this.width,
    this.height,
    this.bitrateKbps,
    this.imageUrls = const [],
    this.imageThumbUrls = const [],
    this.musicUrl,
    this.musicTitle,
    this.musicAuthor,
    this.livePhotoUrls = const [],
    // 作者信息
    this.authorId,
    this.authorName,
    this.authorAvatar,
    // 统计信息
    this.createTime,
    this.likeCount,
    this.collectCount,
    this.commentCount,
    this.shareCount,
  });

  /// 从 JSON Map 创建 VideoInfo
  ///
  /// 统一的反序列化方法，用于从 backend API 或其他 JSON 数据源创建对象
  factory VideoInfo.fromJson(Map<String, dynamic> j) {
    final type = j['type']?.toString() ?? 'video';
    final videoUrl = j['videoUrl']?.toString() ?? '';

    return VideoInfo(
      itemId: j['id']?.toString() ?? j['itemId']?.toString() ?? '',
      title: j['title']?.toString() ?? '',
      videoFileId: _extractVideoFileId(videoUrl),
      videoUrl: videoUrl,
      videoUrlNoWatermark: j['videoUrlNoWatermark']?.toString(),
      mediaType: _parseMediaType(type),
      platform: _parsePlatform(j['platform']?.toString()),
      coverUrl: j['coverUrl']?.toString(),
      shareId: j['shareId']?.toString(),
      width: int.tryParse(j['width']?.toString() ?? ''),
      height: int.tryParse(j['height']?.toString() ?? ''),
      bitrateKbps: _parseBitrate(j['videoBitrate']),
      imageUrls: _parseStringList(j['imageUrls']),
      imageThumbUrls: _parseStringList(j['imageThumbs'] ?? j['imageThumbUrls']),
      musicUrl: _parseNullableString(j['musicUrl']),
      musicTitle: _parseNullableString(j['musicTitle']),
      musicAuthor: _parseNullableString(j['musicAuthor']),
      livePhotoUrls: _parseStringList(j['livePhotoUrls'], keepEmpty: true),
      // 作者信息
      authorId: _parseNullableString(j['authorId']),
      authorName: _parseNullableString(j['authorName']),
      authorAvatar: _parseNullableString(j['authorAvatar']),
      // 统计信息
      createTime: int.tryParse(j['createTime']?.toString() ?? ''),
      likeCount: int.tryParse(j['likeCount']?.toString() ?? ''),
      collectCount: int.tryParse(j['collectCount']?.toString() ?? ''),
      commentCount: int.tryParse(j['commentCount']?.toString() ?? ''),
      shareCount: int.tryParse(j['shareCount']?.toString() ?? ''),
    );
  }

  /// 从视频 URL 中提取 videoFileId
  static String _extractVideoFileId(String videoUrl) {
    if (videoUrl.isEmpty) return '';
    final id = Uri.tryParse(videoUrl)?.queryParameters['video_id'];
    return id ?? '';
  }

  /// 解析媒体类型
  static MediaType _parseMediaType(String type) {
    return switch (type.toLowerCase()) {
      'image' => MediaType.image,
      'livephoto' || 'live_photo' => MediaType.livePhoto,
      _ => MediaType.video,
    };
  }

  /// 解析平台类型
  static ParserPlatform _parsePlatform(String? value) {
    return switch (value?.toLowerCase()) {
      'douyin' => ParserPlatform.douyin,
      'xiaohongshu' => ParserPlatform.xiaohongshu,
      _ => ParserPlatform.unknown,
    };
  }

  /// 解析码率 (bps -> kbps)
  static int? _parseBitrate(dynamic value) {
    final bps = int.tryParse(value?.toString() ?? '');
    return bps != null ? bps ~/ 1000 : null;
  }

  /// 解析字符串列表
  ///
  /// [keepEmpty] 是否保留空字符串（用于 livePhotoUrls 等需要保持索引对应的场景）
  static List<String> _parseStringList(
    dynamic value, {
    bool keepEmpty = false,
  }) {
    if (value is! List) return const [];
    final list = value.map((e) => e.toString()).toList();
    return keepEmpty ? list : list.where((e) => e.isNotEmpty).toList();
  }

  /// 解析可空字符串（空字符串转为 null）
  static String? _parseNullableString(dynamic value) {
    final s = value?.toString();
    return (s != null && s.isNotEmpty) ? s : null;
  }

  /// 分辨率标签，如 "1920×1080"、"3840×2160 (4K)"，无数据时返回 null
  String? get resolutionLabel {
    if (width == null || height == null) return null;
    final base = '$width×$height';
    if (height! >= 2160) return '$base (4K)';
    if (height! >= 1440) return '$base (2K)';
    return base;
  }

  @override
  String toString() =>
      'VideoInfo(itemId: $itemId, title: $title, resolution: $resolutionLabel)';
}

// ==================== 异常定义 ====================

/// 解析器异常基类
abstract class ParserException implements Exception {
  final String message;
  const ParserException(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

/// 抖音解析异常
class DouyinParseException extends ParserException {
  const DouyinParseException(super.message);
}

/// 小红书解析异常
class XiaohongshuParseException extends ParserException {
  const XiaohongshuParseException(super.message);
}

// ==================== 工具类 ====================

/// URL 处理工具类
class UrlUtils {
  UrlUtils._(); // 私有构造函数，防止实例化

  /// 从文本中提取 URL
  ///
  /// 使用 [UrlExtractor] 实现，支持更多中文标点符号
  /// 未找到时返回原字符串
  static String extractUrl(String text) {
    return UrlExtractor.extractFirst(text) ?? text;
  }

  /// 验证 URL 是否可用（HTTP 200-399 视为可用）
  static Future<bool> verifyUrlAvailable(
    String url, {
    required http.Client client,
    Map<String, String>? headers,
  }) async {
    try {
      final resp = await client.head(Uri.parse(url), headers: headers);
      return resp.statusCode >= 200 && resp.statusCode < 400;
    } catch (_) {
      return false;
    }
  }

  /// 验证 URL 并返回文件大小
  static Future<int> verifyUrlAndGetSize(
    String url, {
    required http.Client client,
    Map<String, String>? headers,
  }) async {
    try {
      final resp = await client.head(Uri.parse(url), headers: headers);
      if (resp.statusCode >= 200 && resp.statusCode < 400) {
        return int.tryParse(resp.headers['content-length'] ?? '0') ?? 0;
      }
    } catch (_) {
      // 忽略失败
    }
    return 0;
  }
}

/// JSON 提取工具类 - 处理 HTML 中内嵌的 JSON 数据
class JsonExtractor {
  JsonExtractor._();

  /// 从 HTML 中提取指定标记后的 JSON 对象
  ///
  /// [html] HTML 内容
  /// [marker] JSON 开始标记，如 "window._ROUTER_DATA = "
  /// [cleanUndefined] 是否将 undefined 替换为 null
  static Map<String, dynamic>? extractJsonObject(
    String html,
    String marker, {
    bool cleanUndefined = false,
  }) {
    final start = html.indexOf(marker);
    if (start < 0) return null;

    final jsonStart = start + marker.length;
    var depth = 0;
    var inString = false;
    var escaped = false;
    var end = -1;

    for (var i = jsonStart; i < html.length; i++) {
      final ch = html[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (ch == '\\') {
        escaped = true;
        continue;
      }
      if (ch == '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;
      if (ch == '{') {
        depth++;
      } else if (ch == '}') {
        depth--;
        if (depth == 0) {
          end = i;
          break;
        }
      }
    }

    if (end <= jsonStart) return null;

    try {
      var raw = html.substring(jsonStart, end + 1);
      if (cleanUndefined) {
        raw = JsonExtractor.cleanUndefined(raw);
      }
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// 使用正则表达式提取并解析 JSON（适用于简单的 JSON 结构）
  ///
  /// 返回一个 record，包含原始 JSON 字符串和解析后的 Map
  /// - rawJson: 提取的原始 JSON 字符串（cleanUndefined 处理后的）
  /// - data: 解析后的 Map，解析失败时为 null
  static ({String rawJson, Map<String, dynamic>? data}) extractJsonWithRegex(
    String html,
    String pattern, {
    bool cleanUndefined = false,
  }) {
    final match = RegExp(pattern).firstMatch(html);
    if (match == null) return (rawJson: '', data: null);

    var jsonStr = match.group(1)!;
    if (cleanUndefined) {
      jsonStr = JsonExtractor.cleanUndefined(jsonStr);
    }

    try {
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      return (rawJson: jsonStr, data: data);
    } catch (_) {
      return (rawJson: jsonStr, data: null);
    }
  }

  /// 从 script 标签中提取 JSON
  static Map<String, dynamic>? extractFromScriptTag(
    String html,
    String scriptId,
  ) {
    final pattern =
        '<script[^>]*id=["\']$scriptId["\'][^>]*>([\\s\\S]*?)</script>';
    final match = RegExp(pattern).firstMatch(html);
    if (match != null) {
      try {
        return jsonDecode(match.group(1)!) as Map<String, dynamic>;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// 将 JavaScript undefined 替换为 null
  static String cleanUndefined(String jsonStr) {
    return jsonStr
        .replaceAllMapped(
          RegExp(r':\s*undefined\s*([,}\]])'),
          (m) => ':null${m.group(1)}',
        )
        .replaceAllMapped(
          RegExp(r'(?<=[,\[\{:])\s*undefined\s*(?=[,\}\]:])'),
          (m) => 'null',
        )
        .replaceAll(RegExp(r'^\s*undefined\s*'), 'null');
  }
}

// ==================== HTTP 解析器 Mixin ====================

/// HTTP 解析器 Mixin - 提供通用的 HTTP 功能和日志功能
///
/// 使用方式：
/// ```dart
/// class MyParser with HttpParserMixin {
///   MyParser({http.Client? client}) {
///     initHttpParser(client: client, logPrefix: '[MyParser]');
///   }
/// }
/// ```
mixin HttpParserMixin {
  late final http.Client _httpClient;
  late final String _logPrefix;

  /// 初始化 mixin
  void initHttpParser({http.Client? client, required String logPrefix}) {
    _httpClient = client ?? http.Client();
    _logPrefix = logPrefix;
  }

  /// 输出日志（始终显示）
  void log(String message) {
    AppLogger.info('$_logPrefix $message');
  }

  /// 输出详细日志（只在 verbose 模式显示）
  void logDebug(String message) {
    AppLogger.debug('$_logPrefix $message');
  }

  /// 获取 HTTP 客户端
  http.Client get httpClient => _httpClient;

  /// 跟随重定向获取最终 URL 和 HTML
  ///
  /// [url] 初始 URL
  /// [headers] 请求头
  /// [maxRedirects] 最大重定向次数
  Future<({String html, String finalUrl})> resolveUrlWithHtml(
    String url, {
    Map<String, String>? headers,
    int maxRedirects = 8,
  }) async {
    final uri = Uri.parse(url);
    final request = await _httpClient.get(uri, headers: headers);

    if (request.statusCode >= 300 && request.statusCode < 400) {
      final location = request.headers['location'];
      if (location != null && maxRedirects > 0) {
        return resolveUrlWithHtml(
          location,
          headers: headers,
          maxRedirects: maxRedirects - 1,
        );
      }
    }

    return (
      html: request.body,
      finalUrl: request.request?.url.toString() ?? url,
    );
  }

  /// 使用 HttpClient 手动跟随重定向（用于需要更精细控制的情况）
  ///
  /// 检测最终 URL 的 HTTP 状态码，404 时抛出 [ParserException]
  Future<String> resolveUrlManually(
    String url, {
    required String userAgent,
    String? referer,
    int maxRedirects = 8,
  }) async {
    var currentUri = Uri.parse(url);
    final ioClient = HttpClient();
    int? lastStatusCode;
    try {
      for (var i = 0; i < maxRedirects; i++) {
        final request = await ioClient.getUrl(currentUri);
        request.headers.set(HttpHeaders.userAgentHeader, userAgent);
        if (referer != null) {
          request.headers.set(HttpHeaders.refererHeader, referer);
        }
        request.followRedirects = false;

        final response = await request.close();
        lastStatusCode = response.statusCode;
        await response.drain<void>();

        if (response.statusCode >= 300 && response.statusCode < 400) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location == null) break;
          currentUri = currentUri.resolve(location);
        } else {
          break;
        }
      }
    } finally {
      ioClient.close();
    }

    // 检测 404 状态码
    if (lastStatusCode == 404) {
      throw const DouyinParseException('作品不存在或已被删除（链接返回404）');
    }

    return currentUri.toString();
  }

  /// 释放资源
  void disposeHttpParser() => _httpClient.close();
}
