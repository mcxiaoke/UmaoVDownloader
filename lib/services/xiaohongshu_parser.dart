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
    _log('  type: ${result.videoUrl.isNotEmpty ? 'video' : result.imageUrls.isNotEmpty ? 'image' : 'unknown'}');
    _log('  imageCount: ${result.imageUrls.length}');
    if (result.videoUrl.isNotEmpty) {
      _log('  最佳视频: ${result.videoUrl.substring(0, result.videoUrl.length.clamp(0, 80))}...');
    }
    if (result.imageUrls.isNotEmpty) {
      _log('  imageUrls[0]: ${result.imageUrls[0]}');
      // 详细日志：打印所有缩略图和下载地址
      if (_debug) {
        for (var i = 0; i < result.imageUrls.length; i++) {
          final thumb = result.imageThumbUrls.length > i ? result.imageThumbUrls[i] : result.imageUrls[i];
          final full = result.imageUrls[i];
          _log('  图片 ${i + 1}: thumb: $thumb');
          _log('  图片 ${i + 1}: full:  $full');
        }
      }
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
  /// 优先使用 JSON 解析，失败则回退到手动提取
  Map<String, dynamic>? _extractInitialState(String html) {
    // 方法1: 优先使用 JSON 解析（将 undefined 替换为 null）
    final jsonResult = _extractInitialStateJson(html);
    if (jsonResult != null) {
      _log('  使用 JSON 解析成功');
      return jsonResult;
    }

    // 方法2: 回退到手动提取
    _log('  JSON 解析失败，回退到手动提取');
    return _extractInitialStateLegacy(html);
  }

  /// 使用 JSON 解析提取 __INITIAL_STATE__
  /// 将 JavaScript undefined 替换为 null 使其成为合法 JSON
  Map<String, dynamic>? _extractInitialStateJson(String html) {
    final match = RegExp(r'window\.__INITIAL_STATE__\s*=\s*(\{[\s\S]*?\})(?:;|\s*</script>)')
        .firstMatch(html);
    if (match == null) return null;

    var jsonStr = match.group(1)!;

    // 将 JavaScript undefined 替换为 null
    // 匹配: : undefined, : undefined} : undefined] 等情况
    jsonStr = jsonStr.replaceAllMapped(
      RegExp(r':\s*undefined\s*([,}\]])'),
      (m) => ':null${m.group(1)}',
    );

    try {
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      // JSON 解析失败，返回 null 让调用方使用备用方案
      return null;
    }
  }

  /// 备用方案：手动提取 + 处理边界情况
  Map<String, dynamic>? _extractInitialStateLegacy(String html) {
    final marker = RegExp(r'window\.__INITIAL_STATE__\s*=\s*').firstMatch(html);
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
            // 尝试先清理 undefined 再解析
            final cleanJson = _cleanUndefinedLegacy(jsonStr);
            return jsonDecode(cleanJson) as Map<String, dynamic>;
          } catch (e) {
            _log('备用解析失败: $e');
            return null;
          }
        }
      }
    }
    return null;
  }

  /// 将 undefined 替换为 null，修复 JSON（备用方案使用）
  String _cleanUndefinedLegacy(String jsonStr) {
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

    // 提取图片列表（返回包含 thumb 和 full 的对象列表）
    final imageList = _extractImageUrls(note);
    final imageUrls = imageList.map((i) => i['full']!).toList();
    final imageThumbUrls = imageList.map((i) => i['thumb']!).toList();

    // 提取背景音乐
    final (:musicUrl, :musicTitle) = _extractMusicInfo(note);
    if (musicUrl != null) {
      _log('  背景音乐: $musicTitle');
    }

    // 判断是否为视频笔记：只要有 video 字段且非空即为视频
    final hasVideoField = note['video'] != null && note['video'] is Map;
    _log('  hasVideoField: $hasVideoField');

    // 提取视频信息（包括实况图）
    final videoInfo = await _extractVideoInfo(note);
    final hasVideoStream = videoInfo != null && videoInfo.videoUrl.isNotEmpty;
    final isLivePhoto = videoInfo?.isLivePhoto ?? false;
    _log('  hasVideoStream: $hasVideoStream, isLivePhoto: $isLivePhoto');

    if (hasVideoField || isLivePhoto) {
      // 视频笔记或实况图（即使无法提取流信息，也标记为视频类型）
      return VideoInfo(
        videoId: id,
        title: title.isNotEmpty ? title : desc.substring(0, desc.length.clamp(0, 50)),
        videoFileId: id,
        videoUrl: videoInfo?.videoUrl ?? '',
        coverUrl: coverUrl,
        shareId: null,
        width: videoInfo?.width ?? note['width'] as int?,
        height: videoInfo?.height ?? note['height'] as int?,
        imageUrls: imageUrls, // 视频笔记也可能有封面图
        imageThumbUrls: imageThumbUrls,
        livePhotoUrls: videoInfo?.livePhotoUrls ?? const [],
        musicUrl: musicUrl,
        musicTitle: musicTitle,
      );
    } else if (imageUrls.isNotEmpty) {
      // 纯图片笔记
      return VideoInfo(
        videoId: id,
        title: title.isNotEmpty ? title : desc.substring(0, desc.length.clamp(0, 50)),
        videoFileId: '',
        videoUrl: '',
        coverUrl: coverUrl,
        shareId: null,
        width: note['width'] as int?,
        height: note['height'] as int?,
        imageUrls: imageUrls,
        imageThumbUrls: imageThumbUrls,
        livePhotoUrls: const [],
        musicUrl: musicUrl,
        musicTitle: musicTitle,
      );
    }

    // 未知类型
    return VideoInfo(
      videoId: id,
      title: title.isNotEmpty ? title : desc.substring(0, desc.length.clamp(0, 50)),
      videoFileId: '',
      videoUrl: '',
      coverUrl: coverUrl,
      shareId: null,
      width: note['width'] as int?,
      height: note['height'] as int?,
      imageUrls: imageUrls,
      imageThumbUrls: imageThumbUrls,
      livePhotoUrls: const [],
      musicUrl: musicUrl,
      musicTitle: musicTitle,
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
  /// 缩略图：优先 WB_PRV > H5_PRV > urlPre > urlDefault
  /// 大图：优先 WB_DFT > H5_DTL > 其他 DFT > 无水印版
  List<Map<String, String>> _extractImageUrls(Map<String, dynamic> note) {
    final imageList = note['imageList'] ?? note['images'];
    if (imageList is! List) return [];

    return imageList.map((img) {
      if (img is! Map) return null;

      String? thumbUrl; // 预览图/缩略图
      String? fullOrigUrl; // 原图（带水印）
      String? fullNoWaterUrl; // 无水印图

      final infoList = img['infoList'];
      if (infoList is List && infoList.isNotEmpty) {
        // 找大图：WB_DFT > H5_DTL > 其他含 DFT 的
        final dftScenes = ['WB_DFT', 'H5_DTL'];
        for (final scene in dftScenes) {
          final match = infoList.cast<Map<String, dynamic>>().firstWhere(
            (i) => i['imageScene'] == scene && i['url'] is String,
            orElse: () => {},
          );
          if (match.isNotEmpty) {
            fullOrigUrl = match['url'];
            break;
          }
        }
        // 如果没找到，尝试任何含 DFT 的
        if (fullOrigUrl == null) {
          final dftMatch = infoList.cast<Map<String, dynamic>>().firstWhere(
            (i) => (i['imageScene'] as String?)?.contains('DFT') == true && i['url'] is String,
            orElse: () => {},
          );
          if (dftMatch.isNotEmpty) {
            fullOrigUrl = dftMatch['url'];
          }
        }

        // 找预览图：WB_PRV > H5_PRV
        final prvScenes = ['WB_PRV', 'H5_PRV'];
        for (final scene in prvScenes) {
          final match = infoList.cast<Map<String, dynamic>>().firstWhere(
            (i) => i['imageScene'] == scene && i['url'] is String,
            orElse: () => {},
          );
          if (match.isNotEmpty) {
            thumbUrl = match['url'];
            break;
          }
        }
      }

      // 外层字段作为备选
      if (fullOrigUrl == null) {
        if (img['urlDefault'] is String) {
          fullOrigUrl = img['urlDefault'];
        } else if (img['url'] is String) {
          fullOrigUrl = img['url'];
        }
      }

      if (thumbUrl == null) {
        if (img['urlPre'] is String) {
          thumbUrl = img['urlPre'];
        } else if (img['urlDefault'] is String) {
          thumbUrl = img['urlDefault'];
        }
      }

      // 生成无水印 URL
      if (fullOrigUrl != null) {
        fullNoWaterUrl = _buildNoWatermarkUrl(fullOrigUrl);
      }

      // 决定最终使用的 URL
      final fullUrl = fullNoWaterUrl ?? fullOrigUrl;
      final thumb = thumbUrl ?? fullUrl;

      if (fullUrl == null && thumb == null) return null;

      return {
        'thumb': thumb ?? fullUrl!,
        'full': fullUrl ?? thumb!,
      };
    }).whereType<Map<String, String>>().toList();
  }

  /// 构建无水印图片 URL
  String? _buildNoWatermarkUrl(String originalUrl) {
    try {
      final uri = Uri.parse(originalUrl);
      final pathParts = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (pathParts.isEmpty) return null;

      // 提取 fileId（最后一部分，去掉 ! 后缀）
      final lastPart = pathParts.last;
      final fileId = lastPart.split('!').first;

      if (fileId.isEmpty || !RegExp(r'^[a-z0-9]+$', caseSensitive: false).hasMatch(fileId)) {
        return null;
      }

      // 确定路径前缀（注意：有单数 note 和复数 notes 两种形式）
      String prefix = '';
      if (pathParts.contains('notes_pre_post')) {
        prefix = 'notes_pre_post/';
      } else if (pathParts.contains('note_pre_post_uhdr')) {
        prefix = 'note_pre_post_uhdr/';
      } else if (pathParts.contains('notes_uhdr')) {
        prefix = 'notes_uhdr/';
      }

      return 'https://sns-img-hw.xhscdn.com/$prefix$fileId?imageView2/2/w/0/format/jpg';
    } catch (_) {
      return null;
    }
  }

  /// 提取背景音乐信息
  /// 返回 (musicUrl, musicTitle)
  ({String? musicUrl, String? musicTitle}) _extractMusicInfo(Map<String, dynamic> note) {
    // 小红书音乐字段可能在不同位置
    // 1. 直接在 note.music
    final music = note['music'];
    if (music is Map) {
      final url = music['url']?.toString() ??
                  music['playUrl']?.toString() ??
                  music['path']?.toString();
      final title = music['title']?.toString() ??
                    music['name']?.toString();
      if (url != null && url.isNotEmpty) {
        return (musicUrl: url, musicTitle: title);
      }
    }

    // 2. 在 note.bgm
    final bgm = note['bgm'];
    if (bgm is Map) {
      final url = bgm['url']?.toString() ??
                  bgm['playUrl']?.toString() ??
                  bgm['path']?.toString();
      final title = bgm['title']?.toString() ??
                    bgm['name']?.toString();
      if (url != null && url.isNotEmpty) {
        return (musicUrl: url, musicTitle: title);
      }
    }

    // 3. 在 note.audio
    final audio = note['audio'];
    if (audio is Map) {
      final url = audio['url']?.toString() ??
                  audio['playUrl']?.toString() ??
                  audio['path']?.toString();
      final title = audio['title']?.toString() ??
                    audio['name']?.toString();
      if (url != null && url.isNotEmpty) {
        return (musicUrl: url, musicTitle: title);
      }
    }

    return (musicUrl: null, musicTitle: null);
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

    String? bestVideoUrl;
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
        bestVideoUrl = url;

        bestWidth ??= (bestStream['width'] as num?)?.toInt();
        bestHeight ??= (bestStream['height'] as num?)?.toInt();
      }
    }

    if (bestVideoUrl == null) return null;

    // 默认使用第一个质量的URL，如果失败再尝试切换CDN
    var bestUrl = bestVideoUrl;

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

      return _VideoInfoResult(
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

/// 视频信息结果
class _VideoInfoResult {
  final String videoUrl;
  final int? width;
  final int? height;
  final bool isLivePhoto;
  final List<String>? livePhotoUrls; // 所有实况图视频 URL

  _VideoInfoResult({
    required this.videoUrl,
    this.width,
    this.height,
    this.isLivePhoto = false,
    this.livePhotoUrls,
  });
}
