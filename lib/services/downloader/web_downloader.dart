import '../douyin_parser.dart';
import 'video_downloader.dart';

/// Web 平台下载器（预留接口，暂未实现）
///
/// 实现思路（待完成）：
/// 1. 由于浏览器 CORS 限制，需要一个后端代理中转请求
/// 2. 拿到视频 Blob/URL 后，通过 dart:html 创建 <a download> 元素触发浏览器下载
/// 3. 用户无法选择目录，由浏览器控制保存路径
class WebDownloader implements VideoDownloader {
  @override
  Future<String> downloadVideo(
    VideoInfo info, {
    String? directory,
    String? filename,
  }) {
    // TODO: 实现 Web 下载
    throw UnimplementedError('Web 下载功能尚未实现');
  }

  @override
  Future<String> getDefaultDirectory() async {
    // Web 平台无目录概念
    return '浏览器默认下载目录';
  }
}
