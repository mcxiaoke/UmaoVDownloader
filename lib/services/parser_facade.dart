import 'parser_common.dart';
import 'douyin_parser.dart';
import 'xiaohongshu_parser.dart';

/// 解析日志回调函数类型定义
/// 用于接收解析过程中的日志信息
typedef ParserLog = void Function(String message);

/// 解析器门面类
///
/// 提供统一的视频解析接口，支持抖音和小红书平台。
class ParserFacade {
  const ParserFacade();

  /// 解析视频信息
  ///
  /// [input] 用户输入的链接或文本
  /// [log] 日志回调函数
  ///
  /// 返回解析后的视频信息
  Future<VideoInfo> parse(String input, {ParserLog? log}) async {
    // 从输入中提取URL链接
    final url = RegExp(r'https?://[^\s，,。]+').firstMatch(input)?.group(0);

    // 根据URL判断平台类型
    final platform =
        url != null ? ParserPlatform.fromUrl(url) : ParserPlatform.unknown;

    // 记录解析信息
    log?.call('检测到平台: ${platform.name}');

    return _parseByDart(input, platform, log: log);
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
}
