import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// 视频清晰度枚举（ratio 参数值即为实际传参字符串）
enum VideoQuality {
  p360('360p'),
  p480('480p'),
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

/// 解析视频信息的结果
class VideoInfo {
  final String videoId;
  final String title;

  /// video_id 参数（用于构造 play URL，如 v0200fg10000xxxxxx）
  final String videoFileId;

  /// 视频播放 URL（无水印，已自动选择最高质量）
  final String videoUrl;

  final String? coverUrl;

  /// 原始短链接中的分享 ID，如 v.douyin.com/jjA4YdaFphk/ 中的 jjA4YdaFphk
  /// 每条视频唯一，可直接拼回原始分享页，优先用于文件命名
  final String? shareId;

  /// 视频原始宽高（像素），从分享页 HTML 解析，可能为 null
  final int? width;
  final int? height;

  /// 视频码率（kbps），从分享页 bit_rate 数组解析，可能为 null
  final int? bitrateKbps;

  /// 图文作品的图片 URL 列表（按原始顺序，已去除头像等无关项）
  /// 纯视频作品为空列表
  final List<String> imageUrls;

  /// 图文作品的缩略图 URL 列表（用于预览显示）
  /// 如果为空，使用 imageUrls 代替
  final List<String> imageThumbUrls;

  /// 图文作品背景音乐的直连 CDN URL（MP3），无背景音乐或视频作品时为 null
  final String? musicUrl;

  /// 背景音乐标题，null 表示无音乐或未能解析
  final String? musicTitle;

  /// 实况图视频 URL 列表（小红书 Live Photo）
  /// 每个实况图对应一个短视频，按顺序下载
  final List<String> livePhotoUrls;

  const VideoInfo({
    required this.videoId,
    required this.title,
    required this.videoFileId,
    required this.videoUrl,
    this.coverUrl,
    this.shareId,
    this.width,
    this.height,
    this.bitrateKbps,
    this.imageUrls = const [],
    this.imageThumbUrls = const [],
    this.musicUrl,
    this.musicTitle,
    this.livePhotoUrls = const [],
  });

  /// 是否为图文作品（无视频但有图片）
  bool get isImagePost => videoUrl.isEmpty && imageUrls.isNotEmpty;

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
      'VideoInfo(id: $videoId, title: $title, resolution: $resolutionLabel)';
}

class DouyinParseException implements Exception {
  final String message;
  const DouyinParseException(this.message);

  @override
  String toString() => 'DouyinParseException: $message';
}

/// 抖音视频解析器
///
/// 流程：短链接 → 跟随重定向 → 提取 videoId → 抓取分享页 HTML → 提取 _ROUTER_DATA JSON
///
/// 不依赖任何需要 Cookie / Token 的 API，直接从页面内嵌 JSON 中解析。
class DouyinParser {
  // 分享页必须用手机 UA，否则服务端返回 SPA 壳而非真实数据
  static const _mobileUA =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

  static const _referer = 'https://www.douyin.com/';

  // 无水印播放接口模板（跳转到 CDN，不含水印）
  static const _playBase = 'https://aweme.snssdk.com/aweme/v1/play/';
  static const _routerDataMarker = 'window._ROUTER_DATA = ';

  /// [httpClient] 可传入 mock client 方便单元测试
  final http.Client _httpClient;

  DouyinParser({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  /// 主入口：传入任意抖音链接，返回视频信息
  Future<VideoInfo> parse(String url) async {
    final extracted =
        RegExp(r'https?://[^\s，,。]+').firstMatch(url)?.group(0) ?? url;

    // 从原始缓存短链 ID（跳转后丢失）
    final shareId = RegExp(
      r'v\.douyin\.com/([A-Za-z0-9_-]+)',
    ).firstMatch(extracted)?.group(1);
    final realUrl = await _resolveUrl(extracted);
    final query = Uri.parse(realUrl).hasQuery
        ? '?${Uri.parse(realUrl).query}'
        : '';
    final videoId = _extractVideoId(realUrl);
    if (videoId == null) {
      throw DouyinParseException('无法从链接中提取视频 ID，最终 URL: $realUrl');
    }
    // 注意区分 /note/ 与 /video/ 类型——iesdouyin 使用不同的分享页路径
    // /slides/ (live 图) 使用 /share/video/ 端点同样可获取完整数据
    final isNote = realUrl.contains('/note/');
    return await _parseSharePage(
      videoId,
      shareId: shareId,
      isNote: isNote,
      query: query,
    );
  }

  /// 手动跟随重定向，返回最终落地 URL
  Future<String> _resolveUrl(String url) async {
    const maxRedirects = 8;
    var currentUri = Uri.parse(url);
    final ioClient = HttpClient();
    try {
      for (var i = 0; i < maxRedirects; i++) {
        final request = await ioClient.getUrl(currentUri);
        request.headers.set(HttpHeaders.userAgentHeader, _mobileUA);
        request.headers.set(HttpHeaders.refererHeader, _referer);
        request.followRedirects = false;

        final response = await request.close();
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
    return currentUri.toString();
  }

  /// 从 URL 中提取 videoId（/video/xxx 或 /note/xxx）
  String? _extractVideoId(String url) {
    // /video/ 普通视频  /note/ 图文  /slides/ live 动图
    return RegExp(r'/(?:video|note|slides)/(\d+)').firstMatch(url)?.group(1);
  }

  /// 抓取 iesdouyin 分享页，从内嵌 JSON 中解析视频信息
  Future<VideoInfo> _parseSharePage(
    String videoId, {
    String? shareId,
    bool isNote = false,
    String? initialHtml,
    String query = '',
  }) async {
    // note 类型使用 /share/note/ 端点，video 类型使用 /share/video/
    final segment = isNote ? 'note' : 'video';
    final shareUrl = 'https://www.iesdouyin.com/share/$segment/$videoId/$query';

    var html = initialHtml ?? '';
    if (!html.contains(_routerDataMarker)) {
      final response = await _httpClient.get(
        Uri.parse(shareUrl),
        headers: {HttpHeaders.userAgentHeader: _mobileUA, 'Referer': _referer},
      );
      if (response.statusCode != 200) {
        throw DouyinParseException('分享页请求失败，状态码: ${response.statusCode}');
      }
      html = response.body;
    }

    if (_looksLikeWafChallenge(html)) {
      stderr.writeln('[DouyinParser] 命中风控挑战页: $shareUrl');
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
    final start = html.indexOf(_routerDataMarker);
    if (start < 0) return null;

    final jsonStart = start + _routerDataMarker.length;
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
      final raw = html.substring(jsonStart, end + 1);
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic>) return null;
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
    } catch (_) {
      return null;
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

    final video = item['video'];
    String? coverUrl;
    int? width;
    int? height;
    int? bitrateKbps;

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
      if (bitRates is List && bitRates.isNotEmpty && bitRates.first is Map) {
        final bps = int.tryParse(
          (bitRates.first as Map)['bit_rate']?.toString() ?? '',
        );
        if (bps != null && bps > 0) bitrateKbps = bps ~/ 1000;
      }
    }

    // 判断是否为图文作品
    final images = item['images'];
    if (images is List && images.isNotEmpty) {
      final imageUrls = <String>[];
      final imageThumbUrls = <String>[];

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

        // 找缩略图：优先 shrink:480 > shrink:960 > 其他小图
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

      // 提取背景音乐
      String? musicUrl;
      String? musicTitle;
      final music = item['music'];
      if (music is Map) {
        musicTitle = music['title']?.toString();
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

      return VideoInfo(
        videoId: id,
        title: title,
        videoFileId: '',
        videoUrl: '',
        coverUrl: coverUrl,
        shareId: shareId,
        width: width,
        height: height,
        bitrateKbps: bitrateKbps,
        imageUrls: imageUrls,
        imageThumbUrls: imageThumbUrls,
        musicUrl: musicUrl,
        musicTitle: musicTitle,
      );
    }

    // 视频作品处理
    String? bestVideoUrl;
    String? bestVideoFileId;

    if (video is Map) {
      final bitRates = video['bit_rate'];
      if (bitRates is List && bitRates.isNotEmpty) {
        // 优先选择最高质量（假设列表已按质量排序，取第一个）
        final best = bitRates.first;
        if (best is Map) {
          final playAddr = best['play_addr'];
          final uri = playAddr is Map ? playAddr['uri']?.toString() : null;
          if (uri != null && uri.isNotEmpty) {
            bestVideoFileId = uri;
            bestVideoUrl = '$_playBase?video_id=$uri&ratio=1080p&line=0';
          }
        }
      }

      // 备用：使用 play_addr.uri
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
      videoId: id,
      title: title,
      videoFileId: bestVideoFileId ?? '',
      videoUrl: bestVideoUrl,
      coverUrl: coverUrl,
      shareId: shareId,
      width: width,
      height: height,
      bitrateKbps: bitrateKbps,
    );
  }

  void dispose() => _httpClient.close();
}
