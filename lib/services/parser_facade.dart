import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_logger.dart';
import 'parser_common.dart';
import 'douyin_parser.dart';
import 'xiaohongshu_parser.dart';
import '../constants/app_constants.dart';

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
        final info = await parser.parse(input);
        
        // 抖音图文：尝试从服务端获取动图视频
        AppLogger.debug('解析完成: mediaType=${info.mediaType}, imageUrls.length=${info.imageUrls.length}');
        if (info.mediaType == MediaType.image && info.imageUrls.isNotEmpty) {
          AppLogger.debug('进入动图视频获取流程...');
          return await _fetchDouyinLivePhotos(info, input, log);
        }
        
        return info;
      } finally {
        // 确保释放解析器资源
        parser.dispose();
      }
    }
  }

  /// 从服务端获取抖音图文的动图视频
  ///
  /// 失败时返回原始 info，不影响用户体验
  Future<VideoInfo> _fetchDouyinLivePhotos(
    VideoInfo info,
    String url,
    ParserLog? log,
  ) async {
    try {
      AppLogger.debug('检测到抖音图文，尝试获取动图视频...');
      
      final encodedUrl = Uri.encodeComponent(url);
      final apiUrl = '$kBackendBaseUrl/api/parse?url=$encodedUrl';
      
      AppLogger.debug('请求服务端: $apiUrl');
      
      final response = await http.get(
        Uri.parse(apiUrl),
      ).timeout(const Duration(seconds: kBackendTimeoutSeconds));
      
      if (response.statusCode != 200) {
        AppLogger.warn('服务端返回 ${response.statusCode}，使用本地解析结果');
        return info;
      }
      
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      
      // 检查是否获取到动图视频
      final livePhotoUrls = (json['livePhotoUrls'] as List?)
          ?.map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList();
      
      if (livePhotoUrls == null || livePhotoUrls.isEmpty) {
        AppLogger.debug('未获取到动图视频，使用本地解析结果');
        return info;
      }
      
      AppLogger.info('获取到 ${livePhotoUrls.length} 个动图视频');
      
      // 从服务端返回的 imageList 提取每张图片的视频信息
      final imageList = json['imageList'] as List?;
      final newImageUrls = <String>[];
      final newImageThumbUrls = <String>[];
      final newLivePhotoUrls = <String>[];
      
      // 检查 imageList 是否有效
      bool imageListValid = false;
      if (imageList != null && imageList.isNotEmpty) {
        for (final img in imageList) {
          if (img is! Map) continue;

          // 图片 URL（抖音: full/thumb, 小红书: url/thumbUrl）
          final imgUrl = img['full']?.toString() ??
              img['url']?.toString() ??
              img['imageUrl']?.toString() ??
              '';
          final thumbUrl = img['thumb']?.toString() ??
              img['thumbUrl']?.toString() ??
              imgUrl;

          newImageUrls.add(imgUrl);
          newImageThumbUrls.add(thumbUrl);

          // 动图视频 URL
          final videoUrl = img['videoUrl']?.toString() ?? '';
          newLivePhotoUrls.add(videoUrl);
        }
        // 检查是否有有效图片
        imageListValid = newImageUrls.any((e) => e.isNotEmpty);
      }
      
      // 如果服务端 imageList 无效，使用本地图片 + 服务端视频
      if (!imageListValid) {
        AppLogger.debug('服务端 imageList 无效，使用本地图片');
        newImageUrls.clear();
        newImageThumbUrls.clear();
        newImageUrls.addAll(info.imageUrls);
        newImageThumbUrls.addAll(info.imageThumbUrls);
        
        // 使用之前提取的 livePhotoUrls，按索引对应
        newLivePhotoUrls.clear();
        for (int i = 0; i < newImageUrls.length; i++) {
          if (i < livePhotoUrls.length) {
            newLivePhotoUrls.add(livePhotoUrls[i]);
          } else {
            newLivePhotoUrls.add('');
          }
        }
      }
      
      AppLogger.debug('最终: imageUrls=${newImageUrls.length}, livePhotoUrls=${newLivePhotoUrls.length}');
      
      return VideoInfo(
        itemId: info.itemId,
        title: info.title,
        videoFileId: info.videoFileId,
        videoUrl: info.videoUrl,
        mediaType: MediaType.livePhoto,
        platform: info.platform,
        coverUrl: info.coverUrl,
        shareId: info.shareId,
        width: info.width,
        height: info.height,
        bitrateKbps: info.bitrateKbps,
        // 保持索引对应，不过滤空值
        imageUrls: newImageUrls,
        imageThumbUrls: newImageThumbUrls,
        musicUrl: info.musicUrl,
        musicTitle: info.musicTitle,
        musicAuthor: info.musicAuthor,
        livePhotoUrls: newLivePhotoUrls,
        authorId: info.authorId,
        authorName: info.authorName,
        authorAvatar: info.authorAvatar,
        createTime: info.createTime,
        likeCount: info.likeCount,
        collectCount: info.collectCount,
        commentCount: info.commentCount,
        shareCount: info.shareCount,
      );
    } catch (e) {
      AppLogger.warn('获取动图视频失败: $e，使用本地解析结果');
      return info;
    }
  }
}
