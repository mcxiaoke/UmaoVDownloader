import 'douyin_parser.dart';
import 'settings_service.dart';
import 'webview_parser.dart';

typedef ParserLog = void Function(String message);

/// 支持的平台类型
enum ParserPlatform {
  douyin,
  xiaohongshu,
  unknown;

  static ParserPlatform fromUrl(String url) {
    if (url.contains('douyin.com') || url.contains('iesdouyin.com')) {
      return ParserPlatform.douyin;
    }
    if (url.contains('xiaohongshu.com') || url.contains('xhslink.com')) {
      return ParserPlatform.xiaohongshu;
    }
    return ParserPlatform.unknown;
  }
}

/// 解析门面：统一接入解析策略，后续在这里挂接 WebView 后备解析。
class ParserFacade {
  static final _webViewParser = WebViewParser();

  const ParserFacade();

  Future<VideoInfo> parse(
    String input, {
    required ParserStrategy strategy,
    bool compareParsers = false,
    ParserLog? log,
  }) async {
    // 检测平台
    final url = RegExp(r'https?://[^\s，,。]+').firstMatch(input)?.group(0);
    final platform = url != null ? ParserPlatform.fromUrl(url) : ParserPlatform.unknown;
    log?.call('检测到平台: ${platform.name}');
    log?.call('解析策略: ${strategy.value}');
    log?.call('并行对比: ${compareParsers ? "开启" : "关闭"}');

    // 小红书目前仅支持 WebView 解析
    if (platform == ParserPlatform.xiaohongshu) {
      log?.call('小红书仅支持 WebView 解析');
      final webview = await _tryParseByWebView(input, log: log);
      if (webview != null) return _normalize(webview);
      throw Exception('小红书 WebView 解析失败');
    }

    if (compareParsers && strategy == ParserStrategy.auto) {
      return _parseWithCompare(input, strategy: strategy, log: log);
    }

    if (strategy == ParserStrategy.auto) {
      log?.call('优先尝试 WebView 解析');
      final webview = await _tryParseByWebView(input, log: log);
      if (webview != null) return _normalize(webview);
      log?.call('WebView 解析未命中，回退 Dart 解析');
      return _normalize(await _parseByDart(input));
    }

    if (strategy == ParserStrategy.jsOnly) {
      final webview = await _tryParseByWebView(input, log: log);
      if (webview != null) return _normalize(webview);
      throw Exception('JS解析器未命中');
    }

    return _normalize(await _parseByDart(input));
  }

  Future<VideoInfo> _parseWithCompare(
    String input, {
    required ParserStrategy strategy,
    ParserLog? log,
  }) async {
    final webSw = Stopwatch()..start();
    final dartSw = Stopwatch()..start();

    VideoInfo? webInfo;
    VideoInfo? dartInfo;
    Object? webError;
    Object? dartError;

    final webFuture = _tryParseByWebView(input, log: log)
        .then((v) => webInfo = v)
        .catchError((e) => webError = e)
        .whenComplete(() => webSw.stop());

    final dartFuture = _parseByDart(input)
        .then((v) => dartInfo = v)
        .catchError((e) => dartError = e)
        .whenComplete(() => dartSw.stop());

    await Future.wait([webFuture, dartFuture]);

    log?.call(
      '对比结果: webview=${webInfo != null ? "OK" : "MISS"} (${webSw.elapsedMilliseconds}ms), '
      'dart=${dartInfo != null ? "OK" : "FAIL"} (${dartSw.elapsedMilliseconds}ms)',
    );
    if (webError != null) log?.call('WebView 解析异常: $webError');
    if (dartError != null) log?.call('Dart 解析异常: $dartError');

    if (webInfo != null) return _normalize(webInfo!);
    if (dartInfo != null) return _normalize(dartInfo!);
    throw dartError ?? webError ?? Exception('两个解析器均失败');
  }

  Future<VideoInfo> _parseByDart(String input) async {
    final parser = DouyinParser();
    try {
      return await parser.parse(input);
    } finally {
      parser.dispose();
    }
  }

  Future<VideoInfo?> _tryParseByWebView(String input, {ParserLog? log}) async {
    return await _webViewParser.tryParse(input, log: log);
  }

  /// 统一结果归一化，后续不同策略都走同一出口。
  VideoInfo _normalize(VideoInfo info) {
    if (!info.isImagePost) return info;

    final imageUrls = info.imageUrls.where((u) => u.isNotEmpty).toList();
    final musicUrl = (info.musicUrl != null && info.musicUrl!.isNotEmpty)
        ? info.musicUrl
        : null;

    return VideoInfo(
      videoId: info.videoId,
      title: info.title,
      videoFileId: info.videoFileId,
      qualityUrls: info.qualityUrls,
      coverUrl: info.coverUrl,
      shareId: info.shareId,
      width: info.width,
      height: info.height,
      bitrateKbps: info.bitrateKbps,
      imageUrls: imageUrls,
      musicUrl: musicUrl,
      musicTitle: info.musicTitle,
    );
  }
}
