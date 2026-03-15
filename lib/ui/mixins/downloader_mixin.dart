import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../services/log_service.dart';
import '../../services/parser_common.dart';
import '../../services/downloader/base_downloader.dart';
import '../../services/downloader/desktop_downloader.dart';
import '../../services/downloader/mobile_downloader.dart';
import '../../services/settings_service.dart';

/// 下载逻辑 Mixin
mixin DownloaderMixin<T extends StatefulWidget> on State<T> {
  // 服务
  LogService get log;
  SettingsService get settings;

  // 状态变量
  bool get downloading;
  set downloading(bool value);
  double? get downloadProgress;
  set downloadProgress(double? value);
  int? get lastVerboseProgressBucket;
  set lastVerboseProgressBucket(int? value);
  bool get downloadingMusic;
  set downloadingMusic(bool value);
  bool get downloadingLiveVideos;
  set downloadingLiveVideos(bool value);
  double? get liveVideoProgress;
  set liveVideoProgress(double? value);
  Map<int, double> get singleProgress;
  Map<int, bool> get singleDownloading;

  // 当前视频信息
  VideoInfo? get videoInfo;

  // 文件大小（用于视频下载进度）
  int? get fileSizeBytes;

  // 详细日志
  bool get verbose => settings.verboseLog;

  void vlog(String msg) {
    if (verbose) log.info(msg);
  }

  /// 清理文件名
  String sanitizeFilename(String name, {int maxLen = 20}) {
    var result = name.replaceAll(
      RegExp(
        r'[^\u4e00-\u9fff'
        r'\u3400-\u4dbf'
        r'\u3000-\u303f'
        r'\uff01-\uffe6'
        r'a-zA-Z0-9'
        r' .,_\-!?()'
        r']',
      ),
      '',
    );
    result = result.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (result.length > maxLen) result = result.substring(0, maxLen).trim();
    return result.isEmpty ? 'file' : result;
  }

  /// 下载单个 Live Photo 视频
  Future<void> downloadSingleLivePhoto(int index) async {
    final info = videoInfo;
    if (info == null || info.livePhotoUrls.isEmpty) return;
    if (singleDownloading[index] == true) return;

    final url = info.livePhotoUrls[index];
    final prefix = info.shareId ?? info.itemId;
    final cleanTitle = sanitizeFilename(info.title);
    final filename = '${prefix}_${cleanTitle}_${index + 1}';

    setState(() {
      singleDownloading[index] = true;
      singleProgress[index] = 0;
    });
    log.info('开始下载实况视频 ${index + 1}/${info.livePhotoUrls.length}');

    try {
      final downloader = (Platform.isAndroid || Platform.isIOS)
          ? MobileDownloader()
          : DesktopDownloader();
      final path = await downloader.downloadSingleLivePhoto(
        url,
        directory: settings.downloadDir,
        filename: filename,
        onProgress: (received, total) {
          if (!mounted) return;
          if (total != null && total > 0) {
            setState(() => singleProgress[index] = received / total);
          }
        },
        onLog: (msg) => log.info('[DL] $msg'),
      );
      log.info('实况视频 ${index + 1} 下载完成：$path');
      if (mounted) {
        setState(() => singleProgress[index] = 1.0);
        // 2秒后清除进度状态
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            setState(() {
              singleProgress.remove(index);
              singleDownloading.remove(index);
            });
          }
        });
      }
    } on StoragePermissionDeniedException {
      log.error('存储权限被永久拒绝，请到系统设置中手动开启');
      setState(() {
        singleProgress.remove(index);
        singleDownloading.remove(index);
      });
      if (mounted) showPermissionDialog();
    } catch (e) {
      log.error('实况视频 ${index + 1} 下载失败：$e');
      setState(() {
        singleProgress.remove(index);
        singleDownloading.remove(index);
      });
    }
  }

  /// 下载单个图片
  Future<void> downloadSingleImage(int index) async {
    final info = videoInfo;
    if (info == null || info.imageUrls.isEmpty) return;
    if (singleDownloading[index] == true) return;

    final url = info.imageUrls[index];
    final prefix = info.shareId ?? info.itemId;
    final cleanTitle = sanitizeFilename(info.title);
    final filename = '${prefix}_${cleanTitle}_${index + 1}';

    setState(() {
      singleDownloading[index] = true;
      singleProgress[index] = 0;
    });
    log.info('开始下载图片 ${index + 1}/${info.imageUrls.length}');

    try {
      final downloader = (Platform.isAndroid || Platform.isIOS)
          ? MobileDownloader()
          : DesktopDownloader();
      final path = await downloader.downloadSingleImage(
        url,
        directory: settings.downloadDir,
        filename: filename,
        onProgress: (received, total) {
          if (!mounted) return;
          if (total != null && total > 0) {
            setState(() => singleProgress[index] = received / total);
          }
        },
        onLog: (msg) => log.info('[DL] $msg'),
      );
      log.info('图片 ${index + 1} 下载完成：$path');
      if (mounted) {
        setState(() => singleProgress[index] = 1.0);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            setState(() {
              singleProgress.remove(index);
              singleDownloading.remove(index);
            });
          }
        });
      }
    } on StoragePermissionDeniedException {
      log.error('存储权限被永久拒绝，请到系统设置中手动开启');
      setState(() {
        singleProgress.remove(index);
        singleDownloading.remove(index);
      });
      if (mounted) showPermissionDialog();
    } catch (e) {
      log.error('图片 ${index + 1} 下载失败：$e');
      setState(() {
        singleProgress.remove(index);
        singleDownloading.remove(index);
      });
    }
  }

  /// 下载主内容
  Future<void> download() async {
    final info = videoInfo;
    if (info == null || downloading) return;

    setState(() {
      downloading = true;
      downloadProgress = 0;
      lastVerboseProgressBucket = null;
    });
    // livePhoto 类型现在默认下载图片，动图视频只能单独下载
    final downloadLabel = switch (info.mediaType) {
      MediaType.image => '图文（${info.imageUrls.length} 张）',
      MediaType.livePhoto => '实况图（${info.imageUrls.length} 张）',
      MediaType.video => '视频',
    };
    log.info('开始下载 $downloadLabel：${info.title}');

    try {
      final downloader = (Platform.isAndroid || Platform.isIOS)
          ? MobileDownloader()
          : DesktopDownloader();
      vlog('下载器=${downloader.runtimeType}, 目录=${settings.downloadDir}');
      final path = await downloader.downloadVideo(
        info,
        directory: settings.downloadDir,
        onProgress: (received, total) {
          if (!mounted) return;
          // 图文或实况图：received = 当前张数/个数， total = 总数
          if (info.mediaType == MediaType.image ||
              info.mediaType == MediaType.livePhoto) {
            if (total != null && total > 0) {
              final p = received / total;
              setState(() => downloadProgress = p);
              final bucket = (p * 10).floor();
              if (verbose && lastVerboseProgressBucket != bucket) {
                lastVerboseProgressBucket = bucket;
                final type = info.mediaType == MediaType.image ? '图文' : '实况图';
                vlog(
                  '$type下载进度 ${(p * 100).toStringAsFixed(0)}% ($received/$total)',
                );
              }
            }
          } else {
            final t = total ?? fileSizeBytes;
            if (t != null && t > 0) {
              final p = received / t;
              setState(() => downloadProgress = p);
              final bucket = (p * 10).floor();
              if (verbose && lastVerboseProgressBucket != bucket) {
                lastVerboseProgressBucket = bucket;
                vlog('视频下载进度 ${(p * 100).toStringAsFixed(0)}% ($received/$t)');
              }
            }
          }
        },
        onLog: (msg) => log.info('[DL] $msg'),
      );
      log.info('下载完成：$path');
      setState(() => downloadProgress = 1.0);
      onDownloadComplete();
    } on StoragePermissionDeniedException {
      log.error('存储权限被永久拒绝，请到系统设置中手动开启');
      setState(() => downloadProgress = null);
      if (mounted) showPermissionDialog();
    } catch (e) {
      log.error('下载失败：$e');
      setState(() => downloadProgress = null);
    } finally {
      setState(() => downloading = false);
    }
  }

  /// 下载完成回调（子类可重写）
  void onDownloadComplete() {}

  /// 单独下载背景音乐
  Future<void> downloadMusicOnly() async {
    final info = videoInfo;
    if (info == null || info.musicUrl == null || downloadingMusic) return;

    setState(() => downloadingMusic = true);

    try {
      final downloader = (Platform.isAndroid || Platform.isIOS)
          ? MobileDownloader()
          : DesktopDownloader();

      final prefix = info.shareId ?? info.itemId;
      final cleanTitle = sanitizeFilename(info.title);
      String filename;
      if (info.musicAuthor != null && info.musicTitle != null) {
        final cleanAuthor = sanitizeFilename(info.musicAuthor!, maxLen: 50);
        final cleanMusicTitle = sanitizeFilename(info.musicTitle!, maxLen: 50);
        filename = '${prefix}_$cleanAuthor - $cleanMusicTitle';
      } else {
        filename = '${prefix}_${cleanTitle}_bgm';
      }

      final path = await downloader.downloadMusicFile(
        info.musicUrl!,
        filename: filename,
        onLog: (msg) => log.info('[DL] $msg'),
      );

      if (path == null) {
        log.warn('背景音乐下载失败');
      }
    } on StoragePermissionDeniedException {
      log.error('存储权限被永久拒绝，请到系统设置中手动开启');
      if (mounted) showPermissionDialog();
    } catch (e) {
      log.error('背景音乐下载失败：$e');
    } finally {
      setState(() => downloadingMusic = false);
    }
  }

  /// 批量下载实况图的视频（动图）
  Future<void> downloadLiveVideos() async {
    final info = videoInfo;
    if (info == null || downloadingLiveVideos) return;

    // 检查是否有有效的动图视频
    final validCount = info.livePhotoUrls.where((u) => u.isNotEmpty).length;
    if (validCount == 0) {
      log.warn('没有动图视频可下载');
      return;
    }

    setState(() {
      downloadingLiveVideos = true;
      liveVideoProgress = 0;
    });
    log.info('开始下载动图视频（$validCount 个）：${info.title}');

    try {
      final downloader = (Platform.isAndroid || Platform.isIOS)
          ? MobileDownloader()
          : DesktopDownloader();
      vlog('下载器=${downloader.runtimeType}, 目录=${settings.downloadDir}');
      final path = await downloader.downloadLivePhotos(
        info,
        directory: settings.downloadDir,
        onProgress: (received, total) {
          if (!mounted) return;
          if (total != null && total > 0) {
            final p = received / total;
            setState(() => liveVideoProgress = p);
            final bucket = (p * 10).floor();
            if (verbose && lastVerboseProgressBucket != bucket) {
              lastVerboseProgressBucket = bucket;
              vlog('动图视频下载进度 ${(p * 100).toStringAsFixed(0)}% ($received/$total)');
            }
          }
        },
        onLog: (msg) => log.info('[DL] $msg'),
      );
      if (path.isNotEmpty) {
        log.info('动图视频下载完成：$path');
        setState(() => liveVideoProgress = 1.0);
      }
    } on StoragePermissionDeniedException {
      log.error('存储权限被永久拒绝，请到系统设置中手动开启');
      setState(() => liveVideoProgress = null);
      if (mounted) showPermissionDialog();
    } catch (e) {
      log.error('动图视频下载失败：$e');
      setState(() => liveVideoProgress = null);
    } finally {
      setState(() => downloadingLiveVideos = false);
    }
  }

  /// 权限被永久拒绝时弹对话框引导用户去设置页
  void showPermissionDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('需要存储权限'),
        content: const Text('存储权限已被永久拒绝，请在系统设置中手动开启后重试。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }
}
