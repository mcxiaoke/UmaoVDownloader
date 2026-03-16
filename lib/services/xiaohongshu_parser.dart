import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'parser_common.dart';

/// 视频流信息 - 小红书特有
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

/// 视频信息结果 - 小红书特有
class _VideoInfoResult {
  final String videoUrl;
  final int? width;
  final int? height;
  final bool isLivePhoto;
  final List<String>? livePhotoUrls;

  _VideoInfoResult({
    required this.videoUrl,
    this.width,
    this.height,
    this.isLivePhoto = false,
    this.livePhotoUrls,
  });
}

/// 小红书解析器
///
/// 流程：分享链接 → 跟随重定向 → 提取 __INITIAL_STATE__ → 解析笔记数据
class XiaohongshuParser with HttpParserMixin {
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

  XiaohongshuParser({http.Client? client}) {
    initHttpParser(client: client, logPrefix: '[XHS]');
  }

  /// 解析小红书分享链接
  Future<VideoInfo> parse(String input) async {
    log('开始解析: $input');

    final extracted = UrlUtils.extractUrl(input);
    logDebug('提取URL: $extracted');

    final shareId = _extractShareId(extracted);
    log('  shareId: $shareId');

    log('→ 请求页面...');
    final (:html, :finalUrl) = await _resolveXhsUrl(extracted);
    logDebug('  最终URL: $finalUrl');
    log('  HTML长度: ${html.length} bytes');

    log('→ 提取 __INITIAL_STATE__...');
    var data = _extractInitialState(html);

    if (data == null) {
      log('  未找到 __INITIAL_STATE__, 尝试 SSR 数据...');
      data = _extractSsrData(html);
    }

    if (data == null) {
      throw const XiaohongshuParseException('未找到 __INITIAL_STATE__ 或 SSR 数据');
    }
    log('  ✓ 数据提取成功');

    log('→ 提取笔记数据...');
    final note = _extractNoteData(data);
    if (note == null || note.isEmpty) {
      throw const XiaohongshuParseException('无法提取笔记数据');
    }
    final noteId = note['noteId'] ?? note['id'];
    if (noteId == null) {
      throw const XiaohongshuParseException('笔记数据无效，可能是链接已失效');
    }
    // 保存 note 数据用于调试
    _saveDebugJson(note, 'note_data', shareId: shareId);
    final title = (note['title'] ?? note['desc'] ?? '').toString().trim();
    final hasVideo = note['video'] != null && note['video'] is Map;
    final type = hasVideo
        ? 'video'
        : note['imageList'] != null
        ? 'image'
        : 'unknown';
    log(
      '  ✓ noteId: $noteId, title: ${title.isEmpty ? "<无标题>" : title}, type: $type',
    );

    final result = await _buildResult(note, shareId: shareId);

    final resultType = result.videoUrl.isNotEmpty
        ? 'video'
        : result.imageUrls.isNotEmpty
        ? 'image'
        : 'unknown';
    log('→ 构建结果: type=$resultType, imageCount=${result.imageUrls.length}');

    // 验证结果有效性：既没有视频也没有图片，说明解析失败
    if (result.videoUrl.isEmpty && result.imageUrls.isEmpty) {
      throw const XiaohongshuParseException('无法获取有效的媒体内容，可能是链接无效或已被删除');
    }
    // URL 只在详细日志模式下打印
    if (result.videoUrl.isNotEmpty) {
      logDebug('  videoUrl: ${result.videoUrl}');
    }
    if (result.videoUrlNoWatermark != null) {
      logDebug('  videoUrlNoWatermark: ${result.videoUrlNoWatermark}');
    }
    if (result.imageUrls.isNotEmpty) {
      logDebug('  imageUrls[0]: ${result.imageUrls[0]}');
      for (var i = 0; i < result.imageUrls.length; i++) {
        final thumb = result.imageThumbUrls.length > i
            ? result.imageThumbUrls[i]
            : result.imageUrls[i];
        final full = result.imageUrls[i];
        logDebug('thumb${i + 1}=$thumb');
        logDebug('full${i + 1}=$full');
      }
    }

    return result;
  }

  /// 从 URL 中提取 shareId
  ///
  /// 支持格式：
  /// - 短链接: xhslink.com/o/xxxxx
  /// - 长链接: xiaohongshu.com/explore/xxxxx
  String? _extractShareId(String url) {
    // 短链接格式
    final shortMatch = RegExp(
      r'xhslink\.com/o/([A-Za-z0-9_-]+)',
    ).firstMatch(url);
    if (shortMatch != null) return shortMatch.group(1);

    // 长链接格式: /explore/xxxxx 或 /discovery/item/xxxxx
    final longMatch = RegExp(
      r'xiaohongshu\.com/(?:explore|discovery/item)/([a-z0-9]+)',
    ).firstMatch(url);
    if (longMatch != null) return longMatch.group(1);

    return null;
  }

  /// 跟随重定向获取真实 URL 和 HTML
  Future<({String html, String finalUrl})> _resolveXhsUrl(String url) async {
    final uri = Uri.parse(url);
    final request = await httpClient.get(uri, headers: _headers);

    if (request.statusCode >= 300 && request.statusCode < 400) {
      final location = request.headers['location'];
      if (location != null) {
        return _resolveXhsUrl(location);
      }
    }

    return (
      html: request.body,
      finalUrl: request.request?.url.toString() ?? url,
    );
  }

  /// 从 HTML 中提取 __INITIAL_STATE__
  Map<String, dynamic>? _extractInitialState(String html) {
    return _extractInitialStateJson(html);
  }

  /// 使用 JSON 解析提取 __INITIAL_STATE__
  Map<String, dynamic>? _extractInitialStateJson(String html) {
    final result = JsonExtractor.extractJsonWithRegex(
      html,
      r'window\.__INITIAL_STATE__\s*=\s*(\{[\s\S]*?\})(?:;|\s*</script>)',
      cleanUndefined: true,
    );

    return result.data;
  }

  /// 保存调试 JSON 到下载目录（仅桌面平台）
  void _saveDebugJson(Map<String, dynamic> data, String prefix, {String? shareId}) {
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) return;

    try {
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final idPrefix = shareId != null ? '${shareId}_' : '';
      final downloadDir = getDebugOutputDir();

      final dir = Directory(downloadDir);
      dir.createSync(recursive: true);

      final file = File(
        '${dir.path}${Platform.pathSeparator}xhs_$idPrefix${prefix}_$timestamp.json',
      );
      final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
      file.writeAsStringSync(jsonStr, encoding: utf8);
      log('  调试 JSON 已保存: ${file.path}');
    } catch (e) {
      log('  保存调试 JSON 失败: $e');
    }
  }

  /// 尝试从 SSR 渲染的 HTML 中提取数据
  Map<String, dynamic>? _extractSsrData(String html) {
    final pattern =
        '<script[^>]*id=["\']ssr-data["\'][^>]*>([\\s\\S]*?)</script>';
    final match = RegExp(pattern).firstMatch(html);
    if (match == null) return null;

    final jsonStr = match.group(1)!;

    try {
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
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

    // 备用路径
    final note = data['note'];
    if (note is Map) {
      final noteDetailMap = note['noteDetailMap'];
      if (noteDetailMap is Map) {
        final keys = noteDetailMap.keys.toList();
        if (keys.isNotEmpty) {
          final noteItem = noteDetailMap[keys.first];
          if (noteItem is Map) {
            final actualNote = noteItem['note'];
            if (actualNote is Map<String, dynamic>) return actualNote;
            if (noteItem['noteId'] != null || noteItem['id'] != null) {
              return Map<String, dynamic>.from(noteItem);
            }
          }
        }
      }
    }

    return null;
  }

  /// 构建无水印视频 URL（通过替换 CDN 域名实现）
  ///
  /// 原理：将视频 CDN 域名从火山引擎(hs)替换为华为云(hw)，可能获得无水印版本
  /// - 有水印: sns-video-hs.xhscdn.com (火山引擎)
  /// - 无水印: sns-video-hw.xhscdn.com (华为云)
  String? _buildNoWatermarkVideoUrl(String originalUrl) {
    try {
      final uri = Uri.parse(originalUrl);
      final host = uri.host;

      // 只处理小红书的视频 CDN 域名
      if (!host.contains('xhscdn.com')) return null;

      // 将视频 CDN 域名中的 -hs- 替换为 -hw- (火山引擎->华为云)
      // 例如: sns-video-hs.xhscdn.com -> sns-video-hw.xhscdn.com
      final newHost = host.replaceFirst(
        RegExp(r'sns-video-([a-z]+)'),
        'sns-video-hw',
      );
      final newUri = uri.replace(host: newHost);

      return newUri.toString();
    } catch (_) {
      return null;
    }
  }

  /// 构建统一的结果对象
  Future<VideoInfo> _buildResult(
    Map<String, dynamic> note, {
    String? shareId,
  }) async {
    final id = note['noteId']?.toString() ?? note['id']?.toString() ?? '';
    final title = note['title']?.toString() ?? '';
    final desc = note['desc']?.toString() ?? '';

    final coverUrl = _extractCoverUrl(note);
    final imageList = _extractImageUrls(note);
    final imageUrls = imageList.map((i) => i['full']!).toList();
    final imageThumbUrls = imageList.map((i) => i['thumb']!).toList();

    final hasVideoField = note['video'] != null && note['video'] is Map;

    final videoInfo = await _extractVideoInfo(note);
    final isLivePhoto = videoInfo?.isLivePhoto ?? false;
    final hasVideoStream = videoInfo?.videoUrl.isNotEmpty ?? false;

    // 合并日志：hasVideoField, hasVideoStream, isLivePhoto
    final liveCount = videoInfo?.livePhotoUrls?.where((u) => u.isNotEmpty).length ?? 0;
    log('  hasVideoField: $hasVideoField, hasVideoStream: $hasVideoStream, isLivePhoto: $isLivePhoto${isLivePhoto ? ', liveCount: $liveCount' : ''}');

    final displayTitle = title.isNotEmpty
        ? title
        : desc.substring(0, desc.length.clamp(0, 50));

    // 构建无水印 URL（仅对普通视频）
    String? noWatermarkUrl;
    if (videoInfo?.videoUrl.isNotEmpty == true && !isLivePhoto) {
      noWatermarkUrl = _buildNoWatermarkVideoUrl(videoInfo!.videoUrl);
      if (noWatermarkUrl != null) {
        logDebug('  原始URL: ${videoInfo.videoUrl}');
        logDebug('  无水印URL: $noWatermarkUrl');
      }
    }

    // 确定媒体类型
    final MediaType mediaType;
    if (isLivePhoto) {
      mediaType = MediaType.livePhoto;
    } else if (hasVideoField) {
      mediaType = MediaType.video;
    } else if (imageUrls.isNotEmpty) {
      mediaType = MediaType.image;
    } else {
      mediaType = MediaType.video; // 默认
    }

    return _createVideoInfo(
      id: id,
      title: displayTitle,
      note: note,
      shareId: shareId,
      coverUrl: coverUrl,
      imageUrls: imageUrls,
      imageThumbUrls: imageThumbUrls,
      mediaType: mediaType,
      videoUrl: videoInfo?.videoUrl ?? '',
      videoUrlNoWatermark: noWatermarkUrl,
      width: videoInfo?.width ?? note['width'] as int?,
      height: videoInfo?.height ?? note['height'] as int?,
      livePhotoUrls: videoInfo?.livePhotoUrls ?? const [],
    );
  }

  /// 创建 VideoInfo 对象（统一构造）
  VideoInfo _createVideoInfo({
    required String id,
    required String title,
    required Map<String, dynamic> note,
    String? shareId,
    String? coverUrl,
    required List<String> imageUrls,
    required List<String> imageThumbUrls,
    required MediaType mediaType,
    required String videoUrl,
    String? videoUrlNoWatermark,
    int? width,
    int? height,
    List<String> livePhotoUrls = const [],
  }) {
    final author = _extractAuthorInfo(note);
    final stats = _extractInteractInfo(note);

    return VideoInfo(
      itemId: id,
      title: title,
      videoFileId: mediaType == MediaType.image ? '' : id,
      videoUrl: videoUrl,
      videoUrlNoWatermark: videoUrlNoWatermark,
      mediaType: mediaType,
      platform: ParserPlatform.xiaohongshu,
      coverUrl: coverUrl,
      shareId: shareId,
      width: width,
      height: height,
      imageUrls: imageUrls,
      imageThumbUrls: imageThumbUrls,
      livePhotoUrls: livePhotoUrls,
      authorId: author.id,
      authorName: author.name,
      authorAvatar: author.avatar,
      createTime: stats.createTime,
      likeCount: stats.likeCount,
      collectCount: stats.collectCount,
      commentCount: stats.commentCount,
      shareCount: stats.shareCount,
    );
  }

  /// 提取作者信息
  ({String? id, String? name, String? avatar}) _extractAuthorInfo(
    Map<String, dynamic> note,
  ) {
    final user = note['user'];
    if (user is! Map) return (id: null, name: null, avatar: null);

    return (
      id: user['userId']?.toString(),
      name: user['nickName']?.toString(),
      avatar: user['avatar']?.toString(),
    );
  }

  /// 提取互动统计信息
  ({
    int? createTime,
    int? likeCount,
    int? collectCount,
    int? commentCount,
    int? shareCount,
  })
  _extractInteractInfo(Map<String, dynamic> note) {
    // 发布时间（毫秒）
    final createTimeRaw = note['time'];
    final createTime = createTimeRaw is int
        ? createTimeRaw
        : int.tryParse(createTimeRaw?.toString() ?? '');

    final interact = note['interactInfo'];
    if (interact is! Map) {
      return (
        createTime: createTime,
        likeCount: null,
        collectCount: null,
        commentCount: null,
        shareCount: null,
      );
    }

    return (
      createTime: createTime,
      likeCount: _parseInt(interact['likedCount']),
      collectCount: _parseInt(interact['collectedCount']),
      commentCount: _parseInt(interact['commentCount']),
      shareCount: _parseInt(interact['shareCount']),
    );
  }

  int? _parseInt(dynamic value) {
    if (value is int) return value;
    final s = value?.toString();
    if (s == null || s.isEmpty) return null;
    return int.tryParse(s);
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
  List<Map<String, String>> _extractImageUrls(Map<String, dynamic> note) {
    final imageList = note['imageList'] ?? note['images'];
    if (imageList is! List) return [];

    return imageList
        .map((img) {
          if (img is! Map) return null;

          String? thumbUrl;
          String? fullOrigUrl;
          String? fullNoWaterUrl;

          final infoList = img['infoList'];
          if (infoList is List && infoList.isNotEmpty) {
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
            if (fullOrigUrl == null) {
              final dftMatch = infoList.cast<Map<String, dynamic>>().firstWhere(
                (i) =>
                    (i['imageScene'] as String?)?.contains('DFT') == true &&
                    i['url'] is String,
                orElse: () => {},
              );
              if (dftMatch.isNotEmpty) {
                fullOrigUrl = dftMatch['url'];
              }
            }

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

          if (fullOrigUrl != null) {
            fullNoWaterUrl = _buildNoWatermarkUrl(fullOrigUrl);
          }

          final fullUrl = fullNoWaterUrl ?? fullOrigUrl;
          // 缩略图：优先使用无水印 URL 的缩略版本（避免移动端返回的劣化图）
          // 无水印 URL 格式: https://sns-img-hw.xhscdn.com/{fileId}?imageView2/2/w/0/format/jpg
          // 缩略图修改 w/0 为 w/540
          final thumb = fullNoWaterUrl != null
              ? fullNoWaterUrl.replaceFirst('w/0', 'w/540')
              : (thumbUrl ?? fullUrl);

          if (fullUrl == null && thumb == null) return null;

          return {'thumb': thumb ?? fullUrl!, 'full': fullUrl ?? thumb!};
        })
        .whereType<Map<String, String>>()
        .toList();
  }

  /// 构建无水印图片 URL - 小红书特有
  String? _buildNoWatermarkUrl(String originalUrl) {
    try {
      final uri = Uri.parse(originalUrl);
      final pathParts = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (pathParts.isEmpty) return null;

      final lastPart = pathParts.last;
      final fileId = lastPart.split('!').first;

      if (fileId.isEmpty ||
          !RegExp(r'^[a-z0-9]+$', caseSensitive: false).hasMatch(fileId)) {
        return null;
      }

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

  /// 提取实况图视频 URL 列表 - 小红书特有
  /// 返回与 imageList 索引对应的列表，非实况图的项为空字符串
  List<String> _extractLivePhotoUrls(Map<String, dynamic> note) {
    final imageList = note['imageList'] ?? note['images'];
    if (imageList is! List) return [];

    final urls = <String>[];
    for (final img in imageList) {
      if (img is! Map) {
        urls.add('');
        continue;
      }

      // 检查是否为实况图
      if (img['livePhoto'] != true) {
        urls.add('');
        continue;
      }

      final stream = img['stream'];
      if (stream is! Map) {
        urls.add('');
        continue;
      }

      final formats = ['h264', 'h265', 'hevc', 'av1'];
      String? videoUrl;
      for (final fmt in formats) {
        final streams = stream[fmt];
        if (streams is List && streams.isNotEmpty) {
          final first = streams.first;
          if (first is Map) {
            videoUrl =
                first['masterUrl']?.toString() ?? first['url']?.toString();
            if (videoUrl != null) break;
          }
        }
      }

      if (videoUrl != null) {
        urls.add(videoUrl);
      } else {
        urls.add('');
      }
    }
    return urls;
  }

  /// 提取视频信息 - 小红书特有（含 CDN 切换逻辑）
  Future<_VideoInfoResult?> _extractVideoInfo(Map<String, dynamic> note) async {
    final video = note['video'];
    if (video is! Map) {
      final livePhotoUrls = _extractLivePhotoUrls(note);
      // 过滤出非空的实况图视频 URL
      final nonEmptyUrls = livePhotoUrls.where((u) => u.isNotEmpty).toList();
      if (nonEmptyUrls.isNotEmpty) {
        return _VideoInfoResult(
          videoUrl: nonEmptyUrls.first,
          isLivePhoto: true,
          livePhotoUrls: livePhotoUrls, // 保留与 imageUrls 索引对应的完整列表
        );
      }
      return null;
    }

    final media = video['media'];
    if (media is! Map) {
      log('  video.media 为空');
      return null;
    }

    final stream = media['stream'];
    if (stream is! Map) {
      log('  video.media.stream 为空');
      return null;
    }

    log('  视频流格式: ${stream.keys.join(', ')}');

    String? bestVideoUrl;
    final candidateUrls = <_VideoStream>[];

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

      var bestStream = streams.first;
      var bestBitrate = 0;

      for (final s in streams) {
        if (s is! Map) continue;
        final bitrate = (s['videoBitrate'] as num?)?.toInt() ?? 0;
        if (bitrate > bestBitrate) {
          bestBitrate = bitrate;
          bestStream = s;
        }

        final url = s['masterUrl']?.toString() ?? s['url']?.toString();
        if (url != null) {
          candidateUrls.add(
            _VideoStream(
              url: url,
              bitrate: bitrate,
              size: (s['size'] as num?)?.toInt(),
              width: (s['width'] as num?)?.toInt(),
              height: (s['height'] as num?)?.toInt(),
              codec: format.key,
            ),
          );
        }
      }

      final url =
          bestStream['masterUrl']?.toString() ?? bestStream['url']?.toString();
      if (url != null) {
        bestVideoUrl = url;
        bestWidth ??= (bestStream['width'] as num?)?.toInt();
        bestHeight ??= (bestStream['height'] as num?)?.toInt();
      }
    }

    if (bestVideoUrl == null) return null;

    // 如果 bestStream 没有 width/height，从 candidateUrls 中找
    if (bestWidth == null || bestHeight == null) {
      for (final c in candidateUrls) {
        if (c.width != null && c.height != null) {
          bestWidth = c.width;
          bestHeight = c.height;
          break;
        }
      }
    }

    var bestUrl = bestVideoUrl;

    if (candidateUrls.isNotEmpty) {
      logDebug('  视频流信息:');
      final sorted = [...candidateUrls]
        ..sort((a, b) => (b.size ?? 0) - (a.size ?? 0));
      for (var i = 0; i < sorted.length.clamp(0, 5); i++) {
        final c = sorted[i];
        final sizeMB = c.size != null
            ? '${(c.size! / 1024 / 1024).toStringAsFixed(2)}MB'
            : 'unknown';
        log('    ${c.codec}: ${c.width}x${c.height}, ${c.bitrate}bps, $sizeMB');
        logDebug('      ${c.url}');
      }
    }

    return _VideoInfoResult(
      videoUrl: bestUrl,
      width: bestWidth,
      height: bestHeight,
    );
  }

  /// 释放资源
  void dispose() => disposeHttpParser();
}
