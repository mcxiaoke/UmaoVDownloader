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
  });

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

  // 无水印播放接口模板（跳转到 CDN，不含水印）
  static const _playBase = 'https://aweme.snssdk.com/aweme/v1/play/';

  /// [httpClient] 可传入 mock client 方便单元测试
  final http.Client _httpClient;

  DouyinParser({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  /// 主入口：传入任意抖音链接，返回视频信息
  Future<VideoInfo> parse(String url) async {
    // 从原始缓存短链 ID（跳转后丢失）
    final shareId = RegExp(
      r'v\.douyin\.com/([A-Za-z0-9_-]+)',
    ).firstMatch(url)?.group(1);
    final realUrl = await _resolveUrl(url);
    final videoId = _extractVideoId(realUrl);
    if (videoId == null) {
      throw DouyinParseException('无法从链接中提取视频 ID，最终 URL: $realUrl');
    }
    return await _parseSharePage(videoId, shareId: shareId);
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
    return RegExp(r'/(?:video|note)/(\d+)').firstMatch(url)?.group(1);
  }

  /// 抓取 iesdouyin 分享页，从内嵌 JSON 中解析视频信息
  Future<VideoInfo> _parseSharePage(String videoId, {String? shareId}) async {
    final shareUrl = Uri.parse(
      'https://www.iesdouyin.com/share/video/$videoId/',
    );

    final response = await _httpClient.get(
      shareUrl,
      headers: {HttpHeaders.userAgentHeader: _mobileUA, 'Referer': _referer},
    );

    if (response.statusCode != 200) {
      throw DouyinParseException('分享页请求失败，状态码: ${response.statusCode}');
    }

    final html = response.body;

    // 从 play_addr 的 URL 里提取 video_id 参数
    final rawPlayUrl = _playAddrRe.firstMatch(html)?.group(1);
    if (rawPlayUrl == null) {
      throw DouyinParseException('分享页中未找到视频地址，页面结构可能已变更');
    }
    final playUrl = _decodeJsonString(rawPlayUrl);
    final videoFileId = Uri.parse(playUrl).queryParameters['video_id'];
    if (videoFileId == null || videoFileId.isEmpty) {
      throw DouyinParseException('无法从播放地址提取 video_id: $playUrl');
    }

    // 构造各清晰度的无水印 play URL（跟随重定向时才会产生带时效的 CDN URL）
    final qualityUrls = <VideoQuality, String>{
      for (final q in VideoQuality.values)
        q: '$_playBase?video_id=$videoFileId&ratio=${q.ratio}&line=0',
    };

    // 提取标题
    final rawDesc = _descRe.firstMatch(html)?.group(1);
    final title = (rawDesc != null && rawDesc.isNotEmpty)
        ? _decodeJsonString(rawDesc)
        : '视频_$videoId';

    // 提取封面（可选）
    final rawCover = _coverRe.firstMatch(html)?.group(1);
    final coverUrl = rawCover != null ? _decodeJsonString(rawCover) : null;

    // 提取视频尺寸：在 play_addr 位置之后搜索，避免匹配到头像等小图
    int? videoWidth, videoHeight;
    final playAddrIdx = html.indexOf('play_addr');
    if (playAddrIdx >= 0) {
      final sub = html.substring(playAddrIdx);
      final hm = RegExp(r'"height"\s*:\s*(\d+)').firstMatch(sub);
      final wm = RegExp(r'"width"\s*:\s*(\d+)').firstMatch(sub);
      final h = hm != null ? int.tryParse(hm.group(1)!) : null;
      final w = wm != null ? int.tryParse(wm.group(1)!) : null;
      // 过滤掉明显不是视频分辨率的小尺寸（<120px）
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
