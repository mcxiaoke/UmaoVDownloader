import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../services/app_logger.dart';
import '../services/downloader/base_downloader.dart';
import '../constants/app_constants.dart';
import '../services/log_service.dart';
import '../services/parser_common.dart';
import '../services/parser_facade.dart';
import '../services/settings_service.dart';
import '../services/url_extractor.dart';
import 'providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// VideoNotifier - 视频解析状态管理
//
// 负责管理解析过程中的状态变化，不直接操作 UI。
// UI 相关操作（如 SnackBar、FocusScope）由 Widget 层处理。
// ─────────────────────────────────────────────────────────────────────────────

/// 视频解析状态 Notifier
///
/// 提供解析相关的状态管理和业务逻辑。
/// 状态变化通过 Riverpod 自动通知监听者。
///
/// 使用方式：
/// ```dart
/// // 读取状态
/// final state = ref.watch(videoNotifierProvider);
/// if (state.parsing) { ... }
///
/// // 调用方法
/// ref.read(videoNotifierProvider.notifier).parse(input);
/// ```
class VideoNotifier extends Notifier<VideoState> {
  /// 解析器门面
  late final ParserFacade _parserFacade;

  @override
  VideoState build() {
    _parserFacade = ParserFacade();
    return const VideoState.initial();
  }

  // ─── 便捷 getter ───────────────────────────────────────────────────────

  LogService get _log => ref.read(logServiceProvider);

  void _vlog(String msg) => AppLogger.debug(msg);

  // ─── 状态更新方法 ───────────────────────────────────────────────────────

  /// 重置状态（新解析开始时调用）
  void reset() {
    state = state.reset();
  }

  /// 清除错误
  void clearError() {
    if (state.error != null) {
      state = state.clearError();
    }
  }

  // ─── 解析逻辑 ───────────────────────────────────────────────────────────

  /// 解析输入内容
  ///
  /// 返回 ParseResult，包含解析结果和需要 UI 层处理的信息。
  /// 不直接显示 SnackBar，由调用方处理。
  Future<ParseResult> parse(String input) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return ParseResult.empty;
    }

    _vlog('原始输入长度=${trimmed.length}');

    // 提取 URL
    final url = UrlExtractor.extractFirst(trimmed);
    if (url == null) {
      _log.warn('无效输入，未找到链接');
      return ParseResult.invalidUrl;
    }

    // 校验平台
    final platform = ParserPlatform.fromUrl(url);
    if (platform == ParserPlatform.unknown) {
      _log.warn('不支持的链接: $url');
      return ParseResult.unsupportedPlatform;
    }

    // 开始解析
    state = state.copyWithParsing();
    _log.info('开始解析：$url');
    _vlog('当前平台: ${Platform.operatingSystem}');
    final sw = Stopwatch()..start();

    try {
      final info = await _parserFacade.parse(url, log: (m) => _vlog(m));

      // 解析成功
      state = state.copyWithSuccess(info);
      _log.info(
        '解析成功：title=${info.title} itemId=${info.itemId} 耗时: ${sw.elapsedMilliseconds} ms',
      );

      // 日志输出
      switch (info.mediaType) {
        case MediaType.image:
          _log.info('图文作品，共 ${info.imageUrls.length} 张图片');
          _vlog('musicUrl=${info.musicUrl ?? "<none>"}');
        case MediaType.livePhoto:
          _log.info('实况图作品，共 ${info.livePhotoUrls.length} 个视频');
          _vlog('封面=${info.coverUrl ?? "<none>"}');
        case MediaType.video:
          _log.info('fileId=${info.videoFileId}');
          _vlog('封面=${info.coverUrl ?? "<none>"}');
          _vlog('分辨率=${info.resolutionLabel ?? "<unknown>"}');
          _vlog('videoUrl=${info.videoUrl}');
      }

      // 视频类型：获取文件大小
      if (info.mediaType == MediaType.video && info.videoUrl.isNotEmpty) {
        _fetchFileSize(info);
      }

      return ParseResult.success(info);
    } catch (e, st) {
      _log.error('解析失败：$e');
      _vlog('解析异常堆栈: $st');

      state = state.copyWithError(e.toString());

      // 返回友好错误信息
      final friendlyMsg = _getFriendlyErrorMessage(e.toString());
      return ParseResult.error(friendlyMsg);
    } finally {
      sw.stop();
    }
  }

  /// 获取视频文件大小
  Future<void> _fetchFileSize(VideoInfo info) async {
    if (state.fetchingSize) return;

    state = state.copyWithFileSize(null, fetching: true);
    _vlog('开始获取视频文件大小');
    _vlog('原始 videoUrl: ${info.videoUrl}');

    try {
      final ioClient = HttpClient();
      String resolvedUrl = info.videoUrl;

      try {
        final req = await ioClient.getUrl(Uri.parse(info.videoUrl));
        req.headers.set(HttpHeaders.userAgentHeader, kUaEdge);
        req.followRedirects = false;
        final resp = await req.close();
        await resp.drain<void>();

        _vlog('重定向检测: statusCode=${resp.statusCode}');
        if (resp.statusCode >= 300 && resp.statusCode < 400) {
          resolvedUrl =
              resp.headers.value(HttpHeaders.locationHeader) ?? info.videoUrl;
          _vlog('重定向到: $resolvedUrl');
        }
      } finally {
        ioClient.close();
      }

      final headResp = await http.head(
        Uri.parse(resolvedUrl),
        headers: {HttpHeaders.userAgentHeader: kUaEdge},
      );

      _vlog('HEAD 响应: statusCode=${headResp.statusCode}');
      _vlog('HEAD headers: ${headResp.headers}');

      final cl = headResp.headers['content-length'];
      final size = cl != null ? int.tryParse(cl) : null;

      // 详细日志：记录 Content-Length 原始值
      _vlog('Content-Length 原始值: "$cl"');
      _vlog('解析后文件大小: $size bytes');

      if (size != null && size < 1024) {
        _vlog('警告: 文件大小 < 1KB，可能解析异常');
      }

      state = state.copyWithFileSize(size, fetching: false);
      _vlog('视频文件大小: ${formatFileSize(size)}');
    } catch (e) {
      _vlog('获取文件大小失败: $e');
      state = state.copyWithFileSize(state.fileSizeBytes, fetching: false);
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
    if (error.contains('不存在') ||
        error.contains('已删除') ||
        error.contains('404')) {
      return '作品不存在或已被删除';
    }
    if (error.contains('403') || error.contains('被拒绝')) {
      return '访问被拒绝，作品可能已设为私密';
    }
    if (error.contains('401') || error.contains('未授权')) {
      return '需要登录才能访问此内容';
    }
    if (error.contains('风控') || error.contains('挑战页')) {
      return '触发风控，请稍后重试或更换网络';
    }
    if (error.contains('SocketException') ||
        error.contains('TimeoutException')) {
      return '网络连接失败，请检查网络后重试';
    }
    if (error.contains('无法提取') || error.contains('未找到')) {
      return '解析失败，页面结构可能已变更';
    }
    return '解析失败，请稍后重试';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ParseResult - 解析结果
//
// 用于 Notifier 返回给 UI 层的结果，包含需要 UI 处理的信息。
// ─────────────────────────────────────────────────────────────────────────────

/// 解析结果
///
/// 封装解析操作的结果，用于 Notifier 与 UI 层通信。
/// UI 层根据结果类型显示相应的反馈（如 SnackBar）。
class ParseResult {
  /// 结果类型
  final ParseResultType type;

  /// 解析后的视频信息（仅 success 类型有效）
  final VideoInfo? videoInfo;

  /// 错误信息（仅 error 类型有效）
  final String? errorMessage;

  const ParseResult._({required this.type, this.videoInfo, this.errorMessage});

  /// 输入为空
  static const empty = ParseResult._(type: ParseResultType.empty);

  /// 无效 URL
  static const invalidUrl = ParseResult._(type: ParseResultType.invalidUrl);

  /// 不支持的平台
  static const unsupportedPlatform = ParseResult._(
    type: ParseResultType.unsupportedPlatform,
  );

  /// 解析成功
  factory ParseResult.success(VideoInfo info) =>
      ParseResult._(type: ParseResultType.success, videoInfo: info);

  /// 解析失败
  factory ParseResult.error(String message) =>
      ParseResult._(type: ParseResultType.error, errorMessage: message);

  /// 是否成功
  bool get isSuccess => type == ParseResultType.success;

  /// 是否需要显示错误 SnackBar
  bool get shouldShowErrorSnack =>
      type == ParseResultType.invalidUrl ||
      type == ParseResultType.unsupportedPlatform ||
      type == ParseResultType.error;
}

/// 解析结果类型
enum ParseResultType {
  /// 输入为空
  empty,

  /// 未找到有效 URL
  invalidUrl,

  /// 不支持的平台
  unsupportedPlatform,

  /// 解析成功
  success,

  /// 解析失败
  error,
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider 定义
// ─────────────────────────────────────────────────────────────────────────────

/// 视频解析状态 Provider
///
/// 全局单例，管理应用的解析状态。
final videoNotifierProvider = NotifierProvider<VideoNotifier, VideoState>(() {
  return VideoNotifier();
});
