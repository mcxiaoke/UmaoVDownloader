import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'douyin_parser.dart';

/// 小红书解析异常
class XiaohongshuParseException implements Exception {
  final String message;
  const XiaohongshuParseException(this.message);

  @override
  String toString() => 'XiaohongshuParseException: $message';
}

/// 视频流信息
class _VideoStream {
  final String url;
  final int bitrate;
  final int? size;
  final int? width;
  final int? height;
  final String codec;

  _VideoStream({
    required this.url,
    required this.bitrate,
    this.size,
    this.width,
    this.height,
    required this.codec,
  });
}

/// 小红书解析器
///
/// 流程：分享链接 → 跟随重定向 → 提取 __INITIAL_STATE__ → 解析笔记数据
class XiaohongshuParser {
  static const _timeout = Duration(seconds: 15);
  static const _mobileUserAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1';

  static const _headers = {
    'User-Agent': _mobileUserAgent,
    'Referer': 'https://www.xiaohongshu.com/',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9',
  };

  // CDN 域名列表（用于视频切换）
  static const _cdnDomains = [
    'sns-video-hw.xhscdn.com', // 华为云
    'sns-video-hs.xhscdn.com', // 火山引擎
    'sns-video-al.xhscdn.com', // 阿里云
    'sns-video-qn.xhscdn.com', // 七牛
    'sns-video-bd.xhscdn.com', // 百度云
  ];

  final http.Client _client;
  bool _debug = false;

  XiaohongshuParser({http.Client? client}) : _client = client ?? http.Client();

  /// 解析小红书分享链接
  Future<VideoInfo> parse(String input, {bool debug = false}) async {
    _debug = debug;
    _log('开始解析: $input');

    // 提取 URL
    final extracted = _extractUrl(input);
    _log('提取URL: $extracted');

    // 跟随重定向获取真实 URL 和 HTML
    _log('→ 请求页面...');
    final (:html, :finalUrl) = await _resolveXhsUrl(extracted);
    _log('  最终URL: $finalUrl');
    _log('  HTML长度: ${html.length} bytes');

    // 尝试从 __INITIAL_STATE__ 提取数据
    _log('→ 提取 __INITIAL_STATE__...');
    var data = _extractInitialState(html);

    // 如果失败，尝试 SSR 数据
    if (data == null) {
      _log('  未找到 __INITIAL_STATE__, 尝试 SSR 数据...');
      data = _extractSsrData(html);
    }

    if (data == null) {
      throw const XiaohongshuParseException('未找到 __INITIAL_STATE__ 或 SSR 数据');
    }
    _log('  ✓ 数据提取成功');

    // 提取笔记数据
    _log('→ 提取笔记数据...');
    final note = _extractNoteData(data);
    if (note == null) {
      throw const XiaohongshuParseException('无法提取笔记数据');
    }
    _log('  ✓ noteId: ${note['noteId'] ?? note['id'] ?? 'unknown'}');
    _log('  ✓ title: ${(note['title'] ?? note['desc'] ?? '').toString().substring(0, (note['title'] ?? note['desc'] ?? '').toString().length.clamp(0, 50))}');
    final hasVideo = note['video'] != null && note['video'] is Map;
    _log('  ✓ type: ${hasVideo ? 'video' : note['imageList'] != null ? 'image' : 'unknown'}');

    final result = await _buildResult(note);

    _log('→ 构建结果:');
    _log('  type: ${result.qualityUrls.isNotEmpty ? 'video' : result.imageUrls.isNotEmpty ? 'image' : 'unknown'}');
    _log('  imageCount: ${result.imageUrls.length}');
    if (result.availableQualities.isNotEmpty) {
      _log('  qualities: ${result.availableQualities.map((q) => q.ratio).join('/')}');
      _log('  最佳视频: ${result.videoUrl.substring(0, result.videoUrl.length.clamp(0, 80))}...');
    }
    if (result.imageUrls.isNotEmpty) {
      _log('  imageUrls[0]: ${result.imageUrls[0]}');
    }

    return result;
  }

  void _log(String msg) {
    if (_debug) stderr.writeln('  [XHS] $msg');
  }

  /// 从文本中提取 URL
  String _extractUrl(String text) {
    final match = RegExp(r'https?://[^\s，,。]+').firstMatch(text);
    return match?.group(0) ?? text;
  }

  /// 跟随重定向获取真实 URL 和 HTML
  Future<({String html, String finalUrl})> _resolveXhsUrl(String url) async {
    final uri = Uri.parse(url);
    final request = await _client.get(uri, headers: _headers);

    if (request.statusCode >= 300 && request.statusCode < 400) {
      final location = request.headers['location'];
      if (location != null) {
        return _resolveXhsUrl(location);
      }
    }

    return (html: request.body, finalUrl: request.request?.url.toString() ?? url);
  }

  /// 从 HTML 中提取 __INITIAL_STATE__
  /// 注意：小红书的数据包含 undefined，需要预处理
  Map<String, dynamic>? _extractInitialState(String html) {
    final marker = RegExp(r'window\.__INITIAL_STATE__\s*=\s*')
        .firstMatch(html);
    if (marker == null) return null;

    final start = marker.end;
    var depth = 0;
    var inString = false;
    var escaped = false;

    for (var i = start; i < html.length; i++) {
      final ch = html[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (ch == r'\') {
        escaped = true;
        continue;
      }
      if (ch == '"' && html[i - 1] != r'\') {
        inString = !inString;
        continue;
      }
      if (inString) continue;

      if (ch == '{' || ch == '[') depth++;
      else if (ch == '}' || ch == ']') {
        depth--;
        if (depth == 0) {
          final jsonStr = html.substring(start, i + 1);
          try {
            // 小红书数据包含 undefined，需要替换为 null
            final cleanJson = _cleanUndefined(jsonStr);
            return jsonDecode(cleanJson) as Map<String, dynamic>;
          } catch (e) {
            _log('JSON解析失败: $e');
            return null;
          }
        }
      }
    }
    return null;
  }

  /// 将 undefined 替换为 null，修复 JSON
  String _cleanUndefined(String jsonStr) {
    // 替换独立的 undefined 为 null
    return jsonStr
        .replaceAllMapped(
          RegExp(r'(?<=[,\[\{:])\s*undefined\s*(?=[,\}\]\:])'),
          (m) => 'null',
        )
        .replaceAll(RegExp(r'^\s*undefined\s*'), 'null');
  }

  /// 尝试从 SSR 渲染的 HTML 中提取数据（备用方案）
  Map<String, dynamic>? _extractSsrData(String html) {
    // 匹配 id="ssr-data" 或 id='ssr-data'
    final ssrMatch = RegExp(
      r'<script[^>]*id=["\x27]ssr-data["\x27][^>]*>([\s\S]*?)</script>',
    ).firstMatch(html);
    if (ssrMatch != null) {
      try {
        return jsonDecode(ssrMatch.group(1)!) as Map<String, dynamic>;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// 从 __INITIAL_STATE__ 中提取笔记数据
  Map<String, dynamic>? _extractNoteData(Map<String, dynamic> data) {
    // 新结构：noteData.data.noteData
    final noteData = data['noteData'];
    if (noteData is Map) {
      final data2 = noteData['data'];
      if (data2 is Map) {
        final note = data2['noteData'];
        if (note is Map<String, dynamic>) return note;
      }
    }

    // 备用路径: note.noteDetailMap[key].note
    final note = data['note'];
    if (note is Map) {
      final noteDetailMap = note['noteDetailMap'];
      if (noteDetailMap is Map) {
        final keys = noteDetailMap.keys.toList();
        if (keys.isNotEmpty) {
          final noteItem = noteDetailMap[keys.first];
          if (noteItem is Map) {
            // 实际的笔记数据在 .note 字段中
            final actualNote = noteItem['note'];
            if (actualNote is Map<String, dynamic>) return actualNote;
            // 有些结构直接是 noteItem
            if (noteItem['noteId'] != null || noteItem['id'] != null) {
              return Map<String, dynamic>.from(noteItem);
            }
          }
        }
      }
    }

    return null;
  }

  /// 构建统一的结果对象
  Future<VideoInfo> _buildResult(Map<String, dynamic> note) async {
    final id = note['noteId']?.toString() ?? note['id']?.toString() ?? '';
    final title = note['title']?.toString() ?? '';
    final desc = note['desc']?.toString() ?? '';

    // 封面图
    final coverUrl = _extractCoverUrl(note);

    // 提取图片列表（视频笔记也可能有封面图）
    final imageUrls = _extractImageUrls(note);

    // 判断是否为视频笔记：只要有 video 字段且非空即为视频
    final hasVideoField = note['video'] != null && note['video'] is Map;
    _log('  hasVideoField: $hasVideoField');

    // 提取视频信息（包括实况图）
    final videoInfo = await _extractVideoInfo(note);
    final hasVideoStream = videoInfo != null && videoInfo.qualityUrls.isNotEmpty;
    final isLivePhoto = videoInfo?.isLivePhoto ?? false;
    _log('  hasVideoStream: $hasVideoStream, isLivePhoto: $isLivePhoto');

    if (hasVideoField || isLivePhoto) {
      // 视频笔记或实况图（即使无法提取流信息，也标记为视频类型）
      return VideoInfo(
        videoId: id,
        title: title.isNotEmpty ? title : desc.substring(0, desc.length.clamp(0, 50)),
        videoFileId: id,
        qualityUrls: videoInfo?.qualityUrls ?? const {},
        coverUrl: coverUrl,
        shareId: null,
        width: videoInfo?.width ?? note['width'] as int?,
        height: videoInfo?.height ?? note['height'] as int?,
        imageUrls: imageUrls, // 视频笔记也可能有封面图
        livePhotoUrls: videoInfo?.livePhotoUrls ?? const [],
      );
    } else if (imageUrls.isNotEmpty) {
      // 纯图片笔记
      return VideoInfo(
        videoId: id,
        title: title.isNotEmpty ? title : desc.substring(0, desc.length.clamp(0, 50)),
        videoFileId: '',
        qualityUrls: const {},
        coverUrl: coverUrl,
        shareId: null,
        width: note['width'] as int?,
        height: note['height'] as int?,
        imageUrls: imageUrls,
        livePhotoUrls: const [],
      );
    }

    // 未知类型
    return VideoInfo(
      videoId: id,
      title: title.isNotEmpty ? title : desc.substring(0, desc.length.clamp(0, 50)),
      videoFileId: '',
      qualityUrls: const {},
      coverUrl: coverUrl,
      shareId: null,
      width: note['width'] as int?,
      height: note['height'] as int?,
      imageUrls: imageUrls,
      livePhotoUrls: const [],
    );
  }

  /// 提取封面图 URL
  String? _extractCoverUrl(Map<String, dynamic> note) {
    final cover = note['cover'];
    if (cover is Map) {
      if (cover['urlDefault'] is String) return cover['urlDefault'];
      if (cover['url'] is String) return cover['url'];
      final infoList = cover['infoList'];
      if (infoList is List && infoList.isNotEmpty) {
        final first = infoList.first;
        if (first is Map && first['url'] is String) return first['url'];
      }
    }

    final imageList = note['imageList'] ?? note['images'];
    if (imageList is List && imageList.isNotEmpty) {
      final first = imageList.first;
      if (first is Map) {
        if (first['urlDefault'] is String) return first['urlDefault'];
        if (first['url'] is String) return first['url'];
        final infoList = first['infoList'];
        if (infoList is List && infoList.isNotEmpty) {
          final info = infoList.first;
          if (info is Map && info['url'] is String) return info['url'];
        }
      }
    }

    // 从视频首帧提取
    final video = note['video'];
    if (video is Map) {
      final media = video['media'];
      if (media is Map) {
        final videoFirstFrame = media['videoFirstFrame'];
        if (videoFirstFrame is Map && videoFirstFrame['url'] is String) {
          return videoFirstFrame['url'];
        }
      }
    }

    return null;
  }

  /// 提取图片 URL 列表（无水印）
  /// 使用 sns-webpic.xhscdn.com 域名支持受保护的图片（作者禁止直接保存）
  List<String> _extractImageUrls(Map<String, dynamic> note) {
    final imageList = note['imageList'] ?? note['images'];
    if (imageList is! List) return [];

    return imageList.map((img) {
      if (img is! Map) return null;

      // 从 infoList 中提取原始 fileId 构建高清 URL
      final infoList = img['infoList'];
      if (infoList is List && infoList.isNotEmpty) {
        final best = infoList.last;
        if (best is Map && best['url'] is String) {
          final result = _extractFileIdFromUrl(best['url']);
          if (result != null) {
            // 使用 sns-webpic 域名构建高清无水印 URL（支持受保护图片）
            // 格式: https://sns-webpic.xhscdn.com/notes_pre_post/{fileId}?imageView2/2/w/0/format/jpg/v3&c=v1
            return 'https://sns-webpic.xhscdn.com/notes_pre_post/${result.fileId}?imageView2/2/w/0/format/jpg/v3&c=v1';
          }
          return best['url'];
        }
      }

      // 其次尝试 traceId 构建（备用）
      final traceId = img['traceId'];
      if (traceId is String) {
        return 'https://sns-webpic.xhscdn.com/notes_pre_post/$traceId?imageView2/2/w/0/format/jpg/v3&c=v1';
      }
      final firstInfo = infoList is List && infoList.isNotEmpty ? infoList.first : null;
      if (firstInfo is Map) {
        final imageScene = firstInfo['imageScene'];
        if (imageScene is Map) {
          final traceId2 = imageScene['traceId'];
          if (traceId2 is String) {
            return 'https://sns-webpic.xhscdn.com/notes_pre_post/$traceId2?imageView2/2/w/0/format/jpg/v3&c=v1';
          }
        }
      }

      // 最后备用：urlDefault 或 url
      if (img['urlDefault'] is String) return img['urlDefault'];
      if (img['url'] is String) return img['url'];
      return null;
    }).whereType<String>().toList();
  }

  /// 从小红书 URL 中提取 fileId 和路径前缀
  _FileIdResult? _extractFileIdFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final pathParts = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (pathParts.isEmpty) return null;

      // 取最后一部分，去掉 !style_xxx 后缀
      final lastPart = pathParts.last;
      final fileId = lastPart.split('!').first;

      // 验证 fileId 格式（通常是 1040g 开头）
      if (fileId.isNotEmpty && RegExp(r'^[a-z0-9]+$').hasMatch(fileId)) {
        // 检查是否有 notes_uhdr 前缀
        final prefix = pathParts.contains('notes_uhdr') ? 'notes_uhdr/' : '';
        return _FileIdResult(fileId: fileId, prefix: prefix);
      }
    } catch (_) {
      // 解析失败返回 null
    }
    return null;
  }

  /// 提取实况图视频 URL 列表
  /// 实况图 (livePhoto) 每张图都带有一个短视频（带声音）
  List<String> _extractLivePhotoUrls(Map<String, dynamic> note) {
    final imageList = note['imageList'] ?? note['images'];
    if (imageList is! List) return [];

    final urls = <String>[];
    for (final img in imageList) {
      if (img is! Map) continue;
      // 检查是否为实况图
      if (img['livePhoto'] != true) continue;

      // 提取视频流
      final stream = img['stream'];
      if (stream is! Map) continue;

      // 优先 h264，其次 h265/av1
      final formats = ['h264', 'h265', 'hevc', 'av1'];
      String? videoUrl;
      for (final fmt in formats) {
        final streams = stream[fmt];
        if (streams is List && streams.isNotEmpty) {
          final first = streams.first;
          if (first is Map) {
            videoUrl = first['masterUrl']?.toString() ?? first['url']?.toString();
            if (videoUrl != null) break;
          }
        }
      }
      if (videoUrl != null) {
        urls.add(videoUrl);
        _log('  实况图视频: ${videoUrl.substring(videoUrl.lastIndexOf('/') + 1)}');
      }
    }
    return urls;
  }

  /// 提取视频信息
  Future<_VideoInfoResult?> _extractVideoInfo(Map<String, dynamic> note) async {
    final video = note['video'];
    if (video is! Map) {
      // 检查是否有实况图视频
      final livePhotoUrls = _extractLivePhotoUrls(note);
      if (livePhotoUrls.isNotEmpty) {
        _log('  检测到 ${livePhotoUrls.length} 张实况图');
        // 实况图返回第一个视频的 URL，标记为实况图类型
        return _VideoInfoResult(
          qualityUrls: {VideoQuality.p720: livePhotoUrls.first},
          videoUrl: livePhotoUrls.first,
          width: null,
          height: null,
          isLivePhoto: true,
          livePhotoUrls: livePhotoUrls,
        );
      }
      _log('  无 video 字段');
      return null;
    }

    final media = video['media'];
    if (media is! Map) {
      _log('  video.media 为空');
      return null;
    }

    final stream = media['stream'];
    if (stream is! Map) {
      _log('  video.media.stream 为空');
      return null;
    }

    _log('  视频流格式: ${stream.keys.join(', ')}');

    final qualities = <VideoQuality>[];
    final qualityUrls = <VideoQuality, String>{};
    final candidateUrls = <_VideoStream>[];

    // 尝试各种编码格式（按优先级排序）
    final formats = [
      (key: 'origin', name: '原画', quality: VideoQuality.p1080),
      (key: 'h264', name: 'HD', quality: VideoQuality.p720),
      (key: 'h265', name: 'HD (H.265)', quality: VideoQuality.p720),
      (key: 'hevc', name: 'HD (HEVC)', quality: VideoQuality.p720),
      (key: 'av1', name: 'HD (AV1)', quality: VideoQuality.p720),
      (key: 'mp4', name: 'MP4', quality: VideoQuality.p720),
    ];

    int? bestWidth;
    int? bestHeight;

    for (final format in formats) {
      final streams = stream[format.key];
      if (streams is! List || streams.isEmpty) continue;

      // 遍历所有流，找码率最高的
      var bestStream = streams.first;
      var bestBitrate = 0;

      for (final s in streams) {
        if (s is! Map) continue;
        final bitrate = (s['videoBitrate'] as num?)?.toInt() ?? 0;
        if (bitrate > bestBitrate) {
          bestBitrate = bitrate;
          bestStream = s;
        }

        // 收集所有候选URL
        final url = s['masterUrl']?.toString() ?? s['url']?.toString();
        if (url != null) {
          candidateUrls.add(_VideoStream(
            url: url,
            bitrate: bitrate,
            size: (s['size'] as num?)?.toInt(),
            width: (s['width'] as num?)?.toInt(),
            height: (s['height'] as num?)?.toInt(),
            codec: format.key,
          ));
        }
      }

      final url = bestStream['masterUrl']?.toString() ?? bestStream['url']?.toString();
      if (url != null) {
        qualities.add(format.quality);
        qualityUrls[format.quality] = url;

        bestWidth ??= (bestStream['width'] as num?)?.toInt();
        bestHeight ??= (bestStream['height'] as num?)?.toInt();
      }
    }

    if (qualities.isEmpty) return null;

    // 默认使用第一个质量的URL，如果失败再尝试切换CDN
    var bestUrl = qualityUrls[qualities.first]!;

    // 验证默认URL是否可用，如果不可用则尝试切换CDN
    _log('  验证视频URL可用性...');
    final isAvailable = await _verifyUrlAvailable(bestUrl);
    if (!isAvailable) {
      _log('    默认URL不可用，尝试切换CDN...');
      final cdnVariants = _generateCdnVariants([_VideoStream(url: bestUrl, bitrate: 0, codec: 'h264')]);
      for (final variant in cdnVariants) {
        final size = await _verifyUrlAndGetSize(variant.url);
        if (size > 0) {
          _log('    找到可用CDN: ${variant.url.substring(0, variant.url.length.clamp(0, 60))}... (${(size / 1024 / 1024).toStringAsFixed(2)}MB)');
          bestUrl = variant.url;
          break;
        }
      }
    } else {
      _log('    默认URL可用');
    }

    // 打印调试信息
    if (_debug && candidateUrls.isNotEmpty) {
      _log('  视频流信息:');
      final sorted = [...candidateUrls]..sort((a, b) => (b.size ?? 0) - (a.size ?? 0));
      for (var i = 0; i < sorted.length.clamp(0, 5); i++) {
        final c = sorted[i];
        final sizeMB = c.size != null ? '${(c.size! / 1024 / 1024).toStringAsFixed(2)}MB' : 'unknown';
        _log('    ${c.codec}: ${c.width}x${c.height}, ${c.bitrate}bps, $sizeMB');
        _log('      ${c.url.substring(0, c.url.length.clamp(0, 80))}...');
      }
    }

    // 更新最佳 URL
    if (bestUrl != qualityUrls[qualities.first]) {
      qualityUrls[qualities.first] = bestUrl;
    }

    return _VideoInfoResult(
      qualityUrls: qualityUrls,
      videoUrl: bestUrl,
      width: bestWidth,
      height: bestHeight,
    );
  }

  /// 生成不同CDN域名的变体URL
  List<_VideoStream> _generateCdnVariants(List<_VideoStream> candidates) {
    final variants = <_VideoStream>[];

    for (final c in candidates) {
      final match = RegExp(r'https://([^/]+)(/.*)').firstMatch(c.url);
      if (match == null) continue;

      final currentDomain = match.group(1)!;
      final path = match.group(2)!;

      // 为每个CDN生成变体
      for (final domain in _cdnDomains) {
        if (domain != currentDomain) {
          variants.add(_VideoStream(
            url: 'https://$domain$path',
            bitrate: c.bitrate,
            codec: c.codec,
            width: c.width,
            height: c.height,
          ));
        }
      }
    }

    return variants;
  }

  /// 验证 URL 是否可用（HTTP 200-399 视为可用）
  Future<bool> _verifyUrlAvailable(String url) async {
    try {
      final resp = await _client.head(Uri.parse(url), headers: {
        'User-Agent': _mobileUserAgent,
        'Referer': 'https://www.xiaohongshu.com/',
      });
      return resp.statusCode >= 200 && resp.statusCode < 400;
    } catch (_) {
      return false;
    }
  }

  /// 验证 URL 并返回文件大小
  Future<int> _verifyUrlAndGetSize(String url) async {
    try {
      final resp = await _client.head(Uri.parse(url), headers: {
        'User-Agent': _mobileUserAgent,
        'Referer': 'https://www.xiaohongshu.com/',
      });
      if (resp.statusCode >= 200 && resp.statusCode < 400) {
        return int.tryParse(resp.headers['content-length'] ?? '0') ?? 0;
      }
    } catch (_) {
      // 忽略失败
    }
    return 0;
  }

  void dispose() => _client.close();
}

/// fileId 提取结果
class _FileIdResult {
  final String fileId;
  final String prefix;

  _FileIdResult({required this.fileId, required this.prefix});
}

/// 视频信息结果
class _VideoInfoResult {
  final Map<VideoQuality, String> qualityUrls;
  final String videoUrl;
  final int? width;
  final int? height;
  final bool isLivePhoto;
  final List<String>? livePhotoUrls; // 所有实况图视频 URL

  _VideoInfoResult({
    required this.qualityUrls,
    required this.videoUrl,
    this.width,
    this.height,
    this.isLivePhoto = false,
    this.livePhotoUrls,
  });
}
