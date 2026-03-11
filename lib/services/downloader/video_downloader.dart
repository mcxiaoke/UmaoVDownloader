import '../douyin_parser.dart';

/// 视频下载器抽象接口
///
/// 各平台实现：
/// - [DesktopDownloader]：Windows / macOS / Linux
/// - [MobileDownloader]：Android / iOS
/// - [WebDownloader]：Web（预留）
abstract class VideoDownloader {
  /// 下载视频文件
  ///
  /// - [info] 由 [DouyinParser] 解析得到的视频信息
  /// - [directory] 保存目录；null 则使用 [getDefaultDirectory]
  /// - [filename] 文件名（不含扩展名）；null 则使用视频标题
  ///
  /// 返回最终保存的完整文件路径
  Future<String> downloadVideo(
    VideoInfo info, {
    String? directory,
    String? filename,
  });

  /// 获取该平台的默认下载目录
  Future<String> getDefaultDirectory();
}
