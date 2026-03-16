import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/downloader/base_downloader.dart';
import '../services/downloader/desktop_downloader.dart';
import '../services/downloader/mobile_downloader.dart';
import '../services/log_service.dart';
import '../services/parser_common.dart';
import '../services/settings_service.dart';
import '../utils/filename_utils.dart';
import 'providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DownloadNotifier - 下载状态管理
//
// 负责管理下载过程中的状态变化，不直接操作 UI。
// UI 相关操作（如 SnackBar、权限对话框）由 Widget 层处理。
// ─────────────────────────────────────────────────────────────────────────────

/// 下载状态 Notifier
///
/// 提供下载相关的状态管理和业务逻辑。
/// 状态变化通过 Riverpod 自动通知监听者。
///
/// 使用方式：
/// ```dart
/// // 读取状态
/// final state = ref.watch(downloadNotifierProvider);
/// if (state.downloading) { ... }
///
/// // 调用方法
/// ref.read(downloadNotifierProvider.notifier).download();
/// ```
class DownloadNotifier extends Notifier<DownloadState> {
  @override
  DownloadState build() {
    return const DownloadState.initial();
  }

  // ─── 便捷 getter ───────────────────────────────────────────────────────

  LogService get _log => ref.read(logServiceProvider);
  SettingsService get _settings => ref.read(settingsServiceProvider);
  bool get _verbose => _settings.verboseLog;

  VideoState get _videoState => ref.read(videoNotifierProvider);

  void _vlog(String msg) {
    if (_verbose) _log.info(msg);
  }

  /// 当前视频信息
  VideoInfo? get videoInfo => _videoState.videoInfo;

  // ─── 状态更新方法 ───────────────────────────────────────────────────────

  /// 重置下载状态（新解析成功时调用）
  void reset() {
    state = state.reset();
  }

  // ─── 下载逻辑 ───────────────────────────────────────────────────────────

  /// 下载主内容
  ///
  /// 返回 DownloadResult，包含下载结果和需要 UI 层处理的信息。
  Future<DownloadResult> download() async {
    final info = videoInfo;
    if (info == null) {
      return DownloadResult.noVideoInfo;
    }

    if (state.downloading) {
      return DownloadResult.alreadyDownloading;
    }

    // 开始下载
    state = state.copyWithStartDownload();

    final downloadLabel = switch (info.mediaType) {
      MediaType.image => '图文（${info.imageUrls.length} 张）',
      MediaType.livePhoto => '实况图（${info.imageUrls.length} 张）',
      MediaType.video => '视频',
    };
    _log.info('开始下载 $downloadLabel：${info.title}');

    try {
      final downloader = _createDownloader();
      _vlog('下载器=${downloader.runtimeType}, 目录=${_settings.downloadDir}');

      final path = await downloader.downloadVideo(
        info,
        directory: _settings.downloadDir,
        onProgress: (received, total) {
          _updateMainProgress(info, received, total);
        },
        onLog: (msg) => _log.info('[DL] $msg'),
      );

      _log.info('下载完成：$path');
      state = state.copyWithDownloadComplete();

      // 返回结果
      final isBatch = info.mediaType == MediaType.image ||
          info.mediaType == MediaType.livePhoto;
      return DownloadResult.success(
        path: isBatch ? _settings.downloadDir : path,
        isBatch: isBatch,
      );
    } on StoragePermissionDeniedException {
      _log.error('存储权限被永久拒绝，请到系统设置中手动开启');
      state = state.copyWithDownloadFailed();
      return DownloadResult.permissionDenied;
    } catch (e) {
      _log.error('下载失败：$e');
      state = state.copyWithDownloadFailed();
      return DownloadResult.error(e.toString());
    }
  }

  /// 下载单个图片
  Future<DownloadResult> downloadSingleImage(int index) async {
    final info = videoInfo;
    if (info == null || info.imageUrls.isEmpty) {
      return DownloadResult.noVideoInfo;
    }

    if (state.isSingleDownloading(index)) {
      return DownloadResult.alreadyDownloading;
    }

    final url = info.imageUrls[index];
    final filename = _buildFilename(info, index);

    state = state.copyWithStartSingleDownload(index);
    _log.info('开始下载图片 ${index + 1}/${info.imageUrls.length}');

    try {
      final downloader = _createDownloader();
      final path = await downloader.downloadSingleImage(
        url,
        directory: _settings.downloadDir,
        filename: filename,
        onProgress: (received, total) {
          _updateSingleProgress(index, received, total);
        },
        onLog: (msg) => _log.info('[DL] $msg'),
      );

      _log.info('图片 ${index + 1} 下载完成：$path');
      state = state.copyWithSingleComplete(index);

      return DownloadResult.success(path: path, index: index);
    } on StoragePermissionDeniedException {
      _log.error('存储权限被永久拒绝，请到系统设置中手动开启');
      state = state.copyWithSingleFailed(index);
      return DownloadResult.permissionDenied;
    } catch (e) {
      _log.error('图片 ${index + 1} 下载失败：$e');
      state = state.copyWithSingleFailed(index);
      return DownloadResult.error(e.toString(), index: index);
    }
  }

  /// 下载单个实况视频
  Future<DownloadResult> downloadSingleLivePhoto(int index) async {
    final info = videoInfo;
    if (info == null || info.livePhotoUrls.isEmpty) {
      return DownloadResult.noVideoInfo;
    }

    if (state.isSingleDownloading(index)) {
      return DownloadResult.alreadyDownloading;
    }

    final url = info.livePhotoUrls[index];
    final filename = _buildFilename(info, index);

    state = state.copyWithStartSingleDownload(index);
    _log.info('开始下载实况视频 ${index + 1}/${info.livePhotoUrls.length}');

    try {
      final downloader = _createDownloader();
      final path = await downloader.downloadSingleLivePhoto(
        url,
        directory: _settings.downloadDir,
        filename: filename,
        onProgress: (received, total) {
          _updateSingleProgress(index, received, total);
        },
        onLog: (msg) => _log.info('[DL] $msg'),
      );

      _log.info('实况视频 ${index + 1} 下载完成：$path');
      state = state.copyWithSingleComplete(index);

      return DownloadResult.success(path: path, index: index);
    } on StoragePermissionDeniedException {
      _log.error('存储权限被永久拒绝，请到系统设置中手动开启');
      state = state.copyWithSingleFailed(index);
      return DownloadResult.permissionDenied;
    } catch (e) {
      _log.error('实况视频 ${index + 1} 下载失败：$e');
      state = state.copyWithSingleFailed(index);
      return DownloadResult.error(e.toString(), index: index);
    }
  }

  /// 下载背景音乐
  Future<DownloadResult> downloadMusic() async {
    final info = videoInfo;
    if (info == null || info.musicUrl == null) {
      return DownloadResult.noMusic;
    }

    if (state.downloadingMusic) {
      return DownloadResult.alreadyDownloading;
    }

    state = state.copyWithStartMusic();

    try {
      final downloader = _createDownloader();
      final filename = _buildMusicFilename(info);

      final path = await downloader.downloadMusicFile(
        info.musicUrl!,
        filename: filename,
        onLog: (msg) => _log.info('[DL] $msg'),
      );

      if (path != null) {
        _log.info('背景音乐下载完成：$path');
        state = state.copyWithMusicComplete();
        return DownloadResult.success(path: path);
      } else {
        _log.warn('背景音乐下载失败');
        state = state.copyWithMusicComplete();
        return DownloadResult.error('背景音乐下载失败');
      }
    } on StoragePermissionDeniedException {
      _log.error('存储权限被永久拒绝，请到系统设置中手动开启');
      state = state.copyWithMusicComplete();
      return DownloadResult.permissionDenied;
    } catch (e) {
      _log.error('背景音乐下载失败：$e');
      state = state.copyWithMusicComplete();
      return DownloadResult.error(e.toString());
    }
  }

  /// 批量下载动图视频
  Future<DownloadResult> downloadLiveVideos() async {
    final info = videoInfo;
    if (info == null) {
      return DownloadResult.noVideoInfo;
    }

    final validCount = info.livePhotoUrls.where((u) => u.isNotEmpty).length;
    if (validCount == 0) {
      _log.warn('没有动图视频可下载');
      return DownloadResult.noLiveVideos;
    }

    if (state.downloadingLiveVideos) {
      return DownloadResult.alreadyDownloading;
    }

    state = state.copyWithStartLiveVideos();
    _log.info('开始下载动图视频（$validCount 个）：${info.title}');

    try {
      final downloader = _createDownloader();
      _vlog('下载器=${downloader.runtimeType}, 目录=${_settings.downloadDir}');

      final path = await downloader.downloadLivePhotos(
        info,
        directory: _settings.downloadDir,
        onProgress: (received, total) {
          _updateLiveVideoProgress(received, total);
        },
        onLog: (msg) => _log.info('[DL] $msg'),
      );

      if (path.isNotEmpty) {
        _log.info('动图视频下载完成：$path');
        state = state.copyWithLiveVideoComplete();
        return DownloadResult.success(path: _settings.downloadDir, count: validCount);
      } else {
        state = state.copyWithLiveVideoFailed();
        return DownloadResult.error('动图视频下载失败');
      }
    } on StoragePermissionDeniedException {
      _log.error('存储权限被永久拒绝，请到系统设置中手动开启');
      state = state.copyWithLiveVideoFailed();
      return DownloadResult.permissionDenied;
    } catch (e) {
      _log.error('动图视频下载失败：$e');
      state = state.copyWithLiveVideoFailed();
      return DownloadResult.error(e.toString());
    }
  }

  /// 清除单个下载的进度显示
  void clearSingleProgress(int index) {
    state = state.removeSingleProgress(index);
  }

  // ─── 私有辅助方法 ───────────────────────────────────────────────────────

  /// 创建下载器
  BaseDownloader _createDownloader() {
    return (Platform.isAndroid || Platform.isIOS)
        ? MobileDownloader()
        : DesktopDownloader();
  }

  /// 构建文件名
  String _buildFilename(VideoInfo info, int index) {
    final prefix = info.shareId ?? info.itemId;
    final cleanTitle = sanitizeFilename(info.title);
    final platformPrefix = info.platform.filePrefix;
    return '$platformPrefix${prefix}_${cleanTitle}_${index + 1}';
  }

  /// 构建音乐文件名
  String _buildMusicFilename(VideoInfo info) {
    final prefix = info.shareId ?? info.itemId;
    final cleanTitle = sanitizeFilename(info.title);
    final platformPrefix = info.platform.filePrefix;

    if (info.musicAuthor != null && info.musicTitle != null) {
      final cleanAuthor = sanitizeFilename(info.musicAuthor!, maxLen: 50);
      final cleanMusicTitle = sanitizeFilename(info.musicTitle!, maxLen: 50);
      return '$platformPrefix${prefix}_$cleanAuthor - $cleanMusicTitle';
    } else {
      return '$platformPrefix${prefix}_${cleanTitle}_bgm';
    }
  }

  /// 更新主下载进度
  void _updateMainProgress(VideoInfo info, int received, int? total) {
    // 图文或实况图：received = 当前张数/个数，total = 总数
    if (info.mediaType == MediaType.image ||
        info.mediaType == MediaType.livePhoto) {
      if (total != null && total > 0) {
        final p = received / total;
        final bucket = (p * 10).floor();

        state = state.copyWithDownloadProgress(p, verboseBucket: bucket);

        if (_verbose && state.lastVerboseProgressBucket != bucket) {
          final type = info.mediaType == MediaType.image ? '图文' : '实况图';
          _vlog('$type下载进度 ${(p * 100).toStringAsFixed(0)}% ($received/$total)');
        }
      }
    } else {
      // 视频
      final t = total ?? _videoState.fileSizeBytes;
      if (t != null && t > 0) {
        final p = received / t;
        final bucket = (p * 10).floor();

        state = state.copyWithDownloadProgress(p, verboseBucket: bucket);

        if (_verbose && state.lastVerboseProgressBucket != bucket) {
          _vlog('视频下载进度 ${(p * 100).toStringAsFixed(0)}% ($received/$t)');
        }
      }
    }
  }

  /// 更新单个下载进度
  void _updateSingleProgress(int index, int received, int? total) {
    if (total != null && total > 0) {
      state = state.copyWithSingleProgress(index, received / total);
    }
  }

  /// 更新动图视频下载进度
  void _updateLiveVideoProgress(int received, int? total) {
    if (total != null && total > 0) {
      final p = received / total;
      final bucket = (p * 10).floor();

      state = state.copyWithLiveVideoProgress(p, verboseBucket: bucket);

      if (_verbose && state.lastVerboseProgressBucket != bucket) {
        _vlog('动图视频下载进度 ${(p * 100).toStringAsFixed(0)}% ($received/$total)');
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DownloadResult - 下载结果
//
// 用于 Notifier 返回给 UI 层的结果，包含需要 UI 处理的信息。
// ─────────────────────────────────────────────────────────────────────────────

/// 下载结果
///
/// 封装下载操作的结果，用于 Notifier 与 UI 层通信。
/// UI 层根据结果类型显示相应的反馈（如 SnackBar）。
class DownloadResult {
  /// 结果类型
  final DownloadResultType type;

  /// 文件路径
  final String? path;

  /// 是否批量下载
  final bool isBatch;

  /// 索引（单个下载时）
  final int? index;

  /// 数量（批量下载时）
  final int? count;

  /// 错误信息
  final String? errorMessage;

  const DownloadResult._({
    required this.type,
    this.path,
    this.isBatch = false,
    this.index,
    this.count,
    this.errorMessage,
  });

  /// 无视频信息
  static const noVideoInfo =
      DownloadResult._(type: DownloadResultType.noVideoInfo);

  /// 无音乐
  static const noMusic = DownloadResult._(type: DownloadResultType.noMusic);

  /// 无动图视频
  static const noLiveVideos =
      DownloadResult._(type: DownloadResultType.noLiveVideos);

  /// 已在下载中
  static const alreadyDownloading =
      DownloadResult._(type: DownloadResultType.alreadyDownloading);

  /// 权限被拒绝
  static const permissionDenied =
      DownloadResult._(type: DownloadResultType.permissionDenied);

  /// 成功
  factory DownloadResult.success({
    String? path,
    bool isBatch = false,
    int? index,
    int? count,
  }) =>
      DownloadResult._(
        type: DownloadResultType.success,
        path: path,
        isBatch: isBatch,
        index: index,
        count: count,
      );

  /// 失败
  factory DownloadResult.error(String message, {int? index}) =>
      DownloadResult._(
        type: DownloadResultType.error,
        errorMessage: message,
        index: index,
      );

  /// 是否成功
  bool get isSuccess => type == DownloadResultType.success;

  /// 是否需要显示权限对话框
  bool get shouldShowPermissionDialog => type == DownloadResultType.permissionDenied;
}

/// 下载结果类型
enum DownloadResultType {
  /// 无视频信息
  noVideoInfo,

  /// 无音乐
  noMusic,

  /// 无动图视频
  noLiveVideos,

  /// 已在下载中
  alreadyDownloading,

  /// 权限被拒绝
  permissionDenied,

  /// 成功
  success,

  /// 失败
  error,
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider 定义
// ─────────────────────────────────────────────────────────────────────────────

/// 下载状态 Provider
///
/// 全局单例，管理应用的下载状态。
final downloadNotifierProvider =
    NotifierProvider<DownloadNotifier, DownloadState>(() {
  return DownloadNotifier();
});
