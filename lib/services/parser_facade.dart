import 'parser_common.dart';
import 'douyin_parser.dart';
import 'settings_service.dart';
import 'webview_parser.dart';
import 'xiaohongshu_parser.dart';

/// 解析日志回调函数类型定义
/// 用于接收解析过程中的日志信息
typedef ParserLog = void Function(String message);

/// 支持的视频平台类型枚举
///
/// 用于标识不同的短视频平台，支持抖音和小红书
enum ParserPlatform {
  douyin,       // 抖音平台
  xiaohongshu,  // 小红书平台
  unknown;      // 未知平台

  /// 根据URL判断平台类型
  ///
  /// [url] 视频分享链接
  /// 返回对应的平台类型
  static ParserPlatform fromUrl(String url) {
    // 检测抖音域名
    if (url.contains('douyin.com') || url.contains('iesdouyin.com')) {
      return ParserPlatform.douyin;
    }

    // 检测小红书域名
    if (url.contains('xiaohongshu.com') || url.contains('xhslink.com')) {
      return ParserPlatform.xiaohongshu;
    }

    // 未识别的平台
    return ParserPlatform.unknown;
  }
}

/// 解析器门面类
///
/// 提供统一的视频解析接口，支持多种解析策略和平台。
/// 实现了策略模式，可以在WebView解析和Dart解析之间切换。
/// 支持解析器对比模式用于测试和验证。
class ParserFacade {
  /// WebView解析器单例
  static final _webViewParser = WebViewParser();

  const ParserFacade();

  /// 解析视频信息
  ///
  /// [input] 用户输入的链接或文本
  /// [strategy] 解析策略（自动、仅JS、仅Dart）
  /// [compareParsers] 是否启用解析器对比模式
  /// [log] 日志回调函数
  ///
  /// 返回解析后的视频信息
  Future<VideoInfo> parse(
    String input, {
    required ParserStrategy strategy,
    bool compareParsers = false,
    ParserLog? log,
  }) async {
    // 从输入中提取URL链接
    final url = RegExp(r'https?://[^\s，,。]+').firstMatch(input)?.group(0);

    // 根据URL判断平台类型
    final platform = url != null ? ParserPlatform.fromUrl(url) : ParserPlatform.unknown;

    // 记录解析信息
    log?.call('检测到平台: ${platform.name}');
    log?.call('解析策略: ${strategy.value}');
    log?.call('并行对比: ${compareParsers ? "开启" : "关闭"}');

    // 如果启用对比模式且策略为自动，则使用对比解析
    if (compareParsers && strategy == ParserStrategy.auto) {
      return _parseWithCompare(input, platform: platform, strategy: strategy, log: log);
    }

    // 自动策略：优先使用WebView解析，失败时回退到Dart解析
    if (strategy == ParserStrategy.auto) {
      log?.call('优先尝试 WebView 解析');
      final webview = await _tryParseByWebView(input, log: log);
      if (webview != null) return _normalize(webview);

      log?.call('WebView 解析未命中，回退 Dart 解析');
      return _normalize(await _parseByDart(input, platform, log: log));
    }

    // 仅使用JS解析策略
    if (strategy == ParserStrategy.jsOnly) {
      final webview = await _tryParseByWebView(input, log: log);
      if (webview != null) return _normalize(webview);
      throw Exception('JS解析器未命中');
    }

    // 仅使用Dart解析策略或其他策略
    return _normalize(await _parseByDart(input, platform, log: log));
  }

  /// 使用对比模式解析视频信息
  ///
  /// 同时运行WebView和Dart解析器，对比它们的结果和性能
  /// 用于测试和验证解析器的准确性
  ///
  /// [input] 输入的链接或文本
  /// [platform] 平台类型
  /// [strategy] 解析策略
  /// [log] 日志回调函数
  ///
  /// 返回解析结果，优先使用WebView的结果
  Future<VideoInfo> _parseWithCompare(
    String input, {
    required ParserPlatform platform,
    required ParserStrategy strategy,
    ParserLog? log,
  }) async {
    // 初始化性能计时器
    final webSw = Stopwatch()..start();
    final dartSw = Stopwatch()..start();

    // 存储解析结果和错误信息
    VideoInfo? webInfo;
    VideoInfo? dartInfo;
    Object? webError;
    Object? dartError;

    // WebView解析任务
    final webFuture = _tryParseByWebView(input, log: log)
        .then((v) => webInfo = v)
        .catchError((e) => webError = e)
        .whenComplete(() => webSw.stop());

    // Dart解析任务
    final dartFuture = _parseByDart(input, platform, log: log)
        .then((v) => dartInfo = v)
        .catchError((e) => dartError = e)
        .whenComplete(() => dartSw.stop());

    // 并行执行两个解析任务
    await Future.wait([webFuture, dartFuture]);

    // 记录对比结果和性能数据
    log?.call(
      '对比结果: webview=${webInfo != null ? "OK" : "MISS"} (${webSw.elapsedMilliseconds}ms), '
      'dart=${dartInfo != null ? "OK" : "FAIL"} (${dartSw.elapsedMilliseconds}ms)',
    );
    if (webError != null) log?.call('WebView 解析异常: $webError');
    if (dartError != null) log?.call('Dart 解析异常: $dartError');

    // 优先返回WebView解析结果，其次返回Dart解析结果
    if (webInfo != null) return _normalize(webInfo!);
    if (dartInfo != null) return _normalize(dartInfo!);

    // 两个解析器都失败时抛出异常
    throw dartError ?? webError ?? Exception('两个解析器均失败');
  }

  /// 使用Dart解析器解析视频信息
  ///
  /// 根据平台类型选择对应的Dart解析器进行解析
  ///
  /// [input] 输入的链接或文本
  /// [platform] 平台类型
  /// [log] 日志回调函数
  ///
  /// 返回解析后的视频信息
  Future<VideoInfo> _parseByDart(
    String input,
    ParserPlatform platform, {
    ParserLog? log,
  }) async {
    // 根据平台选择对应的解析器
    if (platform == ParserPlatform.xiaohongshu) {
      // 小红书平台使用XiaohongshuParser
      final parser = XiaohongshuParser();
      try {
        return await parser.parse(input);
      } finally {
        // 确保释放解析器资源
        parser.dispose();
      }
    } else {
      // 抖音平台或其他平台使用DouyinParser
      final parser = DouyinParser();
      try {
        return await parser.parse(input);
      } finally {
        // 确保释放解析器资源
        parser.dispose();
      }
    }
  }

  /// 尝试使用WebView解析器解析视频信息
  ///
  /// [input] 输入的链接或文本
  /// [log] 日志回调函数
  ///
  /// 返回解析结果，如果解析失败则返回null
  Future<VideoInfo?> _tryParseByWebView(String input, {ParserLog? log}) async {
    return await _webViewParser.tryParse(input, log: log);
  }

  /// 统一结果归一化
  ///
  /// 对解析结果进行标准化处理，确保不同解析策略的输出格式一致
  /// 主要用于处理图文类型的内容，过滤无效数据
  ///
  /// [info] 原始解析结果
  /// 返回标准化后的视频信息
  VideoInfo _normalize(VideoInfo info) {
    if (info.mediaType != MediaType.image) return info;

    final imageUrls = info.imageUrls.where((u) => u.isNotEmpty).toList();
    final musicUrl = (info.musicUrl != null && info.musicUrl!.isNotEmpty)
        ? info.musicUrl
        : null;

    // 返回标准化后的视频信息
    return VideoInfo(
      itemId: info.itemId,
      title: info.title,
      videoFileId: info.videoFileId,
      videoUrl: info.videoUrl,
      videoUrlNoWatermark: info.videoUrlNoWatermark,  // 传递无水印URL
      mediaType: info.mediaType,
      coverUrl: info.coverUrl,
      shareId: info.shareId,
      width: info.width,
      height: info.height,
      bitrateKbps: info.bitrateKbps,
      imageUrls: imageUrls,           // 过滤后的图片URL列表
      imageThumbUrls: info.imageThumbUrls,
      musicUrl: musicUrl,             // 过滤后的音乐URL
      musicTitle: info.musicTitle,
      musicAuthor: info.musicAuthor,
      livePhotoUrls: info.livePhotoUrls,
    );
  }
}
