import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../services/app_logger.dart';
import '../../services/downloader/base_downloader.dart';
import '../../services/log_service.dart';
import '../../services/parser_common.dart';
import '../../services/parser_facade.dart';
import '../../services/settings_service.dart';
import '../../services/url_extractor.dart';

/// 解析逻辑 Mixin
mixin ParserMixin<T extends StatefulWidget> on State<T> {
  // 控制器
  TextEditingController get inputController;

  // 服务
  LogService get log;
  SettingsService get settings;
  ParserFacade get parserFacade;

  // 状态变量
  bool get parsing;
  set parsing(bool value);
  VideoInfo? get videoInfo;
  set videoInfo(VideoInfo? value);
  int? get fileSizeBytes;
  set fileSizeBytes(int? value);
  bool get fetchingSize;
  set fetchingSize(bool value);

  // 详细日志
  bool get verbose => settings.verboseLog;

  void vlog(String msg) {
    if (verbose) log.info(msg);
  }

  /// 解析 URL
  Future<void> parse() async {
    // 让输入框失去焦点，隐藏键盘
    FocusScope.of(context).unfocus();

    final input = inputController.text.trim();
    if (input.isEmpty) return;

    vlog('原始输入长度=${input.length}');

    final url = UrlExtractor.extractFirst(input);
    if (url == null) {
      log.warn('无效输入，未找到链接');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('未找到有效的链接，请粘贴抖音/小红书分享文本或链接'),
            duration: Duration(seconds: 3),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    // 校验是否为支持的平台
    final platform = ParserPlatform.fromUrl(url);
    if (platform == ParserPlatform.unknown) {
      log.warn('不支持的链接: $url');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('目前仅支持抖音/小红书链接'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    setState(() {
      parsing = true;
      videoInfo = null;
    });
    // 清除错误状态
    onParseError('');
    log.info('开始解析：$url');
    vlog('当前平台: ${Platform.operatingSystem}');
    final sw = Stopwatch()..start();

    try {
      final info = await parserFacade.parse(url, log: (m) => vlog(m));

      setState(() {
        videoInfo = info;
        fileSizeBytes = null;
      });
      onParseSuccess(info);
      // 视频作品：获取文件大小
      if (info.mediaType == MediaType.video && info.videoUrl.isNotEmpty) {
        fetchFileSize(info);
      }
      log.info('解析成功：${info.title}');
      vlog('解析耗时: ${sw.elapsedMilliseconds} ms');
      log.info('itemId=${info.itemId}');
      switch (info.mediaType) {
        case MediaType.image:
          log.info('图文作品，共 ${info.imageUrls.length} 张图片');
          vlog('musicUrl=${info.musicUrl ?? "<none>"}');
        case MediaType.livePhoto:
          log.info('实况图作品，共 ${info.livePhotoUrls.length} 个视频');
          vlog('封面=${info.coverUrl ?? "<none>"}');
        case MediaType.video:
          log.info('fileId=${info.videoFileId}');
          vlog('封面=${info.coverUrl ?? "<none>"}');
          vlog('分辨率=${info.resolutionLabel ?? "<unknown>"}');
          vlog('videoUrl=${info.videoUrl}');
      }
    } catch (e, st) {
      // 日志记录完整错误信息
      log.error('解析失败：$e');
      vlog('解析异常堆栈: $st');

      // 调用错误回调
      onParseError(e.toString());

      // 向用户显示友好提示
      if (mounted) {
        final friendlyMsg = _getFriendlyErrorMessage(e.toString());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyMsg),
            duration: const Duration(seconds: 4),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      sw.stop();
      setState(() => parsing = false);
    }
  }

  /// 重置下载进度（子类实现）
  void resetDownloadProgress();

  /// 解析成功回调（子类可重写）
  void onParseSuccess(VideoInfo info) {
    resetDownloadProgress();
  }

  /// 解析失败回调（子类可重写）
  void onParseError(String error) {}

  /// 获取视频文件大小
  Future<void> fetchFileSize(VideoInfo info) async {
    if (fetchingSize) return;
    setState(() {
      fileSizeBytes = null;
      fetchingSize = true;
    });

    try {
      vlog('开始获取视频文件大小');

      final ioClient = HttpClient();
      String resolvedUrl = info.videoUrl;
      try {
        final req = await ioClient.getUrl(Uri.parse(info.videoUrl));
        req.headers.set(HttpHeaders.userAgentHeader, kUaEdge);
        req.followRedirects = false;
        final resp = await req.close();
        await resp.drain<void>();
        if (resp.statusCode >= 300 && resp.statusCode < 400) {
          resolvedUrl =
              resp.headers.value(HttpHeaders.locationHeader) ?? info.videoUrl;
        }
      } finally {
        ioClient.close();
      }
      final headResp = await http.head(
        Uri.parse(resolvedUrl),
        headers: {HttpHeaders.userAgentHeader: kUaEdge},
      );
      final cl = headResp.headers['content-length'];
      final size = cl != null ? int.tryParse(cl) : null;

      if (mounted) {
        setState(() {
          fileSizeBytes = size;
          fetchingSize = false;
        });
      }

      vlog('视频文件大小: ${formatFileSize(size)}');
    } catch (e) {
      vlog('获取文件大小失败: $e');
      if (mounted) {
        setState(() {
          fetchingSize = false;
        });
      }
    }
  }

  /// 格式化文件大小
  String formatFileSize(int? bytes) {
    if (bytes == null) return 'unknown';
    final mb = bytes / (1024 * 1024);
    if (mb >= 1) return '${mb.toStringAsFixed(2)} MB';
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }

  /// 将技术错误转换为友好提示
  String _getFriendlyErrorMessage(String error) {
    // 作品不存在/已删除
    if (error.contains('不存在') ||
        error.contains('已删除') ||
        error.contains('404')) {
      return '作品不存在或已被删除';
    }
    // 访问被拒绝
    if (error.contains('403') || error.contains('被拒绝')) {
      return '访问被拒绝，作品可能已设为私密';
    }
    // 未授权
    if (error.contains('401') || error.contains('未授权')) {
      return '需要登录才能访问此内容';
    }
    // 风控
    if (error.contains('风控') || error.contains('挑战页')) {
      return '触发风控，请稍后重试或更换网络';
    }
    // 网络错误
    if (error.contains('SocketException') ||
        error.contains('TimeoutException')) {
      return '网络连接失败，请检查网络后重试';
    }
    // 解析错误
    if (error.contains('无法提取') || error.contains('未找到')) {
      return '解析失败，页面结构可能已变更';
    }
    // 默认
    return '解析失败，请稍后重试';
  }
}
