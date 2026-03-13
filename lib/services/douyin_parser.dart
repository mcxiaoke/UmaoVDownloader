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

  /// 各清晰度对应的播放 URL（无水印）
  /// key = VideoQuality，value = aweme/v1/play/... URL（跟随重定向后为 CDN 地址）
  final Map<VideoQuality, String> qualityUrls;

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

  /// 图文作品背景音乐的直连 CDN URL（MP3），无背景音乐或视频作品时为 null
  final String? musicUrl;

  /// 背景音乐标题，null 表示无音乐或未能解析
  final String? musicTitle;

  const VideoInfo({
    required this.videoId,
    required this.title,
    required this.videoFileId,
    required this.qualityUrls,
    this.coverUrl,
    this.shareId,
    this.width,
    this.height,
    this.bitrateKbps,
    this.imageUrls = const [],
    this.musicUrl,
    this.musicTitle,
  });

  /// 是否为图文作品（有图片列表）
  bool get isImagePost => imageUrls.isNotEmpty;

  /// 分辨率标签，如 "1920×1080"、"3840×2160 (4K)"，无数据时返回 null
  String? get resolutionLabel {
    if (width == null || height == null) return null;
    final base = '$width×$height';
    if (height! >= 2160) return '$base (4K)';
    if (height! >= 1440) return '$base (2K)';
    return base;
  }

  /// 当前最佳可用地址（优先最高清晰度）
  String get videoUrl =>
      qualityUrls[VideoQuality.p2160] ??
      qualityUrls[VideoQuality.p1080] ??
      qualityUrls[VideoQuality.p720] ??
      qualityUrls[VideoQuality.p480] ??
      qualityUrls[VideoQuality.p360] ??
      qualityUrls.values.first;

  /// 获取指定清晰度地址，不存在则返回最佳地址
  String urlFor(VideoQuality quality) => qualityUrls[quality] ?? videoUrl;

  /// 已解析出的清晰度列表（从高到低）
  List<VideoQuality> get availableQualities {
    const ordered = VideoQuality.values; // 360p..1080p，枚举顺序从低到高
    return ordered.reversed.where((q) => qualityUrls.containsKey(q)).toList();
  }

  @override
  String toString() =>
      'VideoInfo(id: $videoId, title: $title, '
      'qualities: ${availableQualities.map((q) => q.ratio).join(", ")})';
}

class DouyinParseException implements Exception {
  final String message;
  const DouyinParseException(this.message);

  @override
  String toString() => 'DouyinParseException: $message';
}

/// 抖音视频解析器
///
/// 流程：短链接 → 跟随重定向 → 提取 videoId → 抓取分享页 HTML → 正则提取视频地址
///
/// 不依赖任何需要 Cookie / Token 的 API，直接从页面内嵌 JSON 中解析。
class DouyinParser {
  // 分享页必须用手机 UA，否则服务端返回 SPA 壳而非真实数据
  static const _mobileUA =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

  static const _referer = 'https://www.douyin.com/';

  // 从 play_addr.url_list[0] 里找任意 play/playwm URL，提取 video_id 参数
  // 匹配形如: "url_list":["https://...video_id=v0200fg..."]
  static final _playAddrRe = RegExp(
    r'"play_addr(?:_h264)?"\s*:\s*\{[^{}]*"url_list"\s*:\s*\["((?:[^"\\]|\\.)*)"\]',
  );

  // desc 字段
  static final _descRe = RegExp(r'"desc"\s*:\s*"((?:[^"\\]|\\.)*)"');

  // cover.url_list[0]
  static final _coverRe = RegExp(
    r'"cover"\s*:\s*\{[^{}]*"url_list"\s*:\s*\["((?:[^"\\]|\\.)*)"\]',
  );

  // bit_rate 数组第一项的码率值（bps 单位）
  static final _bitrateArrRe = RegExp(
    r'"bit_rate"\s*:\s*\[\s*\{[^{}]*"bit_rate"\s*:\s*(\d+)',
  );

  // 提取 url_list 数组第一个元素（处理 JSON 字符串转义，如 \u002F → /）
  // 分类逻辑由 _extractImageUrls() 的 if/else 承担，无需在此写复杂断言
  static final _urlListFirstRe = RegExp(
    r'"url_list"\s*:\s*\["((?:[^"\\]|\\.)+)"',
  );

  // 图文作品背景音乐：HTML <audio> 标签的 src，直链 CDN MP3
  static final _audioTagRe = RegExp(r'<audio[^>]+src="(https://[^"]+\.mp3)"');

  // music 对象 title 字段（dotAll 跨越嵌套内容）
  static final _musicTitleRe = RegExp(
    r'"music"\s*:\s*\{.*?"title"\s*:\s*"((?:[^"\\]|\\.*)*)"',
    dotAll: true,
  );

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

    // 提取标题
    final rawDesc = _descRe.firstMatch(html)?.group(1);
    final title = (rawDesc != null && rawDesc.isNotEmpty)
        ? _decodeJsonString(rawDesc)
        : '作品_$videoId';

    // 提取封面（可选）
    final rawCover = _coverRe.firstMatch(html)?.group(1);
    final coverUrl = rawCover != null ? _decodeJsonString(rawCover) : null;

    // ── 检测图文作品 ───────────────────────────────────────────
    // 按优先级尝试三种 transform：lqen-new > aweme-images > shrink:1000+
    final imageUrls = _extractImageUrls(html);

    if (imageUrls.isNotEmpty) {
      // 图文作品：提取背景音乐直链（<audio src="...mp3">）及其标题
      final musicUrl = _audioTagRe.firstMatch(html)?.group(1);
      final rawMusicTitle = _musicTitleRe.firstMatch(html)?.group(1);
      final musicTitle = rawMusicTitle != null
          ? _decodeJsonString(rawMusicTitle)
          : null;
      return VideoInfo(
        videoId: videoId,
        title: title,
        videoFileId: '',
        qualityUrls: const {},
        coverUrl: coverUrl,
        shareId: shareId,
        imageUrls: imageUrls,
        musicUrl: musicUrl,
        musicTitle: musicTitle,
      );
    }

    // ── 视频作品 ────────────────────────────────────────────────
    // 从 play_addr 的 URL 里提取 video_id 和 ratio 参数
    final rawPlayUrl = _playAddrRe.firstMatch(html)?.group(1);
    if (rawPlayUrl == null) {
      throw DouyinParseException('分享页中未找到视频地址，页面结构可能已变更');
    }
    final playUrl = _decodeJsonString(rawPlayUrl);
    final parsedPlayUri = Uri.parse(playUrl);
    final videoFileId = parsedPlayUri.queryParameters['video_id'];
    if (videoFileId == null || videoFileId.isEmpty) {
      throw DouyinParseException('无法从播放地址提取 video_id: $playUrl');
    }

    // CDN 实际存在两条独立码流：720p（较小体积）和 1080p（标准质量）
    final qualityUrls = <VideoQuality, String>{
      VideoQuality.p720: '$_playBase?video_id=$videoFileId&ratio=720p&line=0',
      VideoQuality.p1080: '$_playBase?video_id=$videoFileId&ratio=1080p&line=0',
    };

    // 提取视频尺寸：在 play_addr 位置之后搜索，避免匹配到头像等小图
    int? videoWidth, videoHeight;
    final playAddrIdx = html.indexOf('play_addr');
    if (playAddrIdx >= 0) {
      final sub = html.substring(playAddrIdx);
      final hm = RegExp(r'"height"\s*:\s*(\d+)').firstMatch(sub);
      final wm = RegExp(r'"width"\s*:\s*(\d+)').firstMatch(sub);
      final h = hm != null ? int.tryParse(hm.group(1)!) : null;
      final w = wm != null ? int.tryParse(wm.group(1)!) : null;
      if ((h ?? 0) >= 120 && (w ?? 0) >= 120) {
        videoHeight = h;
        videoWidth = w;
      }
    }

    // 提取码率（单位 bps → kbps）
    int? bitrateKbps;
    final brMatch = _bitrateArrRe.firstMatch(html);
    if (brMatch != null) {
      final bps = int.tryParse(brMatch.group(1)!);
      if (bps != null && bps > 0) bitrateKbps = bps ~/ 1000;
    }

    return VideoInfo(
      videoId: videoId,
      title: title,
      videoFileId: videoFileId,
      qualityUrls: qualityUrls,
      coverUrl: coverUrl,
      shareId: shareId,
      width: videoWidth,
      height: videoHeight,
      bitrateKbps: bitrateKbps,
    );
  }

  bool _looksLikeWafChallenge(String html) {
    return html.contains('Please wait...') &&
        (html.contains('waf_js') ||
            html.contains('_wafchallengeid') ||
            html.contains('waf-jschallenge'));
  }

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

    final images = item['images'];
    if (images is List && images.isNotEmpty) {
      final imageUrls = <String>[];
      for (final img in images) {
        if (img is! Map) continue;
        final urlList = img['url_list'];
        if (urlList is! List || urlList.isEmpty) continue;
        String? picked;
        for (final u in urlList) {
          final s = u.toString();
          if (s.contains('tplv-dy-lqen-new') && !s.contains('-water')) {
            picked = s;
            break;
          }
        }
        picked ??= urlList
            .map((e) => e.toString())
            .firstWhere(
              (u) => u.contains('tplv-dy-aweme-images'),
              orElse: () => urlList.first.toString(),
            );
        imageUrls.add(picked);
      }

      String? musicUrl;
      String? musicTitle;
      final music = item['music'];
      if (music is Map) {
        musicTitle = music['title']?.toString();
        final playUrl = music['play_url'];
        if (playUrl is Map) {
          final list = playUrl['url_list'];
          if (list is List && list.isNotEmpty)
            musicUrl = list.first?.toString();
        }
      }

      return VideoInfo(
        videoId: id,
        title: title,
        videoFileId: '',
        qualityUrls: const {},
        coverUrl: coverUrl,
        shareId: shareId,
        width: width,
        height: height,
        bitrateKbps: bitrateKbps,
        imageUrls: imageUrls,
        musicUrl: musicUrl,
        musicTitle: musicTitle,
      );
    }

    final qualityUrls = <VideoQuality, String>{};
    String? bestVideoFileId;

    if (video is Map) {
      final bitRates = video['bit_rate'];
      if (bitRates is List) {
        for (final br in bitRates) {
          if (br is! Map) continue;
          final ratio =
              br['gear_name']?.toString().replaceFirst('gear_', '') ?? '';
          final quality = VideoQuality.fromRatio(ratio);
          final playAddr = br['play_addr'];
          final uri = playAddr is Map ? playAddr['uri']?.toString() : null;
          if (quality == null || uri == null || uri.isEmpty) continue;
          qualityUrls[quality] =
              '$_playBase?video_id=$uri&ratio=${quality.ratio}&line=0';
        }
      }

      if (qualityUrls.isEmpty) {
        final playAddr = video['play_addr'];
        final uri = playAddr is Map ? playAddr['uri']?.toString() : null;
        if (uri != null && uri.isNotEmpty) {
          final h = int.tryParse(video['height']?.toString() ?? '');
          final guessed = h != null && h >= 1080
              ? VideoQuality.p1080
              : VideoQuality.p720;
          qualityUrls[guessed] =
              '$_playBase?video_id=$uri&ratio=${guessed.ratio}&line=0';
        }
      }
    }

    if (qualityUrls.isEmpty) {
      throw DouyinParseException('分享页中未找到视频地址，页面结构可能已变更');
    }

    for (final q in [
      VideoQuality.p2160,
      VideoQuality.p1080,
      VideoQuality.p720,
      VideoQuality.p480,
      VideoQuality.p360,
    ]) {
      final url = qualityUrls[q];
      if (url != null) {
        final videoId = Uri.parse(url).queryParameters['video_id'];
        if (videoId != null && videoId.isNotEmpty) {
          bestVideoFileId = videoId;
          break;
        }
      }
    }

    if (bestVideoFileId == null) {
      throw DouyinParseException('无法从播放地址提取 video_id');
    }

    return VideoInfo(
      videoId: id,
      title: title,
      videoFileId: bestVideoFileId,
      qualityUrls: qualityUrls,
      coverUrl: coverUrl,
      shareId: shareId,
      width: width,
      height: height,
      bitrateKbps: bitrateKbps,
    );
  }

  /// 从 HTML 中提取图文作品的图片 URL 列表。
  /// 先收集所有 url_list 首 URL，再按 transform 类型分桶，优先返回高清无水印版本：
  ///   lqen-new（无水印）/ aweme-images  >  shrink:N（N≥1000）
  /// 封面/头像的 resize-walign-adapt、带水印的 lqen-new-water 均被排除。
  static List<String> _extractImageUrls(String html) {
    final hqUrls = <String>[]; // lqen-new（无水印）或 aweme-images
    final shrinkUrls = <String>[]; // shrink:N，N≥1000

    for (final m in _urlListFirstRe.allMatches(html)) {
      final url = _decodeJsonString(m.group(1)!);
      if (!url.contains('tplv-dy-')) continue;

      if (url.contains('tplv-dy-lqen-new')) {
        // 排除带水印版本 lqen-new-water
        if (!url.contains('tplv-dy-lqen-new-water')) hqUrls.add(url);
      } else if (url.contains('tplv-dy-aweme-images')) {
        hqUrls.add(url);
      } else if (url.contains('tplv-dy-shrink:')) {
        // shrink:480 / shrink:960 是缩略图，排除宽度 < 1000 的
        final wm = RegExp(r'shrink:(\d+)').firstMatch(url);
        if (wm != null && int.parse(wm.group(1)!) >= 1000) shrinkUrls.add(url);
      }
    }

    if (hqUrls.isNotEmpty) return hqUrls;
    if (shrinkUrls.isNotEmpty) return shrinkUrls;
    return const [];
  }

  /// 解码 JSON 字符串中的 unicode 转义（如 \u002F → /）和常规转义
  static String _decodeJsonString(String s) {
    // 借助 jsonDecode 来完整处理 JSON 字符串转义
    // 给字符串加上引号使其成为合法 JSON 字符串字面量
    try {
      return jsonDecode('"$s"') as String;
    } catch (_) {
      // fallback：只处理常见的 \u002F → /
      return s.replaceAllMapped(
        RegExp(r'\\u([0-9a-fA-F]{4})'),
        (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
      );
    }
  }

  void dispose() => _httpClient.close();
}
