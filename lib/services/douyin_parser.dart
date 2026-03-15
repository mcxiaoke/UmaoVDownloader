import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'app_logger.dart';
import 'parser_common.dart';

/// 抖音作品类型枚举
enum DouyinMediaType {
  video, // 视频
  image, // 图文/图集
  unknown, // 未知
}

/// aweme_type 类型判断工具 - 抖音特有
class AwemeTypeHelper {
  /// 视频类型 aweme_type 值列表
  static const videoTypes = {0, 4, 51, 55, 58, 61, 109, 201};

  /// 图文类型 aweme_type 值列表
  static const imageTypes = {2, 68, 150};

  /// 根据 aweme_type 判断是否为视频
  static bool isVideo(dynamic awemeType) {
    if (awemeType == null) return false;
    final type = awemeType is int ? awemeType : int.tryParse(awemeType.toString());
    if (type == null) return false;
    return videoTypes.contains(type);
  }

  /// 根据 aweme_type 判断是否为图文
  static bool isImage(dynamic awemeType) {
    if (awemeType == null) return false;
    final type = awemeType is int ? awemeType : int.tryParse(awemeType.toString());
    if (type == null) return false;
    return imageTypes.contains(type);
  }

  /// 是否为已知的类型（视频或图文）
  static bool isKnownType(dynamic awemeType) {
    return isVideo(awemeType) || isImage(awemeType);
  }

  /// 智能检测作品类型
  static DouyinMediaType detectType(Map<String, dynamic> item) {
    void log(String msg) => AppLogger.debug('[TypeDetector] $msg');

    // 1. 优先使用 aweme_type 判断
    final awemeTypeRaw = item['aweme_type'];
    final awemeType = awemeTypeRaw is int
        ? awemeTypeRaw
        : int.tryParse(awemeTypeRaw?.toString() ?? '');

    if (awemeType != null) {
      if (isVideo(awemeType)) {
        log('aweme_type=$awemeType 判定为视频');
        return DouyinMediaType.video;
      }
      if (isImage(awemeType)) {
        log('aweme_type=$awemeType 判定为图文');
        return DouyinMediaType.image;
      }
      log('未知 aweme_type=$awemeType，进入兜底判断');
    } else {
      log('无 aweme_type，进入兜底判断');
    }

    // 2. 兜底：综合特征判断
    final video = item['video'];
    final images = item['images'];

    // 特征 1：images 字段存在且非空 → 图文
    if (images is List && images.isNotEmpty) {
      log('images 字段存在且非空，判定为图文');
      return DouyinMediaType.image;
    }

    // 特征 2：video.play_addr.uri 以 http 开头 → 图文（实况图/音频）
    if (video is Map) {
      final playAddr = video['play_addr'];
      if (playAddr is Map) {
        final uri = playAddr['uri']?.toString();
        if (uri != null && uri.startsWith('http')) {
          log('video.play_addr.uri 为 URL 格式，判定为图文');
          return DouyinMediaType.image;
        }
      }
    }

    // 特征 3：video.duration 为 0 或 null，且 images 为空 → 可能是图文
    if (video is Map) {
      final duration = video['duration'];
      final durationMs = duration is int ? duration : int.tryParse(duration?.toString() ?? '');
      if ((durationMs == null || durationMs == 0) && (images == null || (images is List && images.isEmpty))) {
        final bitRate = video['bit_rate'];
        if (bitRate == null || (bitRate is List && bitRate.isEmpty)) {
          log('duration=0 且无码率信息，判定为图文');
          return DouyinMediaType.image;
        }
      }
    }

    // 默认判定为视频
    log('无图文特征，默认判定为视频');
    return DouyinMediaType.video;
  }
}

/// 抖音视频解析器
///
/// 流程：短链接 → 跟随重定向 → 提取 videoId → 抓取分享页 HTML → 提取 _ROUTER_DATA JSON
///
/// 不依赖任何需要 Cookie / Token 的 API，直接从页面内嵌 JSON 中解析。
class DouyinParser with HttpParserMixin {
  // 分享页必须用手机 UA，否则服务端返回 SPA 壳而非真实数据
  static const _mobileUA =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

  static const _referer = 'https://www.douyin.com/';

  // 无水印播放接口模板
  static const _playBase = 'https://aweme.snssdk.com/aweme/v1/play/';
  static const _routerDataMarker = 'window._ROUTER_DATA = ';

  /// [httpClient] 可传入 mock client 方便单元测试
  DouyinParser({http.Client? httpClient}) {
    initHttpParser(client: httpClient, logPrefix: '[DouyinParser]');
  }

  /// 主入口：传入任意抖音链接，返回视频信息
  Future<VideoInfo> parse(String url) async {
    final extracted = UrlUtils.extractUrl(url);

    // 从原始缓存短链 ID
    final shareId = _extractShareId(extracted);
    final realUrl = await _resolveUrl(extracted);
    final query = Uri.parse(realUrl).hasQuery
        ? '?${Uri.parse(realUrl).query}'
        : '';
    final videoId = _extractVideoId(realUrl);
    if (videoId == null) {
      throw DouyinParseException('无法从链接中提取视频 ID，最终 URL: $realUrl');
    }
    final isNote = realUrl.contains('/note/');
    return await _parseSharePage(
      videoId,
      shareId: shareId,
      isNote: isNote,
      query: query,
    );
  }

  /// 从抖音 URL 提取 shareId
  String? _extractShareId(String url) {
    final match = RegExp(r'v\.douyin\.com/([A-Za-z0-9_-]+)').firstMatch(url);
    return match?.group(1);
  }

  /// 手动跟随重定向，返回最终落地 URL
  Future<String> _resolveUrl(String url) async {
    return resolveUrlManually(
      url,
      userAgent: _mobileUA,
      referer: _referer,
    );
  }

  /// 从 URL 中提取 videoId（/video/xxx 或 /note/xxx）
  String? _extractVideoId(String url) {
    return RegExp(r'/(?:video|note|slides)/(\d+)').firstMatch(url)?.group(1);
  }

  /// 抓取 iesdouyin 分享页，从内嵌 JSON 中解析视频信息
  Future<VideoInfo> _parseSharePage(
    String videoId, {
    String? shareId,
    bool isNote = false,
    String query = '',
  }) async {
    final segment = isNote ? 'note' : 'video';
    final shareUrl = 'https://www.iesdouyin.com/share/$segment/$videoId/$query';

    final response = await httpClient.get(
      Uri.parse(shareUrl),
      headers: {HttpHeaders.userAgentHeader: _mobileUA, 'Referer': _referer},
    );
    if (response.statusCode != 200) {
      throw DouyinParseException('分享页请求失败，状态码: ${response.statusCode}');
    }
    final html = response.body;

    if (_looksLikeWafChallenge(html)) {
      log('命中风控挑战页: $shareUrl');
      throw const DouyinParseException('触发风控挑战页，请更换网络后重试');
    }

    final item = _extractItemFromRouterData(html);
    if (item != null) {
      return _buildFromRouterItem(
        item,
        fallbackVideoId: videoId,
        shareId: shareId,
      );
    }

    throw DouyinParseException('无法从页面提取 _ROUTER_DATA 数据');
  }

  bool _looksLikeWafChallenge(String html) {
    return html.contains('Please wait...') &&
        (html.contains('waf_js') ||
            html.contains('_wafchallengeid') ||
            html.contains('waf-jschallenge'));
  }

  /// 从 HTML 中提取 window._ROUTER_DATA 的 JSON 数据
  Map<String, dynamic>? _extractItemFromRouterData(String html) {
    final data = JsonExtractor.extractJsonObject(html, _routerDataMarker);
    if (data == null) return null;

    final loader = data['loaderData'];
    if (loader is! Map) return null;

    for (final entry in loader.entries) {
      if (!entry.key.toString().contains('/page')) continue;
      final page = entry.value;
      if (page is! Map) continue;
      final videoInfoRes = page['videoInfoRes'];
      if (videoInfoRes is! Map) continue;
      final itemList = videoInfoRes['item_list'];
      if (itemList is List && itemList.isNotEmpty && itemList.first is Map) {
        return Map<String, dynamic>.from(itemList.first as Map);
      }
    }
    return null;
  }

  /// 从 _ROUTER_DATA 的 item 构建 VideoInfo
  VideoInfo _buildFromRouterItem(
    Map<String, dynamic> item, {
    required String fallbackVideoId,
    String? shareId,
  }) {
    final id = item['aweme_id']?.toString() ?? fallbackVideoId;
    final title = item['desc']?.toString().trim().isNotEmpty == true
        ? item['desc'].toString()
        : '作品_$id';

    final mediaType = AwemeTypeHelper.detectType(item);

    return switch (mediaType) {
      DouyinMediaType.image => _buildImagePost(item, id, title, shareId),
      DouyinMediaType.video => _buildVideoPost(item, id, title, shareId),
      DouyinMediaType.unknown => _buildVideoPost(item, id, title, shareId),
    };
  }

  /// 构建图文作品
  VideoInfo _buildImagePost(
    Map<String, dynamic> item,
    String id,
    String title,
    String? shareId,
  ) {
    final images = item['images'];
    final imageUrls = <String>[];
    final imageThumbUrls = <String>[];

    if (images is List) {
      for (final img in images) {
        if (img is! Map) continue;
        final urlList = img['url_list'];
        if (urlList is! List || urlList.isEmpty) continue;

        // 找大图：优先 lqen-new（无水印）> aweme-images
        String? fullUrl;
        for (final u in urlList) {
          final s = u.toString();
          if (s.contains('tplv-dy-lqen-new') && !s.contains('-water')) {
            fullUrl = s;
            break;
          }
        }
        fullUrl ??= urlList
            .map((e) => e.toString())
            .firstWhere(
              (u) => u.contains('tplv-dy-aweme-images'),
              orElse: () => urlList.first.toString(),
            );

        // 找缩略图：优先 shrink:480 > shrink:960
        String? thumbUrl;
        for (final u in urlList) {
          final s = u.toString();
          if (s.contains('tplv-dy-shrink:480')) {
            thumbUrl = s;
            break;
          }
        }
        if (thumbUrl == null) {
          for (final u in urlList) {
            final s = u.toString();
            if (s.contains('tplv-dy-shrink:960')) {
              thumbUrl = s;
              break;
            }
          }
        }
        thumbUrl ??= fullUrl;

        imageUrls.add(fullUrl);
        imageThumbUrls.add(thumbUrl);
      }
    }

    // 提取背景音乐
    String? musicUrl;
    String? musicTitle;
    String? musicAuthor;
    final music = item['music'];
    final video = item['video'];

    if (music is Map) {
      musicTitle = music['title']?.toString();
      musicAuthor = music['author']?.toString();
      final playUrl = music['play_url'];
      if (playUrl is Map) {
        final list = playUrl['url_list'];
        if (list is List && list.isNotEmpty) {
          final url = list.first.toString();
          if (url.startsWith('http')) {
            musicUrl = url;
          }
        }
      }
    }

    // 降级：某些图文数据中音频放在 video.play_addr.uri
    if (musicUrl == null || musicUrl.isEmpty) {
      final playAddr = video is Map ? video['play_addr'] : null;
      final uri = playAddr is Map ? playAddr['uri']?.toString() : null;
      if (uri != null && uri.startsWith('http')) {
        musicUrl = uri;
      }
    }

    // 提取封面
    String? coverUrl;
    if (video is Map) {
      final cover = video['cover'];
      if (cover is Map) {
        final urlList = cover['url_list'];
        if (urlList is List && urlList.isNotEmpty) {
          coverUrl = urlList.first?.toString();
        }
      }
    }

    return VideoInfo(
      itemId: id,
      title: title,
      videoFileId: '',
      videoUrl: '',
      mediaType: MediaType.image,
      coverUrl: coverUrl,
      shareId: shareId,
      imageUrls: imageUrls,
      imageThumbUrls: imageThumbUrls,
      musicUrl: musicUrl,
      musicTitle: musicTitle,
      musicAuthor: musicAuthor,
    );
  }

  /// 构建视频作品
  VideoInfo _buildVideoPost(
    Map<String, dynamic> item,
    String id,
    String title,
    String? shareId,
  ) {
    final video = item['video'];
    String? coverUrl;
    int? width;
    int? height;
    int? bitrateKbps;
    String? bestVideoUrl;
    String? bestVideoFileId;

    if (video is Map) {
      final cover = video['cover'];
      if (cover is Map) {
        final urlList = cover['url_list'];
        if (urlList is List && urlList.isNotEmpty) {
          coverUrl = urlList.first?.toString();
        }
      }
      width = int.tryParse(video['width']?.toString() ?? '');
      height = int.tryParse(video['height']?.toString() ?? '');

      final bitRates = video['bit_rate'];
      if (bitRates is List && bitRates.isNotEmpty) {
        final best = bitRates.first;
        if (best is Map) {
          final bps = int.tryParse(best['bit_rate']?.toString() ?? '');
          if (bps != null && bps > 0) bitrateKbps = bps ~/ 1000;

          final playAddr = best['play_addr'];
          final uri = playAddr is Map ? playAddr['uri']?.toString() : null;
          if (uri != null && uri.isNotEmpty) {
            bestVideoFileId = uri;
            bestVideoUrl = '$_playBase?video_id=$uri&ratio=1080p&line=0';
          }
        }
      }

      // 备用
      if (bestVideoUrl == null) {
        final playAddr = video['play_addr'];
        final uri = playAddr is Map ? playAddr['uri']?.toString() : null;
        if (uri != null && uri.isNotEmpty) {
          bestVideoFileId = uri;
          bestVideoUrl = '$_playBase?video_id=$uri&ratio=1080p&line=0';
        }
      }
    }

    if (bestVideoUrl == null) {
      throw DouyinParseException('分享页中未找到视频地址，页面结构可能已变更');
    }

    return VideoInfo(
      itemId: id,
      title: title,
      videoFileId: bestVideoFileId ?? '',
      videoUrl: bestVideoUrl,
      mediaType: MediaType.video,
      coverUrl: coverUrl,
      shareId: shareId,
      width: width,
      height: height,
      bitrateKbps: bitrateKbps,
    );
  }

  /// 释放资源
  void dispose() => disposeHttpParser();
}
