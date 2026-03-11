import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// 解析视频信息的结果
class VideoInfo {
  final String videoId;
  final String title;

  /// 视频下载地址（v1.0 为带水印版本）
  final String videoUrl;

  final String? coverUrl;

  const VideoInfo({
    required this.videoId,
    required this.title,
    required this.videoUrl,
    this.coverUrl,
  });

  @override
  String toString() => 'VideoInfo(id: $videoId, title: $title, url: $videoUrl)';
}

class DouyinParseException implements Exception {
  final String message;
  const DouyinParseException(this.message);

  @override
  String toString() => 'DouyinParseException: $message';
}

/// 抖音视频解析器
///
/// 流程：短链接 → 跟随重定向 → 提取 videoId → 调用 API → 返回 [VideoInfo]
class DouyinParser {
  // 模拟手机端 UA，避免被拦截
  static const _mobileUA =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

  static const _referer = 'https://www.douyin.com/';

  /// [httpClient] 可传入 mock client 方便单元测试
  final http.Client _httpClient;

  DouyinParser({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  /// 主入口：传入任意抖音链接，返回视频信息
  Future<VideoInfo> parse(String url) async {
    final realUrl = await _resolveUrl(url);
    final videoId = _extractVideoId(realUrl);
    if (videoId == null) {
      throw DouyinParseException('无法从链接中提取视频 ID，最终 URL: $realUrl');
    }
    return await _fetchVideoInfo(videoId);
  }

  /// 手动跟随重定向，返回最终落地 URL
  ///
  /// 使用 dart:io HttpClient 并关闭自动跳转，以便捕获 Location 头
  Future<String> _resolveUrl(String url) async {
    const maxRedirects = 5;
    var currentUri = Uri.parse(url);
    final ioClient = HttpClient();
    try {
      for (var i = 0; i < maxRedirects; i++) {
        final request = await ioClient.getUrl(currentUri);
        request.headers.set(HttpHeaders.userAgentHeader, _mobileUA);
        request.followRedirects = false;

        final response = await request.close();
        await response.drain<void>(); // 丢弃响应体节省内存

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

  /// 从 URL 中提取 videoId（形如 /video/1234567890123456789）
  String? _extractVideoId(String url) {
    final match = RegExp(r'/video/(\d+)').firstMatch(url);
    return match?.group(1);
  }

  /// 调用 iesdouyin API 获取视频详情
  Future<VideoInfo> _fetchVideoInfo(String videoId) async {
    final uri = Uri.parse(
      'https://www.iesdouyin.com/web/api/v2/aweme/iteminfo/?item_ids=$videoId',
    );

    final response = await _httpClient.get(
      uri,
      headers: {HttpHeaders.userAgentHeader: _mobileUA, 'Referer': _referer},
    );

    if (response.statusCode != 200) {
      throw DouyinParseException('API 请求失败，状态码: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final awemeList = data['aweme_list'] as List<dynamic>?;
    if (awemeList == null || awemeList.isEmpty) {
      throw DouyinParseException('API 返回数据为空，视频可能已被删除或链接无效');
    }

    final aweme = awemeList[0] as Map<String, dynamic>;
    final desc = aweme['desc'] as String?;
    final title = (desc != null && desc.isNotEmpty) ? desc : '视频_$videoId';

    final video = aweme['video'] as Map<String, dynamic>?;
    if (video == null) {
      throw DouyinParseException('视频字段缺失，API 结构可能已变更');
    }

    // v1.0: 取带水印的 play_addr
    final playAddr = video['play_addr'] as Map<String, dynamic>?;
    final urlList = (playAddr?['url_list'] as List<dynamic>?)
        ?.whereType<String>()
        .toList();
    if (urlList == null || urlList.isEmpty) {
      throw DouyinParseException('无法获取视频播放地址，API 结构可能已变更');
    }

    final coverUrlList =
        ((video['cover'] as Map<String, dynamic>?)?['url_list']
                as List<dynamic>?)
            ?.whereType<String>()
            .toList();

    return VideoInfo(
      videoId: videoId,
      title: title,
      videoUrl: urlList.first,
      coverUrl: coverUrlList?.isNotEmpty == true ? coverUrlList!.first : null,
    );
  }

  void dispose() => _httpClient.close();
}
