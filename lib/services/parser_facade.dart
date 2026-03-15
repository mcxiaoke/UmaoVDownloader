import 'parser_common.dart';
import 'douyin_parser.dart';
import 'xiaohongshu_parser.dart';

/// 解析日志回调函数类型定义
/// 用于接收解析过程中的日志信息
typedef ParserLog = void Function(String message);

/// 支持的视频平台类型枚举
///
/// 用于标识不同的短视频平台，支持抖音和小红书
enum ParserPlatform {
  douyin, // 抖音平台
  xiaohongshu, // 小红书平台
  unknown; // 未知平台

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
